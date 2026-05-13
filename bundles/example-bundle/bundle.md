---
name: example-bundle
description: Reference skeleton showing how to package a multi-primitive customization. Safe to delete in your fork; kept here as documentation.
kind: bundle
supported_hosts: [claude-code, antigravity, gemini-cli]
contents:
  - skill: example-skill
version: 0.1.0
---

# Example Bundle

This is a **reference skeleton** demonstrating how an `agent-toolkit` bundle is structured. It is intentionally a no-op — the included `example-skill` does nothing useful. Keep it for new-contributor onboarding, or delete it in your fork.

## Why bundles?

Some customizations make sense as a single primitive (one skill, one hook, one agent). Others want to package multiple primitives together — e.g. the planned `quality-gates` bundle will combine an evaluator sub-agent, a kill-switch hook, a steer hook, a commit-on-stop hook, and an evidence-tracking skill. Bundles let you install them as one unit.

## How a bundle is structured

```
bundles/example-bundle/
├── bundle.md                    # this file: manifest + description
└── skills/                      # primitives inside the bundle, organized by kind
    └── example-skill/
        └── SKILL.md             # primitive content (host-native shape)
```

The `bundle.md` is the manifest. Its `contents:` list enumerates each primitive inside. The installer (task 3) reads the manifest and dispatches each primitive to its host-specific destination per the manifest's `supported_hosts`.

## Adding to this bundle

To add a new primitive (say, a hook):

1. Create the directory: `bundles/example-bundle/hooks/<name>/`
2. Add the primitive file (e.g. `<name>.sh`)
3. Add a `contents:` entry to `bundle.md`:
   ```yaml
   contents:
     - skill: example-skill
     - hook: <name>
   ```
4. Run `python3 scripts/validate-manifests.py` (lands task 3) to confirm the new entry resolves.

## Deleting this bundle

In your fork: `git rm -r bundles/example-bundle/` and commit. The installer skips missing bundles silently.
