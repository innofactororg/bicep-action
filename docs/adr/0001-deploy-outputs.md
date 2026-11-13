# ADR 0001: Expose deployment outputs, with masked outputs

- Status: Proposed
- Date: 2026-11-13
- Issue: https://github.com/innofactororg/bicep-action/issues/54
- Plan: [specs/0001-deploy-outputs.html](../../specs/0001-deploy-outputs.html)

## Context

The deploy action and the Azure DevOps deploy stage return nothing. A later job that needs a resource ID, an endpoint or a principal ID has to ask Azure again.

What the code does today:

- `.github/actions/deploy/action.yml` has no `outputs:` block, and the "Create deployment" step (lines 175-197) has no `id`. `docs/configuration.md` says "The deploy action has no outputs."
- `.azuredevops/templates/deploy-stage.yml` and the Deploy stage in `.azuredevops/ms.azure.deploy.yml` run `./az-deploy.sh create` in an `AzureCLI@2` task with no `name:` (deploy-stage.yml:148-157, ms.azure.deploy.yml:367-376), so nothing can reference its variables.
- `scripts/az-deploy.sh` runs `az deployment <scope> create` with its stdout teed to the step log (line 585) and `az stack <scope> create` the same way (line 528). Both commands print the full result, which includes `properties.outputs` with every value in clear text.
- For a standard deployment, `log_output` (lines 34-88) also copies that JSON into the step's Markdown file inside a `<details>` block (lines 54-59). `scripts/pr-comment.sh` posts every `step_*.md` verbatim, and the logs artifact contains the same files. The stack path writes its own short Markdown (line 529), so a stack's result reaches the console and the log only.

So template outputs already reach the log, and for standard deployments the pull request comment and the logs artifact, today. The feature must not add a second route, and masking has to close the existing one, or the guarantee "a masked output never appears in the log, the comment or the artifact" is false.

The plan records settings that change what gets deployed (Bicep version, mode, stack settings), and the deploy refuses to run if they differ (`check_plan_settings`, az-deploy.sh:252-271). Outputs are read after the deployment and change nothing that is deployed, so they are not part of that check.

Constraints from the platforms:

- A GitHub composite action can only return outputs declared in its `action.yml`. Names that depend on the template cannot be declared.
- A GitHub job output that contains a registered mask is dropped by the runner.
- Azure DevOps output variables need a named step. From another stage a deployment job's output is read as `stageDependencies.<stage>.<job>.outputs['<job>.<step>.<name>']`.
- Deployment stacks are not used at tenant scope, or for templates with Bicep extensions. Those runs already fall back to a standard deployment (az-deploy.sh:326-343), and their outputs come from the standard deployment.

## Decision

Add one new script, `scripts/deploy-outputs.sh`, sourced by `az-deploy.sh` after a successful create, in both modes and at every scope. It reads `properties.outputs` from the result of the create command (a fallback `az deployment <scope> show` / `az stack <scope> show` covers an empty result) and publishes:

**New input** `masked_outputs` (GitHub) / `MASKED_OUTPUTS` (Azure DevOps): comma-separated output names, case-insensitive. Default empty.

**Masking rule.** An output is masked when its name is in `masked_outputs`, or its type is `securestring` or `secureObject`, whatever the input says. Masking is registered before the value is written anywhere. Azure normally does not return the value of a secure output; if there is no value, nothing is published for it and the log says so.

**Redaction.** The create command's stdout is captured rather than teed. Masked values are replaced by `***` in the JSON that goes to the console, the log and the step Markdown. Any remaining literal occurrence of a masked value is scrubbed from the log file. Non-masked outputs appear in the comment as they do today.

**GitHub.**

- The deploy step gets `id: deploy`. The action declares one output, `outputs`: a compact JSON object `{"name": value}` of all non-masked outputs. Objects and arrays stay JSON values, so `fromJSON(steps.x.outputs.outputs).vnet.id` works.
- Masked values are not in `outputs`, because a job output containing a mask is dropped. Each is written to the job environment as `BICEP_OUTPUT_<NAME>` (upper case) after `::add-mask::`, for later steps in the same job. They never cross jobs.
- Per-output step outputs are not possible for a composite action; this is documented with the `fromJSON()` pattern.

**Azure DevOps.**

- The Deploy step is named `deploy`. For every non-masked output the script sets `##vso[task.setvariable variable=<name>;isOutput=true]`, and `outputs` holds the JSON of all non-masked outputs.
- A masked output is set with `isOutput=true;issecret=true`. It is not in `outputs`.
- Values are escaped for logging commands (`%`, CR, LF). A template output called `outputs` is only available in the JSON, with a warning.
- The stage templates and the single-file pipeline download `deploy-outputs.sh` with the other scripts.

**Behaviour with no outputs.** The script returns without writing anything, and the create path then prints exactly what it does today.

**Not in the plan settings.** `masked_outputs` is read at deploy time only, like `auto_merge`. It changes what is hidden, not what is deployed.

## Alternatives considered

- **One step output per template output on GitHub.** Not possible in a composite action. A reusable workflow could, but would remove the action form that all examples use.
- **Write outputs to `GITHUB_ENV` for everything.** Simple, but it puts every value in the environment of every later step, including third-party actions. Kept only for masked values, which have no other route.
- **Only an `outputs` JSON, masked values included.** The runner would drop the whole job output when a value is masked.
- **Read outputs with a second `az ... show` and leave the create stdout alone.** Leaves the existing leak into the comment and the artifact, so masking would not hold.
- **Make outputs part of the plan settings check.** Rejected: they do not change what is deployed, and a plan cannot know deploy-time values.
- **Mask by value pattern.** Unreliable. Masking by output name and type is explicit.

## Consequences

- No change for pipelines that do not use the feature. Defaults reproduce today's behaviour, with one exception: the create command's JSON now prints after the command finishes instead of streaming, and secure values in it are shown as `***`.
- At `log_severity` DEBUG, `az` writes raw HTTP bodies to stderr. Masked values can appear in the live log of that run, although the script scrubs the log file and the artifact afterwards. This is documented; do not use DEBUG on deployments with sensitive outputs.
- Azure DevOps secret output variables may not be readable from a later job. This has to be verified in the test deployment and the result written into the docs. See the plan.
- New or changed files: `scripts/deploy-outputs.sh`, `scripts/az-deploy.sh`, `.github/actions/deploy/action.yml`, `.azuredevops/templates/deploy-stage.yml`, `.azuredevops/ms.azure.deploy.yml`, `docs/configuration.md`, `docs/how-it-works.md`, two examples under `docs/examples/`.
- Minor version bump: new input, new outputs, no removals.

## Plan

[specs/0001-deploy-outputs.html](../../specs/0001-deploy-outputs.html)
