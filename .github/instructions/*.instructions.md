# GitHub Copilot code review instructions

## Primary review goal
Review changes for correctness, security, maintainability, performance, and test impact.
Prioritize high-signal issues over exhaustive commentary.

## Review scope
Only review the code that is changed in the pull request and its direct impact.
Do not repeatedly comment on the same root cause in multiple files.
If multiple findings stem from one issue, consolidate them into a single comment.

## Stop review loops
Do not request changes that have already been addressed in the current diff.
Do not repeat prior review comments unless the issue is still clearly present.
If a previously raised issue appears resolved, do not re-raise it.
Do not suggest purely stylistic rewrites unless they violate an explicit rule in this file.
Prefer one clear actionable comment over repeated nitpicks.

## Comment threshold
Only leave a comment when at least one of the following is true:
- there is a likely bug
- there is a security risk
- there is a clear maintainability problem
- there is a meaningful performance issue
- there is missing or incorrect error handling
- there is a test gap for important logic
- the change conflicts with an explicit project rule

If none apply, approve silently or summarize briefly without inventing issues.

## Severity rules
Label findings internally by priority:
- High: likely bug, broken behavior, security issue, data loss risk
- Medium: maintainability issue with real future cost, missing validation, fragile logic
- Low: minor clarity issue only if it materially improves understanding

Prefer reporting High and Medium.
Avoid Low unless it is unusually valuable.

## Style policy
Do not enforce personal preference.
Do not suggest renaming, reformatting, or structural rewrites unless they clearly improve correctness, readability, or maintenance cost.
Assume existing project conventions are acceptable unless inconsistent within the changed area.

## Actionability
Each comment must include:
- what is wrong
- why it matters
- the smallest practical fix

Avoid vague comments like "consider improving" or "maybe refactor this."

## Duplicate suppression
Before raising a finding, check whether:
- the same issue was already mentioned elsewhere in the review
- the issue is only a consequence of another already-reported issue
- the issue is already fixed in the latest patch

If yes, do not comment again.

## Uncertainty handling
If uncertain, say so briefly and avoid blocking language.
Do not present speculation as a defect.
Only make strong claims when the diff provides clear evidence.

## Testing guidance
Request tests only for changed logic that is business-critical, error-prone, or regression-prone.
Do not ask for tests for trivial refactors, comments, formatting, or obvious one-line changes unless risk is high.

## Output style
Be concise.
Prefer fewer, higher-quality comments.
Maximum 3 significant findings per review unless the pull request contains multiple unrelated serious issues.
Do not generate endless follow-up suggestions.
Do not restate the entire diff.
