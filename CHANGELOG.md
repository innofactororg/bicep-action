# Changelog

All notable changes to this project are documented in this file.

Each release has a `## <version> (YYYY-MM-DD)` section. The Release workflow publishes that section as the release notes and announces it in Teams, and fails if the section is missing. Add the entry in the pull request that makes the change.

## 2026.11.13 (2026-11-13)

### Fixed

- Keep masked values from garbling the diff blocks in Azure DevOps ([#53](https://github.com/innofactororg/bicep-action/pull/53))

## 2026.11.12 (2026-11-12)

### Added

- Expose existing tag values to the template before every compile ([#43](https://github.com/innofactororg/bicep-action/pull/43), closes #42)
- Publish the plan's what-if summary as `whatif-summary.json` ([#49](https://github.com/innofactororg/bicep-action/pull/49), closes #48)
- Limit `EXISTING_TAGS` to given resource groups ([#51](https://github.com/innofactororg/bicep-action/pull/51), closes #50)

### Changed

- Restructure the documentation, add graphics, a full configuration reference and examples ([#52](https://github.com/innofactororg/bicep-action/pull/52))
- Show what the pull request looks like in the docs; recommend deployment stacks and the cost estimate ([#39](https://github.com/innofactororg/bicep-action/pull/39))

### Fixed

- Give PSRule the plan's Bicep CLI in Azure DevOps and name setup errors ([#45](https://github.com/innofactororg/bicep-action/pull/45), closes #44)
- The cost estimate defaults the currency and is report-only without a threshold ([#47](https://github.com/innofactororg/bicep-action/pull/47), closes #46)

## 2026.11.6 (2026-11-06)

### Changed

- Move the GitHub actions to Node 24 ([#41](https://github.com/innofactororg/bicep-action/pull/41))

### Fixed

- Never write the client secret or federated token into the PR comment ([#37](https://github.com/innofactororg/bicep-action/pull/37))
- Do not count new resources as adopted in the stack plan summary ([#38](https://github.com/innofactororg/bicep-action/pull/38))
- Run PSRule without the Azure DevOps extension (Node 16 retirement) ([#40](https://github.com/innofactororg/bicep-action/pull/40))

## 2026.10.29 (2026-10-29)

### Added

- Deployment stacks, opt-in ([#34](https://github.com/innofactororg/bicep-action/pull/34), closes #20)
- Bicep snapshot check in the plan stage ([#30](https://github.com/innofactororg/bicep-action/pull/30), closes #28)
- Use the latest Bicep for plans; the deployment is locked to the plan's Bicep version ([#31](https://github.com/innofactororg/bicep-action/pull/31))

### Changed

- Document pinning PSRule with a quarterly baseline; ACE default is 1.6.5 ([#27](https://github.com/innofactororg/bicep-action/pull/27), closes #22 and #21)
- Add DonPedroDK as code owner ([#29](https://github.com/innofactororg/bicep-action/pull/29))

### Fixed

- The PR comment no longer fails on large plan output ([#26](https://github.com/innofactororg/bicep-action/pull/26), closes #23)
- The provider registration wait never timed out ([#32](https://github.com/innofactororg/bicep-action/pull/32))
- Retry only "subscription doesn't exist in cloud" when selecting the subscription ([#36](https://github.com/innofactororg/bicep-action/pull/36), closes #35)

## 2026.10.22 (2026-10-22)

### Added

- Multi-environment support ([#24](https://github.com/innofactororg/bicep-action/pull/24))

### Fixed

- Azure DevOps: unique log artifact names per job attempt ([#25](https://github.com/innofactororg/bicep-action/pull/25))

## 1.0.7 (2024-10-30)

### Fixed

- PSRule config uses a path relative to the repo root ([#19](https://github.com/innofactororg/bicep-action/pull/19))

## 1.0.6 (2024-10-08)

### Added

- Unique artifact names when the plan/deploy module is used more than once in a workflow ([#15](https://github.com/innofactororg/bicep-action/pull/15))
- Updated Azure DevOps pipeline ([#17](https://github.com/innofactororg/bicep-action/pull/17))
- New Azure DevOps pipeline that takes its values from a variable group ([#12](https://github.com/innofactororg/bicep-action/pull/12))

### Fixed

- Parameter bug for ACE v1.6 ([#18](https://github.com/innofactororg/bicep-action/pull/18))

## 1.0.5 (2024-03-14)

### Fixed

- Strip the new line from `CLIENT_SECRET` ([#10](https://github.com/innofactororg/bicep-action/pull/10))

## 1.0.4 (2024-03-01)

### Added

- Input `azure_providers` accepts `disable` to skip the provider registration ([#8](https://github.com/innofactororg/bicep-action/pull/8))

### Fixed

- An empty `azure_providers` input made the deploy job fail with "ERROR: argument --namespace/-n: expected one argument" ([#8](https://github.com/innofactororg/bicep-action/pull/8))

## 1.0.3 (2024-02-22)

### Added

- Allow skipping the cost estimator

## 1.0.2 (2024-02-22)

### Fixed

- The providers output of the plan job ([339974a](https://github.com/innofactororg/bicep-action/commit/339974a7ac6fcde3f58c6e119025a22ef84f2ab3))

## 1.0.1 (2024-02-22)

### Fixed

- The `bicep build-params` run condition ([#4](https://github.com/innofactororg/bicep-action/pull/4))

## 1.0.0 (2024-02-21)

### Added

- First release ([#3](https://github.com/innofactororg/bicep-action/pull/3))
