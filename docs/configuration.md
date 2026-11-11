# Configuration reference

Every setting has a GitHub action input and an Azure DevOps variable with the same meaning. This page lists them all, grouped by what they control.

- [How settings are passed](#how-settings-are-passed)
- [All settings at a glance](#all-settings-at-a-glance)
- [Azure connection](#azure-connection)
- [Template and scope](#template-and-scope)
- [Deployment mode and stacks](#deployment-mode-and-stacks)
- [Quality gates](#quality-gates)
- [Existing tags](#existing-tags)
- [Resource providers](#resource-providers)
- [Pull request and merge](#pull-request-and-merge)
- [Logging and artifacts](#logging-and-artifacts)
- [Azure DevOps only](#azure-devops-only)
- [Outputs](#outputs)
- [Secrets](#secrets)
- [Recommended settings](#recommended-settings)

## How settings are passed

**GitHub.** Settings are inputs of the two composite actions, `innofactororg/bicep-action/.github/actions/plan` and `.../deploy`, given under `with:`. Settings that both actions use must have the **same value** in both. The examples keep them in a workflow-level `env:` block for that reason.

**Azure DevOps.** Settings are pipeline variables. Put them in the `variables:` section, in a [variable group](https://learn.microsoft.com/azure/devops/pipelines/library/variable-groups), or, with the [stage templates](../.azuredevops/templates/), in the `variables` parameter. Pipeline variables reach the scripts as environment variables automatically. An unset variable counts as empty.

## All settings at a glance

Job: **P** = plan, **D** = deploy.

| Setting | GitHub input | Azure DevOps variable | Job | Default |
|---|---|---|---|---|
| Client ID | `azure_client_id` (required) | service connection | P D | |
| Client secret | `azure_client_secret` | service connection | P D | empty (use OpenID Connect) |
| Tenant ID | `azure_tenant_id` (required) | service connection | P D | |
| Subscription ID | `azure_subscription_id` (required) | `SUBSCRIPTION_ID` | P D | |
| Service connection | | `SERVICE_CONNECTION` | P D | |
| Subscription wait | `subscription_wait_minutes` | `SUBSCRIPTION_WAIT_MINUTES` | P D | `30` |
| Scope | `scope` (required) | `IN_SCOPE` | P D | |
| Location | `location` (required) | `IN_LOCATION` | P D | |
| Resource group | `resource_group` | `IN_RESOURCE_GROUP` | P D | empty |
| Management group | `management_group` | `IN_MANAGEMENT_GROUP` | P D | empty |
| Template | `template` (required) | `IN_TEMPLATE` | P D | |
| Template parameters | `template_parameters` | `IN_TEMPLATE_PARAMS` | P D | empty |
| Deployment mode | `deployment_mode` | `DEPLOYMENT_MODE` | P D | `deployment` |
| Stack name | `stack_name` | `STACK_NAME` | P D | repository name |
| Action on unmanage | `stack_action_on_unmanage` | `STACK_ACTION_ON_UNMANAGE` | P D | `detachAll` |
| Deny settings | `stack_deny_settings_mode` | `STACK_DENY_SETTINGS_MODE` | P D | `none` |
| Approved deletes | `stack_approved_deletes` | `STACK_APPROVED_DELETES` | P D | empty |
| Plan stack settings | `plan_stack_settings` | automatic | D | empty |
| Bicep version | `bicep_version` | automatic | D | empty (latest) |
| PSRule options file | `rule_option` | `RULE_OPTION` | P | empty (PSRule skipped) |
| PSRule baseline | `rule_baseline` | `RULE_BASELINE` | P | `Azure.Default` |
| PSRule modules | `rule_modules` | `RULE_MODULES` | P | GitHub: `Az.Resources,PSRule.Rules.Azure`; Azure DevOps: empty |
| Cost estimator version | `version_ace_tool` | `VERSION_ACE` | P | GitHub: `1.6.5`; Azure DevOps: empty (skipped) |
| Cost threshold | `cost_threshold` | `COST_THRESHOLD` | P | `-1` (report only) |
| Currency | `currency` | `IN_CURRENCY` | P | `EUR` |
| Existing tag names | `existing_tags_keys` | `EXISTING_TAGS_KEYS` | P D | empty (skipped) |
| Existing tags resource groups | `existing_tags_resource_groups` | `EXISTING_TAGS_RESOURCE_GROUPS` | P D | empty (all groups) |
| Resource providers | `azure_providers` | `IN_PROVIDERS` | P D | empty |
| Provider wait count | `azure_provider_wait_count` | `WAIT_COUNT` | D | `30` |
| Provider wait seconds | `azure_provider_wait_seconds` | `WAIT_SECONDS` | D | `10` |
| Auto merge | `auto_merge` | | D | `squash` |
| Token | `token` | `System.AccessToken` (automatic) | P D | `${{ github.token }}` |
| Log verbosity | `log_severity` | `IN_SEVERITY` | P D | GitHub: `ERROR`; Azure DevOps: empty (standard) |
| Artifact identifier | `artifact_identifier` | `ARTIFACT_IDENTIFIER` | P D | empty |
| Environment | `environment:` on the deploy job | `ENVIRONMENT` / `environmentName` | D | |
| Script version | `@<tag>` in `uses:` | `WORKFLOW_VERSION` | P D | |

## Azure connection

### `azure_client_id`, `azure_tenant_id`, `azure_client_secret` (GitHub)

The application (client) ID and tenant ID of the Microsoft Entra application that signs in to Azure. Both are required.

Leave `azure_client_secret` empty to sign in with **OpenID Connect** through federated credentials, which is recommended. Set it, as a secret, only when the application signs in with a client secret. See [GitHub setup](./setup-github.md#2-let-the-repository-sign-in-to-azure).

### `SERVICE_CONNECTION` (Azure DevOps)

The name of an Azure Resource Manager service connection. Use the workload identity federation type. It replaces the client ID, tenant ID and secret. With the stage templates it is the `serviceConnection` parameter.

### `azure_subscription_id` / `SUBSCRIPTION_ID`

The subscription to deploy to. It is required on GitHub. In Azure DevOps it is also the subscription the scripts select, which matters when the service connection is scoped to a management group and signs in at tenant level.

### `subscription_wait_minutes` / `SUBSCRIPTION_WAIT_MINUTES`

How many minutes to wait for the subscription to become visible to the signed-in identity. A new role assignment, or a subscription that was just created or moved, can take a while to appear. Only the "subscription doesn't exist in cloud" error is retried; any other error fails at once. Default `30`.

## Template and scope

### `scope` / `IN_SCOPE`

Where the deployment is created: `tenant`, `mg` (management group), `sub` (subscription) or `group` (resource group). Required.

### `location` / `IN_LOCATION`

The Azure region that stores the deployment metadata, for example `westeurope`. Required. It is not used for the `group` scope, where the resource group's region applies. It does not decide where resources go; the template does.

### `resource_group` / `IN_RESOURCE_GROUP`

The resource group to deploy to. Required for the `group` scope.

### `management_group` / `IN_MANAGEMENT_GROUP`

The management group ID to deploy to. Required for the `mg` scope.

### `template` / `IN_TEMPLATE`

The template to deploy. It can be:

- A path to a `.bicep` or ARM `.json` file, relative to the repository root, for example `infra/main.bicep`.
- A URL to a template.
- A template spec resource ID (`/subscriptions/.../templateSpecs/<name>/versions/<version>`). The Bicep build and the cost estimate are then skipped.

### `template_parameters` / `IN_TEMPLATE_PARAMS`

The parameter values, in any form `az deployment ... --parameters` accepts:

- A `.bicepparam` file, which is recommended. It also turns on the [Bicep snapshot](./how-it-works.md#bicep-snapshot) check.
- A JSON parameters file or URL.
- Inline `KEY=VALUE` pairs, for example `namePrefix=t serviceShort=tst`.

## Deployment mode and stacks

See [Deployment stacks and the delete gate](./how-it-works.md#deployment-stacks-and-the-delete-gate). Use the **same values in the plan and deploy jobs**; a deployment whose settings differ from its plan fails.

### `deployment_mode` / `DEPLOYMENT_MODE`

- `deployment`, the default: a standard ARM deployment.
- `stack`: an Azure deployment stack. This is recommended for new pipelines, and the Azure DevOps starter pipeline uses it.

### `stack_name` / `STACK_NAME`

The name of the deployment stack. It defaults to the repository name. Characters that a stack name cannot hold become `-`, and the name is cut to 90 characters. Give each pipeline that deploys to the same scope its own name.

### `stack_action_on_unmanage` / `STACK_ACTION_ON_UNMANAGE`

What happens to a resource that is removed from the template:

| Value | Effect |
|---|---|
| `detachAll` (default) | The resource is released from the stack and left in place. Nothing is ever deleted. |
| `deleteResources` | Resources are deleted; resource groups and management groups are detached. |
| `deleteAll` | Resources, resource groups and management groups are deleted. |

With either delete mode, every delete must be listed in `stack_approved_deletes`, and a what-if that is not deterministic fails the plan.

### `stack_deny_settings_mode` / `STACK_DENY_SETTINGS_MODE`

`none` (the default), `denyDelete` or `denyWriteAndDelete`. With a deny mode, Azure blocks changes to the stack's resources that are made outside the stack.

### `stack_approved_deletes` / `STACK_APPROVED_DELETES`

The path to a JSON file holding an array of the resource IDs the stack may delete. The match ignores case:

```json
[
  "/subscriptions/<id>/resourceGroups/rg-app/providers/Microsoft.Storage/storageAccounts/stold"
]
```

The plan fails on any delete that is not listed. With a delete mode, the deploy job checks again just before it deploys. Commit the file, so that every delete is approved in a reviewed change.

### `plan_stack_settings` (GitHub deploy action)

The plan action's `stack_settings` output. A stack deployment requires it, and a deployment whose mode or stack settings differ from it fails. In Azure DevOps the deploy stage reads it from the plan stage automatically (`PLAN_STACK_SETTINGS`).

### `bicep_version` (GitHub deploy action)

The plan action's `bicep_version` output. The deployment installs and compiles with that version, so it deploys exactly what the what-if showed. If it is empty, the latest version is used. If it cannot be installed, the deployment stops and asks for a new plan. In Azure DevOps this is automatic (`BICEP_VERSION`).

## Quality gates

### PSRule

| Setting | Meaning |
|---|---|
| `rule_option` / `RULE_OPTION` | The path to a PSRule options file, for example [`ps-rule.yaml`](../ps-rule.yaml). **Empty skips PSRule.** |
| `rule_baseline` / `RULE_BASELINE` | The baseline. `Azure.Default` takes every new rule as soon as it is released. Pin a quarterly baseline such as `Azure.GA_2026_03` for stable results. A quarterly baseline ignores local rules unless the options file sets `Rule.IncludeLocal: true`. [Baselines](https://azure.github.io/PSRule.Rules.Azure/en/baselines/Azure.All/) |
| `rule_modules` / `RULE_MODULES` | Comma-separated modules. Use `Az.Resources,PSRule.Rules.Azure`. In Azure DevOps there is no default, so set it, as the starter pipeline does. |
| `PSRULE_AZURE_RESOURCE_MODULE_NOWARN` (Azure DevOps) | `true` hides a warning about the Az.Resources module version. |

To turn off one rule, exclude it in the options file: `rule: { exclude: [Azure.VNET.PrivateSubnet] }`.

### Cost estimate

| Setting | Meaning |
|---|---|
| `version_ace_tool` / `VERSION_ACE` | The [Azure Cost Estimator](https://github.com/TheCloudTheory/arm-estimator/releases) version. **Empty skips the estimate.** Use 1.6.5 or later; 1.6 cannot read templates compiled with `languageVersion` 2.0. |
| `cost_threshold` / `COST_THRESHOLD` | The maximum monthly estimate. Above it the plan fails. `-1` (or unset) only reports the cost, and an estimator failure is then a warning. With a number set, an estimator failure fails the plan. |
| `currency` / `IN_CURRENCY` | The [currency code](https://github.com/TheCloudTheory/arm-estimator/wiki/Options#currency). Empty means `EUR`. |

### Bicep snapshot

There is no setting. The check runs when `template_parameters` is a `.bicepparam` file and a `<name>.snapshot.json` file sits next to it. See [Bicep snapshot](./how-it-works.md#bicep-snapshot).

## Existing tags

See [Existing tags](./how-it-works.md#existing-tags). Use the same values in the plan and deploy jobs.

| Setting | Meaning |
|---|---|
| `existing_tags_keys` / `EXISTING_TAGS_KEYS` | Comma-separated tag names, for example `createdOn`. Their current values are exposed to the template as the environment variable `EXISTING_TAGS`. **Empty skips the step.** Only the `sub` and `group` scopes are supported. |
| `existing_tags_resource_groups` / `EXISTING_TAGS_RESOURCE_GROUPS` | Comma-separated resource group names, or prefixes ending with `*`, for example `rg-app-prod,rg-shared-*`. Case is ignored. Only these groups and their resources are listed, which keeps platform groups out of `EXISTING_TAGS` and out of a snapshot. With the `group` scope it must include that group. Empty means every group in the scope. |

## Resource providers

| Setting | Meaning |
|---|---|
| `azure_providers` / `IN_PROVIDERS` | Comma-separated resource providers to register in addition to those that `validate` finds in the template. **`disable`** turns registration off, for identities that are not allowed to register providers. |
| `azure_provider_wait_count` / `WAIT_COUNT` | How many times to check a provider's status before giving up. Default `30`. Set it in Azure DevOps; the starter pipeline does. |
| `azure_provider_wait_seconds` / `WAIT_SECONDS` | Seconds between the checks. Default `10`. |

The plan's `providers` output passes the found providers to the deploy job. The examples wire it up, and in Azure DevOps it is automatic.

The Azure DevOps [deploy stage template](../.azuredevops/templates/deploy-stage.yml) fixes the waits at 30 checks, 10 seconds apart. `WAIT_COUNT` and `WAIT_SECONDS` only take effect in the inline starter, [`ms.azure.deploy.yml`](../.azuredevops/ms.azure.deploy.yml).

## Pull request and merge

### `token` (GitHub)

The token used to comment on the pull request and to turn on auto merge. The default `${{ github.token }}` works when the job has `pull-requests: write`, and `contents: write` for auto merge. In Azure DevOps the pipeline uses `System.AccessToken`. The build service then needs **Contribute to pull requests** on the repository.

### `auto_merge` (GitHub deploy action)

After a successful deployment, turn on auto merge for the pull request with `merge`, `squash` (the default) or `rebase`. Any other value, or an empty one, turns it off. Auto merge needs **Allow auto-merge** in the repository settings and at least one required status check. See [GitHub setup](./setup-github.md#5-auto-merge-optional).

## Logging and artifacts

### `log_severity` / `IN_SEVERITY`

| Value | Effect |
|---|---|
| `ERROR` | Only errors (`--only-show-errors`). This is the GitHub default. |
| `INFO` | Standard output. Empty has the same effect in Azure DevOps. |
| `VERBOSE` | `--verbose`. |
| `DEBUG` | `--debug`. |

With any value other than `ERROR`, the job also prints debug information. It always does when a step fails.

### `artifact_identifier` / `ARTIFACT_IDENTIFIER`

Added to the log artifact names. Give each plan and deploy pair its own value when several run in one workflow or pipeline, for example one per environment, so their artifacts do not collide.

## Azure DevOps only

| Variable | Meaning |
|---|---|
| `SERVICE_CONNECTION` | The Azure Resource Manager service connection. With the stage templates it is the `serviceConnection` parameter. |
| `ENVIRONMENT` | The Azure DevOps environment of the deploy job. Its approval check is the review gate. With the stage templates it is the `environmentName` parameter. |
| `WORKFLOW_VERSION` | The bicep-action tag or branch whose scripts the pipeline downloads, for example `v1`. Pin a tag. |
| `PSRULE_AZURE_RESOURCE_MODULE_NOWARN` | `true` hides the Az.Resources version warning. |

The deploy stage reads `BICEP_VERSION`, `PLAN_STACK_SETTINGS` and the providers (`IN_PROVIDERS`) from the plan stage's outputs. Do not set them yourself.

## Outputs

| GitHub plan action output | Azure DevOps output variable | Meaning |
|---|---|---|
| `providers` | `validate.providers` | The resource providers the template uses, plus `azure_providers`. |
| `bicep_version` | `what_if.bicep_version` | The Bicep CLI version the plan compiled with. |
| `stack_settings` | `what_if.stack_settings` | The plan's mode and stack settings, for example `deployment`, or `stack;id=<stack id>;unmanage=detachAll;deny=none`. |
| `whatif_summary` | `what_if.whatif_summary` | The path to `whatif-summary.json` on the agent. The file is also in the plan logs artifact. See [What-if summary file](./how-it-works.md#what-if-summary-file). |

The deploy action has no outputs.

## Secrets

On GitHub, the client ID, subscription ID and tenant ID can be passed as secrets. That hides them in logs, which also makes a wrong ID harder to spot. A client secret must be a secret:

```yaml
with:
  azure_client_id: ${{ secrets.AZURE_CLIENT_ID }}
  azure_client_secret: ${{ secrets.AZURE_CLIENT_SECRET }} # only without OpenID Connect
  azure_subscription_id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
  azure_tenant_id: ${{ secrets.AZURE_TENANT_ID }}
```

In Azure DevOps the service connection holds the credentials. Put any other sensitive values in a variable group, and allow the pipeline to read it.

Template parameters that are secrets should be `@secure()`. Their values are not written to the Bicep snapshot. They are **not** kept out of the logs artifact, though: the plan copies the compiled parameters file (`*.parameters.json`) into it, and inline `KEY=VALUE` parameters appear in the logged commands. Do not put secret values in the parameters file or inline. Pass them from Key Vault references, or from the pipeline's secret variables through `readEnvironmentVariable()`, and keep the logs artifact as private as the repository.

## Recommended settings

For a new pipeline:

| Setting | Value | Why |
|---|---|---|
| `deployment_mode` | `stack` | Azure tracks the template's resources, and the plan shows deletes. |
| `stack_action_on_unmanage` | `detachAll` | Nothing is deleted by accident. Switch to a delete mode once the delete gate is part of your review. |
| `template_parameters` | a `.bicepparam` file, plus a committed snapshot | The snapshot shows the exact resource change in the pull request diff. |
| `rule_option`, `rule_baseline` | an options file and a quarterly baseline | Rules are checked, and results stay stable. |
| `version_ace_tool`, `cost_threshold` | `1.6.5`, and a budget or `-1` | The cost of every change is visible. |
| `log_severity` | `INFO` | Readable logs without debug noise. |
