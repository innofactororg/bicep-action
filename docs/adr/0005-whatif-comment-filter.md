# ADR 0005: Filter change types out of the what-if comment

- Status: Proposed
- Date: 2026-11-13
- Issue: https://github.com/innofactororg/bicep-action/issues/58
- Plan: [specs/0005-whatif-comment-filter.html](../../specs/0005-whatif-comment-filter.html)

## Context

Some resource types report `Modify` on every what-if although nothing changed, for example properties that Azure or a policy sets itself. The noise buries the real changes in the pull request comment. `Azure/bicep-deploy` has `what-if-exclude-change-types` for this.

How the comment is built today:

- **Classic mode.** `scripts/az-deploy.sh` runs `az deployment <scope> what-if --exclude-change-types Ignore NoChange` (line 582) and tees the CLI's text rendering to the step log (line 585). `log_output` (lines 34-142) reads that log, moves the change symbol to column 0 with `sed`, turns `~` into `!`, runs `diff_safe` (lines 41-46), and writes the step's `.md` file (line 114). Over 5000 characters the diff is folded under `<details>` (lines 87-97).
- **Stack mode.** `stack_whatif_gate` (lines 388-508) runs `az stack-whatif`, takes the text from the log (line 412) and the JSON from `az stack-whatif show` (line 413). The delete gate, the detach list and the determinism check read the JSON only (lines 431-474). The diff for the comment comes from the text (line 489).
- **`whatif-summary.json`.** `write_summary` (lines 167-210) builds it from JSON. In classic mode the JSON comes from a second what-if with `--result-format ResourceIdOnly` (lines 591-621), so it never touches the text. In stack mode it is the same `json` as the gate (lines 475-488).
- **Comment.** `scripts/pr-comment.sh` concatenates the `step_*.md` files. It replaces a section over 60000 characters with a pointer to the logs and truncates the whole comment at 65000 (lines 7-9, 24-26, 65-69), the fix for the "too many characters" bug (#23). The same text goes to the job summary.
- **Logs artifact.** The `step_*.log` files are uploaded whole, so the log always holds Azure's unfiltered output.

So the comment and everything that decides or records something are already separate paths. The filter only has to sit between the text and the `.md` file.

## Decision

Add two plan-job settings. Both default to empty, and empty reproduces today's comment byte for byte.

| GitHub input | Azure DevOps variable | Meaning |
|---|---|---|
| `whatif_comment_exclude_change_types` | `WHATIF_COMMENT_EXCLUDE_CHANGE_TYPES` | Comma separated change types to leave out of the comment. Case is ignored. |
| `whatif_comment_exclude_resource_types` | `WHATIF_COMMENT_EXCLUDE_RESOURCE_TYPES` | Comma separated resource types (for example `Microsoft.Network/privateDnsZones`). Narrows the change types. Case is ignored. |

**Semantics.** A resource block is hidden only when its change type is listed **and**, if resource types are given, its resource type is listed. Resource types without change types is a configuration error, because "hide every change on this type" would also hide creates.

**Accepted values.** `Create`, `Modify`, `Deploy`, `NoChange`, `Ignore`, `NoEffect`, `Unsupported`. `Delete` and `Detach` are rejected: the plan fails before the what-if runs, with a message that says why. An unknown value is also an error. `Ignore` and `NoChange` are accepted but have no effect in classic mode, where the what-if already leaves them out.

**How.** Filter the CLI text, not a re-rendering of the JSON. A new sourced script `scripts/whatif-filter.sh` splits the text into resource blocks (a block starts at a line with two spaces, a change symbol and a `Type/name [api-version]` token, and runs to the next block, a `Scope:` line or the `Resource changes:` line), maps the symbol to a change type, derives the resource type from the name, and drops matching blocks. It writes a tally of what it dropped to a file. `log_output` and `stack_whatif_gate` call it on the text before the existing `sed` and `diff_safe` steps, and only on a successful what-if. The failure path (`error()`) never filters.

**Notice.** When something was hidden, a block quote goes above the diff, for example:

```text
> Hidden from this comment: 3 `Modify` changes on `Microsoft.Network/privateDnsZones`, by `whatif_comment_exclude_change_types`. The full what-if is in the logs artifact. The deployment and `whatif-summary.json` are not affected.
```

Groups are listed by change type and resource type, at most eight, then a count of the rest. The notice sits at the top of the what-if section so that comment truncation cuts the end of the diff first.

**Fail open.** If a block's symbol is unknown, or the hidden count for a type exceeds the total on the text's `Resource changes:` line, the script shows everything and adds a one-line note. It never hides on doubt.

**Untouched.** `whatif-summary.json` (schema stays at 1, counts stay unfiltered), the logs, the delete gate, the approved-deletes check, the deterministic check, the stack head line and the delete and detach lists. The text's own `Resource changes:` summary line stays too, and the notice explains the difference.

## Alternatives considered

- **Render the comment from JSON.** Exact, but it needs a full-payload what-if (a third run or a heavier second one), and it re-implements Azure's diff renderer. That changes the comment for everyone, including users who set nothing. Rejected.
- **Pass `--exclude-change-types` to `az`.** It changes the what-if result itself, so the second what-if and the summary would need it too, and a stack what-if has no such flag. It would also change what the safety checks see. Rejected.
- **Filter in `pr-comment.sh`.** It only sees Markdown with the symbols already rewritten and no change-type metadata, and it runs for validate and deploy sections too. Rejected.
- **Only a change-type input.** Simpler, but `Modify` is a common type, and hiding all of it is wrong when only one resource type is noisy. The second input is optional and the default is unchanged, so it stays.
- **Hide `Delete` behind an explicit opt-in.** The issue says it cannot be hidden. Kept as a hard error.

## Consequences

- **Compatibility.** No change unless a pipeline sets the new inputs. No change to outputs, artifacts or `whatif-summary.json`.
- **Docs.** `counts` in the summary file now differ from the comment when a filter is set, so `docs/how-it-works.md` ("Counts. `counts` match the comment") and `docs/configuration.md` change. Plan job only; the deploy job does not read the settings.
- **Job summary.** The GitHub job summary and the Azure DevOps summary are made from the same file, so they are filtered too. The notice says where the full output is.
- **Text format risk.** The filter depends on the layout of `az` text output. The classic symbol set is known; the stack symbols must be confirmed from a real run (see the plan's open questions). Unknown layout fails open.
- **Truncation.** A hidden-heavy filter makes the comment shorter, so it also lowers the chance of the 60000 and 65000 limits. If a section is still replaced by the "too long" pointer, the notice goes with it, which is acceptable because the pointer already sends the reader to the logs.
- **Tests.** The repository has no test directory. This change adds `tests/` with fixture-based tests of the filter and runs them with plain bash, `awk` and `jq`.
