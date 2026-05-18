#!/usr/bin/env python3
# embed.py — text embedding for MemoryVault entries.
#
# Three modes (locked design call C2 — toolkit ships Anthropic API by
# default + local sentence-transformers fallback both in v1; v0.9.0+):
#   - "api"   — Anthropic API call (requires ANTHROPIC_API_KEY env var).
#   - "local" — sentence-transformers via Python (requires the
#               `sentence-transformers` pip package; lazy-loads
#               `all-MiniLM-L6-v2` on first use).
#   - "stub"  — deterministic 384-d hash-based vector. ONLY for testing;
#               NEVER used in production. Smoke install + unit fixtures
#               use stub mode to validate wiring without external deps.
#
# Mode resolution:
#   1. Explicit --mode arg (CLI) or `mode=` kwarg (Python).
#   2. MEMORY_USE_API_EMBEDDINGS env var: "false" → local; else → api.
#   3. Default: "api".
#
# Graceful-skip behavior (per parent design's Tech Debt #1):
#   - If API mode + no ANTHROPIC_API_KEY → raise EmbeddingUnavailable.
#   - If local mode + no sentence-transformers → raise EmbeddingUnavailable.
#   - Callers (save.py / evolve.py async path) catch EmbeddingUnavailable
#     + log warning + leave the queue entry pending. File write is never
#     blocked.

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import urllib.error
import urllib.request

# Anthropic embeddings endpoint (Claude embeddings API).
# Voyage AI provides the actual embedding service; Anthropic's docs point
# at the Voyage endpoint for API embeddings. We hit Voyage directly to
# avoid an extra hop. Operators can switch providers via env vars later
# (cross-host embedding support is deferred per ROADMAP follow-up).
_VOYAGE_ENDPOINT = "https://api.voyageai.com/v1/embeddings"
_VOYAGE_MODEL = "voyage-2"  # Default model; balances quality + cost.

# Local sentence-transformers model (Tech Debt #1 — small + offline-capable).
_LOCAL_MODEL = "all-MiniLM-L6-v2"  # 384-d, ~80MB

# Embedding dimensions — must match across modes for vec-index consistency.
# Voyage voyage-2 produces 1024-d; sentence-transformers all-MiniLM-L6-v2
# produces 384-d. For v1 we use the local dimension (384) for both paths
# so the vec-index doesn't need per-mode-partitioned schemas. The api mode
# pads voyage's output to 384-d via truncation (lossy but deterministic).
# Cross-provider dimension mismatch is captured as ROADMAP follow-up
# (cross-host embedding support).
EMBEDDING_DIM = 384


class EmbeddingUnavailable(Exception):
    """Raised when the requested embedding mode can't be served (no API key,
    no local model, etc.). Callers should catch + log + leave queue entry
    pending; file write is never blocked."""


def _resolve_mode(arg_mode: str | None) -> str:
    """Resolve embedding mode per the documented chain."""
    if arg_mode:
        if arg_mode not in {"api", "local", "stub"}:
            raise ValueError(f"unknown mode {arg_mode!r}: expected api / local / stub")
        return arg_mode
    env_use_api = os.environ.get("MEMORY_USE_API_EMBEDDINGS", "true").strip().lower()
    if env_use_api == "false":
        return "local"
    return "api"


def _embed_api(text: str) -> list[float]:
    """Embed via Voyage API (Anthropic's recommended provider).

    Raises EmbeddingUnavailable if VOYAGE_API_KEY (or ANTHROPIC_API_KEY)
    not set, or if the request fails.
    """
    # Accept either env var; VOYAGE_API_KEY is more accurate for the
    # actual provider but ANTHROPIC_API_KEY is the convention operators
    # are more likely to have already configured.
    api_key = os.environ.get("VOYAGE_API_KEY") or os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        raise EmbeddingUnavailable(
            "API mode requires VOYAGE_API_KEY or ANTHROPIC_API_KEY env var; "
            "neither set. Either configure the key, set "
            "MEMORY_USE_API_EMBEDDINGS=false to use the local fallback, or "
            "let this queue entry stay pending until the key is configured."
        )
    payload = json.dumps({
        "input": [text],
        "model": _VOYAGE_MODEL,
    }).encode("utf-8")
    req = urllib.request.Request(
        _VOYAGE_ENDPOINT,
        data=payload,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError) as e:
        raise EmbeddingUnavailable(f"API embedding request failed: {e}") from e
    embedding = data.get("data", [{}])[0].get("embedding")
    if not embedding or not isinstance(embedding, list):
        raise EmbeddingUnavailable(
            f"API response missing or malformed embedding field: {data!r}"
        )
    # Truncate to local-model dimension for cross-mode consistency
    # (see EMBEDDING_DIM comment). Voyage voyage-2 produces 1024-d; we
    # take the first 384 components. Lossy but deterministic.
    return embedding[:EMBEDDING_DIM]


def _embed_local(text: str) -> list[float]:
    """Embed via sentence-transformers (offline; 384-d).

    Lazy-imports sentence-transformers — the package isn't a hard toolkit
    dep, so callers that only ever use api or stub mode don't need it.
    """
    try:
        from sentence_transformers import SentenceTransformer  # type: ignore
    except ImportError as e:
        raise EmbeddingUnavailable(
            "Local mode requires `sentence-transformers` Python package. "
            "Install via: pip install sentence-transformers"
        ) from e
    # Lazy-load the model on first call; cache in module globals.
    global _LOCAL_MODEL_INSTANCE
    try:
        model = _LOCAL_MODEL_INSTANCE  # noqa: F821
    except NameError:
        _LOCAL_MODEL_INSTANCE = SentenceTransformer(_LOCAL_MODEL)
        model = _LOCAL_MODEL_INSTANCE
    embedding = model.encode([text])[0].tolist()
    return list(embedding)


def _embed_stub(text: str) -> list[float]:
    """Deterministic hash-based fake embedding. Testing only."""
    # SHA-256 of text -> 32 bytes -> repeat to fill EMBEDDING_DIM floats.
    # Each byte normalized to [-1, 1].
    digest = hashlib.sha256(text.encode("utf-8")).digest()
    out: list[float] = []
    i = 0
    while len(out) < EMBEDDING_DIM:
        b = digest[i % len(digest)]
        out.append((b - 128) / 128.0)
        i += 1
    return out


def embed_text(text: str, *, mode: str | None = None) -> list[float]:
    """Embed text via the configured mode. Returns EMBEDDING_DIM-length floats.

    Raises:
        EmbeddingUnavailable: if the requested mode can't be served.
        ValueError: if mode is not one of api/local/stub.
    """
    resolved = _resolve_mode(mode)
    if resolved == "api":
        return _embed_api(text)
    if resolved == "local":
        return _embed_local(text)
    if resolved == "stub":
        return _embed_stub(text)
    raise ValueError(f"internal: unhandled mode {resolved!r}")  # pragma: no cover


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="memory-embed",
        description="Embed text via Voyage API (default), local sentence-transformers, or stub.",
    )
    parser.add_argument("text", help="text to embed (or '-' to read from stdin)")
    parser.add_argument(
        "--mode",
        choices=["api", "local", "stub"],
        default=None,
        help="embedding mode (default: api unless MEMORY_USE_API_EMBEDDINGS=false)",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv if argv is not None else sys.argv[1:])
    text = sys.stdin.read() if args.text == "-" else args.text
    try:
        embedding = embed_text(text, mode=args.mode)
    except EmbeddingUnavailable as e:
        print(f"EMBEDDING_UNAVAILABLE: {e}", file=sys.stderr)
        return 2  # Distinct exit code so callers can detect graceful-skip.
    except ValueError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1
    # Stdout: JSON-encoded list of floats (script-pipeable).
    print(json.dumps(embedding))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
