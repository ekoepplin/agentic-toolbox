# shellcheck shell=bash
# Shared plumbing for the ralph loop scripts — sourced, not executed.
#
#   once.sh / pi-once.sh   one iteration on one issue (Claude Code / pi)
#   afk.sh                 loop once.sh until the issue closes
#   pi-afk.sh              loop pi-once.sh until the harness-run Verify is
#                          green, then push + open a PR (never merge)
#
# Stays bash 3.2-compatible, so the loop also runs on a bare Mac.

RALPH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The base repo: it supplies these scripts, as-bot and .env.ralph. The repo the
# loop works on is the target (ralph_target) — a host project or the base.
RALPH_ROOT="$(cd "$RALPH_DIR/../.." && pwd)"

# An AFK loop must never wait on a credential prompt: missing credentials fail.
export GIT_TERMINAL_PROMPT=0

# ralph_gh <args...> — gh with the bot's credentials when BOT_GIT_USER is set
# (inside a workbench plain gh is not logged in); plain gh otherwise.
ralph_gh() { "$RALPH_ROOT/.devcontainer/as-bot.sh" gh "$@"; }

# ralph_target — the git repo of the current directory is the target: sets
# PROJECT_ROOT (its top level), REPO (owner/name of its GitHub origin) and
# DEFAULT_BRANCH (from GitHub). Exits 2 outside a git repo or without a
# GitHub origin.
ralph_target() {
  local url r
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || { echo "ralph: $PWD is not inside a git repo — run from the target repo's root" >&2; exit 2; }
  url="$(git -C "$PROJECT_ROOT" remote get-url origin 2>/dev/null)" \
    || { echo "ralph: $PROJECT_ROOT has no origin remote" >&2; exit 2; }
  r="${url#https://github.com/}"; r="${r#git@github.com:}"; r="${r#ssh://git@github.com/}"; r="${r%.git}"; r="${r%/}"
  if [[ "$r" == "$url" || "$r" != */* || "$r" == */*/* ]]; then
    echo "ralph: origin '$url' is not a GitHub repo" >&2; exit 2
  fi
  REPO="$r"
  DEFAULT_BRANCH="$(ralph_gh repo view "$REPO" --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null)" \
    && [[ -n "$DEFAULT_BRANCH" ]] \
    || { echo "ralph: cannot read $REPO on GitHub (no access with these credentials?)" >&2; exit 2; }
}

# .env.ralph at the repo root sets RALPH_BACKEND / RALPH_MODEL defaults.
if [[ -f "$RALPH_ROOT/.env.ralph" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$RALPH_ROOT/.env.ralph"
  set +a
fi

# ralph_parse_once <args...> — sets ISSUE, BACKEND, MODEL (flag > .env.ralph >
# built-in default). Calls the sourcing script's usage() on bad input.
# shellcheck disable=SC2034  # ISSUE/BACKEND/MODEL are read by the caller
ralph_parse_once() {
  ISSUE="${1:-}"
  [[ -n "$ISSUE" ]] || usage
  shift
  BACKEND="${RALPH_BACKEND:-vllm}"
  MODEL="${RALPH_MODEL:-}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --backend | --model)
        [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || { echo "error: $1 needs a value" >&2; usage; }
        if [[ "$1" == --backend ]]; then BACKEND="$2"; else MODEL="$2"; fi
        shift 2 ;;
      -h|--help) usage ;;
      *) echo "error: unknown arg: $1" >&2; usage ;;
    esac
  done
}

ralph_bad_backend() {
  echo "error: --backend must be one of: anthropic, vllm, ollama (got '$BACKEND')" >&2
  exit 1
}

# ralph_mission <issue> <prompt-file> — the full prompt for one iteration:
# mission line, issue body, recent commits, then the loop prompt.
ralph_mission() {
  local issue commits
  issue=$(ralph_gh issue view "$1" --repo "$REPO" \
    --json number,title,body,labels,state \
    --jq '"# Issue #\(.number): \(.title)\nState: \(.state)\nLabels: \(.labels | map(.name) | join(", "))\n\n\(.body)"') \
    || return 1
  commits=$(git log -n 5 --format='%h %ad %s' --date=short) || return 1
  printf 'MISSION: deliver issue #%s of %s. Its project instructions are the CLAUDE.md / AGENTS.md at the repo root, plus its glossary and docs/adr/ when they exist. Do NOT switch to other issues even if you see references to them.\n\n%s\n\nRecent commits:\n%s\n\n%s' \
    "$1" "$REPO" "$issue" "$commits" "$(cat "$2")"
}

# ── Execution contract (pi loop) ────────────────────────────────────────────
# An issue qwen may run carries a stamped plan in its body. This is the one
# format refine (#31) writes and the only one the loop accepts:
#
#   ## Execution plan
#   steps, out of scope, …
#   ```files
#   path/to/file            one planned path per line; " (new)" may follow
#   ```
#   ## Verify
#   ```
#   one shell command per line; every one must exit 0
#   ```
#   <!-- ralph:plan base=<sha> hash=<sha256> -->
#
# hash: sha256 of the two sections, headings included, with marker lines,
# blank lines and trailing whitespace dropped (so edits elsewhere in the body
# don't count). base: origin/master when the plan was stamped. plan-stamp.sh
# writes the marker; nothing else should. The loop runs Verify itself and gates
# the diff against the files block — qwen's claim of done is never trusted.
# See docs/harnesses/pi-agent-harness/ralph-on-pi.md.

# ralph_issue_body <issue> — the issue body, CRLF-normalised.
ralph_issue_body() {
  ralph_gh issue view "$1" --repo "$REPO" --json body --jq .body | tr -d '\r'
}

# ralph_verify_cmds <body> — the commands in the first fenced block under
# `## Verify`, one per line; blank lines and `#` comments are dropped.
ralph_verify_cmds() {
  printf '%s\n' "$1" | awk '
    /^## / { in_verify = ($0 ~ /^## Verify[[:space:]]*$/); next }
    in_verify && /^```/ { if (fence) exit; fence = 1; next }
    fence && $0 !~ /^[[:space:]]*(#|$)/ { print }
  '
}

# ralph_plan_files <body> — the paths in the first ```files block of the
# `## Execution plan` section, one per line (a trailing " (new)" is dropped).
ralph_plan_files() {
  printf '%s\n' "$1" | awk '
    /^## / { in_plan = ($0 ~ /^## Execution plan[[:space:]]*$/); next }
    in_plan && !fence && /^```files[[:space:]]*$/ { fence = 1; next }
    fence && /^```/ { exit }
    fence {
      sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, ""); sub(/[[:space:]]+\(new\)$/, "")
      if ($0 != "" && $0 !~ /^#/) print
    }
  '
}

# ralph_plan_hash <body> — the plan hash (see the format above).
ralph_plan_hash() {
  printf '%s\n' "$1" | awk '
    /^## / { keep = ($0 ~ /^## (Execution plan|Verify)[[:space:]]*$/) }
    keep && $0 !~ /^<!-- ralph:plan / { sub(/[[:space:]]+$/, ""); if ($0 != "") print }
  ' | python3 -c 'import hashlib, sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())'
}

# ralph_plan_marker <body> — "<base> <hash>" from the marker, empty if none.
ralph_plan_marker() {
  printf '%s\n' "$1" | sed -n 's/^<!-- ralph:plan base=\([0-9a-f]*\) hash=\([0-9a-f]*\) -->[[:space:]]*$/\1 \2/p' | head -n1
}

# ralph_plan_problem <body> [unstamped] — prints why the body is not a
# runnable plan and returns 1; returns 0 silently when it is. With
# "unstamped", the marker is not required (plan-stamp.sh's precheck).
ralph_plan_problem() {
  local marker
  if ! printf '%s\n' "$1" | grep -q '^## Execution plan[[:space:]]*$'; then
    echo "no '## Execution plan' section"; return 1
  fi
  [[ -n "$(ralph_verify_cmds "$1")" ]] || { echo "no command in the '## Verify' block"; return 1; }
  [[ -n "$(ralph_plan_files "$1")" ]] || { echo "no \`\`\`files block in the plan"; return 1; }
  [[ "${2:-}" == unstamped ]] && return 0
  marker="$(ralph_plan_marker "$1")"
  [[ -n "$marker" ]] || { echo "the plan is not stamped (no ralph:plan marker; run plan-stamp.sh)"; return 1; }
  if [[ "${marker#* }" != "$(ralph_plan_hash "$1")" ]]; then
    echo "the plan changed since it was stamped (hash mismatch) — re-refine or re-stamp it"; return 1
  fi
}

# ralph_require_plan <issue> — exits 2 unless the issue carries a stamped,
# unchanged plan; on success sets PLAN_BODY to the body it checked.
ralph_require_plan() {
  local problem
  PLAN_BODY="$(ralph_issue_body "$1")" || { echo "error: cannot read issue #$1" >&2; exit 2; }
  if ! problem="$(ralph_plan_problem "$PLAN_BODY")"; then
    echo "ralph: issue #$1: $problem — refusing to run qwen." >&2
    exit 2
  fi
}

# ralph_require_bot — exits 2 unless as-bot resolves to a bot identity whose
# token logs in as that same account. Without it qwen would commit, push and
# open PRs with the caller's own credentials — on the Mac that is the admin,
# who may bypass the master ruleset.
ralph_require_bot() {
  local user login
  user="$("$RALPH_ROOT/.devcontainer/as-bot.sh" sh -c 'printf %s "${GIT_AUTHOR_NAME:-}"')"
  if [[ -z "$user" ]]; then
    echo "ralph: no bot identity (BOT_GIT_USER/BOT_GH_TOKEN unset, no ~/.config/as-bot.env) — refusing to run qwen with your own credentials; run it in a workbench docked with BOT_* set." >&2
    exit 2
  fi
  login="$(ralph_gh api user --jq .login 2>/dev/null || true)"
  if [[ "$login" != "$user" ]]; then
    echo "ralph: bot token logs in as '${login:-nothing}', not '$user' — refusing to run qwen." >&2
    exit 2
  fi
  if [[ "$(ralph_gh api "repos/$REPO" --jq .permissions.push 2>/dev/null)" != true ]]; then
    echo "ralph: $user has no write access to $REPO — onboard the repo first (ralph-onboard.sh)." >&2
    exit 2
  fi
}

# ralph_verify <body> <ref> <log> — runs the plan's Verify commands in a
# clean, detached worktree at <ref>, so only committed work can turn them
# green. Pass the snapshot taken at the start of the run, not a fresh fetch.
# Writes each command and its output to <log>; returns 1 if any fails.
ralph_verify() {
  local cmds wt cmd rc=0
  cmds="$(ralph_verify_cmds "$1")"
  wt="$(mktemp -d "${TMPDIR:-/tmp}/ralph-verify.XXXXXX")"
  git -C "$PROJECT_ROOT" worktree add -q --detach "$wt" "$2" || { rm -rf "$wt"; return 2; }
  : > "$3"
  while IFS= read -r cmd; do
    printf '$ %s\n' "$cmd" >> "$3"
    if (cd "$wt" && bash -c "$cmd" < /dev/null) >> "$3" 2>&1; then
      printf '[ok]\n' >> "$3"
    else
      printf '[FAILED: exit %s]\n' "$?" >> "$3"
      rc=1
    fi
  done <<EOF
$cmds
EOF
  git -C "$PROJECT_ROOT" worktree remove --force "$wt"
  return "$rc"
}

# ralph_scope_gate <body> <ref> <log> — fails unless every file the branch
# changed since its merge-base with origin/<default branch> is in the plan's files
# block. That includes the scripts a Verify command calls: editing one the
# plan does not list fails here. Appends its verdict to <log>.
ralph_scope_gate() {
  local planned changed extra
  planned="$(ralph_plan_files "$1")"
  changed="$(git -C "$PROJECT_ROOT" diff --name-only --no-renames "origin/$DEFAULT_BRANCH...$2")"
  extra="$(printf '%s\n' "$changed" | grep -vxF -e "" -f <(printf '%s\n' "$planned") || true)"
  printf '$ scope gate: files changed vs origin/%s must all be in the plan\n' "$DEFAULT_BRANCH" >> "$3"
  if [[ -z "$extra" ]]; then
    printf '[ok]\n' >> "$3"
    return 0
  fi
  printf 'not in the plan (revert these):\n%s\n[FAILED]\n' "$extra" >> "$3"
  return 1
}

# ralph_afk <iteration-script> <issue> [max-iters] [flags...] — runs the
# iteration script until the issue is CLOSED or max-iters (default 10) is hit.
ralph_afk() {
  local once="$1"; shift
  local issue="${1:-}"
  if [[ -z "$issue" ]]; then
    cat >&2 <<EOF
Usage: $0 <issue-number> [max-iters] [--backend NAME] [--model NAME]

  max-iters  default: 10
  --backend  one of: anthropic | vllm | ollama (forwarded to $once)
  --model    model name for the chosen backend (forwarded to $once)
EOF
    exit 1
  fi
  shift
  local max=10 i state
  if [[ $# -gt 0 && "$1" =~ ^[0-9]+$ ]]; then
    max="$1"
    shift
  fi
  for ((i = 1; i <= max; i++)); do
    state=$(ralph_gh issue view "$issue" --repo "$REPO" --json state --jq '.state' 2>/dev/null || echo UNKNOWN)
    if [[ "$state" == "CLOSED" ]]; then
      echo "Issue #$issue is CLOSED — done in $((i - 1)) iters."
      exit 0
    fi
    echo "=== iter $i/$max on #$issue (state=$state) ==="
    "$RALPH_DIR/$once" "$issue" "$@"
    echo "=== iter $i complete ==="
  done
  echo "Hit MAX=$max iters on #$issue without closing. Inspect and resume manually."
  exit 1
}
