# ADR 0004: Granular action on unmanage

- Status: Proposed
- Date: 2026-11-13
- Issue: https://github.com/innofactororg/bicep-action/issues/57
- Plan: [specs/0004-granular-action-on-unmanage.html](../../specs/0004-granular-action-on-unmanage.html)

## Context

A deployment stack decides what to do with a resource that leaves the template. Azure expresses that per kind of object: resources, resource groups and management groups are each `delete` or `detach` (the `actionOnUnmanage` object of the stack API, and the three `action-on-unmanage-*` inputs of `Azure/bicep-deploy`).

bicep-action exposes one setting, `stack_action_on_unmanage` (GitHub input) / `STACK_ACTION_ON_UNMANAGE` (Azure DevOps variable), with the values `detachAll`, `deleteResources` and `deleteAll`. These are the three values of the Azure CLI flag `--action-on-unmanage`.

How it is used today, in `scripts/az-deploy.sh`:

- Line 351 reads the value, defaulting to `detachAll`. Line 382 passes it to `az stack-whatif` and `az stack <scope> create` as `--action-on-unmanage`.
- Line 384 builds the plan record `stack;id=<id>;unmanage=<value>;deny=<mode>` and passes it to `check_plan_settings` (line 306). On the plan it becomes the `stack_settings` output. On the deploy it is compared with `PLAN_STACK_SETTINGS`, and any difference fails the job.
- The delete gate is `stack_whatif_gate` (line 388). It lists every `delete` change (line 436), fails on any ID that is not in the `STACK_APPROVED_DELETES` file (lines 439-449), and fails when the what-if is not deterministic and `unmanage != detachAll` (line 469).
- Line 519 runs the gate again before the deploy when `unmanage != detachAll`.
- Line 483 writes `stackSettings.actionOnUnmanage` into `whatif-summary.json`.
- The input is declared in `.github/actions/plan/action.yml` (line 48) and `.github/actions/deploy/action.yml` (line 38), both with the default `detachAll`. Azure DevOps has no declaration: pipeline variables reach the scripts as environment variables, so `.azuredevops/*` needs no new input wiring.

The installed Azure CLI (2.87.0) has only `--action-on-unmanage` with those three values, plus `--resources-without-delete-support`. There are no granular flags on `az stack group|sub|mg create`. The `az stack-whatif` command is not present in that CLI at all, so what-if behaviour could not be checked locally.

The three CLI values map to the granular model like this:

| CLI value | resources | resource groups | management groups |
|---|---|---|---|
| `detachAll` | detach | detach | detach |
| `deleteResources` | delete | detach | detach |
| `deleteAll` | delete | delete | delete |

So "delete unmanaged resources but never delete a resource group" already works today as `deleteResources`. What cannot be said is any combination outside this table, and the setting does not tell a reader which of the three kinds a value affects.

Which kinds apply depends on the stack scope. A resource group stack manages resources only. A subscription stack manages resources and resource groups. Only a management group stack manages all three.

## Decision

Add three inputs, keep the shorthand, and normalise everything to one triple that the gate, the plan record and the deploy check all use.

**Inputs.**

| GitHub input | Azure DevOps variable | Values |
|---|---|---|
| `stack_action_on_unmanage_resources` | `STACK_ACTION_ON_UNMANAGE_RESOURCES` | `delete`, `detach` |
| `stack_action_on_unmanage_resource_groups` | `STACK_ACTION_ON_UNMANAGE_RESOURCE_GROUPS` | `delete`, `detach` |
| `stack_action_on_unmanage_management_groups` | `STACK_ACTION_ON_UNMANAGE_MANAGEMENT_GROUPS` | `delete`, `detach` |

The GitHub inputs `stack_action_on_unmanage_*` keep the existing prefix, so they sort next to the shorthand in the docs. The issue proposes the names `action_on_unmanage_*`; this ADR keeps the `stack_` prefix that every other stack input has. All four inputs default to empty. The `detachAll` default of the shorthand moves from `action.yml` into the script, because a non-empty default would make "the shorthand was set" impossible to detect.

**Resolution** (new `scripts/stack-unmanage.sh`, sourced by `az-deploy.sh`):

1. If the shorthand and any granular input are both set: error, naming both.
2. Shorthand only: expand through the table above. Empty everything: `detachAll`.
3. Granular only: an unset granular value is `detach`. Safe is the default.
4. Drop the kinds that do not apply at the scope (resource groups at `group`, management groups at `group` and `sub`). A `delete` for a kind that does not apply is an error. A `detach` for it is accepted and dropped. The shorthand `deleteAll` at `group` scope therefore keeps working as it does today.
5. Refuse a contradictory triple: `resource_groups: delete` with `resources: detach`, and `management_groups: delete` with a `detach` for either of the other applicable kinds. Deleting a container deletes what is in it, so such a triple cannot be honoured as written. This is the nesting rule. It leaves four valid triples at management group scope, three at subscription scope and two at resource group scope. It is open to challenge, see the plan's Questionables.

**CLI mapping.** A valid triple that equals one of the three table rows is passed as `--action-on-unmanage <legacy value>`. This covers every valid triple except one: `delete`, `delete`, `detach` at management group scope. For that one the script fails with a clear message, until the pinned CLI offers granular flags or the REST path is built (open question in the plan). Nothing is silently widened or narrowed.

**Plan record.** The record keeps today's format when the triple is one of the three rows, so a plan and deploy made with the shorthand and with the granular inputs for the same behaviour match, and a plan from an older release still matches. For the one other triple it is `unmanage=resources:delete,resourceGroups:delete,managementGroups:detach`. The comparison is on the normalised triple, never on which input was used. `whatif-summary.json` gains `stackSettings.unmanage` with the three values next to the existing `actionOnUnmanage`; the schema version stays 1, since the change only adds a field.

**Delete gate.** "Delete mode" becomes "the normalised triple has at least one `delete`". Everything that today tests `unmanage != detachAll` (the non-deterministic failure at line 469 and the second gate run at line 519) tests that instead. The approved list stays one flat list of IDs. The gate adds a kind check: each `delete` change is classified as resource, resource group or management group from its ID, and a delete of a kind whose action is `detach` fails the plan as unexpected. That is a check on what Azure reports, on top of what the plan asked for. Detaches are reported as today.

**Both platforms.** The behaviour lives in the shared scripts, so GitHub and Azure DevOps (templates and the single-file `ms.azure.deploy.yml`) behave the same. The single-file pipeline and both stage templates download scripts from a list, so `stack-unmanage` is added to all four lists (`ms.azure.deploy.yml` lines 93 and 318, `templates/plan-stage.yml` line 82, `templates/deploy-stage.yml` line 97).

## Alternatives considered

- **Pass the granular values straight to Azure through `az rest`.** It expresses every triple, but it means compiling the template, building the request body and handling the stack what-if ourselves, and replacing `az stack` for those runs only. Too large for this change and a second code path to keep correct. Kept as an option if the CLI does not gain flags.
- **Only add the inputs, validate nothing.** Contradictory triples would reach Azure or, worse, reach the gate as something it does not model. Rejected.
- **Make the granular inputs replace the shorthand.** Breaks every existing pipeline. Rejected by the issue.
- **Let the granular inputs override the shorthand silently.** Hides mistakes in exactly the setting that deletes things. Rejected; a conflict is an error.
- **Record `unmanage=custom` in the plan.** The deploy could not tell two different custom triples apart. Rejected; the record carries the values.

## Consequences

- No change for existing pipelines: the shorthand values, the default, the plan record and the summary file stay as they are. Only a new key is added to the summary.
- A plan made by an older release and deployed by this one (or the reverse) still matches for the three shorthand rows. A plan with the long record form fails on an older deploy with the existing "settings differ" message, which is the safe outcome.
- The matrix of valid combinations is small and documented, instead of eight values and an unwritten rule.
- One combination is rejected for now because the CLI cannot express it. The docs and the error say so.
- Docs to update: `docs/configuration.md` (settings table, the unmanage section, the outputs table, recommended settings), `docs/how-it-works.md` (settings check, delete gate flowchart text, summary file), `docs/troubleshooting.md`, and the examples.
- The repository has no automated tests. This change adds a small shell test suite for the resolver and the gate with a stubbed `az`, which the other features can reuse.

## Plan

The implementation plan, with phases, files, tests and open questions, is in [specs/0004-granular-action-on-unmanage.html](../../specs/0004-granular-action-on-unmanage.html).
