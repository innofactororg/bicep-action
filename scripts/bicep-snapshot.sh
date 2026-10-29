#!/usr/bin/env bash
# Copyright (c) Innofactor Plc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause
#
# Validate the template against a committed Bicep snapshot.
#
# `bicep snapshot <file>.bicepparam` writes <file>.snapshot.json: every
# resource the template will produce, fully expanded, computed offline.
# When that file is committed next to the parameters file, this step runs
# `bicep snapshot --mode validate` and fails if the template no longer
# produces the committed snapshot, like a plan with unexpected changes.
# Without a snapshot file the step is skipped.
set -e
mkdir -p "${LOG_PATH}"
log="${LOG_PATH}/step_${LOG_ORDER}_${LOG_NAME}.log"
md="${log/.log/.md}"
nl=$'\n'
cleanup() {
  if test -z "${TF_BUILD-}"; then
    echo '::endgroup::'
  fi
}
trap cleanup EXIT
print_error() {
  if test -n "${TF_BUILD-}"; then
    echo "##[error]${1}"
  else
    echo "::error::${1}"
  fi
}
if test -z "${TF_BUILD-}"; then
  echo "::group::Output"
fi
params="${IN_TEMPLATE_PARAMS%% *}"
if [[ "${params}" != *'.bicepparam' ]] || [[ "${params}" == 'http'* ]]; then
  echo "Skip bicep snapshot, not a local bicepparam file: ${params}"
  exit 0
fi
snapshot="${params%.bicepparam}.snapshot.json"
if ! test -f "${snapshot}"; then
  echo "Skip bicep snapshot, no snapshot file: ${snapshot}"
  exit 0
fi

# Use the Bicep CLI the plan selected (bicep-version.sh): the same version the
# build and the what-if compiled with, installed in this step's az config.
# shellcheck source=bicep-version.sh
source "$(dirname "${BASH_SOURCE[0]}")/bicep-version.sh"
if ! select_bicep; then
  print_error "${BICEP_ERROR}"
  printf '%s\n' "## Bicep snapshot${nl}${nl}${BICEP_ERROR}❗" > "${md}"
  exit 1
fi
bicep="${AZURE_CONFIG_DIR:-${HOME}/.azure}/bin/bicep"
bicep_version="${BICEP_SELECTED}"
# az runs the Bicep CLI with invariant globalization where ICU is missing (for
# example Azure Linux images); do the same when calling it directly.
if test -x "${bicep}" && ! "${bicep}" --version >/dev/null 2>&1 && \
   DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 "${bicep}" --version >/dev/null 2>&1; then
  export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
fi
if ! test -x "${bicep}" || \
   [ "$("${bicep}" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)" != "${bicep_version}" ]; then
  msg="The Bicep CLI ${bicep_version} selected for this plan was not found at ${bicep}."
  print_error "${msg}"
  printf '%s\n' "## Bicep snapshot${nl}${nl}${msg}❗" > "${md}"
  exit 1
fi
if ! "${bicep}" snapshot --help >/dev/null 2>&1; then
  msg="Bicep CLI ${bicep_version}, used by this plan, has no snapshot command."
  print_error "${msg}"
  printf '%s\n' "## Bicep snapshot${nl}${nl}${msg}❗" > "${md}"
  exit 1
fi
echo "Bicep CLI ${bicep_version} (${bicep})" | tee -a "${log}"
# The Bicep CLI version that made the snapshot, recorded in metadata.bicepVersion
# (bicep snapshot ignores the extra field when validating).
snapshot_version=$(jq -r '.metadata.bicepVersion // empty' "${snapshot}" 2>/dev/null || true)
version_note=''
if test -n "${snapshot_version}" && [ "${snapshot_version}" != "${bicep_version}" ]; then
  version_note="The snapshot was made with Bicep CLI ${snapshot_version} and this plan uses ${bicep_version}."
fi

# Tenant scope: there is no subscription, so the snapshot is evaluated with
# the tenant and location only (partly supported, see the README).
args=()
case "${IN_SCOPE}" in
  group)  args+=(--subscription-id "${SUBSCRIPTION_ID}" --resource-group "${IN_RESOURCE_GROUP}");;
  sub)    args+=(--subscription-id "${SUBSCRIPTION_ID}");;
  mg)     args+=(--management-group-id "${IN_MANAGEMENT_GROUP}");;
esac
tenant_id="${TENANT_ID-}"
if test -z "${tenant_id}"; then
  tenant_id=$(az account show --query tenantId -o tsv 2>/dev/null || true)
fi
if test -n "${tenant_id}"; then
  args+=(--tenant-id "${tenant_id}")
fi
if test -n "${IN_LOCATION-}"; then
  args+=(--location "${IN_LOCATION}")
fi
shown_args=''
if [ ${#args[@]} -gt 0 ]; then
  shown_args=$(printf ' %q' "${args[@]}")
fi

cmd="bicep snapshot ${params} --mode validate${shown_args}"
echo "Run: ${cmd}"
set +e
output=$("${bicep}" snapshot "${params}" --mode validate "${args[@]}" 2>&1)
code=$?
set -e
output=$(echo "${output}" | sed -e 's/\x1b\[[0-9;]*m//g')
if test -n "${SOURCE_PATH-}"; then
  output="${output//${SOURCE_PATH}\//}"
fi
echo "${output}" | tee -a "${log}"
if [ "${code}" -eq 0 ]; then
  result="The template matches \`${snapshot}\`. No changes ✅"
  if test -n "${version_note}"; then
    result+="${nl}${nl}${version_note} The output is unchanged."
  fi
  printf '%s\n' "## Bicep snapshot${nl}${nl}${result}" > "${md}"
  exit 0
fi
regen="bicep snapshot ${params} --mode overwrite${shown_args}"
regen+="${nl}jq --arg v \"\$(bicep --version | grep -oE '[0-9]+\\.[0-9]+\\.[0-9]+' | head -n1)\" '.metadata.bicepVersion = \$v' ${snapshot} > ${snapshot}.tmp && mv ${snapshot}.tmp ${snapshot}"
if [[ "${output}" == *'Snapshot validation failed'* ]]; then
  diff=$(
    echo "${output}" | sed -n '/^Scope:/,$p' | grep -v '^Scope: <unknown>' | \
      sed -r 's/^([[:space:]]+)([-+~x])[[:space:]]/\2\1/g' | sed -e 's/^~/!/g'
  )
  summary="The template no longer matches \`${snapshot}\` ❗"
  if test -n "${version_note}"; then
    summary+="${nl}${nl}${version_note} Some of these differences may come from the Bicep upgrade rather than from a change to the code."
  fi
  summary+="${nl}${nl}\`\`\`diff${nl}${diff}${nl}\`\`\`"
  summary+="${nl}${nl}If these changes are intended, regenerate the snapshot, record the Bicep CLI version that made it, and commit it:"
  summary+="${nl}${nl}\`\`\`text${nl}${regen}${nl}\`\`\`"
  print_error "The template no longer matches ${snapshot}."
else
  summary="The snapshot validation failed (exit code ${code}) ❗"
  summary+="${nl}${nl}\`\`\`text${nl}${output}${nl}\`\`\`"
  print_error "Bicep snapshot failed with exit code ${code}."
fi
printf '%s\n' "## Bicep snapshot${nl}${nl}${summary}" > "${md}"
exit 1
