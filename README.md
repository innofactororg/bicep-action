# Bicep workflow

[![GitHub Super-Linter](https://github.com/innofactororg/bicep-action/actions/workflows/linter.yml/badge.svg)](https://github.com/marketplace/actions/super-linter)

A reusable workflow to to manage Azure infrastructure with Bicep.

## Getting Started

To use the workflow, several prerequisite steps are required.

1. **Create GitHub Environment**

   The workflow utilizes GitHub Environments to enable an approval process for the deployment.

   [Create an environment](https://docs.github.com/actions/deployment/targeting-different-environments/using-environments-for-deployment#creating-an-environment) in the repository that use this workflow.

   Add **Required reviewers** that need to sign off on deployments. Save the protection rules.

   Limit the environment to the **main** branch.

1. **Setup Azure Identity**

   A Microsoft Entra ID application is required by this workload. It must have permission to deploy the code.

   Create a single application and give it the appropriate read/write permissions in Azure.

   [Add federated credentials](https://docs.microsoft.com/azure/developer/github/connect-from-azure?tabs=azure-portal%2Clinux#use-the-azure-login-action-with-openid-connect) for the scenario **GitHub Actions deploying Azure resources**.

   Add one credential for each of the following entity types:

   - **Branch**, specify GitHub branch name, e.g. `main`.
   - **Environment**, specify GitHub Environment name, e.g. `production`.
   - **Pull Request**.

Target each credential to the repository that use this workflow.

## Workflow

Each time a pull request is created or updated, the workflow will produce a [what-if](https://docs.microsoft.com/cli/azure/deployment/sub#az-deployment-sub-what-if) report and attach it to the pull request for easy review.

Each time a pull request review is submitted, the workflow will check if it is approved, and if so, the workflow will [deploy](https://docs.microsoft.com/cli/azure/deployment/sub#az-deployment-sub-create) the code to Azure.

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
      # A path or URI to the template / Bicep file or a template spec resource id.
      #
      # Default: main.bicep
      code_template: main.bicep

      # Deployment parameter values.
      #
      # Parameters may be supplied from a file using the @{path} syntax, a JSON string,
      # or as <KEY=VALUE> pairs. Parameters are evaluated in order, so when a value is
      # assigned twice, the latter value will be used. It is recommended that you supply
      # your parameters file first, and then override selectively using KEY=VALUE syntax.
      #
      # Default: ''
      parameters: main.bicepparam

      # The format to use for date and time in comments.
      # Corresponds to the locales parameter of the Intl.DateTimeFormat()
      # constructor. The default format, sv-SE, is yyyy-MM-dd HH:mm:ss.
      #
      # Default: sv-SE
      date_time_language_format: sv-SE

      # The time zone to use for time in comments.
      # It is used to convert from UTC time. Official list of time zones:
      # https://www.iana.org/time-zones.
      #
      # Default: Europe/Oslo
      time_zone: Europe/Oslo

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

## License

The code and documentation in this project are released under the [MIT License](LICENSE).
