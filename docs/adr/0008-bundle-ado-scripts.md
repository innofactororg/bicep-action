# ADR 0008: Run the Azure DevOps scripts from a checkout of this repository

- Status: Proposed
- Date: 2026-11-13
- Issue: https://github.com/innofactororg/bicep-action/issues/61
- Plan: [specs/0008-bundle-ado-scripts.html](../../specs/0008-bundle-ado-scripts.html)

## Context

The Azure DevOps stage templates are read from this repository through a `resources.repositories` entry (alias `bicep_action`, see `docs/examples/azure-devops/multi-environment.yml:24-29` and `variable-group.yml:24-29`). The scripts they run come from somewhere else: they are downloaded from GitHub on every run.

- `.azuredevops/templates/plan-stage.yml:78-104` and `deploy-stage.yml:94-115` loop over a script list and `curl` each file from `https://github.com/innofactororg/bicep-action/raw/${WORKFLOW_VERSION}/scripts/<name>.sh` into the current directory.
- `debug-info.sh` and `pipeline-summary.sh` are fetched separately from `raw.githubusercontent.com` (`plan-stage.yml:262`, `:299`; `deploy-stage.yml:189`, `:226`).
- `.azuredevops/ms.azure.deploy.yml:89-115` (plan) and `:310-336` (deploy) run the same download loop. Unlike the templates, its debug step (`:261-270`) and the deploy equivalent (`:400-410`) only print the environment, and there is no pipeline-summary step, so there is nothing else to download.

Consequences today:

1. Two versions to keep in step: the repository `ref` and `WORKFLOW_VERSION` (`docs/examples/azure-devops/multi-environment.yml:7-8`, `docs/examples/README.md:29`, `docs/configuration.md:251`).
2. The pipeline executes code it fetched at run time from a mutable tag.
3. An agent that cannot reach `github.com` or `raw.githubusercontent.com` cannot run the scripts, and a GitHub outage fails the pipeline.

Findings from reading the code that shape the design:

- The scripts never read `WORKFLOW_VERSION`. Only the download URLs, two error messages and the `env:` blocks of the debug and summary steps use it.
- The scripts find their siblings with `source "$(dirname "${BASH_SOURCE[0]}")/bicep-version.sh"` (for example `az-bicep.sh:114`, `az-deploy.sh:258`, `existing-tags.sh:139`), so they run from any folder.
- The GitHub composite actions already run scripts from the checked-out action: `.github/actions/plan/action.yml:134-138` appends `${GITHUB_ACTION_PATH}/../../../scripts` to `PATH`. They are not affected.
- The scripts resolve `IN_TEMPLATE`, `IN_TEMPLATE_PARAMS` and `RULE_OPTION` relative to the current directory, and write output files there. The current directory must therefore stay the workload repository.
- Today the downloaded scripts are written into the workload checkout, so they show up in its working tree and in the PSRule input (`INPUT_PATH: $(Build.SourcesDirectory)`, `plan-stage.yml:184`).
- Adding a second `checkout:` switches the job to multi-repository layout. `$(Build.SourcesDirectory)` and the default working directory become the parent folder, and `self` moves into a subfolder. Every step that assumes the workload repository is at the sources root must change.
- Not every download goes away. `az bicep install` and the cost estimator (`azure-cost.sh:163-164`, from `github.com/TheCloudTheory`) still reach the internet. This ADR removes the script download only.

## Decision

1. **Check out this repository in the same job and run the scripts from it.** A new step template `.azuredevops/templates/steps/checkout-and-scripts.yml` does, in order: `checkout: self` to `path: workload`, `checkout: ${{ parameters.bicepActionRepository }}` to `path: bicep-action`, then a "Locate scripts" step. The template parameter `bicepActionRepository` (string, default `bicep_action`) names the repository resource. Both stage templates call the step template.
2. **Put the scripts on `PATH`, as the GitHub action does.** The Locate step runs `##vso[task.prependpath]$(BICEP_ACTION_PATH)/scripts`. Steps call `install-tools.sh`, `az-deploy.sh validate` and so on without `./`. Nothing is copied into the workload repository.
3. **Keep the workload repository as the working directory.** Each stage declares `WORKLOAD_PATH: $(Pipeline.Workspace)/s/workload` and `BICEP_ACTION_PATH: $(Pipeline.Workspace)/s/bicep-action`. Every step that runs a script sets `workingDirectory: $(WORKLOAD_PATH)`. `SOURCE_PATH` and PSRule `INPUT_PATH` become `$(WORKLOAD_PATH)`.
4. **Check out the template repository without credentials and with a shallow fetch.** `fetchDepth: 1`, no `persistCredentials` on `bicep_action`. `self` keeps `fetchDepth: 1` and `persistCredentials: true` as today.
5. **Deprecate `WORKFLOW_VERSION`.** It no longer selects scripts. The Locate step derives `BICEP_ACTION_VERSION` from the repository resource (`ref`, plus the short commit) and the debug and summary steps report that. If `WORKFLOW_VERSION` is set and differs from the ref, the step logs a warning that it is ignored. Setting it is harmless.
6. **Single-file pipeline: add a repository resource and the same checkout** (option 2 in the issue). The curl loops go. The file gains a `resources.repositories` entry and a GitHub service connection, which it did not need before. Option 1 alone does not remove the download; option 3 keeps a run-time fetch.
7. **Releases.** The `v1` tag is moved by hand after the release is tagged, so templates and scripts reach `v1` users together. `innofactororg/code-release@v2` moves only `v2026` and needs no change.

## Alternatives considered

- **Recommend the stage templates and leave the single file as is (issue option 1).** Does not meet the acceptance criterion for `ms.azure.deploy.yml`, and the file keeps the run-time download.
- **Download at a pinned commit SHA and verify checksums (issue option 3).** Fixes the mutable tag but keeps the availability problem, adds a checksum file to every release, and still needs a second version to pin.
- **Publish scripts as a pipeline artifact or a container image.** More moving parts than a checkout, and needs a publishing pipeline for a public repository.
- **Copy the scripts into the workload checkout after the second checkout.** Keeps `./script.sh` but repeats the pollution of the working tree and the PSRule input. Rejected for `PATH`.
- **Embed script bodies in the YAML.** Duplicates 16 scripts and breaks the GitHub and Azure DevOps parity.

## Consequences

- One pin. Changing only `ref` on the repository resource changes templates and scripts together.
- Stage templates make no run-time request to GitHub for scripts. Agents still need access for Bicep, PSRule and the cost estimator downloads.
- Existing pipelines that set `WORKFLOW_VERSION` keep working. One behaviour change: with `ref: main` and `WORKFLOW_VERSION: v1`, the scripts now come from `main`, not `v1`. The warning says so. Pipelines pinned to `v1.0.x` tags keep the old download behaviour because those tags contain the old templates.
- The layout of the agent folder changes: the workload repository is at `$(Pipeline.Workspace)/s/workload`. User steps added to the same job that assume `$(Build.SourcesDirectory)` is the repository root need `$(WORKLOAD_PATH)`. This goes in the docs.
- Checkout of the repository resource uses the service connection at run time, as template expansion already does. For a mirror in Azure Repos (`type: git`), the build service needs read access to the mirror.
- `docs/setup-azure-devops.md`, `docs/configuration.md`, `docs/how-it-works.md`, `docs/examples/*`, `.azuredevops/README.md` and the root `README.md` stop asking for two matching versions.

## Plan

See [specs/0008-bundle-ado-scripts.html](../../specs/0008-bundle-ado-scripts.html). It starts with a spike that confirms the multi-checkout folder layout on a real agent, because the `path` rules and `Build.SourcesDirectory` behaviour are the main assumption in this design.
