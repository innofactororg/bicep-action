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
#   VERSION_BICEP_CLI  Bicep CLI version the plan compiled with (optional)
#   PSRULE_AZURE_BICEP_PATH  Bicep CLI for PSRule; when set it is used as is
#
# PSRule.Rules.Azure expands .bicep and .bicepparam files with the Bicep CLI,
# which it looks for only on PATH or in PSRULE_AZURE_BICEP_PATH. The earlier
# steps install Bicep through az into the Azure CLI config folder of their own
# task, which is neither, so this script installs the same version (the one
# the plan compiled with) into a folder of its own and points PSRule at it.
set -e
export PSRULE_VERSION="${PSRULE_VERSION:-2.9.0}"
export PSRULE_REPOSITORY="${PSRULE_REPOSITORY:-PSGallery}"
export INPUT_PATH="${INPUT_PATH:-.}"
notice() {
  if test -n "${TF_BUILD-}"; then
    echo "##[${1}]${2}"
  else
    echo "::${1}::${2}"
  fi
}
if ! command -v pwsh >/dev/null 2>&1; then
  notice error 'PowerShell (pwsh) is required for the PSRule analysis'
  exit 1
fi
# Installs the Bicep CLI for PSRule. Never fails the step: without Bicep,
# PSRule reports what it could not expand, and a repository without Bicep
# files does not need it.
resolve_bicep() {
  local target=''
  # An unset Azure DevOps variable arrives as the literal '$(VERSION_BICEP_CLI)'.
  # shellcheck disable=SC2016
  if test -n "${VERSION_BICEP_CLI-}" && [[ "${VERSION_BICEP_CLI}" != *'$('* ]]; then
    target="${VERSION_BICEP_CLI}"
  fi
  if ! command -v az >/dev/null 2>&1; then
    notice warning 'Azure CLI not found, so PSRule cannot expand Bicep files unless the Bicep CLI is on PATH.'
    return 0
  fi
  local tmp="${AGENT_TEMPDIRECTORY:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}}"
  local dir="${tmp}/psrule-azure-cli"
  local cmd=(az bicep install)
  if test -n "${target}"; then
    cmd+=(--version "v${target}")
  fi
  mkdir -p "${dir}"
  # az installs into ${dir}/bin; PSRule runs that binary directly.
  if ! AZURE_CONFIG_DIR="${dir}" "${cmd[@]}" >/dev/null 2>&1; then
    sleep 10
    if ! AZURE_CONFIG_DIR="${dir}" "${cmd[@]}" >/dev/null 2>&1; then
      notice warning "Unable to install the Bicep CLI ${target:-latest} for PSRule ('${cmd[*]}' failed twice)."
      return 0
    fi
  fi
  local bin="${dir}/bin/bicep"
  if test -f "${bin}.exe"; then
    bin="${bin}.exe"
  fi
  local found
  found=$("${bin}" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)
  if test -z "${found}"; then
    notice warning "The Bicep CLI for PSRule was installed, but ${bin} does not run."
    return 0
  fi
  if test -n "${target}" && [ "${found}" != "${target}" ]; then
    notice warning "Bicep CLI ${target}, that the plan compiled with, could not be installed for PSRule (found ${found}), so PSRULE_AZURE_BICEP_PATH is not set."
    return 0
  fi
  export PSRULE_AZURE_BICEP_PATH="${bin}"
  echo "Bicep CLI ${found} for PSRule: ${bin}"
}
if test -z "${PSRULE_AZURE_BICEP_PATH-}"; then
  resolve_bicep
fi
script=$(mktemp --suffix=.ps1)
trap 'rm -f "${script}"' EXIT
cat > "${script}" <<'EOF'
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$ado = -not [String]::IsNullOrEmpty($Env:TF_BUILD)
function Write-Failure([String]$Message) {
  $Message = $Message -replace '\r?\n', ' '
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
  # PSRule throws this both when a rule fails ('One or more rules reported
  # failure.') and when it logged an error of its own, such as a template it
  # could not expand ('One or more errors occured.'). Name the right one.
  if ($_.Exception.Message -match 'rules reported failure') {
    Write-Failure 'One or more rules reported failure.'
  }
  else {
    Write-Failure "PSRule could not complete the analysis: $($_.Exception.Message) No rule failure was reported; see the errors above, for example a Bicep or parameter file that could not be expanded."
  }
  exit 1
}
catch {
  Write-Failure "PSRule analysis failed: $($_.Exception.Message)"
  exit 1
}
EOF
pwsh -NoProfile -NonInteractive -File "${script}"
