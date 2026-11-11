#!/usr/bin/env bash
# Copyright (c) Innofactor Plc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause
#
# Runs the PSRule analysis with PowerShell, without the PSRule Azure DevOps
# extension. The extension task (ps-rule-assert@2) only ships Node 10 and
# Node 16 handlers, which Azure Pipelines is retiring, and it is no longer
# updated. This script does what the task did: install PSRule and the rule
# modules from the PowerShell Gallery, then run Assert-PSRule on the
# repository. Installs are retried, because a single failed Gallery download
# used to fail the plan.
#
# Environment:
#   RULE_OPTION      path to the PSRule options file (required)
#   RULE_BASELINE    baseline name (optional)
#   RULE_MODULES     comma separated rule modules (optional)
#   INPUT_PATH       path to analyse (default: current directory)
#   OUTPUT_PATH      Markdown report file (optional)
#   PSRULE_VERSION   PSRule version (default 2.9.0)
#   PSRULE_REPOSITORY  PowerShell repository (default PSGallery)
set -e
export PSRULE_VERSION="${PSRULE_VERSION:-2.9.0}"
export PSRULE_REPOSITORY="${PSRULE_REPOSITORY:-PSGallery}"
export INPUT_PATH="${INPUT_PATH:-.}"
if ! command -v pwsh >/dev/null 2>&1; then
  msg='PowerShell (pwsh) is required for the PSRule analysis'
  if test -n "${TF_BUILD-}"; then
    echo "##[error]${msg}"
  else
    echo "::error::${msg}"
  fi
  exit 1
fi
script=$(mktemp --suffix=.ps1)
trap 'rm -f "${script}"' EXIT
cat > "${script}" <<'EOF'
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$ado = -not [String]::IsNullOrEmpty($Env:TF_BUILD)
function Write-Failure([String]$Message) {
  if ($ado) { Write-Host "##[error]$Message" } else { Write-Host "::error::$Message" }
}
function Install-WithRetry([String]$Name, [Hashtable]$Extra) {
  for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
      $params = @{
        Name = $Name
        Repository = $Env:PSRULE_REPOSITORY
        Scope = 'CurrentUser'
        Force = $True
        AllowClobber = $True
        SkipPublisherCheck = $True
      }
      foreach ($k in $Extra.Keys) { $params[$k] = $Extra[$k] }
      Install-Module @params
      $installed = (Get-InstalledModule -Name $Name | Sort-Object Version -Descending | Select-Object -First 1).Version
      Write-Host "Installed ${Name} ${installed} (attempt ${attempt})"
      return
    }
    catch {
      Write-Host "Install of ${Name} failed (attempt ${attempt} of 3): $($_.Exception.Message)"
      if ($attempt -eq 3) { throw }
      Start-Sleep -Seconds (15 * $attempt)
    }
  }
}
try {
  Install-WithRetry 'PSRule' @{ RequiredVersion = $Env:PSRULE_VERSION }
  $modules = @()
  if (-not [String]::IsNullOrEmpty($Env:RULE_MODULES)) {
    $modules = @($Env:RULE_MODULES.Split(',', [StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim() })
  }
  foreach ($m in $modules) { Install-WithRetry $m @{} }
  Import-Module PSRule -RequiredVersion $Env:PSRULE_VERSION
}
catch {
  Write-Failure "Unable to install PSRule or the rule modules: $($_.Exception.Message)"
  exit 1
}
$invoke = @{
  InputPath = $Env:INPUT_PATH
  Format = 'File'
  Option = $Env:RULE_OPTION
  Style = $(if ($ado) { 'AzurePipelines' } else { 'GitHubActions' })
  ErrorAction = 'Stop'
}
if (Test-Path -Path '.ps-rule/') { $invoke['Path'] = '.ps-rule/' }
if (-not [String]::IsNullOrEmpty($Env:RULE_BASELINE)) { $invoke['Baseline'] = $Env:RULE_BASELINE }
if ($modules.Count -gt 0) { $invoke['Module'] = $modules }
if (-not [String]::IsNullOrEmpty($Env:OUTPUT_PATH)) {
  $invoke['OutputFormat'] = 'Markdown'
  $invoke['OutputPath'] = $Env:OUTPUT_PATH
}
Write-Host "PSRule $((Get-Module PSRule).Version), baseline '$($Env:RULE_BASELINE)', option '$($Env:RULE_OPTION)', input '$($Env:INPUT_PATH)'"
try {
  Assert-PSRule @invoke
}
catch [PSRule.Pipeline.FailPipelineException] {
  Write-Failure 'One or more rules reported failure.'
  exit 1
}
catch {
  Write-Failure "PSRule analysis failed: $($_.Exception.Message)"
  exit 1
}
EOF
pwsh -NoProfile -NonInteractive -File "${script}"
