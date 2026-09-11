**Article:** https://www.anthropic.com/engineering/building-effective-agents

# Best-Practice Guide: Building Effective Agents

> **Source:** [Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents) — Anthropic Engineering
> **Published:** December 19, 2024 · **Authors:** Erik Schluntz & Barry Zhang
>
> This guide summarizes the article's insights and expands each with practical
> guidance. Quoted principles are the authors'; the *"In practice"* notes are
> elaboration for teams applying them.

---

## The one idea to keep

**Find the simplest solution possible, and only increase complexity when needed.**
Agentic systems trade latency and cost for better task performance — that trade is
only worth it when a simpler approach can't hit your quality bar. Often a single
well-tuned LLM call with retrieval and in-context examples is enough.

---

## 1. Core distinction: workflows vs. agents

The article draws a deliberate line between two kinds of "agentic system":

- **Workflows** — LLMs and tools orchestrated through **predefined code paths**.
  The control flow is written by you; the LLM fills in steps.
- **Agents** — LLMs **dynamically direct their own process and tool usage**,
  keeping control over how the task gets done.

**In practice:** Most production value today comes from *workflows*, not fully
autonomous agents. Reach for a workflow when the steps are knowable in advance;
reach for an agent only when they genuinely aren't.

---

## 2. When (and when not) to use agents

- Start with the **simplest** thing that works. Optimize a single call first.
- Use **workflows** for predictability and consistency on well-defined tasks.
- Use **agents** for **open-ended problems** where you can't predict the number
  of steps or hardcode a fixed path — and where you can trust the model's
  decision-making at scale.
- Agents cost more (latency, tokens, compounding errors). Justify the spend.

**In practice:** Write down whether your task has a fixed step-shape. If you can
draw the flowchart, build the flowchart (a workflow). If you can't, and the task
needs the model to decide the path, that's the agent case.

---

## 3. The foundational building block: the augmented LLM

Every pattern below is built from one primitive: an LLM **augmented** with

- **Retrieval** (bring in relevant context),
- **Tools** (act on the world),
- **Memory** (carry state across steps).

Two recommendations:
1. **Tailor** these capabilities to your specific use case.
2. Give the model a **clear, well-documented interface** to each.
   The **Model Context Protocol (MCP)** is one way to standardize tool/context integration.

**In practice:** Invest in the interface the model sees before adding more moving
parts. A clean tool surface pays off in every pattern.

---

## 4. Workflow patterns (in increasing order of freedom)

### 4.1 Prompt chaining
Decompose a task into a **fixed sequence** of steps; each LLM call consumes the
prior output. Add programmatic **gates** between steps to check quality and fail fast.

- **Use when:** the task splits cleanly into predictable subtasks.
- **Trade-off:** more latency in exchange for higher accuracy per step.
- **Examples:** generate marketing copy → then translate it; write an outline →
  validate it → then draft the document.

### 4.2 Routing
**Classify** an input, then send it down a **specialized path**. Lets you write
focused prompts (and pick cheaper/pricier models) per category without one
prompt trying to do everything.

- **Use when:** inputs fall into distinct categories *and* classification is reliable.
- **Examples:** triaging customer-service queries by type; routing easy questions
  to a small model and hard ones to a large model.

### 4.3 Parallelization
Run LLM work concurrently. Two flavors:

- **Sectioning** — split into **independent subtasks** run in parallel, then combine.
  *Examples:* one model answers while a separate guardrail model screens input;
  splitting an eval into per-criterion checks.
- **Voting** — run the **same task multiple times** to get diverse outputs and
  aggregate (e.g., majority vote, or "flag if any run flags").
  *Examples:* multiple passes to review code for vulnerabilities; several checks
  for content appropriateness with tunable thresholds.

- **Use when:** subtasks parallelize for speed, or multiple perspectives raise confidence.

### 4.4 Orchestrator–workers
A central **orchestrator** LLM **dynamically** breaks the task into subtasks,
delegates them to **worker** LLMs, and **synthesizes** their results.

- **Key difference from parallelization:** the subtasks are **not** predefined —
  the orchestrator decides them based on the input.
- **Use when:** you can't predict the subtasks up front.
- **Examples:** code changes touching an unknown set of files; gathering and
  combining information from multiple sources.

### 4.5 Evaluator–optimizer
One LLM **generates**, another **evaluates and gives feedback**, and they **loop**
until the evaluator is satisfied.

- **Use when:** you have **clear evaluation criteria** *and* iteration measurably
  improves the result.
- **Litmus test:** would a human reviewer's feedback visibly improve the output?
  If yes, an LLM evaluator likely helps too.
- **Examples:** refining a literary translation; multi-round research/search
  that deepens each pass.

---

## 5. Agents

Agents are the autonomous end of the spectrum: given a task (and optionally a
brief human check-in), the model **plans, uses tools, observes results, and
recovers from errors** in a loop until done or stopped.

- The loop itself is simple — *LLM uses tools based on environmental feedback,
  repeatedly.* The hard part is everything around it.
- **Ground truth at every step is essential:** tool results, test output, and
  runtime errors are how the agent course-corrects. Without a real feedback
  signal from the environment, agents drift.
- Because tools are the agent's hands, **tool design and documentation are
  critical** to success.
- **Use when:** the problem is open-ended, steps are unpredictable, and you can
  place appropriate **guardrails** and stopping conditions (max steps, budgets,
  human checkpoints).
- **Examples:** resolving SWE-bench issues across many files; computer use.

---

## 6. Three core principles

Whether you ship a single call, a workflow, or an agent, hold to these:

1. **Simplicity** — keep the design as plain as the task allows.
2. **Transparency** — make the system's planning steps **visible**, so behavior
   is inspectable rather than a black box.
3. **A well-crafted agent–computer interface (ACI)** — document and **test tools
   as carefully as you'd design a human UI**.

> "Success isn't about building the most sophisticated system. It's about
> building the *right* system for your needs." Start simple, **measure**, and add
> complexity only when it demonstrably improves outcomes.

---

## 7. Frameworks: use with eyes open

Frameworks (Claude Agent SDK, Strands Agents SDK, Rivet, Vellum, and others) can
speed up a start, but they add **abstraction layers** that hide prompts and
responses and make debugging harder.

**Recommendation:** begin **directly with the LLM API** — many patterns are a few
lines of code. If you adopt a framework, **understand what it does underneath**,
so incorrect assumptions don't become hidden bugs.

---

## 8. Appendix insights worth internalizing

### Agents in practice
- **Customer support:** blends conversation with tools (data lookup, knowledge
  retrieval, taking actions) and has **measurable success criteria** (resolution,
  escalation rate) — a natural fit for an agent.
- **Coding agents:** work well because solutions are **verifiable by automated
  tests**, letting the agent iterate against objective feedback in a well-scoped
  problem space.

### Prompt-engineering your tools (the ACI)
- Give the model **enough token room to "think"** before it commits to a tool call.
- Keep tool **formats close to natural internet text** the model has seen.
- **Remove formatting overhead** — no manual line counting, no fragile string
  escaping.
- **Poka-yoke** your tools: design them so mistakes are hard to make (e.g., require
  absolute paths so the model can't get lost with relative ones).
- **Test extensively** against real inputs and watch how the model actually uses
  each tool.
- Telling stat: on SWE-bench, **more optimization time went into the tools than
  into the overall prompt**.

---

## Quick decision checklist

- [ ] Can a single optimized LLM call (+ retrieval / examples) do it? → **Do that.**
- [ ] Are the steps predictable? → **Workflow** (chain / route / parallelize).
- [ ] Do subtasks depend on the input at runtime? → **Orchestrator–workers.**
- [ ] Clear criteria + iteration helps? → **Evaluator–optimizer.**
- [ ] Truly open-ended with trustworthy feedback + guardrails? → **Agent.**
- [ ] For every tool: documented, tested, poka-yoke'd, natural-format? → ship it.
