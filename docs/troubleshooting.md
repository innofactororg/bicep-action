# Troubleshooting

Start with the pull request comment: each step that failed writes its reason there. The full logs are in the job log and in the logs artifact. See [Logs and artifacts](./how-it-works.md#logs-and-artifacts). Set `log_severity` (`IN_SEVERITY`) to `INFO`, `VERBOSE` or `DEBUG` for more detail.

## Sign-in and permissions

| Message | Cause | Fix |
|---|---|---|
| `AADSTS700213: No matching federated identity record found` | The federated credential's subject does not match what GitHub sent. | Compare the subject in the error with the credential. New repositories use the immutable form `repo:<owner>@<owner-id>/<repo>@<repo-id>:...`. See [GitHub setup](./setup-github.md#2-let-the-repository-sign-in-to-azure). The plan needs a **Pull request** credential and the deploy job an **Environment** credential. |
| `The subscription of '<id>' doesn't exist in cloud 'AzureCloud'` (after retries) | The identity still cannot see the subscription after `subscription_wait_minutes`. | Check the role assignment and its scope. A new assignment, or a subscription that was just moved, can take more than an hour to become visible. Raise `subscription_wait_minutes` for new subscriptions. |
| `AuthorizationFailed` in validate or what-if | The identity lacks a permission that the deployment needs. | Validate and what-if need the same permissions as the deployment. Role assignments need Owner or RBAC Administrator. |
| `AuthorizationFailed` naming `deploymentStacks/manageDenySetting/action` | A stack with deny settings, and an identity without that permission. | Use Owner or **Azure Deployment Stack Owner**, or set `stack_deny_settings_mode: none`. |

### Cross-subscription permissions

A template that touches resources in another subscription needs roles there too. Common cases:

- **Private endpoints with central private DNS zones.** Grant **Private DNS Zone Contributor** on the zone (`Microsoft.Network/privateDnsZones/join/action`).
- **Diagnostic settings to a central Log Analytics workspace.** Grant **Log Analytics Contributor** on the workspace (`Microsoft.OperationalInsights/workspaces/sharedKeys/action`).

```bash
# Object ID of the pipeline identity (from its application/client ID)
az ad sp show --id <application-id> --query id -o tsv

az role assignment create \
  --assignee-object-id <object-id> --assignee-principal-type ServicePrincipal \
  --role "Private DNS Zone Contributor" \
  --scope "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/privateDnsZones/<zone>"
```

## The plan fails

| Symptom | Cause | Fix |
|---|---|---|
| **Bicep snapshot** shows a difference | The template now produces different resources than the committed snapshot. | If the change is intended, run the command from the comment and commit the new snapshot. If you changed nothing, a Bicep upgrade, or a value that comes from outside the template, can cause it; the comment says when the Bicep version differs. |
| Snapshot differs with no code change, around `EXISTING_TAGS` | Tags outside the template changed: a platform resource group gained or lost a requested tag. | Set `existing_tags_resource_groups` to the template's own groups. See [Existing tags](./how-it-works.md#existing-tags). |
| **The stack would delete resources that are not approved** | A resource left the template under a delete mode. | If the delete is intended, add the resource ID to the `stack_approved_deletes` file. If not, restore it in the template, or use `detachAll`. |
| **The what-if result is not deterministic** | Some resource names are only known at deploy time, and a delete mode is on. | Use `detachAll`, or make those names known at plan time, for example from parameters instead of runtime values. |
| **This Azure CLI has no stack-whatif command** | The agent's Azure CLI is too old for deployment stacks. | Update the Azure CLI on a self-hosted agent, or use a hosted one. |
| **One or more rules reported failure** | A PSRule rule failed. | Fix the resource, or exclude the rule in the options file. Pin a quarterly baseline so new rules don't surprise you. |
| **PSRule could not complete the analysis** | PSRule failed without a rule failing, for example because it could not expand a Bicep or parameter file. | Read the errors above the message in the log. The rule results are not the cause. |
| **Total estimated cost exceeds** `<threshold>` | The cost estimate is above `cost_threshold`. | Raise the threshold, or change the template. |
| **The cost estimate is unavailable** (warning) | The estimator failed and no threshold is set. | The plan continues. Use ACE 1.6.5 or later for `languageVersion` 2.0 templates. |
| **EXISTING_TAGS is ... bytes, above the 120000 byte limit** | Too many tagged resources for one environment variable. | Request fewer tags, or set `existing_tags_resource_groups`. |
| **EXISTING_TAGS_RESOURCE_GROUPS ... does not include the resource group** | `group` scope, and a filter that excludes that group. | Add the group to the filter, or clear the filter. |
| **Unable to get the latest Bicep CLI** | The plan could not install the latest Bicep release, after one retry. | Re-run. The plan never falls back to an older compiler. |

## The deployment fails before deploying

| Message | Cause | Fix |
|---|---|---|
| **The deployment settings ... differ from the settings the plan used** | The mode or stack settings changed between the plan and the deployment. | Use the same values in both jobs, and re-run the plan. |
| **A stack deployment needs the settings the plan used** | GitHub: `plan_stack_settings` was not passed to the deploy action. | Pass `${{ needs.plan.outputs.stack_settings }}`. See the [examples](./examples/github/). |
| **The plan was made as a deployment stack, but this deployment is a standard deployment** | `deployment_mode` differs between the jobs. | Use the same `deployment_mode` in both. |
| **The plan was made with Bicep CLI** `<version>`**, but that version could not be installed** | The plan's Bicep version is no longer available. | Run the plan again, so it is made with a version that can be installed. |
| Providers time out | A provider did not register in `WAIT_COUNT` × `WAIT_SECONDS`. | Raise them, or register the provider by hand. |

## Pull request and merge

| Symptom | Cause | Fix |
|---|---|---|
| No comment on the pull request (GitHub) | The job lacks `pull-requests: write`, or the token cannot write. | Add the permission. See [GitHub setup](./setup-github.md#4-add-the-workflow). |
| No comment on the pull request (Azure DevOps) | The build service lacks **Contribute to pull requests**. | Grant it on the repository. See [Azure DevOps setup](./setup-azure-devops.md#4-let-the-pipeline-comment-on-pull-requests). |
| Auto merge fails: **Pull request is in unstable status** | The branch has no required status check. | Add branch protection with a required check, or set `auto_merge` to empty. |
| A run waits, or a waiting run is cancelled | The examples lock each Azure target with `concurrency` (`cancel-in-progress: false`). A second pull request waits until the first is deployed or rejected, and GitHub keeps only the newest waiting run. | Intended. It works like an Atlantis lock. Reject or finish the pending deployment to free the target. |

## Artifacts and logs (Azure DevOps)

- Artifact names must be unique within a run. `ARTIFACT_IDENTIFIER` separates environments, and `System.JobAttempt` separates re-runs, so each attempt keeps its own logs.
- The upload steps use `continueOnError: true`, so a failed upload never fails the stage.
- Each stage ends with a **Pipeline summary**: the status, the configuration, the steps that produced output, and the artifacts.
- The **Debug information** step runs when a step fails, or when `IN_SEVERITY` is not `ERROR`. It shows the pipeline context, the configuration, the tool versions, the Azure account and the environment variables.

## Still stuck?

Open an [issue](https://github.com/innofactororg/bicep-action/issues/new/choose) with the comment and the relevant part of the log. Remove subscription IDs and resource names that you do not want to make public.
