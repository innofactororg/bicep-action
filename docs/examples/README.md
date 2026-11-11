# Examples

Copy one, replace the IDs and names, and see the [configuration reference](../configuration.md) for every setting.

## GitHub Actions

Copy to `.github/workflows/`. Setup: [GitHub setup](../setup-github.md).

| Example | What it shows |
|---|---|
| [`github/recommended.yml`](./github/recommended.yml) | **Start here.** A subscription deployment as a deployment stack, with PSRule on a pinned baseline, the cost estimate with a budget, and a Bicep snapshot. The deploy job uses the plan's Bicep version and stack settings, and merges the pull request. |
| [`github/minimal.yml`](./github/minimal.yml) | The fewest inputs: a standard deployment to one resource group. |
| [`github/multi-environment.yml`](./github/multi-environment.yml) | Test, then production, from one pull request: separate subscriptions, parameters, stacks, environments and artifacts. Only production merges. |
| [`github/auto-approve-safe-plans.yml`](./github/auto-approve-safe-plans.yml) | Reads `whatif-summary.json` and skips the manual approval when the plan neither deletes nor detaches anything. Anything unclear fails closed to the reviewed environment. |

## Azure DevOps

Add to a folder such as `.pipelines/`. Setup: [Azure DevOps setup](../setup-azure-devops.md).

| Example | What it shows |
|---|---|
| [`../../.azuredevops/ms.azure.deploy.yml`](../../.azuredevops/ms.azure.deploy.yml) | **Start here.** One environment, every step inline in one file, no template repository needed. |
| [`azure-devops/multi-environment.yml`](./azure-devops/multi-environment.yml) | Test, then production, with the reusable [stage templates](../../.azuredevops/templates/), loaded from this repository through a GitHub service connection. |
| [`azure-devops/variable-group.yml`](./azure-devops/variable-group.yml) | One environment, with the stage templates and every setting in a variable group. |

## Pin the version

- **GitHub:** pin the actions to a release tag, `innofactororg/bicep-action/.github/actions/plan@v1`.
- **Azure DevOps:** set `WORKFLOW_VERSION` (and the template repository's `ref`) to the same tag.

Releases are listed under [tags](https://github.com/innofactororg/bicep-action/tags).
