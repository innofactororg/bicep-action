#!/usr/bin/env bash
# Copyright (c) Innofactor Plc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause
set -e
mkdir -p "${LOG_PATH}"
log="${LOG_PATH}/step_${LOG_ORDER}_${LOG_NAME}.log"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Pipeline Execution Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Determine status
status="${JOB_STATUS:-unknown}"
status_lower=$(echo "${status}" | tr '[:upper:]' '[:lower:]')

case "${status_lower}" in
  succeeded|success)
    echo "🎉 Status: SUCCESS"
    status_emoji="✅"
    ;;
  failed|failure)
    echo "❌ Status: FAILED"
    status_emoji="❌"
    ;;
  canceled|cancelled)
    echo "⛔ Status: CANCELED"
    status_emoji="⛔"
    ;;
  *)
    echo "⚠️  Status: ${status}"
    status_emoji="⚠️"
    ;;
esac

echo ""
echo "🏗️  Infrastructure Configuration:"
echo "  Template: ${IN_TEMPLATE:-N/A}"
if test -n "${IN_TEMPLATE_PARAMS}"; then
  echo "  Parameters: ${IN_TEMPLATE_PARAMS}"
fi
echo "  Scope: ${IN_SCOPE:-N/A}"
echo "  Location: ${IN_LOCATION:-N/A}"
if [ "${IN_SCOPE}" = "group" ]; then
  echo "  Resource Group: ${IN_RESOURCE_GROUP:-N/A}"
elif [ "${IN_SCOPE}" = "mg" ]; then
  echo "  Management Group: ${IN_MANAGEMENT_GROUP:-N/A}"
fi

echo ""
echo "📋 Execution Details:"
if test -n "${TF_BUILD-}"; then
  echo "  Build: ${BUILD_NUMBER:-N/A}"
  echo "  Branch: ${SOURCE_BRANCH:-N/A}"
  commit="${SOURCE_VERSION:0:8}"
  echo "  Commit: ${commit:-N/A}"
  echo "  Triggered by: ${BUILD_REQUESTED_FOR:-N/A}"
else
  echo "  Run: ${RUN_NUMBER:-N/A}"
  echo "  Branch: ${GITHUB_REF_NAME:-N/A}"
  commit="${GITHUB_SHA:0:8}"
  echo "  Commit: ${commit:-N/A}"
  echo "  Actor: ${GITHUB_ACTOR:-N/A}"
fi

# List the steps that ran, from the logs they wrote. This step cannot tell
# which of them failed, so it does not mark them: the status above is the
# job's, and the failed step is the one marked in the job view.
if [ "${LOG_NAME}" = "stage_summary" ] || [ "${STAGE_RESULT:-}" != "" ]; then
  declare -a STEPS=(
    "install_tools:Install tools"
    "azure_login:Azure login"
    "existing_tags:Existing tags"
    "bicep_build:Bicep build"
    "bicep_build_params:Bicep build params"
    "validate:Validate"
    "what-if:What-if"
    "psrule_report:PSRule report"
    "cost_estimate:Cost estimate"
    "bicep_snapshot:Bicep snapshot"
    "check_providers:Check Azure providers"
    "deploy:Deploy"
    "create_deployment:Deploy"
  )
  ran=()
  for entry in "${STEPS[@]}"; do
    name="${entry%%:*}"
    if compgen -G "${LOG_PATH}/step_*_${name}.*" >/dev/null; then
      ran+=("${entry#*:}")
    fi
  done
  if [ "${#ran[@]}" -gt 0 ]; then
    echo ""
    echo "🎯 Steps with output (job status: ${status_emoji} ${status}):"
    for step in "${ran[@]}"; do
      echo "  • ${step}"
    done
  fi
fi

echo ""
echo "📦 Artifacts:"
if test -n "${TF_BUILD-}"; then
  artifact_name="${ARTIFACT_IDENTIFIER:-pipeline-logs}"
  echo "  • ${artifact_name} (pipeline logs and outputs)"
else
  echo "  • pipeline-logs (build outputs and reports)"
fi

if [ -d "${LOG_PATH}" ]; then
  file_count=$(find "${LOG_PATH}" -type f 2>/dev/null | wc -l || echo "0")
  echo "  • ${file_count} log files generated"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⏱️  Completed at: $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Log to file
{
  echo "Pipeline Summary"
  echo "================"
  echo "Status: ${status}"
  echo "Template: ${IN_TEMPLATE:-N/A}"
  echo "Scope: ${IN_SCOPE:-N/A}"
  echo "Completed: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
} >> "${log}"
