# Bicep deploy pipeline

A pipeline to plan and deploy Azure infrastructure.

## Overview

![Deploy pipeline](../images/deploy-flow.azdo.drawio.png)

1. The user creates a new branch, then commits and push the code.
1. The user creates a pull request.
1. The pipeline is automatically triggered and starts the [plan job](#plan-job).
1. If the plan job was successful, the pipeline will wait for a [required reviewer](#get-started) to approve the [create job](#create-job).
1. When a reviewer has approved, the pipeline starts the [create job](#create-job) to deploy the code.

## Get started

To use the pipeline, several prerequisite steps are required:

1. Install the [PSRule](https://marketplace.visualstudio.com/items?itemName=bewhite.ps-rule) Azure DevOps extension.

1. Create an [environment](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/environments?view=azure-devops).

1. To prevent unapproved deployments, add the [**"Approvals"**](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/approvals?view=azure-devops&tabs=check-pass#approvals) check to the environment.

1. Create a [Azure Resource Manager workload identity service connection](https://learn.microsoft.com/en-us/azure/devops/pipelines/release/configure-workload-identity?view=azure-devops).

1. Assign appropriate [Azure roles](https://learn.microsoft.com/en-us/azure/role-based-access-control/role-assignments-steps) to the application.

1. [If needed, create a repo](https://learn.microsoft.com/en-us/azure/devops/repos/git/create-new-repo?view=azure-devops#create-a-repo-using-the-web-portal).

1. Add the [azure-pipelines-deploy.yml](azure-pipelines-deploy.yml) to a **".pipelines"** repo folder.

1. Customize the variable values in the **"azure-pipelines-deploy.yml"** file and commit the changes.

1. Go to the Azure DevOps **Pipelines** page. Then choose the action to create a **New pipeline**.

1. Select **Azure Repos Git** as the location of the source code.

1. When the list of repositories appears, select the repository.

1. Select **Existing Azure Pipelines YAML file** and choose the YAML file: /.pipelines/azure-pipelines-deploy.yml.

1. Save the pipeline without running it.

1. Configure [branch policies](https://learn.microsoft.com/en-us/azure/devops/repos/git/branch-policies?view=azure-devops&tabs=browser#configure-branch-policies) for the default/main branch.

1. Add a [build validation branch policy](https://learn.microsoft.com/en-us/azure/devops/repos/git/branch-policies?view=azure-devops&tabs=browser#build-validation).

## Pipeline

### Plan job

The plan job will build and test the code. If no issues are found in the code, a [what-if](https://docs.microsoft.com/cli/azure/deployment/sub#az-deployment-sub-what-if) report is generated.

The plan job use the following tools:

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/)
  - [az login](https://learn.microsoft.com/en-us/cli/azure/reference-index?view=azure-cli-latest#az-login)
  - [az bicep build](https://learn.microsoft.com/en-us/cli/azure/bicep?view=azure-cli-latest#az-bicep-build)
  - [az bicep build-params](https://learn.microsoft.com/en-us/cli/azure/bicep?view=azure-cli-latest#az-bicep-build-params)
  - [az deployment {SCOPE} validate](https://learn.microsoft.com/en-us/cli/azure/deployment/sub?view=azure-cli-latest#az-deployment-sub-validate)
  - [az deployment {SCOPE} what-if](https://learn.microsoft.com/en-us/cli/azure/deployment/sub?view=azure-cli-latest#az-deployment-sub-what-if)
- [microsoft/ps-rule@v2](https://github.com/microsoft/ps-rule)
- [azure-cost-estimator](https://github.com/TheCloudTheory/arm-estimator)

The PSRule steps will only run if the repository has a **"ps-rule.yaml"** file. This file must be in the same folder as the main bicep/template file or in the repository root.

For more information about PSRule configuration, see:

- [Sample ps-rule.yaml](../ps-rule.yaml)
- [Configuring options](https://azure.github.io/PSRule.Rules.Azure/setup/configuring-options/)
- [Configuring rule defaults](https://azure.github.io/PSRule.Rules.Azure/setup/configuring-rules/)
- [Available Options](https://microsoft.github.io/PSRule/v2/concepts/PSRule/en-US/about_PSRule_Options/)
- [Available Rules by resource type](https://azure.github.io/PSRule.Rules.Azure/en/rules/resource/)

### Create job

The create job will only run when the plan job was successful. It targets a specific [environment](#get-started). If the environment is configured with **Approvers**, the job will require manual approval.

The create job use the following tools:

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/)
  - [az login](https://learn.microsoft.com/en-us/cli/azure/reference-index?view=azure-cli-latest#az-login)
  - [az provider register](https://learn.microsoft.com/en-us/cli/azure/provider?view=azure-cli-latest#az-provider-register)
  - [az deployment {SCOPE} create](https://learn.microsoft.com/en-us/cli/azure/deployment/sub?view=azure-cli-latest#az-deployment-sub-create)

### Variables

- **vmImageName**: Name of the [VM image](https://learn.microsoft.com/en-us/azure/devops/pipelines/agents/hosted?view=azure-devops&tabs=yaml#software) to use.

- **azureServiceConnection**: Name of the [Azure Resource Manager service connection](#get-started) to use.

- **environment**: Name of the [environment](#get-started) to use for the [create job](#create-job).

- **azure_subscription_id**: The subscription ID in which to deploy the resources.

- **location**: The Azure location to store the deployment metadata.

- **scope**: The deployment scope. Accepted: tenant, mg, sub, group.

- **management_group**: Management group to create deployment at for mg scope.

- **resource_group**: Resource group to create deployment at for group scope.

- **code_template**: The template address. A path or URI to a file or a template spec resource id.

- **parameters**: Deployment parameter values. Either a path, URI, JSON string, or `<KEY=VALUE>` pairs.

- **azure_providers**: A comma separated list of Azure resource providers.

  The pipeline create job will try to register the specified providers in addition to the providers that is detected in code by deployment validate.

- **azure_provider_wait_seconds**: Seconds to wait between each provider status check.

- **azure_provider_wait_count**: Times to check provider status before giving up.

- **ace_version**: Azure Cost Estimator version. The version to use for cost estimation. See versions at <https://github.com/TheCloudTheory/arm-estimator/releases>

- **ace_currency**: Currency code to use for estimations. See allowed values at <https://github.com/TheCloudTheory/arm-estimator/wiki/Options#currency>

- **ace_threshold**: Max acceptable estimated cost. Exceeding threshold causes plan to fail.

- **psrule_baseline**: The name of a PSRule baseline to use. For a list of baseline names for module PSRule.Rules.Azure see <https://azure.github.io/PSRule.Rules.Azure/en/baselines/Azure.All/>

- **psrule_modules**: A comma separated list of modules to use for analysis. For a list of modules see <https://www.powershellgallery.com/packages?q=Tags%3A%22PSRule-rules%22>

- **log_severity**: The log verbosity. Can be one of:

  - ERROR - Only show errors, suppressing warnings. Dump context at fail.
  - INFO - Standard log level. Always dump context.
  - VERBOSE - Increase logging verbosity. Always dump context.
  - DEBUG - Show all debug logs. Always dump context.

## License

The code and documentation in this project are released under the [MIT License](../LICENSE).
