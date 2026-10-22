#!/usr/bin/env bash
# Copyright (c) Innofactor Plc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause
#
set -e
mkdir -p "${LOG_PATH}"
SCRIPT_ACTION="${1}"
log="${LOG_PATH}/step_${LOG_ORDER}_${LOG_NAME}.log"
trap 'error $? $LINENO "$BASH_COMMAND" $log' ERR
trap cleanup EXIT
cleanup() {
  if test -z "${TF_BUILD-}"; then
    echo '::endgroup::'
  fi
}
error() {
  local msg
  msg="Error on or near line $(("${2}" + 1)) (exit code ${1})"
  msg+=" in ${LOG_NAME/_/ } at $(date '+%Y-%m-%d %H:%M:%S')"
  if test -n "${TF_BUILD-}"; then
    echo "##[error]${msg}"
  else
    echo "::error::${msg}"
  fi
  log_output "${4}" "${msg}" "${3}"
  exit "${1}"
}
log_output() {
  local data=''
  local errors=''
  local json_object=''
  local output=''
  local summary=''
  local warnings=''
  if test -f "${1}"; then
    if [ "${SCRIPT_ACTION}" = 'what-if' ]; then
      data=$(
        sed -r 's/^([[:space:]]+)([-+~x])[[:space:]]/\2\1/g' "${1}" | \
        sed -e 's/^~/!/g'
      )
    else
      data=$(sed '/^{$/,$d' "${1}")
      data="${data//${SOURCE_PATH}/}"
      json_object=$(sed -n '/^{$/,$p' "${1}")
      warnings=$(echo "${data}" | sed -n -e '/) : Warning /p')
      warnings="${warnings//WARNING: /}"
      errors=$(echo "${data}" | sed -n '/^ERROR: /,$p')
      errors="${errors//ERROR: /}"
    fi
  fi
  if test -n "${errors}" || test -n "${2}"; then
    if [ "${SCRIPT_ACTION}" = 'validate' ]; then
      summary="The ${LOG_NAME/_/ } failed. ${2}❗"
    else
      summary="${2}"
    fi
    if test -n "${3}"; then
      summary+='\n\nCommand that failed:\n\n```text\n'
      summary+="$(eval echo "${3}")"
      summary+='\n```'
    fi
  elif [ "${SCRIPT_ACTION}" = 'validate' ] && \
       test -z "${json_object}" && \
       test -z "${warnings}"
  then
    summary="The ${LOG_NAME/_/ } failed. No output found❗"
  elif [ "${SCRIPT_ACTION}" != 'validate' ] && \
       test -z "${data}" && \
       test -z "${json_object}" && \
       test -z "${warnings}"
  then
    summary="No output found❗"
  fi
  if test -n "${summary}"; then
    summary="\n\n${summary}"
  fi
  case "${SCRIPT_ACTION}" in
    validate) output="## Deployment validate${summary}";;
    *)        output="${summary}";;
  esac
  if [ "${SCRIPT_ACTION}" = 'what-if' ] && test -n "${data}"; then
    if [ ${#data} -gt 5000 ]; then
      output+='\n\n<details><summary>Click for details</summary>'
    fi
    output+='\n\n```diff\n'
    output+="${data}\n"
    output+='```'
    if [ ${#data} -gt 5000 ]; then
      output+='\n\n</details>'
    fi
  fi
  if test -n "${warnings}"; then
    output+='\n\n:warning: **WARNINGS**:\n\n```text\n'
    output+="${warnings}\n"
    output+='```'
  fi
  if test -n "${errors}"; then
    output+='\n\n:x: **ERRORS**:\n\n```text\n'
    output+="${errors}\n"
    output+='```'
  fi
  if test -n "${json_object}"; then
    output+='\n\n<details><summary>Click for details</summary>\n'
    output+='\n```json\n'
    output+="${json_object}\n"
    output+='```\n\n</details>'
  fi
  echo -e "${output}" > "${1/.log/.md}"
  if [ "${SCRIPT_ACTION}" = 'validate' ]; then
    local from_code=''
    if [[ "${json_object}" == '{'* ]]; then
      from_code=$(
        echo "${json_object}" | \
          jq -r '.properties.providers | map(.namespace) | join(",")'
      )
      echo "Resource providers discovered by ${LOG_NAME}:"
      echo "${from_code}"
    fi
    local list=''
    if [ "$(echo "${IN_PROVIDERS}" | tr '[:upper:]' '[:lower:]')" = 'disable' ]; then
      list=''
    elif test -n "${IN_PROVIDERS}" && test -n "${from_code}"; then
      list="${IN_PROVIDERS},${from_code}"
    elif test -n "${IN_PROVIDERS}"; then
      list=$IN_PROVIDERS
    elif test -n "${from_code}"; then
      list=$from_code
    fi
    echo "Set output providers='${list}'"
    if test -n "${TF_BUILD-}"; then
      echo "##vso[task.setvariable variable=providers;isOutput=true]${list}"
    else
      echo "providers=${list}" >> "$GITHUB_OUTPUT"
    fi
  fi
}
if test -z "${TF_BUILD-}"; then
  echo "::group::Output"
fi
if [[ "${IN_TEMPLATE}" == 'http'* ]]; then
  file="${IN_TEMPLATE##*/}"
  if ! test -f "${file}"; then
    echo "Download ${IN_TEMPLATE}"
    HTTP_CODE=$(curl -sSL --retry 4 --output "${file}" \
      --write-out "%{response_code}" "${IN_TEMPLATE}"
    )
    if [ "${HTTP_CODE}" -lt 200 ] || [ "${HTTP_CODE}" -gt 299 ]; then
      if test -n "${TF_BUILD-}"; then
        echo "##[error]Unable to get ${file}! Response code: ${HTTP_CODE}"
      else
        echo "::error::Unable to get ${file}! Response code: ${HTTP_CODE}"
      fi
      exit 1
    fi
  fi
  IN_TEMPLATE="${file}"
fi
if [[ "${IN_TEMPLATE_PARAMS}" == 'http'* ]]; then
  uri="${IN_TEMPLATE_PARAMS%% *}"
  file="${file##*/}"
  if ! test -f "${file}"; then
    echo "Download ${IN_TEMPLATE_PARAMS}"
    HTTP_CODE=$(curl -sSL --retry 4 --output "${file}" \
      --write-out "%{response_code}" "${uri}"
    )
    if [ "${HTTP_CODE}" -lt 200 ] || [ "${HTTP_CODE}" -gt 299 ]; then
      if test -n "${TF_BUILD-}"; then
        echo "##[error]Unable to get ${file}! Response code: ${HTTP_CODE}"
      else
        echo "::error::Unable to get ${file}! Response code: ${HTTP_CODE}"
      fi
      exit 1
    fi
  fi
  IN_TEMPLATE_PARAMS="${file}"
fi
# Bicep CLI version: see bicep-version.sh. A plan uses the latest release; a
# deployment uses the version its plan used, or stops and asks for a new plan.
if [[ "${IN_TEMPLATE}" == *'.bicep' ]] || [[ "${IN_TEMPLATE_PARAMS%% *}" == *'.bicepparam' ]]; then
  # shellcheck source=bicep-version.sh
  source "$(dirname "${BASH_SOURCE[0]}")/bicep-version.sh"
  if ! select_bicep; then
    if test -n "${TF_BUILD-}"; then
      echo "##[error]${BICEP_ERROR}"
    else
      echo "::error::${BICEP_ERROR}"
    fi
    printf '%s\n' "## Bicep CLI" "" "${BICEP_ERROR}❗" > "${log/.log/.md}"
    exit 1
  fi
  echo "Bicep CLI ${BICEP_SELECTED}" >> "${log}"
fi
# Deployment stacks (opt-in: DEPLOYMENT_MODE=stack). The what-if and the
# deployment run as a stack; validate (and provider discovery) is unchanged.
# Unmanaged resources are detached by default (STACK_ACTION_ON_UNMANAGE),
# and a plan fails when the stack would delete a resource that is not listed
# in STACK_APPROVED_DELETES, or when deletes are possible but not determinable.
if [ "${DEPLOYMENT_MODE:-deployment}" = 'stack' ] && \
   { [ "${SCRIPT_ACTION}" = 'what-if' ] || [ "${SCRIPT_ACTION}" = 'create' ]; }; then
  nl=$'\n'
  md="${log/.log/.md}"
  stack_fail() {
    if test -n "${TF_BUILD-}"; then
      echo "##[error]${1}"
    else
      echo "::error::${1}"
    fi
    printf '%s\n' "## Deployment stack${nl}${nl}${1}❗${2:+${nl}${nl}${2}}" > "${md}"
    exit 1
  }
  stack_fallback=''
  if [ "${IN_SCOPE}" = 'tenant' ]; then
    stack_fallback='Deployment stacks are not available at tenant scope.'
  elif [[ "${IN_TEMPLATE}" == *'.bicep' ]] && \
       az bicep build --file "${IN_TEMPLATE}" --stdout 2>/dev/null | \
         jq -e 'has("extensions") or has("imports")' >/dev/null 2>&1; then
    stack_fallback='The template uses Bicep extensions, which deployment stacks do not support.'
  fi
  if test -n "${stack_fallback}"; then
    msg="${stack_fallback} Using a standard deployment instead."
    if test -n "${TF_BUILD-}"; then
      echo "##[warning]${msg}"
    else
      echo "::warning::${msg}"
    fi
    echo "${msg}" >> "${log}"
  else
    if ! az stack-whatif --help >/dev/null 2>&1; then
      stack_fail 'This Azure CLI has no stack-whatif command. Deployment stacks need a newer Azure CLI.'
    fi
    repo="${BUILD_REPOSITORY_NAME:-${GITHUB_REPOSITORY##*/}}"
    stack_name="${STACK_NAME:-${repo}}"
    stack_name=$(printf '%s' "${stack_name}" | tr -c 'A-Za-z0-9._()-' '-' | cut -c1-90)
    unmanage="${STACK_ACTION_ON_UNMANAGE:-detachAll}"
    deny="${STACK_DENY_SETTINGS_MODE:-none}"
    sub_id="${SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}"
    stack_args=()
    case "${IN_SCOPE}" in
      group)
        stack_scope='group'
        stack_id="/subscriptions/${sub_id}/resourceGroups/${IN_RESOURCE_GROUP}"
        stack_args+=(--resource-group "${IN_RESOURCE_GROUP}");;
      mg)
        stack_scope='mg'
        stack_id="/providers/Microsoft.Management/managementGroups/${IN_MANAGEMENT_GROUP}"
        stack_args+=(--management-group-id "${IN_MANAGEMENT_GROUP}" --location "${IN_LOCATION}");;
      *)
        stack_scope='sub'
        stack_id="/subscriptions/${sub_id}"
        stack_args+=(--location "${IN_LOCATION}");;
    esac
    stack_id+="/providers/Microsoft.Resources/deploymentStacks/${stack_name}"
    template_args=()
    if [[ "${IN_TEMPLATE}" == 'http'* ]]; then
      template_args+=(--template-uri "${IN_TEMPLATE}")
    elif [[ "${IN_TEMPLATE}" == '/subscriptions/'* ]]; then
      template_args+=(--template-spec "${IN_TEMPLATE}")
    else
      template_args+=(--template-file "${IN_TEMPLATE}")
    fi
    if test -n "${IN_TEMPLATE_PARAMS}"; then
      read -ra param_args <<< "${IN_TEMPLATE_PARAMS}"
      template_args+=(--parameters "${param_args[@]}")
    fi
    common=(--action-on-unmanage "${unmanage}" --deny-settings-mode "${deny}")
    echo "Stack ${stack_id} (action on unmanage: ${unmanage}, deny settings: ${deny})" | tee -a "${log}"

    if [ "${SCRIPT_ACTION}" = 'create' ]; then
      stack_cmd=(az stack "${stack_scope}" create --name "${stack_name}" "${template_args[@]}" "${common[@]}" "${stack_args[@]}" --yes)
      echo "Run: ${stack_cmd[*]}"
      "${stack_cmd[@]}" 1> >(tee -a "${log}") 2> >(tee -a "${log}" >&2)
      printf '%s\n' "## Deployment stack${nl}${nl}Stack \`${stack_name}\` deployed (action on unmanage: \`${unmanage}\`, deny settings: \`${deny}\`) ✅" > "${md}"
      exit 0
    fi

    # what-if: one what-if result, read twice: as text for the comment, and
    # as JSON (a plain read, not a second evaluation) for the delete gate.
    result_name=$(printf '%s' "${stack_name}-whatif-${RUN_ID}" | cut -c1-90)
    scope_args=("${stack_args[@]}")
    if [ "${stack_scope}" = 'sub' ]; then
      scope_args=()
    elif [ "${stack_scope}" = 'mg' ]; then
      scope_args=(--management-group-id "${IN_MANAGEMENT_GROUP}")
    fi
    stack_cmd=(az stack-whatif "${stack_scope}" create --name "${result_name}" --stack-id "${stack_id}" "${template_args[@]}" "${common[@]}" "${stack_args[@]}" --retention-interval PT1H --no-color)
    echo "Run: ${stack_cmd[*]}"
    "${stack_cmd[@]}" 1> >(tee -a "${log}") 2> >(tee -a "${log}" >&2)
    text=$(sed -n '/^Resource and property changes/,$p' "${log}")
    json=$(az stack-whatif "${stack_scope}" show --name "${result_name}" "${scope_args[@]}" --no-pretty-print -o json)
    az stack-whatif "${stack_scope}" delete --name "${result_name}" "${scope_args[@]}" --yes >/dev/null 2>&1 || true

    count() { jq -r --arg t "${1}" '[.properties.changes.resourceChanges[]? | select(.changeType == $t)] | length' <<< "${json}"; }
    n_create=$(count create); n_modify=$(count modify); n_delete=$(count delete)
    n_detach=$(count detach); n_unsupported=$(count unsupported); n_nochange=$(count noChange)
    n_adopt=$(jq -r '[.properties.changes.resourceChanges[]? | select(.managementStatusChange.before == "notManaged" and .managementStatusChange.after == "managed")] | length' <<< "${json}")
    nondeterministic=$(jq -r '[.properties.diagnostics[]? | select(.code == "ShortCircuitedResourceId")] | length' <<< "${json}")
    deletes=$(jq -r '.properties.changes.resourceChanges[]? | select(.changeType == "delete") | .id' <<< "${json}")
    detaches=$(jq -r '.properties.changes.resourceChanges[]? | select(.changeType == "detach") | .id' <<< "${json}")

    unapproved=''
    if test -n "${deletes}"; then
      approved=''
      if test -n "${STACK_APPROVED_DELETES-}" && test -f "${STACK_APPROVED_DELETES}"; then
        approved=$(jq -r '.[]' "${STACK_APPROVED_DELETES}" | tr '[:upper:]' '[:lower:]')
      fi
      while read -r id; do
        if ! grep -qxF "$(printf '%s' "${id}" | tr '[:upper:]' '[:lower:]')" <<< "${approved}"; then
          unapproved+="- \`${id}\`${nl}"
        fi
      done <<< "${deletes}"
    fi

    head="**Stack \`${stack_name}\`**: ${n_create} to create, ${n_modify} to modify, **${n_delete} to delete**, ${n_detach} to detach, ${n_unsupported} unsupported, ${n_nochange} unchanged. Action on unmanage: \`${unmanage}\`, deny settings: \`${deny}\`."
    notes=''
    if test -n "${deletes}"; then
      notes+="${nl}${nl}:x: **Resources the stack would delete:**${nl}${nl}$(sed 's/^/- `/; s/$/`/' <<< "${deletes}")"
    fi
    if test -n "${detaches}"; then
      notes+="${nl}${nl}:warning: **Resources the stack would stop managing (detach, not deleted):**${nl}${nl}$(sed 's/^/- `/; s/$/`/' <<< "${detaches}")"
    fi
    if [ "${n_adopt}" -gt 0 ]; then
      notes+="${nl}${nl}:information_source: ${n_adopt} existing resources will be adopted into the stack. Until the stack has been deployed once, the property changes below can include values that Azure set itself (defaults, tags added by policy); Azure filters these out of later plans."
    fi
    gate=''
    if test -n "${unapproved}"; then
      gate="The stack would delete resources that are not approved in \`${STACK_APPROVED_DELETES:-STACK_APPROVED_DELETES (not set)}\`:${nl}${nl}${unapproved}"
    elif [ "${nondeterministic}" -gt 0 ] && [ "${unmanage}" != 'detachAll' ]; then
      gate="The what-if result is not deterministic (${n_unsupported} unsupported resources), so it cannot show every resource the stack might delete with \`${unmanage}\`. Use \`detachAll\`, or make those resource names known at plan time."
    fi
    if [ "${nondeterministic}" -gt 0 ] && [ "${unmanage}" = 'detachAll' ]; then
      notes+="${nl}${nl}:information_source: Azure reports this result as not deterministic (${n_unsupported} unsupported resources). With \`detachAll\` nothing can be deleted, so this is shown for information."
    fi
    diff=$(sed -r 's/^([[:space:]]+)([-+~xv!=])[[:space:]]/\2\1/g' <<< "${text}" | sed -e 's/^~/!/g')
    body="${head}${notes}"
    if test -n "${gate}"; then
      body=":no_entry: ${gate}${nl}${nl}${body}"
    fi
    details="${nl}${nl}\`\`\`diff${nl}${diff}${nl}\`\`\`"
    if [ ${#diff} -gt 5000 ]; then
      details="${nl}${nl}<details><summary>Click for details</summary>${details}${nl}${nl}</details>"
    fi
    printf '%s\n' "${body}${details}" > "${md}"
    if test -n "${gate}"; then
      if test -n "${TF_BUILD-}"; then
        echo "##[error]Deployment stack plan blocked: unapproved or undeterminable deletes."
      else
        echo "::error::Deployment stack plan blocked: unapproved or undeterminable deletes."
      fi
      exit 1
    fi
    exit 0
  fi
fi
cmd="az deployment ${IN_SCOPE} ${SCRIPT_ACTION} --name ${LOG_NAME}_${RUN_ID}"
if [[ "${IN_TEMPLATE}" == 'http'* ]]; then
  cmd+=" --template-uri ${IN_TEMPLATE}"
elif [[ "${IN_TEMPLATE}" == '/subscriptions/'* ]]; then
  cmd+=" --template-spec ${IN_TEMPLATE}"
else
  cmd+=" --template-file ${IN_TEMPLATE}"
fi
if test -n "${IN_TEMPLATE_PARAMS}"; then
  cmd+=" --parameters ${IN_TEMPLATE_PARAMS}"
fi
if ! [ "${IN_SCOPE}" = 'group' ]; then
  cmd+=" --location ${IN_LOCATION}"
fi
if [ "${IN_SCOPE}" = 'mg' ]; then
  cmd+=" --management-group-id ${IN_MANAGEMENT_GROUP}"
fi
if [ "${IN_SCOPE}" = 'group' ]; then
  cmd+=" --resource-group ${IN_RESOURCE_GROUP}"
fi
case "${IN_SEVERITY}" in
  ERROR)   cmd+=' --only-show-errors';;
  VERBOSE) cmd+=' --verbose';;
  DEBUG)   cmd+=' --debug';;
esac
case "${SCRIPT_ACTION}" in
  create)   cmd+=' --no-prompt true';;
  validate) cmd+=' --no-prompt true -o json';;
  what-if)  cmd+=' --exclude-change-types Ignore NoChange --no-prompt true';;
esac
if test -n "${TF_BUILD-}"; then
  az account set -s "${SUBSCRIPTION_ID}" 1> >(tee -a "${log}") 2> >(tee -a "${log}" >&2)
fi
echo "Run: ${cmd}"
eval "${cmd}" 1> >(tee -a "${log}") 2> >(tee -a "${log}" >&2)
log_output "${log}" '' ''
