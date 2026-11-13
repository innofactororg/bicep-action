# ADR 0002: Stack deny settings, description and tags

- Status: Proposed
- Date: 2026-11-13
- Issue: https://github.com/innofactororg/bicep-action/issues/55
- Plan: [specs/0002-stack-deny-settings.html](../../specs/0002-stack-deny-settings.html)

## Context

In stack mode the action creates the stack with `--action-on-unmanage` and `--deny-settings-mode` only (`scripts/az-deploy.sh:382`). The mode is read from `STACK_DENY_SETTINGS_MODE` (`scripts/az-deploy.sh:352`) and is exposed as `stack_deny_settings_mode` on both GitHub actions (`.github/actions/plan/action.yml:52`, `.github/actions/deploy/action.yml:42`) and as a pipeline variable on Azure DevOps.

With `denyWriteAndDelete` and no exclusions, Azure also blocks break-glass accounts and any other pipeline that writes to the managed resources. Few teams can use the mode as a result. The stack description and tags cannot be set at all. `az stack {group|sub|mg} create` already supports all of this (checked against Azure CLI 2.87.0): `--deny-settings-excluded-principals` (up to 5), `--deny-settings-excluded-actions` (up to 200), `--deny-settings-apply-to-child-scopes`, `--description` and `--tags` (space-separated `key[=value]`). The flags are the same at the three scopes.

The plan/deploy contract is implemented in `check_plan_settings` (`scripts/az-deploy.sh:306`). The what-if records one string, `stack;id=<id>;unmanage=<x>;deny=<mode>` (`scripts/az-deploy.sh:384`), as the `stack_settings` output. The deploy builds the same string from its own inputs and fails if it differs from `PLAN_STACK_SETTINGS`. The deny mode is therefore compared today, but the new settings would not be unless added to that string.

## Decision

Add five optional inputs to the plan and deploy actions (GitHub) and five pipeline variables (Azure DevOps, including `.azuredevops/ms.azure.deploy.yml`):

| GitHub input | Azure DevOps variable | Default | `az stack` flag |
|---|---|---|---|
| `stack_deny_settings_excluded_principals` | `STACK_DENY_SETTINGS_EXCLUDED_PRINCIPALS` | empty | `--deny-settings-excluded-principals` |
| `stack_deny_settings_excluded_actions` | `STACK_DENY_SETTINGS_EXCLUDED_ACTIONS` | empty | `--deny-settings-excluded-actions` |
| `stack_deny_settings_apply_to_child_scopes` | `STACK_DENY_SETTINGS_APPLY_TO_CHILD_SCOPES` | `false` | `--deny-settings-apply-to-child-scopes` |
| `stack_description` | `STACK_DESCRIPTION` | empty | `--description` |
| `stack_tags` | `STACK_TAGS` | empty | `--tags` |

The issue proposes `deny_settings_*` names. This ADR prefixes them with `stack_` to match the existing `stack_deny_settings_mode`, `stack_name` and `stack_action_on_unmanage`. This is a naming deviation from the issue and is listed as an open question in the plan.

Behaviour:

1. **Parsing and validation** live in a new sourced helper, `scripts/stack-settings.sh`, used by `az-deploy.sh` for both actions. Lists accept commas, spaces or newlines. Principals must be GUIDs (at most 5), actions must look like `Provider/type/action` (at most 200), tags are a JSON object or `key=value` lines (at most 50), the description is one line of at most 512 characters. Values are normalised (lower-case GUIDs, sorted, de-duplicated) so that ordering does not cause a false mismatch. Invalid input, a masked value (`***`), or any of the new deny settings combined with `deny mode = none` fails before Azure is called.
2. **Defaults change nothing.** When none of the five inputs is set, no new flag is passed and the `stack_settings` string is byte-for-byte what it is today. Existing plans and deployments therefore still compare equal.
3. **The plan records them.** Non-default settings are appended to the `stack_settings` string as extra `;key=value` segments (principals in full, actions, tags and description as a count and a short SHA-256 prefix, so the value stays on one line and short). The `whatif-summary.json` `stackSettings` object gains `excludedPrincipals`, `excludedActions`, `applyToChildScopes`, `description` and `tags` (additive, `schemaVersion` stays 1).
4. **The deploy enforces them.** `check_plan_settings` keeps comparing the whole string and, on a mismatch, names the segments that differ. After `az stack create` the script reads the stack back (`az stack <scope> show`) and fails if the stored deny settings differ from the intended ones.
5. **The PR comment shows them.** The stack summary line in `step_*_what-if.md` gains a "Deny settings" line, only when a new setting is in use, so existing comments do not change. The deploy comment repeats it.
6. **What-if.** The deny and metadata flags do not change the resource change set. They are passed to `az stack-whatif` only if that command lists the flag, and otherwise left out. The plan still records and shows them.

## Alternatives considered

- **Separate comparison variable for the new settings.** Rejected: two things to pass from plan to deploy, and an old deploy action would ignore the second one and skip the check. Extending the one string keeps a mixed-version pair failing safe.
- **A single `stack_deny_settings` JSON input.** Rejected: harder to write in YAML and Azure DevOps variables, and one changed principal would make the whole block look different. Separate inputs match the existing style.
- **Hash everything in the settings string.** Rejected for principals: they are short, and showing them in the mismatch message is useful to the person fixing it. Actions, tags and description are hashed because they can be long or contain characters unsafe in an output.
- **Silently ignore exclusions when the mode is `none`.** Rejected: the user thinks something is protected that is not.
- **Do not validate, let Azure reject.** Rejected: late, unclear errors, and Azure may accept values we do not want in a comment.

## Consequences

- No breaking change. New inputs are optional and the default path is unchanged, including the settings string.
- A plan made with a new bicep-action version and deployed with an older one (or the reverse, with exclusions set) fails on the settings mismatch. That is the safe direction.
- `whatif-summary.json` gains fields. Consumers that ignore unknown keys are unaffected.
- A new script must be added to the download lists in the Azure DevOps templates and `ms.azure.deploy.yml`.
- Principal IDs, actions, tags and description appear in the PR comment, logs and summary. They are configuration, not secrets. Validation rejects masked values, and the docs say not to take these from secrets.
- Changing the allowed number of principals or actions in Azure later means updating one constant in the helper.
- Docs to update: `docs/configuration.md`, `docs/how-it-works.md`, `docs/troubleshooting.md`, `docs/examples/` (new `denyWriteAndDelete` examples for GitHub and Azure DevOps).
- Not verified locally: `az stack-whatif` is not available in the Azure CLI installed here (2.87.0), so its accepted flags and the exact stored shape from `az stack show` are confirmed by a spike in phase 1 of the plan.
