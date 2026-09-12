// Ralph-pi guardrail: blocks force-push in any pi session in this repo.
// Pi-native replacement for agentic-workflow/ralph/settings.ralph.json's deny
// rules (pi has no per-command permission prompts). Auto-discovered from
// .pi/extensions/ once the project is trusted (pi -a, or a saved decision).
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", (event) => {
    // Deliberately over-matching, like settings.ralph.json's prefix-denies:
    // also catches `git push --force-with-lease`.
    if (event.toolName === "bash" && /git push (\s--force|-f)/.test(event.input.command ?? "")) {
      return { block: true, reason: "force-push is not allowed in this repo" };
    }
  });
}
