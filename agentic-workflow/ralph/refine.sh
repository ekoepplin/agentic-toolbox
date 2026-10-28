#!/bin/bash
# Refine (Claude Opus): turn one ticket into a stamped execution plan that the
# pi loop accepts. Opus reads the ticket, its comments and the code, and
# writes `## Execution plan` + `## Verify` into the issue body
# (prompt-refine.md). Scripted plan gates, not a model, then check the plan;
# green -> plan-stamp.sh stamps it. Red -> Opus re-refines with the gate
# output, at most twice, then the ticket goes to the owner (ready-for-human).
# A plan over the size limit must be split into child tickets instead; a
# ticket whose runtime gate only runs on the Mac goes to the owner at once.
#
# Run it from the root of the target repo, like pi-afk.sh.
#
# Exit: 0 plan stamped, or ticket split into child tickets
#       1 handed to the owner (ready-for-human) · 2 bad args / no access
#
# See docs/harnesses/pi-agent-harness/ralph-on-pi.md -> Refine.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() {
  echo "Usage: $0 <issue-number> [--model NAME]   (default model: opus)" >&2
  exit 2
}

ISSUE="${1:-}"
[[ "$ISSUE" =~ ^[0-9]+$ ]] || usage
shift
MODEL=opus
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) [[ $# -ge 2 && -n "$2" ]] || usage; MODEL="$2"; shift 2 ;;
    *) usage ;;
  esac
done

REREFINES=2          # re-refines after the first attempt
MAX_FILES=6          # plan size limit: files in the files block ...
MAX_LINES=60         # ... and non-blank lines in Execution plan + Verify

ralph_target
AS_BOT="$RALPH_ROOT/.devcontainer/as-bot.sh"
LOG="$(mktemp "${TMPDIR:-/tmp}/ralph-refine.XXXXXX")"
trap 'rm -f "$LOG"' EXIT

# A Verify command whose gate only works on the Mac (docs/harnesses/dock-e2e.md,
# "Running the gates inside a workbench"): make image / probe / probe-dock /
# dock-e2e, docker compose. `make -o image probe` runs in a workbench.
mac_only() {
  local seg args rest re_any='docker[[:space:]-]compose|dock-e2e'
  local re_img='[[:space:]](image|probe-dock)[[:space:]]' re_probe='[[:space:]]probe[[:space:]]'
  [[ "$1" =~ $re_any ]] && return 0
  while IFS= read -r seg; do
    seg="${seg#"${seg%%[![:space:]]*}"}"
    [[ "$seg" == "make "* ]] || continue
    args=" ${seg#make } "
    rest="$(printf '%s' "$args" | sed -E 's/[[:space:]]-o[[:space:]]*image[[:space:]]/ /g')"
    [[ "$rest" =~ $re_img ]] && return 0
    [[ "$rest" == "$args" && "$rest" =~ $re_probe ]] && return 0
  done <<EOF
$(printf '%s\n' "$1" | tr ';&|' '\n\n\n')
EOF
  return 1
}

# The plan gates. Appends findings to $3; returns 0 green, 1 red, 3 when the
# ticket needs a Mac-side gate.
plan_gates() {
  local body="$1" base="$2" log="$3" problem f n lines cmd tag ac i wt rc=0
  local re_tag='#[[:space:]]*((AC[0-9]+[[:space:],]*)+|guard)[[:space:]]*$'
  local red=" " criteria
  fail() { printf -- '- %s\n' "$*" >> "$log"; rc=1; }

  if ! problem="$(ralph_plan_problem "$body" unstamped)"; then
    fail "structure: $problem"; return 1
  fi
  for f in 'Execution plan' 'Verify'; do
    n="$(printf '%s\n' "$body" | grep -c "^## $f[[:space:]]*\$" || true)"
    [[ "$n" -eq 1 ]] || fail "$n '## $f' sections — replace the plan, never append a second one"
  done
  while IFS= read -r f; do
    git -C "$PROJECT_ROOT" cat-file -e "$base:$f" 2>/dev/null && continue
    printf '%s\n' "$body" | awk -v f="$f" '
      { sub(/^[ \t]+/, ""); sub(/[ \t]+$/, "") }
      index($0, f) == 1 && substr($0, length(f) + 1) ~ /^[ \t]+\(new\)$/ { found = 1 }
      END { exit !found }' || fail "files: '$f' does not exist at ${base:0:7} and is not marked (new)"
  done <<EOF
$(ralph_plan_files "$body")
EOF
  printf '%s\n' "$body" | awk '
    /^## / { in_plan = ($0 ~ /^## Execution plan[[:space:]]*$/); next }
    in_plan && tolower($0) ~ /out of scope/ { found = 1 }
    END { exit !found }' || fail "the Execution plan does not state what is out of scope"
  n="$(ralph_plan_files "$body" | wc -l | tr -d ' ')"
  lines="$(printf '%s\n' "$body" | awk '
    /^## / { keep = ($0 ~ /^## (Execution plan|Verify)[[:space:]]*$/); next }
    keep && $0 !~ /^[[:space:]]*$/ && $0 !~ /^<!-- ralph:plan / { c++ }
    END { print c + 0 }')"
  if [[ "$n" -gt $MAX_FILES || "$lines" -gt $MAX_LINES ]]; then
    fail "oversized: $n files (limit $MAX_FILES), $lines plan lines (limit $MAX_LINES) — split the ticket into child tickets instead of planning it"
  fi

  criteria="$(printf '%s\n' "$body" | awk '
    /^## / { in_ac = ($0 ~ /^## Acceptance criteria[[:space:]]*$/); next }
    in_ac && /^[[:space:]]*[-*] \[[ xX]\]/ { sub(/^[[:space:]]*[-*] \[[ xX]\][[:space:]]*/, ""); print }')"
  [[ -n "$criteria" ]] || fail "no '- [ ]' items under '## Acceptance criteria'"

  wt="$(mktemp -d "${TMPDIR:-/tmp}/ralph-refine-base.XXXXXX")"
  git -C "$PROJECT_ROOT" worktree add -q --detach "$wt" "$base" || { rm -rf "$wt"; fail "cannot check out base $base"; return 1; }
  while IFS= read -r cmd; do
    if mac_only "$cmd"; then
      printf -- '- Verify `%s` needs a gate that only runs on the Mac (make image/probe/dock-e2e)\n' "$cmd" >> "$log"
      git -C "$PROJECT_ROOT" worktree remove --force "$wt"
      return 3
    fi
    if ! [[ "$cmd" =~ $re_tag ]]; then
      fail "Verify \`$cmd\` has no '# AC<n>' or '# guard' tag"; continue
    fi
    tag="${BASH_REMATCH[1]}"
    [[ "$tag" == guard ]] && continue
    if (cd "$wt" && bash -c "$cmd" < /dev/null) > /dev/null 2>&1; then
      fail "Verify \`$cmd\` is green on base ${base:0:7} — it cannot prove $tag"
    else
      for ac in $(printf '%s' "$tag" | tr ',' ' '); do red="$red$ac "; done
    fi
  done <<EOF
$(ralph_verify_cmds "$body")
EOF
  git -C "$PROJECT_ROOT" worktree remove --force "$wt"

  i=0
  while IFS= read -r ac; do
    [[ -n "$ac" ]] || continue
    i=$((i + 1))
    [[ "$red" == *" AC$i "* ]] || fail "AC$i ($ac) has no Verify command that is red on base"
  done <<EOF
$criteria
EOF
  return "$rc"
}

to_owner() {
  ralph_gh issue comment "$ISSUE" --repo "$REPO" --body "$(printf 'refine: %s — handing this ticket to the owner.\n\n%s\n' "$1" "$(cat "$LOG")")" >/dev/null
  ralph_gh issue edit "$ISSUE" --repo "$REPO" --add-label ready-for-human --remove-label ready-for-agent >/dev/null
  echo "refine: #$ISSUE: $1 — labelled ready-for-human" >&2
  exit 1
}

: > "$LOG"
for ((attempt = 1; attempt <= REREFINES + 1; attempt++)); do
  "$AS_BOT" git -C "$PROJECT_ROOT" fetch -q origin "$DEFAULT_BRANCH"
  base="$(git -C "$PROJECT_ROOT" rev-parse "origin/$DEFAULT_BRANCH")"
  echo "=== refine #$ISSUE attempt $attempt/$((REREFINES + 1)) (base ${base:0:7}) ===" >&2

  ticket="$(ralph_gh issue view "$ISSUE" --repo "$REPO" --json number,title,body,labels,comments \
    --jq '"# Issue #\(.number): \(.title)\nLabels: \(.labels | map(.name) | join(", "))\n\n\(.body)\n\n# Comments\n\n\(.comments | map("## \(.author.login) (\(.createdAt))\n\n\(.body)") | join("\n\n"))"')"
  mission="$(printf 'MISSION: refine issue #%s of %s against base %s (origin/%s). Size limit: %s files, %s plan lines.\n\n%s\n\n%s' \
    "$ISSUE" "$REPO" "$base" "$DEFAULT_BRANCH" "$MAX_FILES" "$MAX_LINES" "$ticket" "$(cat "$RALPH_DIR/prompt-refine.md")")"
  if [[ -s "$LOG" ]]; then
    mission="$mission"$'\n\n# PREVIOUS ATTEMPT\n\nThe plan gates rejected your last attempt:\n\n'"$(cat "$LOG")"
  fi

  out="$(unset ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL
    "$AS_BOT" claude -p --settings "$RALPH_DIR/settings.ralph.json" \
      --permission-mode acceptEdits --model "$MODEL" "$mission")" || true
  printf '%s\n' "$out" >&2
  verdict="$(printf '%s\n' "$out" | grep '^RALPH-REFINE: ' | tail -n1 || true)"
  : > "$LOG"
  case "$verdict" in
    "RALPH-REFINE: human"*)
      printf -- '- Opus: %s\n' "${verdict#RALPH-REFINE: human}" >> "$LOG"
      to_owner "Opus routed it to the owner" ;;
    "RALPH-REFINE: split"*)
      children="$(printf '%s\n' "${verdict#RALPH-REFINE: split}" | grep -oE '[0-9]+' || true)"
      [[ -n "$children" ]] || printf -- '- split verdict names no child issue\n' >> "$LOG"
      printf '%s\n' "$(ralph_issue_body "$ISSUE")" | grep -q '^## Execution plan[[:space:]]*$' \
        && printf -- '- split, but #%s still carries an Execution plan — remove it\n' "$ISSUE" >> "$LOG"
      for c in $children; do
        ralph_issue_body "$c" 2>/dev/null | grep -qE "#$ISSUE([^0-9]|\$)" \
          || printf -- '- child #%s does not exist or does not reference #%s as its parent\n' "$c" "$ISSUE" >> "$LOG"
      done
      if [[ ! -s "$LOG" ]]; then
        ralph_gh issue comment "$ISSUE" --repo "$REPO" --body "refine: over the plan size limit — split into $(printf '#%s ' $children)" >/dev/null
        echo "refine: #$ISSUE split into $(printf '#%s ' $children)" >&2
        exit 0
      fi ;;
    "RALPH-REFINE: plan"*)
      rc=0
      plan_gates "$(ralph_issue_body "$ISSUE")" "$base" "$LOG" || rc=$?
      [[ $rc -ne 3 ]] || to_owner "its runtime gate only runs on the Mac"
      if [[ $rc -eq 0 ]]; then
        "$RALPH_DIR/plan-stamp.sh" "$ISSUE"
        exit 0
      fi ;;
    *) printf -- '- no RALPH-REFINE verdict line in your reply\n' >> "$LOG" ;;
  esac
  echo "refine: #$ISSUE attempt $attempt rejected:" >&2
  cat "$LOG" >&2
done
to_owner "the plan gates are still red after $REREFINES re-refines"
