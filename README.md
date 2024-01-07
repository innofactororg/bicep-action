# Bicep workflow

A reusable workflow to to manage Azure infrastructure with Bicep.

## Getting Started

To use the workflow, several prerequisite steps are required.

### Create GitHub Environment

The workflow utilizes GitHub Environments to enable an approval process for the deployment.

[Create an environment](https://docs.github.com/actions/deployment/targeting-different-environments/using-environments-for-deployment#creating-an-environment) in the repository that use this workflow.

Add **Required reviewers** that need to sign off on deployments. Save the protection rules.

### Setup Azure Identity

A Microsoft Entra ID application is required by this workload. It must have permission to deploy the code.

Create a single application and give it the appropriate read/write permissions in Azure.

#### Use federated credentials (recommended)

[Add federated credentials](https://docs.microsoft.com/azure/developer/github/connect-from-azure?tabs=azure-portal%2Clinux#use-the-azure-login-action-with-openid-connect) for the scenario **GitHub Actions deploying Azure resources** and for each repository that use this workflow.

To allow a pull request to validate and test deployments, add a credential where entity type is **Pull request**.

To allow deployments, add a credential where entity type is **Environment**. Specify the **GitHub Environment name** that is passed to the workflow, e.g. `production`.

Note that there is a limit of 20 federated credentials per application. For this reason, and for security reasons, it is recommended to create a separate application for each repository.

#### Use client secret

To use a **Client secret** instead of federated credentials, specify **AZURE_AD_CLIENT_SECRET** as a secret for the workflow, as shown in usage below.

## Workflow

### Plan

Each time a **pull request** is created or updated, the workflow will start and validate the code. If no issues are found in the code, a [what-if](https://docs.microsoft.com/cli/azure/deployment/sub#az-deployment-sub-what-if) report is generated for easy review.

### Deploy

The workflow can be started manually (**workflow dispatch**) or automatically when a **pull request review** is submitted with an **approved** state.

This stage is set to a specific [environment](#create-github-environment). If **required reviewers** have been added, the deployment job will only run after manual approval from one of the specified approvers.

When started, the workflow will [deploy](https://docs.microsoft.com/cli/azure/deployment/sub#az-deployment-sub-create) the code to Azure.

![Bicep workflow](images/deployment-action-flow.png)

1. Create a new branch and check in the needed code.
1. Create a Pull Request (PR) in GitHub once the changes are ready.
1. A GitHub Actions workflow will trigger to ensure the code is well formatted, internally consistent, and produces secure infrastructure. In addition, a What-If analysis will run to generate a preview of the changes that will happen in Azure.
1. Once appropriately reviewed, the PR can be merged into the main branch.
1. The changes are deployed to Azure.

## Usage

<!-- start usage -->

```yaml
name: Azure Deploy
on:
  workflow_dispatch:
  pull_request:
    types: [opened, synchronize]
    branches: [main]
    paths:
      - "**.json"
      - "**.bicep"
      - "**.bicepparam"

  pull_request_review:
    types: [submitted]

jobs:
  deploy:
    name: 🔧 Bootstrap
    uses: innofactororg/bicep-action/.github/workflows/bootstrap.yml@v1
    secrets:
      # The service principal secret used for Azure login.
      #
      # This secret is optional and only needed as an alternative to
      # federated credentials.
      #
      # Note: Don't add this secret if you want to use federated credentials.
      #
      AZURE_CLIENT_SECRET: ${{ secrets.AZURE_APP1_CLIENT_SECRET }}
    with:
      # The GitHub environment name for the Azure deploy job.
      #
      # Default: production
      environment: production

      # The tenant ID in which the subscription exists.
      #
      # Required
      azure_tenant_id: d0d0d0d0-b93b-4f96-9e73-4ea6caa2f3b4

      # The client ID of the service principal for Azure login.
      #
      # This service principal must have permission to deploy within the
      # Azure subscription.
      #
      # Required
      azure_client_id: d0d0d0d0-4558-43bb-896a-008e763058bd

      # The subscription ID in which to deploy the resources.
      #
      # Required
      azure_subscription_id: d0d0d0d0-ed29-4694-ac26-2e358c364506

      # The Azure location to store the deployment metadata.
      #
      # Default: westeurope
      location: westeurope

      # The deployment scope. Accepted: tenant, mg, sub, group.
      #
      # Default: sub
      scope: sub

      # Management group to create deployment at for mg scope.
      #
      # Default: ''
      management_group:

      # Resource group to create deployment at for group scope.
      #
      # Default: ''
      resource_group:

      # The template address.
      #
      # A path or URI to the a file or a template spec resource id.
      #
      # Default: main.bicep
      code_template: main.bicep

      # Deployment parameter values.
      #
      # A path, URI, JSON string, or <KEY=VALUE> pairs.
      #
      # Default: ''
      parameters: main.bicepparam

      # Required Azure resource providers.
      #
      # The workflow will try to register the specified providers in addition
      # to the providers that is detected in code by deployment validate.
      #
      # Default: ''
      azure_providers: "Microsoft.Advisor microsoft.support"

      # Seconds to wait between each provider status check.
      #
      # Default: '10'
      azure_provider_wait_seconds: 10

      # Times to check provider status before giving up.
      #
      # Default: '30'
      azure_provider_wait_count: 30

      # A comma separated list of modules to use for analysis.
      #
      # For a list of modules see
      # https://www.powershellgallery.com/packages?q=Tags%3A%22PSRule-rules%22
      #
      # Default: PSRule.Rules.Azure
      psrule_modules: PSRule.Rules.CAF

      # The name of a PSRule baseline to use.
      #
      # For a list of baseline names for module PSRule.Rules.Azure see
      # https://azure.github.io/PSRule.Rules.Azure/en/baselines/Azure.All/
      #
      # Default: Azure.Default
      psrule_baseline: Azure.GA_2023_12

      # Ignore rules for PSRule analysis.
      #
      # A comma separated list of specific rules to exclude from evaluation.
      #
      # Default: ''
      psrule_exclude: Azure.Resource.UseTags, Azure.ACR.MinSku

      # Azure Cost Estimator version.
      #
      # The version to use for cost estimation. See versions at
      # https://github.com/TheCloudTheory/arm-estimator/releases
      #
      # Default: '1.3'
      ace_version: 1.3

      # The merge method to use after a successful deployment.
      # Can be one of:
      #
      # merge - retain all of the commits.
      # squash - retain the changes but omit the individual commits.
      # rebase - move the commits to the tip of the target branch.
      # disable - turn off auto merge.
      #
      # Default: squash
      merge_method: disable

      # Prevent deleting the branch after merge.
      #
      # Default: false
      keep_branch_after_merge: true

      # The log verbosity. Can be one of:
      #
      # ERROR - Only show errors, suppressing warnings. Dump context at fail.
      # INFO - Standard log level. Always dump context.
      # VERBOSE - Increase logging verbosity. Always dump context.
      # DEBUG - Show all debug logs. Always dump context.
      #
      # Default: ERROR
      log_severity: INFO
```

<!-- end usage -->

## Passing secret as input

If the input value is stored as a secret, it can still be passed using the env syntax.

In the following example a secret called **AZURE_APP1_TENANT_ID** is passed to the input **azure_tenant_id** using environment variable **TENANT_ID**:

```yaml
name: Azure Deploy
on:
  workflow_dispatch:
  pull_request:
    types: [opened, synchronize]
    branches: [main]
    paths:
      - "**.bicep"
      - "**.bicepparam"

  pull_request_review:
    types: [submitted]

jobs:
  deploy:
    name: 🔧 Bootstrap
    uses: innofactororg/bicep-action/.github/workflows/bootstrap.yml@v1
    env:
      TENANT_ID: ${{ secrets.AZURE_APP1_TENANT_ID }}
    with:
      environment: sandbox1
      azure_tenant_id: ${{ env.TENANT_ID }}
      azure_client_id: 6a31b6a2-4558-43bb-896a-008e763058bd
      azure_subscription_id: aeac59a3-67af-474b-ac4a-67ee18414df1
      location: westeurope
      scope: sub
      code_template: main.bicep
      parameters: main.bicepparam
      log_severity: INFO
```

## License

The code and documentation in this project are released under the [MIT License](LICENSE).
