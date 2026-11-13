# ADR 0006: Inline parameters, recorded in the plan and enforced at deploy

- **Status:** Proposed
- **Date:** 2026-11-13
- **Issue:** [#59](https://github.com/innofactororg/bicep-action/issues/59)
- **Plan:** [specs/0006-inline-parameters.html](../../specs/0006-inline-parameters.html)

## Context

Parameter values come from one input, `template_parameters` (`IN_TEMPLATE_PARAMS`): a `.bicepparam` file, a JSON parameters file or URL, or the file followed by `KEY=VALUE` pairs. Values that change on every run, such as an image tag or a build number, need a file edit or a workaround. `Azure/bicep-deploy` has a `parameters` input for this.

How parameters flow today:

- **The deploy recompiles; it does not reuse plan artifacts.** The plan passes only two things to the deploy: the Bicep version (`bicep_version`) and the stack settings (`stack_settings`, read in `scripts/az-deploy.sh:306-325` and `:541-551`). The deploy runs `az deployment ... create` on the same checkout with the same `template_parameters`. There is no compiled ARM template or parameters file to bake inline values into.
- **The parameters string goes to az on the command line.** `scripts/az-deploy.sh:561-563` appends `--parameters ${IN_TEMPLATE_PARAMS}` to a string that is echoed (`:584`) and `eval`ed (`:585`); the stack path splits it with `read -ra` (`:378-381`). A secret passed this way is in the log and in `argv`. `docs/configuration.md:281` already warns that inline pairs appear in the logged commands.
- **`.bicepparam` and extra values.** `scripts/az-bicep.sh:125` compiles with `az bicep build-params` and copies the result into the logs artifact (`:133-135`). Azure CLI 2.87 accepts `.bicepparam` plus `key=value` items (it passes them to Bicep as `BICEP_PARAMETERS_OVERRIDES`, `custom.py` `_build_bicepparam_file`, needs Bicep 0.22.6 or later) but not a JSON object. Bicep with that variable also fills required parameters the file does not assign (checked locally, Bicep 0.37.4).
- **Cost estimate** passes `KEY=VALUE` pairs as `--inline` arguments (`scripts/azure-cost.sh:185-191`) and the compiled file as `--parameters`.
- **Other places that print the parameters string:** `scripts/debug-info.sh:69`, `scripts/debug-info.sh:196` (prints every `IN_*` variable not matching a short secret-word filter), `scripts/pipeline-summary.sh:40-41`.
- **The PR comment** is the concatenation of `step_*.md` files (`scripts/pr-comment.sh:46`), so a step shows something in the comment by writing a Markdown file.

## Decision

Add an input **`parameters`** (`INLINE_PARAMETERS` in Azure DevOps) to the plan and deploy actions and stage templates. The name is not `IN_*` on purpose, so `debug-info.sh` does not print it.

1. **Format.** A JSON object (`{"imageTag": "1.4.2", "replicas": 3}`) or lines of `name=value`. A value starting with `{` selects JSON. In line form the value is typed from the template parameter (string stays string, `int`, `bool`, JSON for `array` and `object`), as az does. In JSON form the types must already match; a mismatch is an error that names the parameter, not the value. Unknown names fail the plan.
2. **Merge.** Inline values win over the parameters file, for classic and stack deployments. When `parameters` is set, a new script `scripts/inline-parameters.sh` builds one parameters JSON file: `.bicepparam` is compiled with `az bicep build-params --stdout` with the inline values in `BICEP_PARAMETERS_OVERRIDES`; a JSON file or URL is merged with `jq`. `az-deploy.sh` then passes `--parameters <that file>` instead of the original string. The file is created in the runner temp directory, mode 600, outside `LOG_PATH`, and removed on exit. When `parameters` is empty nothing changes: the same command line, byte for byte.
3. **Secure values.** A parameter is secure when the compiled template says `securestring` or `secureObject` (including through a `$ref` to a definition). If the template cannot be read (for example a template spec that cannot be exported), every inline value is treated as secure. Secure values are masked with `::add-mask::` or `##vso[task.setsecret]` before use, are never put in argv, and are scrubbed from the step's log and Markdown files before they are uploaded or posted.
4. **Plan record.** The what-if step emits a new output **`inline_parameters`**: compact JSON `{"v":1,"salt":"…","params":{"<name>":"<sha256>"}}`, one salted SHA-256 of the canonical value per inline parameter, secure or not. No value is in it. The plan also writes `inline-parameters.json` to the logs artifact (names, non-secure values, secure names marked) and an `Inline parameters` section for the PR comment (names and non-secure values; secure values shown as hidden).
5. **Deploy check.** The deploy action takes **`plan_inline_parameters`** (`PLAN_INLINE_PARAMETERS`). Before anything is deployed, `az-deploy.sh create` hashes its own inline values with the plan's salt and compares per name. It fails on a changed, added or removed name, on inline values with no plan record, and on a plan record with no inline values; the message lists parameter names, never values. Both empty: no check, no output. This is the same shape as `plan_stack_settings`.
6. **Compatibility.** `template_parameters` keeps its meaning, including legacy `KEY=VALUE` pairs. Using both `parameters` and `KEY=VALUE` pairs in `template_parameters` is an error. Secure inline values are allowed but the documented route stays `readEnvironmentVariable()` in a `.bicepparam`; the docs say inline secure values must come from a GitHub secret or an Azure DevOps secret variable, never a literal.

## Alternatives considered

- **Pass `key=value` to az and rely on its `.bicepparam` support.** Least code, but secrets go in `argv` and in the logged `Run:` line, a JSON object has to be flattened, and values with spaces break `eval`. Rejected.
- **Bake the values into a compiled artifact from the plan.** The deploy does not use plan artifacts today; adding one would change the whole contract and keep secrets in an artifact. Rejected. The deploy recompiles and checks a hash instead.
- **Store the values in the plan output and compare them.** Puts secrets in job outputs (GitHub drops outputs that contain a secret) and non-secret values in a size-limited, single-line output. Rejected for hashes.
- **One digest over all inline values.** Smaller, but the deploy error could not name the parameter that changed. Rejected.
- **A separate `secure_parameters` input.** Clearer intent, but a second input to keep in sync across two actions and four Azure DevOps templates, and the template already says which parameters are secure. Rejected; recorded as an open question.
- **Pass overrides to az only through `BICEP_PARAMETERS_OVERRIDES` in the environment.** Keeps argv clean for `.bicepparam`, but does not cover JSON parameters files or stacks the same way and leans on a variable az sets itself. Rejected as the main path; the script uses it only when it compiles the `.bicepparam` itself.

## Consequences

- **Backward compatible.** With `parameters` empty and no plan record, no new code runs on the deploy path. The new action inputs and output are optional. Old pipelines keep working.
- **The contract has a limit.** A hash match proves the deploy received the same inline values as the plan. It does not prove the file contents are the same; the checkout is. Values that differ between jobs (a timestamp, a different run's build number) fail the deploy by design. Plan and deploy must run in the same workflow run or pipeline run.
- **Hashes of low-entropy secrets can be guessed** by someone who can read the logs artifact and knows the salt. The docs say so; use long random values, and the artifact is as private as the repository (already the stance in `docs/configuration.md`).
- **Not covered:** PSRule and the Bicep snapshot compile the repository files and do not see inline values (a snapshot is committed, so a per-run value would break it). The what-if shows the real effect. Cost estimate does use the merged file.
- **Docs:** `docs/configuration.md` (new section, secrets section corrected), `docs/how-it-works.md` (plan step, deploy contract), the examples, `.azuredevops/README.md`. A Bicep version below 0.22.6 cannot compile `.bicepparam` with overrides; the script reports it.
- **Verification gap:** the Azure DevOps expansion of a secret variable nested inside a variable value cannot be tested here; the plan tests it on a real pipeline before release.

## Plan

[specs/0006-inline-parameters.html](../../specs/0006-inline-parameters.html)
