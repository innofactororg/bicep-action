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

# The Bicep CLI installed by `az bicep install`; fall back to one on PATH.
az bicep version >/dev/null 2>&1 || true
bicep="${AZURE_CONFIG_DIR:-${HOME}/.azure}/bin/bicep"
if ! test -x "${bicep}"; then
  bicep=$(command -v bicep || true)
fi
if test -z "${bicep}" || ! "${bicep}" --help 2>&1 | grep -q 'snapshot'; then
  msg='The Bicep CLI has no snapshot command. Upgrade it with: az bicep upgrade'
  print_error "${msg}"
  echo -e "## Bicep snapshot\n\n${msg}❗" > "${md}"
  exit 1
fi
"${bicep}" --version | tee -a "${log}"

args=''
case "${IN_SCOPE}" in
  group)  args+=" --subscription-id ${SUBSCRIPTION_ID} --resource-group ${IN_RESOURCE_GROUP}";;
  sub)    args+=" --subscription-id ${SUBSCRIPTION_ID}";;
  mg)     args+=" --management-group-id ${IN_MANAGEMENT_GROUP}";;
esac
tenant_id="${TENANT_ID-}"
if test -z "${tenant_id}"; then
  tenant_id=$(az account show --query tenantId -o tsv 2>/dev/null || true)
fi
if test -n "${tenant_id}"; then
  args+=" --tenant-id ${tenant_id}"
fi
if test -n "${IN_LOCATION-}"; then
  args+=" --location ${IN_LOCATION}"
fi

cmd="bicep snapshot ${params} --mode validate${args}"
echo "Run: ${cmd}"
set +e
output=$("${bicep}" snapshot "${params}" --mode validate ${args} 2>&1)
code=$?
set -e
output=$(echo "${output}" | sed -e 's/\x1b\[[0-9;]*m//g')
if test -n "${SOURCE_PATH-}"; then
  output="${output//${SOURCE_PATH}\//}"
fi
echo "${output}" | tee -a "${log}"
if [ "${code}" -eq 0 ]; then
  echo -e "## Bicep snapshot\n\nThe template matches \`${snapshot}\`. No changes ✅" > "${md}"
  exit 0
fi
regen="bicep snapshot ${params} --mode overwrite${args}"
if [[ "${output}" == *'Snapshot validation failed'* ]]; then
  diff=$(
    echo "${output}" | sed -n '/^Scope:/,$p' | grep -v '^Scope: <unknown>' | \
      sed -r 's/^([[:space:]]+)([-+~x])[[:space:]]/\2\1/g' | sed -e 's/^~/!/g'
  )
  summary="The template no longer matches \`${snapshot}\` ❗"
  summary+='\n\n```diff\n'
  summary+="${diff}\n"
  summary+='```'
  summary+='\n\nIf these changes are intended, regenerate the snapshot and commit it:'
  summary+='\n\n```text\n'
  summary+="${regen}\n"
  summary+='```'
  print_error "The template no longer matches ${snapshot}."
else
  summary="The snapshot validation failed (exit code ${code}) ❗"
  summary+='\n\n```text\n'
  summary+="${output}\n"
  summary+='```'
  print_error "Bicep snapshot failed with exit code ${code}."
fi
echo -e "## Bicep snapshot\n\n${summary}" > "${md}"
exit 1
