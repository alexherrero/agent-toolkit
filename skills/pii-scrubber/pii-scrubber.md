---
name: pii-scrubber
description: Scan the current git diff (or working tree) for personal information — emails, personal paths, API keys, phone numbers — before commit or push. Surfaces findings as file:line with redaction suggestions; loops until clean. Invoke before any git push.
kind: skill
supported_hosts: [claude-code, antigravity, gemini-cli]
version: 0.1.0
install_scope: project
---

# pii-scrubber

Agent-facing PII guardrail. Companion to `scripts/check-no-pii.sh` (the detector) and `templates/hooks/pre-push` (the mandatory enforcer at push time). This skill is the **interactive layer**: when a finding surfaces, the skill helps the agent remediate rather than just failing.

## When to invoke

- **Before any commit** that touches files visible to the user (defensive — catches PII at compose time).
- **Before any `git push`** that touches commits the user might not have seen redact-passes on (mandatory if you intend to push).
- **When the pre-push hook blocks a push** — the hook's error message will direct you here.

If you're an agent about to run `git push`, invoke this skill first. If the pre-push hook is installed and the agent-toolkit script is reachable, the hook will catch you anyway — but using the skill first means you fix the PII once, instead of fighting the hook in a loop.

## Workflow

### 1. Determine the scan range

| Situation | Range to scan |
|---|---|
| About to `git commit` | staged: `--staged` |
| About to `git push` to an existing branch | push range: `--diff <remote>..<local>` |
| About to `git push` a new branch | everything: `--all` |
| Diagnostic / general audit | everything: `--all` |

### 2. Locate and run the scanner

The script lives at `<agent-toolkit-root>/scripts/check-no-pii.sh`. Locate it via:

- `$AGENT_TOOLKIT_PATH/scripts/check-no-pii.sh` if the env var is set
- Sibling convention: `../agent-toolkit/scripts/check-no-pii.sh`
- Common dev-machine paths: `~/Antigravity/agent-toolkit/`, `~/dev/agent-toolkit/`

```bash
bash <path>/scripts/check-no-pii.sh <mode>
```

If the script isn't found, **stop and tell the user** — don't silently skip the check. Suggest: set `AGENT_TOOLKIT_PATH` or re-run `agent-toolkit/install.sh` on the target project.

### 3. Interpret exit code

- **0** → clean. Return to the user: `pii-scrubber: clean (<mode>)`. Done.
- **1** → findings on stderr. Proceed to step 4.
- **2** → argument error. Report and stop.

### 4. Surface findings

Each finding line is `file:line: <kind> match: <match>`. Present them as a numbered list:

```
1. README.md:42: email match: alice@example.com
2. docs/install.md:17: personal-path-mac match: /Users/alex/
3. scripts/run.sh:8: openai-key match: sk-abc123def456ghi789jkl
```

For each finding, propose a one-line redaction:

| Kind | Redaction strategy |
|---|---|
| `email` | Replace with `alice@example.com` / `bob@example.org` (RFC 2606 reserved domains) |
| `personal-path-*` | Replace with `<your-user>/` placeholder or `$HOME` in shell examples |
| API key shape (`openai-key`, `github-token`, `gitlab-token`, `aws-access-key`) | **Remove entirely.** Never replace with a fake — anyone copying it would have a credential-shaped placeholder. Use `<API_KEY>`, `<TOKEN>`, etc. if the example needs a stand-in. |
| `phone-us` | Replace with `555-0100` through `555-0199` (NANP reserved for fiction) |

### 5. Offer remediation

For each finding, ask the user:

> *"Redact this with the proposed strategy, leave as-is and allowlist the pattern, or override with a documented reason?"*

- **Redact:** edit the file via the host's normal edit tool. Confirm the change.
- **Allowlist:** the pattern is intentionally part of documentation (e.g. a tutorial example). Add to `.gitleaks.toml` `[allowlist].regexes` or `scripts/check-no-pii.sh`'s `ALLOWLIST_PATTERNS=`. Document the reason in the commit.
- **Override:** the finding is a true false-positive that doesn't fit either of the above. Log it (§6).

### 6. Override protocol

If the user explicitly wants to skip a finding (not redact, not allowlist):

1. Confirm the user's reason in their own words.
2. Append to `.harness/.pii-overrides.log` (create if absent):
   ```
   <ISO-8601 timestamp> | <file:line> | <kind> | <match redacted to 8 chars> | <reason>
   ```
   Example:
   ```
   2026-05-12T15:30:00Z | docs/example.md:14 | email | bob@exam… | Used as a documentation example in a tutorial about email validation
   ```
3. The override file is itself scanned by CI — any entry triggers a review reminder on the next CI run.
4. **There is no silent suppression.** Every override is visible.

### 7. Re-scan and loop

After remediation, re-run:

```bash
bash <path>/scripts/check-no-pii.sh <mode>
```

If still non-zero, loop back to step 4. If clean (exit 0), return to the user with:

```
pii-scrubber: clean (<N> redactions, <M> allowlists added, <K> overrides logged)
```

## Output contract

On initial clean:
```
pii-scrubber: clean (<mode>)
```

On clean-after-remediation:
```
pii-scrubber: clean (<mode>; <N> redactions, <M> allowlists, <K> overrides logged to .harness/.pii-overrides.log)
```

On abort (user declined to address findings):
```
pii-scrubber: ABORTED — <N> finding(s) unaddressed. Do NOT push.
  See .pii-scrubber-pending.txt for the pending list.
```

The skill writes pending findings to `.pii-scrubber-pending.txt` (gitignored) so the next session can resume.

## Hard rules

- **Do not bypass findings silently.** Every finding must be redacted, allowlisted, or overridden with a logged reason. There is no fourth option.
- **Do not invent the override reason.** The user states the reason; the skill records it verbatim.
- **Do not remove items from `.harness/.pii-overrides.log`.** It's append-only; CI reads it.
- **Do not edit the scanner script or `.gitleaks.toml` without user direction.** If a pattern is wrong, surface it; the user updates the config.
- **The pre-push hook is the final enforcer.** This skill is a courtesy layer that helps the agent fix PII *before* the hook blocks. The hook will catch anything that bypasses the skill.

## Failure modes

- **Script not found** → stop, tell the user, suggest fix. Do not silently degrade.
- **User declines all remediation** → abort and write pending findings to `.pii-scrubber-pending.txt`; tell the user not to push.
- **Re-scan still non-zero after edits** → the edit didn't address the finding (or introduced new ones). Show the remaining findings and offer remediation again.
- **Override-log path not writeable** → abort and tell the user; do not silently drop the override.
