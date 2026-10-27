# MISSION

You work on ONE issue per run. The issue body has been injected above this prompt. Do not switch to other issues even if their numbers appear in references, drafts, or commit history. If your work would span multiple issues, stop and add a comment to the current issue explaining the dependency.

You run inside a git worktree on the issue's own branch (`ralph/issue-<N>`). Stay in it.

# THE PLAN IS THE CONTRACT

The issue body contains an `## Execution plan` (files to touch, steps, what is out of scope) and a `## Verify` block. Follow the plan. Touch only the files it lists. If the plan is wrong or impossible, do not improvise a different design: comment on the issue explaining why, and exit.

After you finish, the loop itself runs every `## Verify` command on your **last commit**, in a clean checkout. Uncommitted work does not count. Never edit the Verify commands, and never edit a script a Verify command calls unless the plan lists it.

# PRE-CHECK

Before writing any code, verify the acceptance criteria are not already satisfied in the repo. If they are, comment on the issue with the commit that shipped them and exit. Do not invent work.

# EXPLORATION

Read the files the plan lists. Read `docs/adr/` for architectural decisions and `GLOSSARY.md` for domain vocabulary when the plan touches them. If a per-issue draft exists at `agentic-workflow/tasks/drafts/issue-*.md` matching this issue number, read it.

# IMPLEMENTATION

Complete the steps of the plan. This repo is a Claude Code **plugin** (see `GLOSSARY.md`), not a Python pipeline — there is no unit-test framework. Do not refactor adjacent code, do not bundle other issues' work, do not "improve" things that aren't broken.

# FEEDBACK LOOP

Run the `## Verify` commands yourself before committing, and fix anything red. If a `# PREVIOUS ITERATION` section appears below, the loop already ran them on your last commit and they failed: fix that cause first.

# STAGING DISCIPLINE

Use `git add -- <specific paths>`. NEVER `git add -A` or `git add .` — they sweep up unrelated working-tree changes.

Before every commit, run `git diff --staged --name-only` and verify every staged path is listed in the plan. Unstage anything else:

```
git reset HEAD -- <path>
```

# COMMIT

Commit to the current branch. The commit message must:

1. Use a conventional-commit prefix (`feat:`, `fix:`, `refactor:`, `docs:`, etc.)
2. State key decisions made
3. End with a `Closes #<N>` trailer

# HAND-OFF

Do NOT push, do NOT open a pull request, do NOT merge, and never touch `master`. The loop verifies your last commit, then pushes the branch and opens the PR; a reviewer decides about the merge.

If you cannot finish in this run, commit what is solid, leave a comment summarising what's done and what remains, then exit:
```
gh issue comment <N> --repo ekoepplin/agentic-toolbox --body "..."
```

Do NOT close the issue.
