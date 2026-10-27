// Ralph-pi guardrail: blocks force-push, merging, and pushing to master in
// any pi session in this repo. Defence in depth only — a regex over bash
// commands is bypassable (a script that runs the command, a bare `git push`
// while on master); the real control is the master ruleset, which requires an
// approval from someone other than the pusher. Pi-native counterpart of
// agentic-workflow/ralph/settings.ralph.json's deny rules (pi has no
// per-command permission prompts). Auto-discovered from .pi/extensions/ once
// the project is trusted (pi -a, or a saved decision).
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

// [pattern, reason]. A segment is one command up to ; & | or a newline.
export const BLOCKED: ReadonlyArray<readonly [RegExp, string]> = [
  // Any --force / -f (also bundled, e.g. -uf) within one `git push` command.
  // Deliberately over-matching: also catches `git push --force-with-lease`.
  [/\bgit\s+push\b[^;&|\n]*\s(--force\b|-[A-Za-z]*f)/, "force-push is not allowed in this repo"],
  // An explicit master target: `origin master`, `HEAD:master`, `HEAD:refs/heads/master`.
  [/\bgit\s+push\b[^;&|\n]*[\s:](refs\/heads\/)?master(\s|$|[;&|])/, "pushing to master is not allowed — the loop opens a PR"],
  [/\bgh\s+pr\s+merge\b/, "merging is the reviewer's job, not the agent's"],
  [/\bgh\s+api\b[^;&|\n]*\/pulls\/\d+\/merge\b/, "merging is the reviewer's job, not the agent's"],
];

export function blockReason(command: string): string | undefined {
  return BLOCKED.find(([re]) => re.test(command))?.[1];
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", (event) => {
    if (event.toolName !== "bash") return;
    const reason = blockReason(event.input.command ?? "");
    if (reason) return { block: true, reason };
  });
}
