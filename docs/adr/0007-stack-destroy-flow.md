# ADR 0007: A separate, approval-gated destroy flow for deployment stacks

- Status: Proposed
- Date: 2026-11-13
- Issue: https://github.com/innofactororg/bicep-action/issues/60
- Plan: [specs/0007-stack-destroy-flow.html](../../specs/0007-stack-destroy-flow.html)

## Context

With `deployment_mode: stack` the actions create and update an Azure deployment stack, but nothing can delete one. A team that wants to retire an environment has to run `az stack ... delete` by hand, outside the plan, review and approval that the rest of the pipeline gives them. `Azure/bicep-deploy` closes the gap with `operation: delete` on its single action.

The core promise of bicep-action is that the deploy job deploys exactly what the plan showed. A destroy needs the same promise: destroy exactly what the destroy plan listed.

What the current code gives us, and what it does not:

- The stack what-if cannot be reused. `az stack-whatif` only models a create or update (`scripts/az-deploy.sh:396`). A destroy plan has to be built from the stack itself (`az stack {scope} show`).
- The delete gate is inline in the what-if function, not a helper. It reads a JSON array of resource IDs from `STACK_APPROVED_DELETES`, lower-cases both sides and lists every delete that is not approved (`scripts/az-deploy.sh:439-450`). Stack name, scope and stack ID are also derived inline (`scripts/az-deploy.sh:348-369`).
- The plan-to-deploy handoff is a set of strings, not files. The plan records `stack_settings` (`scripts/az-deploy.sh:304-325`) and exposes it as an action output (`.github/actions/plan/action.yml:124`) or an `isOutput` variable; the deploy job compares it (`.github/actions/deploy/action.yml:46`, `.azuredevops/templates/deploy-stage.yml:71-73`). `whatif-summary.json` is written by `write_summary` (`scripts/az-deploy.sh:167-210`) but only travels in the logs artifact.
- The Add comment step only runs on `pull_request` events (`.github/actions/plan/action.yml:334-340`), and `scripts/pr-comment.sh` always posts to `COMMENTS_URL` after writing the step summary. A manually started run therefore gets no job summary today.
- Sign-in and the subscription wait are reusable: `scripts/az-login.sh` and `scripts/azure-subscription.sh`. On Azure DevOps each template downloads its own hand-maintained script list (`.azuredevops/templates/deploy-stage.yml:94-102`).
- `az stack {sub|group|mg} delete` requires `--action-on-unmanage`, and also takes `--resources-without-delete-support detach|fail` and `--bypass-stack-out-of-sync-error`.

## Decision

Add a separate destroy flow. The existing plan and deploy actions and templates do not change.

**GitHub.** Two new composite actions, `.github/actions/destroy-plan` and `.github/actions/destroy`, used as two jobs in one workflow. The destroy job uses a GitHub environment with required reviewers. The documented trigger is `workflow_dispatch`, with a typed confirmation of the stack name.

**Azure DevOps.** Two new stage templates, `.azuredevops/templates/destroy-plan-stage.yml` and `.azuredevops/templates/destroy-stage.yml`. The destroy stage is a `deployment` job on an Azure DevOps environment with an approval check.

**Scripts.** One new script, `scripts/az-stack-destroy.sh`, with two actions (`plan`, `destroy`), and one sourced helper, `scripts/stack-common.sh`, for the stack name, scope, stack ID and the approved-deletes check. `az-deploy.sh` is not touched in this change; moving it onto the helper is a later, separate change.

**Destroy plan** (read only):

1. Sign in, wait for the subscription, read the stack. A missing stack, or a stack that is not in state `succeeded`, fails the plan.
2. List what the requested `stack_action_on_unmanage` would do: `detachAll` detaches every managed resource and deletes only the stack record; `deleteResources` deletes managed resources; `deleteAll` also deletes managed resource groups and management groups. For `deleteAll`, also list the resources found inside a managed resource group that the stack does not manage, because deleting the group deletes them too.
3. Every resource that would be deleted must be on the `stack_approved_deletes` list, matched as the delete gate does today. Anything else blocks the destroy. With `detachAll` nothing is deleted, so the list is not needed.
4. Write `destroy-plan.json` (the same field names as `whatif-summary.json` for counts, deletes and detaches, plus the stack, the settings and a fingerprint), a Markdown section, and the job summary or pull request comment.
5. Output `destroy_plan` (the file path) and `destroy_fingerprint`, a string in the style of `stack_settings`: `stack-destroy;id=<stack id>;unmanage=<mode>;sha256=<hash>`. The hash covers the stack ID, the unmanage settings and the sorted, lower-cased managed resource IDs with their status.

**Destroy**:

1. Runs only after the environment approval and only with `plan_destroy_fingerprint`.
2. Signs in, re-reads the stack, recomputes the fingerprint and fails if it differs, naming the added and removed IDs when the plan file is available. This is the "a resource added after the plan stops the destroy" rule.
3. Runs the approved-deletes check again on the current state.
4. Runs `az stack {scope} delete --name ... --action-on-unmanage <planned> --resources-without-delete-support <planned> --yes`, then confirms that the stack no longer exists.

Defaults are the cautious ones: `detachAll`, `resources_without_delete_support: fail`, and `bypass_stack_out_of_sync_error: false`. The bypass flag is an explicit opt-in, because it hides the same kind of mismatch the fingerprint exists to catch.

**Trigger model.** A manual run is the supported trigger. Both flows also work in a pull request run (the plan comments, the destroy needs the environment), but the examples do not use a pull request that deletes the template entry point: the plan job would fail to build it, and it ties an irreversible act to a merge.

**Deny settings.** The flow does not try to work around them. Deleting the stack through `az stack delete` is the supported way to remove stack-owned resources, so deny settings are expected not to block it; the plan step will print each resource's `denyStatus` so a reviewer can see it. This has to be proved on a throwaway stack (see the plan, Phase 1).

## Alternatives considered

- **`operation: delete` on the existing actions (the `Azure/bicep-deploy` model).** One flag turns a plan/deploy pipeline into a destroy pipeline. A typo in a shared workflow, or a copied input block, becomes a deletion with the same review weight as a deployment. It also drags the Bicep build, PSRule, cost and what-if steps into a flow that has no template. A separate flow keeps the existing actions unchanged and makes destruction a named, reviewed act.
- **Reuse `az stack-whatif` for the destroy plan.** It has no delete operation. Feeding it an empty template would model an update that removes everything, which is not what `az stack delete` does with `detachAll` or `resources-without-delete-support`.
- **Pass the whole plan file between jobs instead of a fingerprint.** Needs an artifact download in both platforms and a trust decision about the file. The fingerprint is a string, uses the same mechanism as `stack_settings`, and is enough to prove "same set". The plan file is optional input, only for a readable diff.
- **Trigger on a pull request that deletes the entry point.** Rejected as the primary model (see above). It can be added later on top of the same actions.
- **Move the stack helpers out of `az-deploy.sh` now.** Cleaner, but it changes the file every deployment runs. Deferred.

## Consequences

- Retiring a stack gets the same review, approval and "what was planned is what runs" guarantee as deploying one, on both platforms.
- A destroy that deletes anything needs every resource ID listed in `stack_approved_deletes`. For a large stack that is a long list; the plan prints a ready-to-commit list to make it practical.
- Stack name and scope derivation now exist in two places until the follow-up change. A test asserts they agree.
- The fingerprint closes the gap between plan and destroy, not the gap between the final re-read and the delete call. Azure offers no precondition on stack delete, so that window (seconds) remains, and is documented.
- `az stack` delete behaviour for `deleteAll` and for deny settings depends on the Azure CLI and service version; the first phase records it with a live spike before any code depends on it.

## Plan

[specs/0007-stack-destroy-flow.html](../../specs/0007-stack-destroy-flow.html) holds the phased implementation plan, the file list, the testing strategy and the open questions.
