/**
 * Hybrid orchestrator: one virtual model, three phases, roles enforced.
 *
 * Registers `hybrid/orchestrate`. Every user prompt runs through:
 *
 *   plan    Claude    explores read-only, asks you when the request is unclear, then calls
 *                     `handoff` with a plan: steps, acceptance criteria, files, Verify commands.
 *   build   local     implements the plan with full tools and stops.
 *           (script)  this extension runs the Verify commands. Red -> output back to the local
 *                     model, next round. Green -> review.
 *   review  Claude    reads the result read-only, scores each criterion 0-2 and calls `verdict`.
 *                     Fail -> feedback back to the local model, next round. Pass -> done.
 *
 * Roles are enforced, not suggested: in plan and review, `edit`, `write` and `bash` are blocked,
 * so Claude cannot quietly do the work itself (the weak spot of `hybrid-router.ts`).
 * At most HYBRID_MAX_ROUNDS build rounds per prompt.
 *
 * Fallbacks: local server down at the start of a round -> Claude builds that round. A failed local
 * request retries on Claude, and Claude finishes that round.
 * Compaction summaries go to the local model when it is up.
 *
 * Config (env):
 *   HYBRID_PLANNER     provider/id of the cloud model  (default anthropic/claude-opus-5-5)
 *   HYBRID_WORKER      provider/id of the local model  (required, e.g. gpu/qwen3.8-flash-next-a5b)
 *   HYBRID_HEALTH      URL probed to check the local server (default http://localhost:8000/v1/models)
 *   HYBRID_MAX_ROUNDS  build rounds per prompt (default 3)
 *   HYBRID_HIDDEN_VERIFY  optional file, one command per line, run after the plan's Verify.
 *                     Neither model sees it up front; a failure reaches the local model as feedback.
 *                     For demos: watch round 2 fix what round 1 missed (see hidden-verify.txt).
 *
 * Usage: HYBRID_WORKER=<provider>/<id> pi -e ./hybrid-orchestrator.ts --model hybrid/orchestrate
 *
 * Limitation: the plan and round counter live in memory. Resuming a session in the middle of a
 * build starts the next prompt in plan again.
 */

import type { ExtensionAPI, ExtensionContext, ModelRoute, ModelRouteRequest } from "@earendil-works/pi-coding-agent";
import { readFileSync } from "node:fs";
import { Type } from "typebox";

const PLANNER = process.env.HYBRID_PLANNER ?? "anthropic/claude-opus-5-5";
const WORKER = process.env.HYBRID_WORKER ?? "";
const HEALTH_URL = process.env.HYBRID_HEALTH ?? "http://localhost:8000/v1/models";
const MAX_ROUNDS = Number(process.env.HYBRID_MAX_ROUNDS ?? 3);
const HIDDEN = process.env.HYBRID_HIDDEN_VERIFY
  ? readFileSync(process.env.HYBRID_HIDDEN_VERIFY, "utf8").split("\n").filter((l) => l.trim() && !l.trim().startsWith("#"))
  : [];
const HEALTH_TTL_MS = 30_000;
const VERIFY_TIMEOUT_MS = 120_000;

type Phase = "plan" | "build" | "review";
interface State {
  phase: Phase;
}

/** Tools Claude may use in plan and review. Everything that changes files is blocked. */
const BLOCKED_FOR_CLAUDE = new Set(["edit", "write", "bash"]);
const READ_TOOLS = ["read", "grep", "find", "ls"];

let phase: Phase = "plan";
let pending: Phase | undefined; // set by a tool or the Verify step, applied on the next request
let round = 0;
let builder = WORKER; // model of the current build round
let verify: string[] = [];
let criteria: string[] = [];
let reminded = false;
let health: { ok: boolean; at: number } | undefined;

/** Cached probe of the local server, so a dead tunnel costs at most one short timeout per 30s. */
async function localIsUp(): Promise<boolean> {
  if (health && Date.now() - health.at < HEALTH_TTL_MS) return health.ok;
  let ok = false;
  try {
    ok = (await fetch(HEALTH_URL, { signal: AbortSignal.timeout(3000) })).ok;
  } catch {
    ok = false;
  }
  health = { ok, at: Date.now() };
  return ok;
}

function find(ctx: ExtensionContext, ref: string) {
  const [provider, ...rest] = ref.split("/");
  const model = ctx.modelRegistry.find(provider, rest.join("/"));
  if (!model) throw new Error(`hybrid-orchestrator: model ${ref} is not in the catalog`);
  return model;
}

function isSame(model: { provider: string; id: string } | undefined, ref: string): boolean {
  return model !== undefined && `${model.provider}/${model.id}` === ref;
}

function status(ctx: ExtensionContext) {
  if (!ctx.hasUI) return;
  const who = phase === "build" && builder === WORKER ? "local" : "Claude";
  ctx.ui.setStatus("hybrid", `${phase}${round ? ` · round ${round}/${MAX_ROUNDS}` : ""} · ${who}`);
}

const text = (t: string) => [{ type: "text" as const, text: t }];
const list = (items: string[]) => items.map((s, i) => `${i + 1}. ${s}`).join("\n");

export default function (pi: ExtensionAPI) {
  if (!WORKER) throw new Error("hybrid-orchestrator: set HYBRID_WORKER=<provider>/<id> (your local model)");

  pi.registerTool({
    name: "handoff",
    label: "Hand off plan",
    description:
      "Planner (Claude) only: hand the finished plan to the implementer (the local model). The implementer never calls handoff. " +
      "Verify commands are shell commands that exit 0 when the work is done; a script runs them.",
    promptSnippet: "Hand a finished plan to the local implementer",
    promptGuidelines: [
      "In the plan phase, explore with read, grep, find and ls only; edit, write and bash are blocked for the planner.",
      "If the request is unclear, ask the user before calling handoff. Call handoff once the plan is complete.",
    ],
    parameters: Type.Object({
      goal: Type.String({ description: "What to build, in one or two sentences" }),
      steps: Type.Array(Type.String(), { description: "Implementation steps for the local model" }),
      criteria: Type.Array(Type.String(), { description: "Acceptance criteria, each checkable" }),
      files: Type.Array(Type.String(), { description: "Files to create or change" }),
      verify: Type.Array(Type.String(), { description: "Shell commands that must exit 0, run from the working directory" }),
    }),
    async execute(_id, p) {
      criteria = p.criteria;
      verify = p.verify;
      round = 1;
      pending = "build";
      return {
        content: text(
          `PLAN HANDED OFF. Implementer (local model): implement exactly this plan, nothing more. ` +
            `Touch only the listed files. When you are done, stop with a short summary; ` +
            `a script then runs the Verify commands.\n\n` +
            `Goal: ${p.goal}\n\nSteps:\n${list(p.steps)}\n\nAcceptance criteria:\n${list(p.criteria)}\n\n` +
            `Files: ${p.files.join(", ")}\n\nVerify:\n${p.verify.map((c) => `$ ${c}`).join("\n")}`,
        ),
        details: p,
      };
    },
  });

  pi.registerTool({
    name: "verdict",
    label: "Verdict",
    description:
      "Reviewer (Claude) only: judge the implementation against the acceptance criteria. " +
      "The implementer never calls verdict; it stops with a summary and a script runs Verify.",
    promptSnippet: "Score the implementation against the plan's criteria",
    promptGuidelines: [
      "In the review phase, read the changed files with read, grep, find and ls, then call verdict with a 0-2 score and quoted evidence per criterion.",
    ],
    parameters: Type.Object({
      pass: Type.Boolean({ description: "true only if every criterion scores 2" }),
      scores: Type.Array(
        Type.Object({
          criterion: Type.String(),
          score: Type.Integer({ minimum: 0, maximum: 2 }),
          evidence: Type.String({ description: "Quote or file:line that supports the score" }),
        }),
      ),
      feedback: Type.String({ description: "What the implementer must fix; empty when pass" }),
    }),
    async execute(_id, p) {
      const table = p.scores.map((s) => `[${s.score}/2] ${s.criterion}: ${s.evidence}`).join("\n");
      if (p.pass) {
        pending = "plan";
        return { content: text(`APPROVED after ${round} round(s).\n${table}`), details: p, terminate: true };
      }
      if (round >= MAX_ROUNDS) {
        pending = "plan";
        return {
          content: text(`NOT APPROVED after ${round} round(s), giving up.\n${table}\n\nOpen: ${p.feedback}`),
          details: p,
          terminate: true,
        };
      }
      round++;
      pending = "build";
      return {
        content: text(`NOT APPROVED. Implementer (local model): fix this, then stop.\n${p.feedback}\n\n${table}`),
        details: p,
      };
    },
  });

  pi.on("session_start", () => {
    pi.setActiveTools([...new Set([...pi.getActiveTools(), ...READ_TOOLS, "handoff", "verdict"])]);
  });

  // Enforce the roles: the phase decides which tools may run.
  pi.on("tool_call", (event) => {
    const name = event.toolName;
    if (phase !== "build" && BLOCKED_FOR_CLAUDE.has(name)) {
      return {
        block: true,
        reason:
          phase === "plan"
            ? `${name} is blocked in the plan phase. Explore with ${READ_TOOLS.join(", ")}, then call handoff; the local model implements.`
            : `${name} is blocked in the review phase. Read the files, then call verdict.`,
      };
    }
    if (name === "handoff" && phase !== "plan") return { block: true, reason: "handoff is for the plan phase only." };
    if (name === "verdict" && phase !== "review") return { block: true, reason: "verdict is for the review phase only." };
  });

  // The local model stopped: run Verify, then send it back (red) or on to review (green).
  pi.on("agent_before_settle", async (event, ctx) => {
    if (phase === "review" && pending === undefined && !reminded) {
      reminded = true;
      return {
        entries: [...event.entries, { type: "custom_message", customType: "hybrid", content: "Reviewer: call verdict now.", display: false }],
        continue: true,
      };
    }
    if (phase !== "build" || pending !== undefined) return;

    const results = [];
    for (const cmd of [...verify, ...HIDDEN]) {
      const r = await pi.exec("bash", ["-c", cmd], { cwd: ctx.cwd, timeout: VERIFY_TIMEOUT_MS });
      const out = `${r.stdout}${r.stderr}`.trim().split("\n").slice(-15).join("\n");
      results.push({ cmd, ok: r.code === 0, out });
    }
    const report = results.map((r) => `[${r.ok ? "ok" : "FAIL"}] $ ${r.cmd}${r.ok ? "" : `\n${r.out}`}`).join("\n");
    const green = results.every((r) => r.ok);

    let content: string;
    if (green) {
      pending = "review";
      reminded = false;
      content =
        `VERIFY: ${results.length}/${results.length} ok.\n${report}\n\n` +
        `Reviewer (Claude): read the changed files with read-only tools. Score each acceptance ` +
        `criterion 0-2 with quoted evidence, then call verdict.\nCriteria:\n${list(criteria)}`;
    } else if (round >= MAX_ROUNDS) {
      pending = "plan";
      return {
        entries: [
          ...event.entries,
          { type: "custom_message", customType: "hybrid", content: `VERIFY still red after ${round} round(s), stopping.\n${report}`, display: true },
        ],
      };
    } else {
      round++;
      pending = "build";
      content = `VERIFY failed. Implementer (local model): fix this, then stop.\n${report}`;
    }
    return {
      entries: [...event.entries, { type: "custom_message", customType: "hybrid", content, display: true }],
      continue: true,
    };
  });

  pi.registerVirtualModel<State>({
    provider: "hybrid",
    id: "orchestrate",
    name: "Hybrid orchestrator (Claude plans + reviews, local builds)",
    thinkingLevels: ["low", "medium", "high"],
    contextWindow: 262_144,
    maxTokens: 32_000,
    async route(request: ModelRouteRequest<State>, ctx: ExtensionContext): Promise<ModelRoute<State>> {
      // Compaction and other side requests: free local tokens if possible. No phase change.
      if (request.reason === "direct") {
        return { model: find(ctx, (await localIsUp()) ? WORKER : PLANNER), thinkingLevel: request.thinkingLevel };
      }

      const before = request.state?.phase;
      if (request.reason === "user") {
        phase = "plan";
        pending = undefined;
        round = 0;
      } else if (pending) {
        // Pick the builder once per round, so a slow probe cannot flip a running build to Claude.
        if (pending === "build") builder = (await localIsUp()) ? WORKER : PLANNER;
        phase = pending;
        pending = undefined;
      }

      // Retry after a failed request: try the other side. A failed local build stays on Claude.
      if (request.reason === "retry" && request.failed) {
        if (isSame(request.failed.model, WORKER)) builder = PLANNER;
        else if (phase === "build" && (await localIsUp())) builder = WORKER;
      }
      status(ctx);

      return {
        model: find(ctx, phase === "build" ? builder : PLANNER),
        thinkingLevel: request.thinkingLevel,
        // Only store state when the phase changes (every returned object is persisted).
        state: phase !== before ? { phase } : undefined,
      };
    },
  });
}
