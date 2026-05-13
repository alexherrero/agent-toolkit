# install.ps1 — agent-toolkit installer (STUB — fleshed out in task 3 of v0.1.0 plan).
#
# When complete, this installs `agent-toolkit` customizations into a target project.
# Planned usage:
#   pwsh -NoProfile -File install.ps1 [-Bundle <name>] [-Skill <name>] [-All] [-Update] [-NoPrePushHook] <target-project-path>
#
# Today: stub. Print explanation and exit non-zero so accidental use surfaces.

Write-Error @"
agent-toolkit install.ps1 — not yet implemented (stub from task 1 scaffold).

The full installer body lands in task 3 of the v0.1.0 plan. Until then, customizations
in this repo are not auto-deliverable. Inspect them by hand or wait for v0.1.0.

Planned parameters:
  -Bundle <name>           install one bundle
  -Skill <name>            install one standalone skill
  -All                     install everything (default)
  -Update                  true-sync; wipe and recreate managed dirs
  -NoPrePushHook           skip pre-push hook installation
  <target-project-path>    target project (positional)
"@
exit 2
