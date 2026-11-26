/**
 * Hybrid router: one virtual model that combines a cloud model (Claude) with a local model
 * (e.g. Qwen on your own GPU server).
 *
 * Registers `hybrid/auto`:
 * - Planning: the cloud model reads the code, plans and makes the first edit.
 * - Implementation: after the first successful `edit`/`write` of a turn, the session switches
 *   once to the local model and stays there (one prompt-cache miss).
 * - Each new user prompt starts in planning again.
 * - Fallbacks: local server down -> everything goes to the cloud model.
 *   Cloud request fails (rate limit, quota, overload) -> retry on the local model.
 * - Compaction summaries (`direct`) go to the local model when it is up (free tokens).
 *
 * Config (env):
 *   HYBRID_PLANNER  provider/id of the cloud model   (default anthropic/claude-opus-5-5)
 *   HYBRID_WORKER   provider/id of the local model   (required, e.g. zgx/qwen3.8-flash-next-a5b)
 *   HYBRID_HEALTH   URL probed to check the local server (default http://localhost:8000/v1/models)
 *
 * The local model must be in Pi's catalog, e.g. as a provider in ~/.pi/agent/models.json.
 *
 * Usage: HYBRID_WORKER=<provider>/<id> pi -e ./hybrid-router.ts --model hybrid/auto
 */

import type { Message } from "@earendil-works/pi-ai";
import type {
  ExtensionAPI,
  ExtensionContext,
  ModelRoute,
  ModelRouteRequest,
} from "@earendil-works/pi-coding-agent";

const PLANNER = process.env.HYBRID_PLANNER ?? "anthropic/claude-opus-5-5";
const WORKER = process.env.HYBRID_WORKER ?? "";
const HEALTH_URL = process.env.HYBRID_HEALTH ?? "http://localhost:8000/v1/models";
const HEALTH_TTL_MS = 30_000;
const EDIT_TOOLS = new Set(["edit", "write"]);

interface HybridState {
  phase: "planning" | "implementation";
}

type HybridRequest = ModelRouteRequest<HybridState>;

let health: { ok: boolean; at: number } | undefined;

/** Cached probe of the local server, so a dead tunnel costs at most one short timeout per 30s. */
async function localIsUp(): Promise<boolean> {
  if (health && Date.now() - health.at < HEALTH_TTL_MS) return health.ok;
  let ok = false;
  try {
    const res = await fetch(HEALTH_URL, { signal: AbortSignal.timeout(1500) });
    ok = res.ok;
  } catch {
    ok = false;
  }
  health = { ok, at: Date.now() };
  return ok;
}

function find(ctx: ExtensionContext, ref: string) {
  const [provider, ...rest] = ref.split("/");
  const model = ctx.modelRegistry.find(provider, rest.join("/"));
  if (!model) throw new Error(`hybrid-router: model ${ref} is not in the catalog`);
  return model;
}

function isSame(model: { provider: string; id: string } | undefined, ref: string): boolean {
  return model !== undefined && `${model.provider}/${model.id}` === ref;
}

/** Whether a tool call since the last user message edited a file successfully. */
function editedThisTurn(messages: readonly Message[]): boolean {
  const lastUser = messages.findLastIndex((m) => m.role === "user");
  return messages
    .slice(lastUser + 1)
    .some((m) => m.role === "toolResult" && EDIT_TOOLS.has(m.toolName) && !m.isError);
}

export default function (pi: ExtensionAPI) {
  if (!WORKER) throw new Error("hybrid-router: set HYBRID_WORKER=<provider>/<id> (your local model)");
  pi.registerVirtualModel<HybridState>({
    provider: "hybrid",
    id: "auto",
    name: "Hybrid (Claude plans, local Qwen builds)",
    thinkingLevels: ["low", "medium", "high"],
    contextWindow: 262_144,
    maxTokens: 32_000,
    async route(request: HybridRequest, ctx: ExtensionContext): Promise<ModelRoute<HybridState>> {
      const level = request.thinkingLevel;
      const up = await localIsUp();
      const to = (ref: string, state?: HybridState): ModelRoute<HybridState> => ({
        model: find(ctx, ref),
        thinkingLevel: level,
        // Only store state when the phase changes (every returned object is persisted).
        state: state && state.phase !== request.state?.phase ? state : undefined,
      });

      // Compaction and other side requests: free local tokens if possible.
      if (request.reason === "direct") return to(up ? WORKER : PLANNER);

      // Retry: switch to the other side.
      if (request.reason === "retry" && request.failed) {
        if (isSame(request.failed.model, PLANNER) && up) return to(WORKER);
        if (isSame(request.failed.model, WORKER)) return to(PLANNER, { phase: "planning" });
      }

      // Local server down: everything on the cloud model.
      if (!up) return to(PLANNER, { phase: "planning" });

      // New user prompt: plan on the cloud model.
      if (request.reason === "user") return to(PLANNER, { phase: "planning" });

      // Continuation within a turn.
      const phase = request.state?.phase ?? "planning";
      if (phase === "planning" && editedThisTurn(request.messages)) {
        return to(WORKER, { phase: "implementation" });
      }
      return to(phase === "implementation" ? WORKER : PLANNER);
    },
  });
}
