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
  echo "  Commit: ${SOURCE_VERSION:0:8:-N/A}"
  echo "  Triggered by: ${BUILD_REQUESTED_FOR:-N/A}"
else
  echo "  Run: ${RUN_NUMBER:-N/A}"
  echo "  Branch: ${GITHUB_REF_NAME:-N/A}"
  echo "  Commit: ${GITHUB_SHA:0:8:-N/A}"
  echo "  Actor: ${GITHUB_ACTOR:-N/A}"
fi

# Show stage/job results if this is from stage summary
if [ "${LOG_NAME}" = "stage_summary" ] || [ "${STAGE_RESULT:-}" != "" ]; then
  echo ""
  echo "🎯 Stage Results:"

  # Check for plan stage artifacts
  if [ -f "${LOG_PATH}/step_b3_bicep_build.log" ]; then
    echo "  ${status_emoji} Bicep Build"
  fi
  if [ -f "${LOG_PATH}/step_b5_az_deploy_validate.log" ]; then
    echo "  ${status_emoji} Deployment Validation"
  fi
  if [ -f "${LOG_PATH}/step_b6_az_deploy_what-if.log" ]; then
    echo "  ${status_emoji} What-If Analysis"
  fi
  if [ -f "${LOG_PATH}/step_b7_psrule_report.md" ]; then
    echo "  ${status_emoji} PSRule Analysis"
  fi
  if [ -f "${LOG_PATH}/step_b8_cost_estimate.log" ]; then
    echo "  ${status_emoji} Cost Estimation"
  fi

  # Check for deploy stage artifacts
  if [ -f "${LOG_PATH}/step_c2_az_providers.log" ]; then
    echo "  ${status_emoji} Provider Registration"
  fi
  if [ -f "${LOG_PATH}/step_c3_az_deploy_create.log" ]; then
    echo "  ${status_emoji} Infrastructure Deployment"
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
