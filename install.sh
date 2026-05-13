#!/usr/bin/env bash
# install.sh — agent-toolkit installer.
#
# Installs personal agent customizations (skills, sub-agents, hooks, MCP
# servers, slash commands, etc.) into a target project under host-specific
# paths (.claude/, .agent/, .gemini/). Also installs a pre-push git hook
# that runs check-no-pii.sh against every push.
#
# Usage:
#   install.sh [OPTIONS] <target-project-path>
#
# Options:
#   --bundle <name>          install one bundle (instead of all)
#   --skill <name>           install one standalone skill (instead of all)
#   --agent <name>           install one standalone agent (instead of all)
#   --all                    install everything (default)
#   --update                 true-sync; wipe and recreate managed dirs
#   --no-pre-push-hook       skip pre-push hook installation
#   --help, -h               print this help and exit

set -euo pipefail

# ── argument parsing ──────────────────────────────────────────────────────
TARGET=""
MODE_ALL=1
SELECT_BUNDLE=""
SELECT_SKILL=""
SELECT_AGENT=""
UPDATE_MODE=0
NO_PRE_PUSH_HOOK=0

print_help() {
    sed -n '/^# install.sh/,/^[^#]/p' "$0" | sed 's|^# \?||' | head -n -1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all) MODE_ALL=1; SELECT_BUNDLE=""; SELECT_SKILL=""; SELECT_AGENT=""; shift ;;
        --bundle)
            MODE_ALL=0; SELECT_BUNDLE="${2:-}"
            [[ -z "$SELECT_BUNDLE" ]] && { echo "--bundle requires a name" >&2; exit 2; }
            shift 2
            ;;
        --skill)
            MODE_ALL=0; SELECT_SKILL="${2:-}"
            [[ -z "$SELECT_SKILL" ]] && { echo "--skill requires a name" >&2; exit 2; }
            shift 2
            ;;
        --agent)
            MODE_ALL=0; SELECT_AGENT="${2:-}"
            [[ -z "$SELECT_AGENT" ]] && { echo "--agent requires a name" >&2; exit 2; }
            shift 2
            ;;
        --update) UPDATE_MODE=1; shift ;;
        --no-pre-push-hook) NO_PRE_PUSH_HOOK=1; shift ;;
        --help|-h) print_help; exit 0 ;;
        --*) echo "Unknown option: $1" >&2; echo "" >&2; print_help >&2; exit 2 ;;
        *)
            if [[ -z "$TARGET" ]]; then
                TARGET="$1"; shift
            else
                echo "Unexpected positional argument: $1 (target already set to: $TARGET)" >&2
                exit 2
            fi
            ;;
    esac
done

if [[ -z "$TARGET" ]]; then
    echo "Error: <target-project-path> is required" >&2
    echo "" >&2
    print_help >&2
    exit 2
fi

if [[ ! -d "$TARGET" ]]; then
    echo "Error: target directory does not exist: $TARGET" >&2
    exit 1
fi
TARGET="$(cd "$TARGET" && pwd)"

# ── locate toolkit root ───────────────────────────────────────────────────
TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── source shared install plumbing ────────────────────────────────────────
# The lib reads two caller-set variables:
#   UPDATE_MODE     — already set above
#   BOUNDARY_ROOTS  — allowed cp source roots (everything under these)
BOUNDARY_ROOTS=(
    "$TOOLKIT_ROOT/skills"
    "$TOOLKIT_ROOT/commands"
    "$TOOLKIT_ROOT/agents"
    "$TOOLKIT_ROOT/hooks"
    "$TOOLKIT_ROOT/mcp-servers"
    "$TOOLKIT_ROOT/bundles"
    "$TOOLKIT_ROOT/status-line"
    "$TOOLKIT_ROOT/output-styles"
    "$TOOLKIT_ROOT/workflows"
    "$TOOLKIT_ROOT/rules"
    "$TOOLKIT_ROOT/snippets"
    "$TOOLKIT_ROOT/settings-fragments"
    "$TOOLKIT_ROOT/templates"
)

# shellcheck source=lib/install/bash/primitives.sh
. "$TOOLKIT_ROOT/lib/install/bash/primitives.sh"

# ── operate from inside target dir ────────────────────────────────────────
cd "$TARGET"

echo "==> agent-toolkit install: $TARGET"

# ── --update sync ─────────────────────────────────────────────────────────
# Managed parents the toolkit creates in a target. Each installed
# customization lands under one of these; wiping them on --update gives
# true-sync semantics.
#
# Note on .claude/agents and .gemini/agents: these parents are also written
# to by the sibling agentic-harness installer (for explorer / adversarial-
# reviewer / documenter). When both repos are installed into the same target,
# users must run BOTH installers (in either order) to land the full set; the
# LATER-run installer's --update wipes the parent before recreating from its
# own source. Documented in agent-toolkit/wiki/reference/Installer-CLI.md.
MANAGED_PARENTS=(
    .claude/skills
    .agent/skills
    .agents/skills
    .claude/agents
    .gemini/agents
)
EMPTY_PARENT_CANDIDATES=(
    .agents
)

if [[ $UPDATE_MODE -eq 1 ]]; then
    echo "==> sync mode: wiping toolkit-managed dirs before recreate from source"
    sync_managed_parents \
        "${MANAGED_PARENTS[@]}" \
        -- \
        "${EMPTY_PARENT_CANDIDATES[@]}"
fi

# ── helpers ───────────────────────────────────────────────────────────────

# get_field <manifest-path> <field>
# Reads a YAML frontmatter field via scripts/manifest-info.py.
get_field() {
    local file="$1" field="$2"
    python3 "$TOOLKIT_ROOT/scripts/manifest-info.py" "$file" "$field"
}

# install_skill <source-dir> <skill-name> <comma-separated-hosts>
# Dispatches a skill to per-host destinations under the current dir ($TARGET).
install_skill() {
    local src_dir="$1" name="$2" hosts="$3"
    IFS=',' read -ra host_array <<< "$hosts"
    local host
    for host in "${host_array[@]}"; do
        # Strip whitespace
        host="${host// /}"
        [[ -z "$host" ]] && continue
        case "$host" in
            claude-code)
                mkdir -p .claude/skills
                cp_managed_dir "$src_dir" ".claude/skills/$name"
                ;;
            antigravity)
                mkdir -p .agent/skills
                cp_managed_dir "$src_dir" ".agent/skills/$name"
                ;;
            gemini-cli)
                mkdir -p .agents/skills
                cp_managed_dir "$src_dir" ".agents/skills/$name"
                ;;
            *)
                echo "    warning: unknown host '$host' for skill '$name' — skipped" >&2
                ;;
        esac
    done
}

# install_agent <source-file> <agent-name> <comma-separated-hosts>
# Dispatches an agent to per-host destinations. Source is a single .md file
# (agents are file-level, not dir-level — except for antigravity which has
# no first-class sub-agent surface and gets the agent wrapped as a skill
# at .agent/skills/<name>/SKILL.md per the locked per-host paths table).
install_agent() {
    local src_file="$1" name="$2" hosts="$3"
    IFS=',' read -ra host_array <<< "$hosts"
    local host
    for host in "${host_array[@]}"; do
        host="${host// /}"
        [[ -z "$host" ]] && continue
        case "$host" in
            claude-code)
                mkdir -p .claude/agents
                cp_managed "$src_file" ".claude/agents/$name.md"
                ;;
            antigravity)
                mkdir -p ".agent/skills/$name"
                cp_managed "$src_file" ".agent/skills/$name/SKILL.md"
                ;;
            gemini-cli)
                mkdir -p .gemini/agents
                cp_managed "$src_file" ".gemini/agents/$name.md"
                ;;
            *)
                echo "    warning: unknown host '$host' for agent '$name' — skipped" >&2
                ;;
        esac
    done
}

# install_pre_push_hook
# Copies templates/hooks/pre-push → <target>/.git/hooks/pre-push.
# Skips if --no-pre-push-hook or target isn't a git repo.
# Backs up any existing non-matching hook to .agent-toolkit-bak.<timestamp>.
install_pre_push_hook() {
    if [[ $NO_PRE_PUSH_HOOK -eq 1 ]]; then
        echo "  skipping pre-push hook (--no-pre-push-hook)"
        return 0
    fi
    if [[ ! -d .git ]]; then
        echo "  skipping pre-push hook (target is not a git repo)" >&2
        return 0
    fi
    local hook_src="$TOOLKIT_ROOT/templates/hooks/pre-push"
    local hook_dst=".git/hooks/pre-push"
    if [[ ! -f "$hook_src" ]]; then
        echo "  WARNING: hook template not found at $hook_src — pre-push hook not installed" >&2
        return 0
    fi
    if [[ -e "$hook_dst" ]]; then
        if cmp -s "$hook_src" "$hook_dst"; then
            echo "    kept    $hook_dst (already managed by agent-toolkit)"
            return 0
        fi
        local bak="${hook_dst}.agent-toolkit-bak.$(date +%s)"
        cp "$hook_dst" "$bak"
        echo "    backed up existing $hook_dst → $bak"
    fi
    cp "$hook_src" "$hook_dst"
    chmod +x "$hook_dst"
    echo "    installed $hook_dst"
}

# warn_unsupported_kind <kind>
warn_unsupported_kind() {
    echo "    warning: kind '$1' is not yet supported in agent-toolkit v0.1.0 — skipped" >&2
}

# ── install bundles ───────────────────────────────────────────────────────
install_bundles() {
    local bundle_md bundle_dir bundle_name hosts kind
    for bundle_md in "$TOOLKIT_ROOT"/bundles/*/bundle.md; do
        [[ -f "$bundle_md" ]] || continue
        bundle_dir="$(dirname "$bundle_md")"
        bundle_name="$(basename "$bundle_dir")"
        if [[ $MODE_ALL -eq 0 && -n "$SELECT_BUNDLE" && "$SELECT_BUNDLE" != "$bundle_name" ]]; then
            continue
        fi
        echo "==> installing bundle: $bundle_name"
        hosts="$(get_field "$bundle_md" supported_hosts)"
        if [[ -z "$hosts" ]]; then
            echo "    warning: bundle '$bundle_name' has no supported_hosts — skipped" >&2
            continue
        fi

        # v0.6.0: handle skill + agent kinds inside bundles. Other kinds are stubs.
        if [[ -d "$bundle_dir/skills" ]]; then
            local skill_dir skill_name
            for skill_dir in "$bundle_dir"/skills/*/; do
                [[ -d "$skill_dir" ]] || continue
                skill_name="$(basename "$skill_dir")"
                install_skill "${skill_dir%/}" "$skill_name" "$hosts"
            done
        fi
        if [[ -d "$bundle_dir/agents" ]]; then
            local agent_md inner_agent_name
            for agent_md in "$bundle_dir"/agents/*.md; do
                [[ -f "$agent_md" ]] || continue
                inner_agent_name="$(basename "$agent_md" .md)"
                install_agent "$agent_md" "$inner_agent_name" "$hosts"
            done
        fi
        # Future: iterate other kind subdirs (commands/, hooks/, etc.)
        for other in commands hooks mcp-servers status-line output-styles workflows rules snippets settings-fragments; do
            if [[ -d "$bundle_dir/$other" ]] && [[ -n "$(ls -A "$bundle_dir/$other" 2>/dev/null)" ]]; then
                warn_unsupported_kind "$other"
            fi
        done
    done
}

# ── install standalone skills ─────────────────────────────────────────────
install_standalone_skills() {
    local skill_md skill_dir skill_name hosts kind
    for skill_md in "$TOOLKIT_ROOT"/skills/*/SKILL.md; do
        [[ -f "$skill_md" ]] || continue
        skill_dir="$(dirname "$skill_md")"
        skill_name="$(basename "$skill_dir")"
        if [[ $MODE_ALL -eq 0 && -n "$SELECT_SKILL" && "$SELECT_SKILL" != "$skill_name" ]]; then
            continue
        fi
        kind="$(get_field "$skill_md" kind)"
        if [[ "$kind" != "skill" ]]; then
            echo "    warning: $skill_md has kind '$kind' (expected 'skill') — skipped" >&2
            continue
        fi
        hosts="$(get_field "$skill_md" supported_hosts)"
        if [[ -z "$hosts" ]]; then
            echo "    warning: skill '$skill_name' has no supported_hosts — skipped" >&2
            continue
        fi
        echo "==> installing skill: $skill_name"
        install_skill "$skill_dir" "$skill_name" "$hosts"
    done
}

# ── install standalone agents ─────────────────────────────────────────────
install_standalone_agents() {
    local agent_md agent_name hosts kind
    for agent_md in "$TOOLKIT_ROOT"/agents/*.md; do
        [[ -f "$agent_md" ]] || continue
        agent_name="$(basename "$agent_md" .md)"
        if [[ $MODE_ALL -eq 0 && -n "$SELECT_AGENT" && "$SELECT_AGENT" != "$agent_name" ]]; then
            continue
        fi
        kind="$(get_field "$agent_md" kind)"
        if [[ "$kind" != "agent" ]]; then
            echo "    warning: $agent_md has kind '$kind' (expected 'agent') — skipped" >&2
            continue
        fi
        hosts="$(get_field "$agent_md" supported_hosts)"
        if [[ -z "$hosts" ]]; then
            echo "    warning: agent '$agent_name' has no supported_hosts — skipped" >&2
            continue
        fi
        echo "==> installing agent: $agent_name"
        install_agent "$agent_md" "$agent_name" "$hosts"
    done
}

# ── warn about other unsupported kinds at top level ───────────────────────
warn_unsupported_top_level() {
    local kind
    for kind in commands hooks mcp-servers status-line output-styles workflows rules snippets settings-fragments; do
        if [[ -d "$TOOLKIT_ROOT/$kind" ]] && find "$TOOLKIT_ROOT/$kind" -mindepth 1 -not -name '.gitkeep' -print -quit 2>/dev/null | grep -q .; then
            warn_unsupported_kind "$kind"
        fi
    done
}

# ── run ───────────────────────────────────────────────────────────────────
if [[ $MODE_ALL -eq 1 || -n "$SELECT_BUNDLE" ]]; then
    install_bundles
fi

if [[ $MODE_ALL -eq 1 || -n "$SELECT_SKILL" ]]; then
    install_standalone_skills
fi

if [[ $MODE_ALL -eq 1 || -n "$SELECT_AGENT" ]]; then
    install_standalone_agents
fi

if [[ $MODE_ALL -eq 1 ]]; then
    warn_unsupported_top_level
fi

echo "==> pre-push hook"
install_pre_push_hook

echo ""
echo "agent-toolkit install: complete."
