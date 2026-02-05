#!/usr/bin/env bash
# Copyright (c) Innofactor Plc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause
set -e
mkdir -p "${LOG_PATH}"
log="${LOG_PATH}/step_${LOG_ORDER}_${LOG_NAME}.log"
trap 'error $? $LINENO "$BASH_COMMAND" $log' ERR
trap cleanup EXIT

cleanup() {
  :
}
error() {
  if [ "${1}" != 0 ]; then
    if test -n "${TF_BUILD-}"; then
      echo "##[error]Error on or near line ${2} (exit code ${1}) in ${LOG_NAME} at $(date '+%Y-%m-%d %H:%M:%S')"
      echo ""
      echo "##[error]Failed command: ${3}"
    else
      echo "::error::Error on or near line ${2} (exit code ${1}) in ${LOG_NAME} at $(date '+%Y-%m-%d %H:%M:%S')"
      echo ""
      echo "::error::Failed command: ${3}"
    fi
    if test -f "${4}"; then
      echo ""
      echo "Recent log entries:"
      tail -n 20 "${4}" || true
    fi
  fi
}

# Start grouped output
if test -n "${TF_BUILD-}"; then
  echo "##[group]🔍 Debug Information"
else
  echo "::group::🔍 Debug Information"
fi

echo "Debug information collected at $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Pipeline Context
if test -n "${TF_BUILD-}"; then
  echo "##[group]📋 Pipeline Context"
else
  echo "::group::📋 Pipeline Context"
fi
echo "Build ID: ${BUILD_ID:-N/A}"
echo "Build Number: ${BUILD_NUMBER:-N/A}"
echo "Source Branch: ${SOURCE_BRANCH:-N/A}"
echo "Source Version: ${SOURCE_VERSION:-N/A}"
echo "Build Reason: ${BUILD_REASON:-N/A}"
echo "Requested For: ${BUILD_REQUESTED_FOR:-N/A}"
echo "Repository: ${REPOSITORY:-N/A}"
if test -n "${TF_BUILD-}"; then
  echo "##[endgroup]"
else
  echo "::endgroup::"
fi
echo ""

# Infrastructure Configuration
if test -n "${TF_BUILD-}"; then
  echo "##[group]🏗️ Infrastructure Configuration"
else
  echo "::group::🏗️ Infrastructure Configuration"
fi
echo "Template: ${IN_TEMPLATE:-N/A}"
echo "Template Parameters: ${IN_TEMPLATE_PARAMS:-N/A}"
echo "Scope: ${IN_SCOPE:-N/A}"
echo "Location: ${IN_LOCATION:-N/A}"
echo "Resource Group: ${IN_RESOURCE_GROUP:-N/A}"
echo "Management Group: ${IN_MANAGEMENT_GROUP:-N/A}"
echo "Subscription ID: ${SUBSCRIPTION_ID:-N/A}"
echo "Log Severity: ${IN_SEVERITY:-N/A}"
if test -n "${TF_BUILD-}"; then
  echo "##[endgroup]"
else
  echo "::endgroup::"
fi
echo ""

# Tool Versions
if test -n "${TF_BUILD-}"; then
  echo "##[group]🔧 Tool Versions"
else
  echo "::group::🔧 Tool Versions"
fi
echo "Bicep CLI: ${VERSION_BICEP_CLI:-N/A}"
echo "PSRule Modules: ${RULE_MODULES:-N/A}"
echo "ACE Version: ${VERSION_ACE:-N/A}"
if test -n "${TF_BUILD-}"; then
  echo "##[endgroup]"
else
  echo "::endgroup::"
fi
echo ""

# PSRule Configuration
if test -n "${TF_BUILD-}"; then
  echo "##[group]📏 PSRule Configuration"
else
  echo "::group::📏 PSRule Configuration"
fi
echo "Rule Option: ${RULE_OPTION:-N/A}"
echo "Rule Baseline: ${RULE_BASELINE:-N/A}"
echo "Rule Modules: ${RULE_MODULES:-N/A}"
if test -n "${TF_BUILD-}"; then
  echo "##[endgroup]"
else
  echo "::endgroup::"
fi
echo ""

# File System Information
if test -n "${TF_BUILD-}"; then
  echo "##[group]📁 File System Information"
else
  echo "::group::📁 File System Information"
fi
echo "Current Directory: $(pwd)"
echo ""
echo "Current Directory Contents:"
ls -lah 2>/dev/null | head -20 || echo "Could not list directory"
echo ""
if [ -d "${SOURCE_PATH}" ] && [ "${SOURCE_PATH}" != "$(pwd)" ]; then
  echo "Source Directory (${SOURCE_PATH}):"
  ls -lah "${SOURCE_PATH}" 2>/dev/null | head -20 || echo "Could not list source directory"
  echo ""
fi
if [ -d "${LOG_PATH}" ]; then
  echo "Logs Directory (${LOG_PATH}):"
  ls -lah "${LOG_PATH}" 2>/dev/null || echo "Could not list logs directory"
else
  echo "Logs directory not found at: ${LOG_PATH}"
fi
if test -n "${TF_BUILD-}"; then
  echo "##[endgroup]"
else
  echo "::endgroup::"
fi
echo ""

# Azure CLI Information
if test -n "${TF_BUILD-}"; then
  echo "##[group]☁️ Azure CLI Information"
else
  echo "::group::☁️ Azure CLI Information"
fi
if command -v az >/dev/null 2>&1; then
  echo "Azure CLI Version:"
  az version --output json 2>/dev/null | head -20 || echo "Could not get Azure CLI version"
  echo ""
  echo "Bicep CLI Version:"
  az bicep version 2>/dev/null || echo "Could not get Bicep version"
  echo ""
  echo "Current Azure Account:"
  az account show 2>/dev/null || echo "Not logged in to Azure"
else
  echo "Azure CLI not available"
fi
if test -n "${TF_BUILD-}"; then
  echo "##[endgroup]"
else
  echo "::endgroup::"
fi
echo ""

# System Resources
if test -n "${TF_BUILD-}"; then
  echo "##[group]💻 System Resources"
else
  echo "::group::💻 System Resources"
fi
echo "Disk Usage:"
df -h 2>/dev/null | grep -E '(Filesystem|/$|/workspace|/tmp)' || echo "Could not get disk information"
echo ""
echo "Memory Usage:"
free -h 2>/dev/null || echo "Could not get memory information"
if test -n "${TF_BUILD-}"; then
  echo "##[endgroup]"
else
  echo "::endgroup::"
fi
echo ""

# Environment Variables (filtered for security)
if test -n "${TF_BUILD-}"; then
  echo "##[group]🌍 Environment Variables (Filtered)"
else
  echo "::group::🌍 Environment Variables (Filtered)"
fi
echo "Showing non-sensitive environment variables..."
echo ""
# List environment variables excluding sensitive patterns
env | grep -E '^(AZURE_|BUILD_|SYSTEM_|IN_|VERSION_|RULE_|LOG_|SOURCE_|ARTIFACT_|WORKFLOW_)' | \
  grep -v -iE '(SECRET|PASSWORD|TOKEN|KEY|CREDENTIAL|PAT|SAS|CONNECTION_STRING|ENDPOINT_KEY)' | \
  sort || echo "No matching environment variables"
if test -n "${TF_BUILD-}"; then
  echo "##[endgroup]"
else
  echo "::endgroup::"
fi

# End main group
if test -n "${TF_BUILD-}"; then
  echo "##[endgroup]"
else
  echo "::endgroup::"
fi

echo "" | tee -a "${log}"
echo "✅ Debug information collection completed" | tee -a "${log}"
