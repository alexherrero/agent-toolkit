# Contributing to agent-toolkit

## PII guardrails

This is a public repo. The customizations and configuration kept here are personal but **must not contain personal information that should stay private**.

### What NOT to commit

- **Email addresses** — use the GitHub handle `alexherrero` if you need an identifier; use `@example.com` / `@example.org` / `@example.net` (RFC 2606 reserved) for fake addresses in documentation.
- **Personal paths** — `/Users/<name>/`, `C:\Users\<name>\`, `/home/<name>/`. Use `<your-user>/` placeholder or `$HOME` in examples.
- **API keys / tokens** — anything matching common shapes (`sk-...`, `gho_...`, `ghp_...`, `glpat-...`, `AKIA...`). Never commit these. Use `<API_KEY>` placeholder if an example requires one.
- **Phone numbers** — use `555-0100` through `555-0199` (NANP reserved for fiction) for example phone numbers.
- **Private project names** — anything not already in your public GitHub.
- **Internal hostnames or IP addresses** — corporate VPN endpoints, dev servers, etc.

### Three-layer enforcement

| Layer | What | When it fires |
|---|---|---|
| **Pre-push git hook** | `templates/hooks/pre-push` installed into `.git/hooks/pre-push` by `agent-toolkit/install.sh` | On every `git push`. Runs `check-no-pii.sh --diff <range>`; non-zero exit blocks the push. **Mandatory enforcer.** |
| **`pii-scrubber` skill** | `skills/pii-scrubber/pii-scrubber.md` — interactive agent-facing layer | Invoked by an agent before commit / push. Presents findings, offers redactions, loops until clean. |
| **CI gate** | GitHub Actions workflow (lands in task 4 of v0.1.0 plan) | On every push to GitHub. Runs the same script + gitleaks. Final safety net. |

### How to test locally

```bash
# Scan the entire working tree
bash scripts/check-no-pii.sh --all

# Scan only staged changes (mirrors pre-commit-style check)
bash scripts/check-no-pii.sh --staged

# Scan a git range (mirrors what the pre-push hook does)
bash scripts/check-no-pii.sh --diff origin/main..HEAD

# Run gitleaks against the repo
gitleaks detect --source . --config .gitleaks.toml
```

### False positives — the override protocol

If `check-no-pii.sh` flags something that's a real false positive (e.g. a documentation example that *looks* like PII but isn't):

1. **First option:** rephrase to avoid the regex match — use `alice@example.com` instead of a realistic-looking address, `555-0100` for phone numbers, `<API_KEY>` for credential placeholders. This is almost always what you want.
2. **Second option:** if the pattern legitimately needs to look real (e.g. testing the scanner itself), add it to the allowlist:
   - For `check-no-pii.sh`: append to the `ALLOWLIST_PATTERNS=` array in the script with a comment explaining why.
   - For `gitleaks`: append to `.gitleaks.toml`'s `[allowlist].regexes` list.
   - Document the reason in the same commit message.
3. **Override (last resort):** if neither of the above fits, the `pii-scrubber` skill supports explicit override with a documented reason. The override is appended to `.harness/.pii-overrides.log` with timestamp + reason. CI surfaces every override on the next run — there is no silent suppression.

## Local gates

Run all gates before pushing (the pre-push hook will run a subset automatically; running the full set locally catches things sooner):

```bash
bash scripts/check-no-pii.sh --all
bash scripts/check-syntax.sh
python3 scripts/validate-manifests.py
bash scripts/check-lib-parity.sh
bash scripts/smoke-install-bash.sh
```

> Scripts marked "(coming)" land in later tasks of the v0.1.0 plan:
> - `check-syntax.sh` — task 3
> - `validate-manifests.py` — task 3
> - `check-lib-parity.sh` — task 2
> - `smoke-install-bash.sh` — task 4

## Commit messages

Do not append `Co-Authored-By:` trailers naming agents or models. Plain commit message only. See [AGENTS.md § Conventions § Commit messages](AGENTS.md#commit-messages) for the full rule.
