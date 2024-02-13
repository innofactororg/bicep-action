# Bicep deploy

This repository includes GitHub actions to plan and deploy Azure infrastructure.

For a version that works with Azure DevOps look at this [pipeline](.pipelines/README.md).

## Overview

![Flow overview](images/deploy-flow.drawio.png)

1. The user creates a new branch, then commits and push the code.
1. The user creates a pull request.
1. The workflow is automatically triggered and starts the [plan job](#plan-job).
1. If the plan job was successful, the workflow will wait for a [required reviewer](#get-started) to approve the [create job](#create-job).
1. When a reviewer has approved, the workflow starts the [create job](#create-job) to deploy the code.

## Get started

To set up a bicep deploy workflow, several prerequisite steps are required:

1. Create an [environment](https://docs.github.com/actions/deployment/targeting-different-environments/using-environments-for-deployment#creating-an-environment).

1. To prevent unapproved deployments, add **"Required reviewers"** to the environment. Remember to save the protection rules after making changes.

1. Register a [Microsoft identity platform application](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app).

1. Assign [Azure roles](https://learn.microsoft.com/en-us/azure/role-based-access-control/role-assignments-steps) to the application so it can deploy Azure infrastructure. For example, give it the **"Owner"** role on the target Azure subscription.

1. Give the repository Azure login permission:

   - **Option 1**: Add [federated credentials](https://docs.microsoft.com/azure/developer/github/connect-from-azure?tabs=azure-portal%2Clinux#use-the-azure-login-action-with-openid-connect) (recommended)

     - Use the scenario **"GitHub Actions deploying Azure resources"**.
     - Select entity type **"Pull request"** (needed for the [plan job](#plan-job)).
     - Save the credential.
     - Add another federated credential with the scenario **"GitHub Actions deploying Azure resources"**.
     - Select entity type **"Environment"** (needed for the [create job](#create-job)).
     - Specify the environment name that was created in step 1.
     - Save the credential.

     Note that there is a limit of 20 federated credentials per application. For this reason, and for security reasons, it is recommended to create a separate application for each repository.

   - **Option 2**: Add [client secret](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app#add-a-client-secret)

     - Add the secret from the app registration as a secret in the repository. Remember that the secret must be replaced when it expires.
     - Add **"AZURE_CLIENT_SECRET"** to the workflow, see [passing secrets](#passing-secrets).

### Auto merge

To allow pull requests to merge automatically once all required reviews and status checks have passed, enable **"Allow auto-merge"** in the repository settings under **"General"**.

For auto merge to work as intended, [branch protection](#branch-protection) must be configured.

### Branch protection

It is recommended to protect the default branch. This is done in the repository settings under **"Branches"**.

Recommended branch protection for production use:

- Require a pull request before merging
  - Require approvals
  - Dismiss stale pull request approvals when new commits are pushed
  - Require approval of the most recent reviewable push
- Require status checks to pass before merging
  - Require branches to be up to date before merging
  - Add the following status checks:
    - 🔧 Deploy / 🏃 Create
- Require conversation resolution before merging
- Require linear history
- Require deployments to succeed before merging (and select the environment that must succeed)

This ensures that no changes to the pull request are possible between the approval and the merging and that a successful plan and deploy has occurred.

## Workflow

The workflow is designed to run when a pull request is created or updated.

It has been tested on a [standard GitHub-hosted runner](https://docs.github.com/en/actions/using-github-hosted-runners/about-github-hosted-runners/about-github-hosted-runners#standard-github-hosted-runners-for-public-repositories) with workflow label **"ubuntu-22.04"**.

The concurrency setting is configured to ensure that only one workflow runs at any given time. If a new workflow starts with the same name, GitHub Actions will cancel any workflow already running with that name.

The following tools are used:

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/)
  - [az login](https://learn.microsoft.com/en-us/cli/azure/reference-index?view=azure-cli-latest#az-login)
  - [az bicep build](https://learn.microsoft.com/en-us/cli/azure/bicep?view=azure-cli-latest#az-bicep-build)
  - [az bicep build-params](https://learn.microsoft.com/en-us/cli/azure/bicep?view=azure-cli-latest#az-bicep-build-params)
  - [az provider register](https://learn.microsoft.com/en-us/cli/azure/provider?view=azure-cli-latest#az-provider-register)
  - [az deployment {SCOPE} create](https://learn.microsoft.com/en-us/cli/azure/deployment/sub?view=azure-cli-latest#az-deployment-sub-create)
  - [az deployment {SCOPE} validate](https://learn.microsoft.com/en-us/cli/azure/deployment/sub?view=azure-cli-latest#az-deployment-sub-validate)
  - [az deployment {SCOPE} what-if](https://learn.microsoft.com/en-us/cli/azure/deployment/sub?view=azure-cli-latest#az-deployment-sub-what-if)
- [Azure Cost Estimator](https://github.com/TheCloudTheory/arm-estimator)
- [curl](https://curl.se/)
- GitHub actions:
  - [checkout](https://github.com/actions/checkout/tree/b4ffde65f46336ab88eb53be808477a3936bae11)
  - [github-script](https://github.com/actions/github-script/tree/60a0d83039c74a4aee543508d2ffcb1c3799cdea)
  - [microsoft/ps-rule](https://github.com/microsoft/ps-rule/tree/2fb1024354743290eb724889d62c4f485a15373a)
  - [upload-artifact](https://github.com/actions/upload-artifact/tree/26f96dfa697d77e81fd5907df203aa23a56210a8)
- [GNU bash](https://www.gnu.org/software/bash/)
- [GNU bc](https://www.gnu.org/software/bc/)
- [GNU core utilities](https://www.gnu.org/software/coreutils/coreutils.html)
- [GNU find utilities](https://www.gnu.org/software/findutils/)
- [jq](https://jqlang.github.io/jq/)
- [sed](https://www.gnu.org/software/sed/)
- [unzip](https://infozip.sourceforge.net/)

### Plan job

The plan job will build and test the code. If no issues are found in the code, a [what-if](https://docs.microsoft.com/cli/azure/deployment/sub#az-deployment-sub-what-if) report is generated.

The PSRule steps will only run if **"rule_option"** is specified and points to a file that exist.

For more information about PSRule configuration, see:

- [Sample ps-rule.yaml](ps-rule.yaml)
- [Configuring options](https://azure.github.io/PSRule.Rules.Azure/setup/configuring-options/)
- [Configuring rule defaults](https://azure.github.io/PSRule.Rules.Azure/setup/configuring-rules/)
- [Available Options](https://microsoft.github.io/PSRule/v2/concepts/PSRule/en-US/about_PSRule_Options/)
- [Available Rules by resource type](https://azure.github.io/PSRule.Rules.Azure/en/rules/resource/)

### Create job

The create job will only run when the plan job was successful. It targets a specific [environment](#get-started). If the environment is configured with **required reviewers**, the job will require manual approval.

### Passing secrets

If the value of **"azure_tenant_id"**, **"azure_client_id"** or **"azure_subscription_id"** is stored as a secret, it can be passed using the secrets syntax.

Note that secrets are masked in the job log. The result is that IDs can't be seen and it may be difficult to see if the wrong ID is used.

```yaml
name: Azure Deploy
on:
  pull_request:
    branches: [main]
    paths: ["bicep/**.bicep*"]
    types: [opened, synchronize]

permissions: {}

jobs:
  deploy:
    name: 🔧 Deploy
    uses: innofactororg/bicep-action/.github/workflows/deploy.yml@beta6
    permissions:
      contents: write
      id-token: write
      pull-requests: write
    secrets:
      AZURE_CLIENT_ID: ${{ secrets.CLIENT_ID }}
      AZURE_CLIENT_SECRET: ${{ secrets.CLIENT_SECRET }}
      AZURE_SUBSCRIPTION_ID: ${{ secrets.SUBSCRIPTION_ID }}
      AZURE_TENANT_ID: ${{ secrets.TENANT_ID }}
    with:
      environment: sandbox1
      location: westeurope
      log_severity: INFO
      rule_option: ps-rule.yaml
      scope: sub
      template: main.bicep
      template_parameters: main.bicepparam
```

### Usage

```yaml
name: Azure Deploy
on:
  pull_request:
    branches: [main]
    paths: ["bicep/**.bicep*"]
    types: [opened, synchronize]

permissions: {}

jobs:
  deploy:
    name: 🔧 Deploy
    uses: innofactororg/bicep-action/.github/workflows/deploy.yml@beta6
    permissions:
      contents: write # for Auto Merge
      id-token: write # for Log in to Azure (Federated)
      pull-requests: write # for Comment when done
    secrets:
      # The client ID of the service principal for Azure login.
      #
      # This service principal must have permission to deploy within the
      # Azure subscription.
      #
      # Required if input azure_client_id is not specified.
      # Ignored if input azure_client_id is specified.
      AZURE_CLIENT_ID: ${{ secrets.CLIENT_ID }}

      # The service principal secret used for Azure login.
      #
      # Note: Don't add this secret if you want to use federated credentials.
      #
      # Optional: only needed as an alternative to federated credentials.
      AZURE_CLIENT_SECRET: ${{ secrets.CLIENT_SECRET }}

      # The subscription ID in which to deploy the resources.
      #
      # Required if input azure_subscription_id is not specified.
      # Ignored if input azure_subscription_id is specified.
      AZURE_SUBSCRIPTION_ID: ${{ secrets.SUBSCRIPTION_ID }}

      # The tenant ID in which the subscription exists.
      #
      # Required if input azure_tenant_id is not specified.
      # Ignored if input azure_tenant_id is specified.
      AZURE_TENANT_ID: ${{ secrets.TENANT_ID }}

    with:
      # Auto merge method to use after successful deployment.
      #
      # Can be one of: merge, squash, rebase or disable (turn off auto merge).
      #
      # Default: squash
      auto_merge: disable

      # The client ID of the service principal for Azure login.
      #
      # This service principal must have permission to deploy within the
      # Azure subscription.
      #
      # Required if secret AZURE_CLIENT_ID is not specified.
      azure_client_id: d0d0d0d0-4558-43bb-896a-008e763058bd

      # A comma separated list of Azure resource providers.
      #
      # The workflow will try to register the specified providers in addition
      # to the providers that is detected in code by deployment validate.
      #
      # Default: ''
      azure_providers: Microsoft.Advisor,microsoft.support

      # Times to check provider status before giving up.
      #
      # Default: 30
      azure_provider_wait_count: 30

      # Seconds to wait between each provider status check.
      #
      # Default: 10
      azure_provider_wait_seconds: 10

      # The subscription ID in which to deploy the resources.
      #
      # Required if secret AZURE_SUBSCRIPTION_ID is not specified.
      azure_subscription_id: d0d0d0d0-ed29-4694-ac26-2e358c364506

      # The tenant ID in which the subscription exists.
      #
      # Required if secret AZURE_TENANT_ID is not specified.
      azure_tenant_id: d0d0d0d0-b93b-4f96-9e73-4ea6caa2f3b4

      # Max acceptable estimated cost.
      #
      # Exceeding threshold causes plan to fail.
      #
      # Default: -1
      cost_threshold: 1000

      # Currency code to use for estimations.
      #
      # See allowed values at
      # https://github.com/TheCloudTheory/arm-estimator/wiki/Options#currency
      #
      # Default: 'EUR'
      currency: USD

      # The GitHub environment name to use for the create job.
      #
      # Default: production
      environment: production

      # The Azure location to store the deployment metadata.
      #
      # Default: westeurope
      location: southcentralus

      # The log verbosity. Can be one of:
      #
      # ERROR - Only show errors, suppressing warnings. Dump context at fail.
      # INFO - Standard log level. Always dump context.
      # VERBOSE - Increase logging verbosity. Always dump context.
      # DEBUG - Show all debug logs. Always dump context.
      #
      # Default: ERROR
      log_severity: INFO

      # Management group to create deployment at for mg scope.
      #
      # Default: ''
      management_group:

      # Resource group to create deployment at for group scope.
      #
      # Default: ''
      resource_group:

      # The name of a PSRule baseline to use.
      #
      # For a list of baseline names for module PSRule.Rules.Azure see
      # https://azure.github.io/PSRule.Rules.Azure/en/baselines/Azure.All/
      #
      # Default: Azure.Default
      rule_baseline: Azure.GA_2023_12

      # A comma separated list of modules to use for analysis.
      #
      # For a list of modules see
      # https://www.powershellgallery.com/packages?q=Tags%3A%22PSRule-rules%22
      #
      # Default: Az.Resources,PSRule.Rules.Azure
      rule_modules: Az.Resources,PSRule.Rules.CAF

      # The path to an options file.
      #
      # Default: ''
      rule_option: bicep/pattern1/ps-rule.prod.yaml

      # The deployment scope. Accepted: tenant, mg, sub, group.
      #
      # Default: sub
      scope: sub

      # The template address.
      #
      # A path or URI to a file or a template spec resource id.
      #
      # Default: main.bicep
      template: bicep/pattern1/main.bicep

      # Deployment parameter values.
      #
      # Either a path, URI, JSON string, or <KEY=VALUE> pairs.
      #
      # Default: ''
      template_parameters: bicep/pattern1/main.prod.bicepparam

      # Azure Cost Estimator version.
      #
      # The version to use for cost estimation. See versions at
      # https://github.com/TheCloudTheory/arm-estimator/releases
      #
      # Default: '1.4'
      version_ace_tool: "1.4"
```

## License

The code and documentation in this project are released under the [BSD 3-Clause License](LICENSE).
