# ADR 0003: Sovereign cloud support

- Status: Proposed
- Date: 2026-11-13
- Issue: https://github.com/innofactororg/bicep-action/issues/56

## Context

bicep-action signs in to the public Azure cloud only, and nothing in the scripts says so.

- `scripts/az-login.sh:77` requests the GitHub OpenID Connect token with the fixed audience `api://AzureADTokenExchange`. That is the public cloud audience. Azure US Government and Azure China use other audiences, so the sign-in cannot work there.
- `scripts/az-login.sh:66-99` runs `az login` without `az cloud set`. The Azure CLI then uses whatever cloud it has by default, which is `AzureCloud` on a fresh runner.
- Azure DevOps does not use `az-login.sh`. The `AzureCLI@2` task signs in and selects the cloud from the service connection (`.azuredevops/templates/plan-stage.yml`, `deploy-stage.yml`, `.azuredevops/ms.azure.deploy.yml`). The scripts then use that session.
- The plan records its settings and the deploy refuses to run if they differ: `bicep_version` (`scripts/bicep-version.sh`, plan output in `.github/actions/plan/action.yml:121`) and `stack_settings` (`scripts/az-deploy.sh:304-325`, deploy input `plan_stack_settings`, Azure DevOps `PLAN_STACK_SETTINGS`). The cloud is not recorded.
- The issue asks for a review of hard-coded public-cloud endpoints. The review found fewer than expected:
  - There is no portal link, and no `management.azure.com` or `login.microsoftonline.com` URL, in any script, action, template or doc. The PR comment (`scripts/pr-comment.sh`) holds no Azure links, so there is nothing to derive from `az cloud show` today.
  - `scripts/azure-cost.sh:161-166` downloads Azure Cost Estimator (ACE) from GitHub. ACE prices against the public retail price list, so an estimate for a sovereign cloud would be wrong or fail.
  - `scripts/install-tools.sh` and `scripts/bicep-version.sh` fetch the Bicep CLI from GitHub, and `br/public:` modules come from `mcr.microsoft.com`. Both are internet endpoints, not Azure cloud endpoints.
  - PSRule (`scripts/psrule-*.sh`) analyses the compiled template offline.

## Decision

Add one setting, `azure_environment` (GitHub input) or `AZURE_ENVIRONMENT` (Azure DevOps variable). Accepted values: `AzureCloud` (default), `AzureUSGovernment`, `AzureChinaCloud`. Matching is case-insensitive; the canonical name is used afterwards. Any other value fails the step with a message that lists the accepted values.

**A new sourced script, `scripts/azure-cloud.sh`,** holds the logic so GitHub and Azure DevOps share it:

- `cloud_name`: normalise and validate the requested value.
- `cloud_audience`: map the cloud to the OIDC audience.
- `select_cloud`: on GitHub run `az cloud set --name` before sign-in. In Azure DevOps do not change the cloud (the task already set it); only check that the active cloud equals `AZURE_ENVIRONMENT` when that variable is set, and fail with a clear message if not. When the variable is unset, trust the connection.
- `check_plan_cloud`: record the active cloud in the plan, compare it in the deploy.
- `cloud_is_public`: used by the steps that are public-cloud only.

**GitHub.** `scripts/az-login.sh` sources it, calls `select_cloud` before `az login`, and uses `cloud_audience` for the token request. Both composite actions get the `azure_environment` input and pass it to the sign-in step. The deploy action also gets `plan_azure_environment`.

**Deploy exactly what was planned.** `scripts/az-deploy.sh` calls `check_plan_cloud`. In the what-if it writes the active cloud to a new `azure_environment` step output (plan action output of the same name). In `create` it compares it with `PLAN_AZURE_ENVIRONMENT`:

- planned and current differ: fail and ask for a new plan.
- planned is empty and current is `AzureCloud`: continue (plans and workflows from before this change).
- planned is empty and current is not `AzureCloud`: fail. A sovereign deployment must carry the plan's value, like a stack deployment must carry `stack_settings`.

In Azure DevOps the deploy stage reads `what_if.azure_environment` into `PLAN_AZURE_ENVIRONMENT`, like it does for `BICEP_VERSION`.

**Public-cloud-only steps are skipped with a message.** The cost estimate (`scripts/azure-cost.sh`) is skipped when the cloud is not `AzureCloud`: a warning annotation and a "skipped" note in the PR comment. If a numeric `cost_threshold` is set, the step fails instead, because a threshold that is silently not checked is worse than a clear error. PSRule and Bicep module restore are not skipped; see Alternatives.

**Comment.** The comment header gets an `Azure environment: <name>` line only when the cloud is not `AzureCloud`, so default comments are byte-for-byte unchanged. No portal links are added (there are none today).

**Audience values.** `AzureCloud` uses `api://AzureADTokenExchange`, `AzureUSGovernment` uses `api://AzureADTokenExchangeUSGov`, `AzureChinaCloud` uses `api://AzureADTokenExchangeChina`. These come from the issue text. The Microsoft Learn pages for federated credentials only document the public value, and the Azure/login README says only that the audience must be changed for other clouds. They must be confirmed against a real tenant before release (see the plan, Questionables).

## Alternatives considered

- **Take the cloud from the service connection on GitHub too, with no input.** GitHub has no service connection; the cloud must be given. Rejected.
- **Derive the cloud from the tenant or subscription.** Not possible before sign-in, and sign-in needs the cloud. Rejected.
- **Add an `azure_audience` input instead of a table.** More flexible, but moves a Microsoft-defined mapping onto every user and makes a wrong pair easy. Rejected; the table is three lines.
- **Skip PSRule in sovereign clouds.** PSRule reads the compiled template and needs no Azure endpoint. Skipping it removes a quality gate for no technical reason. Kept enabled.
- **Skip or rewrite `br/public` module restore.** The registry is `mcr.microsoft.com`, an internet host that the runner reaches or does not. This is a network question, not a cloud one, and a skip would produce a template that does not compile. Documented, not changed.
- **Fail the cost step in sovereign clouds always.** Contradicts the issue, and the estimate is report-only by default. Rejected, except with a numeric threshold.
- **Add portal links to the comment.** Out of scope; there are none today. A helper to read `az cloud show --query endpoints.portal` is left as future work.

## Consequences

- Defaults are unchanged: `AzureCloud`, same audience, same sign-in command, same comment text. Existing workflows and pipelines need no edit.
- Plans from before this change have no `azure_environment` output. A public-cloud deploy still works with them (rule above).
- A sovereign-cloud user must set `azure_environment` on both actions and pass `plan_azure_environment`. The setting is not secret and appears in the debug output.
- The federated credential in the sovereign tenant must be created with the matching audience. The setup docs say so.
- Documentation to update: `docs/configuration.md` (settings table, new section, cost estimate and outputs), `docs/how-it-works.md` ("Deploy exactly what was planned"), `docs/setup-github.md`, `docs/setup-azure-devops.md`, `docs/troubleshooting.md`, `docs/examples/`, `README.md`, `.azuredevops/README.md`.
- Residual risk: the Bicep CLI has its own cloud profile (`cloud.currentProfile` in `bicepconfig.json`) for registry credentials. A template repository that restores from a private registry in a sovereign cloud needs that set. Documented.

## Plan

[Implementation plan](../../specs/0003-sovereign-clouds.html)
