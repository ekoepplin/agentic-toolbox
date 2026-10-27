// Table test for .pi/extensions/ralph-guardrail.ts. No test framework here;
// run directly:  node --experimental-strip-types agentic-workflow/ralph/guardrail-test.ts
import { blockReason } from "../../.pi/extensions/ralph-guardrail.ts";

const cases: Array<[string, boolean]> = [
  // blocked
  ["git push --force", true],
  ["git push -f origin ralph/issue-7", true],
  ["git push -uf origin HEAD", true],
  ["git push --force-with-lease origin HEAD", true],
  ["git push origin master", true],
  ["git push origin HEAD:master", true],
  ["git push origin HEAD:refs/heads/master", true],
  ["git push -u origin master && echo done", true],
  ["gh pr merge 12 --squash", true],
  ["gh pr merge --auto --squash", true],
  ["gh api -X PUT repos/ekoepplin/agentic-toolbox/pulls/12/merge", true],
  ["cd x; git push origin master", true],
  // allowed
  ["git push -u origin ralph/issue-7", false],
  ["git push origin HEAD", false],
  ["git push origin feature/master-plan", false],
  ["git push origin master-notes", false],
  ["git fetch origin master", false],
  ["git log origin/master..HEAD", false],
  ["gh pr create --base master --fill", false],
  ["gh pr view 12", false],
  ["gh api repos/ekoepplin/agentic-toolbox/pulls/12", false],
  ["git commit -m 'fix: master doc'", false],
];

let failed = 0;
for (const [cmd, want] of cases) {
  const got = blockReason(cmd) !== undefined;
  if (got !== want) {
    failed++;
    console.log(`FAIL  ${want ? "should block" : "should allow"}: ${cmd}`);
  }
}
console.log(`${cases.length - failed}/${cases.length} guardrail cases pass`);
process.exit(failed ? 1 : 0);
