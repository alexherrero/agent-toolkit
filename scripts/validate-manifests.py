#!/usr/bin/env python3
"""validate-manifests.py — assert every manifest in the toolkit is well-formed.

Walks the repo finding every bundle manifest (`bundles/*/bundle.md`) and
every standalone primitive manifest (`<kind>/<name>/<name-or-SKILL>.md`).
Parses YAML frontmatter and asserts:

Required fields (all customizations):
  - name (string; matches dirname or 'bundle' for bundle.md)
  - description (non-empty string)
  - kind (enum membership)
  - supported_hosts (non-empty list, subset of {claude-code, antigravity};
    gemini-cli removed in v0.9.0 per ROADMAP item #15)
  - version (semver-shape: MAJOR.MINOR.PATCH with optional -prerelease)

Required for bundles only:
  - contents (non-empty list of {kind: name} items; each resolves inside the bundle)

Optional recognized fields:
  - install_scope (one of: user, project, either)
  - deprecated (string; lifecycle marker)

Primitives inside bundles (e.g. `bundles/<b>/skills/<s>/SKILL.md`) have a
relaxed schema: only `name` and `description` required (kind / supported_hosts
/ version are inherited from the parent bundle).

Exit:
  0  all manifests valid
  1  one or more failures (first failure file:line printed)
  2  setup error (pyyaml missing, etc.)
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

try:
    import yaml
except ModuleNotFoundError:
    print("validate-manifests: pyyaml not installed. run: pip install pyyaml", file=sys.stderr)
    sys.exit(2)


# ── schema ────────────────────────────────────────────────────────────────
KIND_ENUM = {
    "bundle", "skill", "command", "agent", "hook", "mcp-server",
    "status-line", "output-style", "workflow", "rule", "snippet",
    "settings-fragment",
}
HOST_ENUM = {"claude-code", "antigravity"}
# Hosts deprecated and removed in this version. Surfaced separately from
# unknown-host errors so the operator gets actionable next-step text
# (point at the CHANGELOG entry that removed the host).
REMOVED_HOSTS = {
    "gemini-cli": "v0.9.0 removed standalone Gemini CLI host support per ROADMAP item #15. "
                  "Drop 'gemini-cli' from supported_hosts. See "
                  "https://github.com/alexherrero/agent-toolkit/blob/main/CHANGELOG.md "
                  "for the v0.9.0 entry. Antigravity (Gemini-in-IDE) stays as a supported host.",
}
SCOPE_ENUM = {"user", "project", "either"}

# Kind → expected manifest filename inside the customization's dir.
# For kinds where the host expects <name>.md, the manifest filename is <name>.md
# (the script substitutes <name> at lookup time). For skills, SKILL.md is the
# Agent Skills standard.
KIND_MANIFEST = {
    "bundle": "bundle.md",          # bundles only — special location
    "skill": "SKILL.md",
    "command": "<name>.md",
    "agent": "<name>.md",
    "hook": None,                   # hooks are executables; no manifest yet (v0.1.0 doesn't ship hooks)
    "mcp-server": "<name>.json",    # may evolve
    "status-line": "<name>.json",
    "output-style": "<name>.md",
    "workflow": "<name>.md",
    "rule": "<name>.md",
    "snippet": "<name>.md",
    "settings-fragment": "<name>.json",
}

FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---\n", re.DOTALL)
SEMVER_RE = re.compile(r"^\d+\.\d+\.\d+(-[0-9A-Za-z-.]+)?$")

ROOT = Path(__file__).resolve().parent.parent
errors: list[str] = []


def err(path: Path, msg: str) -> None:
    rel = path.relative_to(ROOT) if path.is_absolute() else path
    errors.append(f"{rel}: {msg}")
    print(f"FAIL: {rel}: {msg}", file=sys.stderr)


# ── frontmatter parsing ───────────────────────────────────────────────────
def parse_frontmatter(path: Path) -> dict | None:
    text = path.read_text(encoding="utf-8")
    m = FRONTMATTER_RE.match(text)
    if not m:
        err(path, "no YAML frontmatter")
        return None
    try:
        fm = yaml.safe_load(m.group(1)) or {}
    except yaml.YAMLError as e:
        err(path, f"invalid YAML frontmatter: {e}")
        return None
    if not isinstance(fm, dict):
        err(path, "frontmatter is not a mapping")
        return None
    return fm


# ── per-field validators ──────────────────────────────────────────────────
def require_non_empty_string(path: Path, fm: dict, key: str) -> None:
    v = fm.get(key)
    if v is None:
        err(path, f"missing required field '{key}'")
        return
    if not isinstance(v, str) or not v.strip():
        err(path, f"field '{key}' must be a non-empty string (got: {v!r})")


def require_kind(path: Path, fm: dict) -> str | None:
    v = fm.get("kind")
    if v is None:
        err(path, "missing required field 'kind'")
        return None
    if v not in KIND_ENUM:
        err(path, f"field 'kind' must be one of {sorted(KIND_ENUM)} (got: {v!r})")
        return None
    return v


def require_supported_hosts(path: Path, fm: dict) -> None:
    v = fm.get("supported_hosts")
    if v is None:
        err(path, "missing required field 'supported_hosts'")
        return
    if not isinstance(v, list) or not v:
        err(path, f"field 'supported_hosts' must be a non-empty list (got: {v!r})")
        return
    # Surface removed hosts before unknown hosts — gives operator actionable
    # next-step text (CHANGELOG pointer) rather than a generic "unknown host".
    removed = [h for h in v if h in REMOVED_HOSTS]
    for h in removed:
        err(path, f"removed host '{h}' in 'supported_hosts': {REMOVED_HOSTS[h]}")
    unknown = [h for h in v if h not in HOST_ENUM and h not in REMOVED_HOSTS]
    if unknown:
        err(path, f"unknown hosts in 'supported_hosts': {unknown} (allowed: {sorted(HOST_ENUM)})")


def require_version(path: Path, fm: dict) -> None:
    v = fm.get("version")
    if v is None:
        err(path, "missing required field 'version'")
        return
    if not isinstance(v, str) or not SEMVER_RE.match(v):
        err(path, f"field 'version' must be semver-shape (e.g. 0.1.0); got: {v!r}")


def check_optional_scope(path: Path, fm: dict) -> None:
    if "install_scope" in fm:
        v = fm["install_scope"]
        if v not in SCOPE_ENUM:
            err(path, f"field 'install_scope' must be one of {sorted(SCOPE_ENUM)} (got: {v!r})")


def check_name_matches_dir(path: Path, fm: dict, expected: str) -> None:
    v = fm.get("name")
    if v is not None and v != expected:
        err(path, f"field 'name' ({v!r}) must match expected ({expected!r})")


def check_contents(path: Path, fm: dict, bundle_dir: Path) -> None:
    """Bundle-only: assert `contents` is a non-empty list of {kind: name}, each resolving."""
    v = fm.get("contents")
    if v is None:
        err(path, "bundle missing required field 'contents'")
        return
    if not isinstance(v, list) or not v:
        err(path, f"field 'contents' must be a non-empty list (got: {v!r})")
        return
    for i, item in enumerate(v):
        if not isinstance(item, dict) or len(item) != 1:
            err(path, f"contents[{i}] must be a single-key mapping like {{kind: name}} (got: {item!r})")
            continue
        kind, name = next(iter(item.items()))
        if kind not in KIND_ENUM:
            err(path, f"contents[{i}] unknown kind: {kind!r}")
            continue
        # Resolve the primitive within the bundle.
        if kind == "skill":
            primitive_path = bundle_dir / "skills" / str(name) / "SKILL.md"
        elif kind == "agent":
            primitive_path = bundle_dir / "agents" / f"{name}.md"
        elif kind == "hook":
            primitive_path = bundle_dir / "hooks" / str(name) / "hook.md"
        else:
            # other kinds: not yet exercised; check the dir exists
            primitive_path = bundle_dir / f"{kind}s" / str(name)
        if not primitive_path.exists():
            err(path, f"contents[{i}] resolves to non-existent path: {primitive_path.relative_to(ROOT)}")


# ── discovery + dispatch ──────────────────────────────────────────────────
def validate_bundle(bundle_md: Path) -> None:
    fm = parse_frontmatter(bundle_md)
    if fm is None:
        return
    bundle_dir = bundle_md.parent
    expected_name = bundle_dir.name
    require_non_empty_string(bundle_md, fm, "description")
    check_name_matches_dir(bundle_md, fm, expected_name)
    kind = require_kind(bundle_md, fm)
    if kind is not None and kind != "bundle":
        err(bundle_md, f"bundle.md has kind {kind!r}; must be 'bundle'")
    require_supported_hosts(bundle_md, fm)
    require_version(bundle_md, fm)
    check_optional_scope(bundle_md, fm)
    check_contents(bundle_md, fm, bundle_dir)

    # Validate inner skills with relaxed schema
    for primitive_md in bundle_dir.rglob("SKILL.md"):
        if primitive_md == bundle_md:
            continue
        fm2 = parse_frontmatter(primitive_md)
        if fm2 is None:
            continue
        require_non_empty_string(primitive_md, fm2, "description")
        expected = primitive_md.parent.name
        check_name_matches_dir(primitive_md, fm2, expected)

    # Validate inner agents (bundle_dir/agents/*.md) with relaxed schema
    agents_dir = bundle_dir / "agents"
    if agents_dir.is_dir():
        for primitive_md in sorted(agents_dir.glob("*.md")):
            fm2 = parse_frontmatter(primitive_md)
            if fm2 is None:
                continue
            require_non_empty_string(primitive_md, fm2, "description")
            check_name_matches_dir(primitive_md, fm2, primitive_md.stem)


def validate_standalone_skill(skill_md: Path) -> None:
    fm = parse_frontmatter(skill_md)
    if fm is None:
        return
    expected_name = skill_md.parent.name
    require_non_empty_string(skill_md, fm, "description")
    check_name_matches_dir(skill_md, fm, expected_name)
    kind = require_kind(skill_md, fm)
    if kind is not None and kind != "skill":
        err(skill_md, f"file under skills/ has kind {kind!r}; must be 'skill'")
    require_supported_hosts(skill_md, fm)
    require_version(skill_md, fm)
    check_optional_scope(skill_md, fm)


def validate_standalone_agent(agent_md: Path) -> None:
    fm = parse_frontmatter(agent_md)
    if fm is None:
        return
    # For standalone agents, the manifest filename is <name>.md directly under
    # agents/. The frontmatter `name` must match the basename without .md.
    expected_name = agent_md.stem
    require_non_empty_string(agent_md, fm, "description")
    check_name_matches_dir(agent_md, fm, expected_name)
    kind = require_kind(agent_md, fm)
    if kind is not None and kind != "agent":
        err(agent_md, f"file under agents/ has kind {kind!r}; must be 'agent'")
    require_supported_hosts(agent_md, fm)
    require_version(agent_md, fm)
    check_optional_scope(agent_md, fm)


def validate_standalone_hook(hook_md: Path) -> None:
    """Hook customizations live at hooks/<name>/hook.md with sibling files:
    <name>.sh + <name>.ps1 + settings-fragment-bash.json + settings-fragment-pwsh.json.
    """
    fm = parse_frontmatter(hook_md)
    if fm is None:
        return
    hook_dir = hook_md.parent
    expected_name = hook_dir.name
    require_non_empty_string(hook_md, fm, "description")
    check_name_matches_dir(hook_md, fm, expected_name)
    kind = require_kind(hook_md, fm)
    if kind is not None and kind != "hook":
        err(hook_md, f"file under hooks/ has kind {kind!r}; must be 'hook'")
    require_supported_hosts(hook_md, fm)
    require_version(hook_md, fm)
    check_optional_scope(hook_md, fm)

    # v0.7.0: claude-code is the only host with first-class hook support.
    # If supported_hosts contains claude-code, require the bash + pwsh script
    # + bash + pwsh settings-fragment companions to exist.
    hosts = fm.get("supported_hosts", [])
    if isinstance(hosts, list) and "claude-code" in hosts:
        for required in (
            f"{expected_name}.sh",
            f"{expected_name}.ps1",
            "settings-fragment-bash.json",
            "settings-fragment-pwsh.json",
        ):
            sibling = hook_dir / required
            if not sibling.is_file():
                err(
                    hook_md,
                    f"hook '{expected_name}' missing required companion file: {sibling.relative_to(ROOT)}",
                )


# Future: add validate_standalone_<kind> for command / mcp-server / etc.


# ── main ──────────────────────────────────────────────────────────────────
def main() -> int:
    # Bundles
    for bundle_md in sorted((ROOT / "bundles").glob("*/bundle.md")):
        validate_bundle(bundle_md)

    # Standalone skills
    for skill_md in sorted((ROOT / "skills").glob("*/SKILL.md")):
        validate_standalone_skill(skill_md)

    # Standalone agents
    for agent_md in sorted((ROOT / "agents").glob("*.md")):
        validate_standalone_agent(agent_md)

    # Standalone hooks
    for hook_md in sorted((ROOT / "hooks").glob("*/hook.md")):
        validate_standalone_hook(hook_md)

    # Other standalone kinds: future-proofing — none ship yet.
    # for kind in ("command", "mcp-server", ...):
    #     for path in ...

    if errors:
        print(f"\nvalidate-manifests: {len(errors)} error(s)", file=sys.stderr)
        return 1
    bundle_count = len(list((ROOT / "bundles").glob("*/bundle.md")))
    skill_count = len(list((ROOT / "skills").glob("*/SKILL.md")))
    agent_count = len(list((ROOT / "agents").glob("*.md")))
    hook_count = len(list((ROOT / "hooks").glob("*/hook.md")))
    print(
        f"validate-manifests: clean "
        f"({bundle_count} bundle(s), {skill_count} standalone skill(s), "
        f"{agent_count} standalone agent(s), {hook_count} standalone hook(s))"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
