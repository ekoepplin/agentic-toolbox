// Ralph-pi guardrail: blocks force-push, merging, and pushing to the repo's
// default branch (origin/HEAD, else master) in any pi session in this repo.
// Defence in depth only — a regex over bash commands is bypassable (a script
// that runs the command, a bare `git push` while on the default branch); the
// real control is the master ruleset, which requires an
// approval from someone other than the pusher. Pi-native counterpart of
// agentic-workflow/ralph/settings.ralph.json's deny rules (pi has no
// per-command permission prompts). Auto-discovered from .pi/extensions/ once
// the project is trusted (pi -a, or a saved decision).
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { execFileSync } from "node:child_process";

// [pattern, reason]. A segment is one command up to ; & | or a newline.
export const BLOCKED: ReadonlyArray<readonly [RegExp, string]> = [
  // Any --force / -f (also bundled, e.g. -uf) within one `git push` command.
  // Deliberately over-matching: also catches `git push --force-with-lease`.
  [/\bgit\s+push\b[^;&|\n]*\s(--force\b|-[A-Za-z]*f)/, "force-push is not allowed in this repo"],
  [/\bgh\s+pr\s+merge\b/, "merging is the reviewer's job, not the agent's"],
  [/\bgh\s+api\b[^;&|\n]*\/pulls\/\d+\/merge\b/, "merging is the reviewer's job, not the agent's"],
];

// An explicit push to the default branch: `origin main`, `HEAD:main`, `HEAD:refs/heads/main`.
export function defaultBranchPattern(branch: string): RegExp {
  const b = branch.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`\\bgit\\s+push\\b[^;&|\\n]*[\\s:](refs\\/heads\\/)?${b}(\\s|$|[;&|])`);
}

export function blockReason(command: string, defaultBranch = "master"): string | undefined {
  const hit = BLOCKED.find(([re]) => re.test(command));
  if (hit) return hit[1];
  if (defaultBranchPattern(defaultBranch).test(command))
    return `pushing to ${defaultBranch} is not allowed — the loop opens a PR`;
  return undefined;
}

// Default branch of the repo in `cwd`, from the local origin/HEAD symref (no network).
export function resolveDefaultBranch(cwd: string): string {
  try {
    const ref = execFileSync("git", ["symbolic-ref", "--short", "refs/remotes/origin/HEAD"], {
      cwd, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    return ref.replace(/^origin\//, "") || "master";
  } catch {
    return "master";
  }
}

export default function (pi: ExtensionAPI) {
  const defaultBranch = resolveDefaultBranch(process.cwd());
  pi.on("tool_call", (event) => {
    if (event.toolName !== "bash") return;
    const reason = blockReason(event.input.command ?? "", defaultBranch);
    if (reason) return { block: true, reason };
  });
}
