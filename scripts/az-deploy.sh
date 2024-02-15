#!/usr/bin/env bash
# Copyright (c) Innofactor Plc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause
#
set -e
SCRIPT_ACTION="${1}"
log="${LOG_PATH}/step_${LOG_ORDER}_${LOG_NAME}.log"
trap 'error $? $LINENO "$BASH_COMMAND" $log' ERR
trap cleanup EXIT
cleanup() {
  if [ -n "${TF_BUILD-}" ]; then
    echo '##[endgroup]'
  else
    echo '::endgroup::'
  fi
}
error() {
  local msg="Error on or near line $(expr $2 + 1) (exit code $1)"
  msg+=" in ${LOG_NAME/_/ } at $(date '+%Y-%m-%d %H:%M:%S')"
  echo "${msg}"
  log_output "$4" "${msg}" "$3"
  exit $1
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
      data=$(echo "${data//${SOURCE_PATH}/}")
      json_object=$(sed -n '/^{$/,$p' "${1}")
      warnings=$(echo "${data}" | sed -n -e '/) : Warning /p')
      warnings=$(echo "${warnings//WARNING: /}")
      errors=$(echo "${data}" | sed -n '/^ERROR: /,$p')
      errors=$(echo "${errors//ERROR: /}")
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
      summary+="${3}"
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
    if [[ "${json_object}" == {* ]]; then
      from_code=$(
        echo "${json_object}" | \
          jq '.properties.providers | map(.namespace) | join(",")'
      )
      echo "Resource providers discovered by ${LOG_NAME}:"
      echo "${from_code}"
    fi
    local list=$(echo "${IN_PROVIDERS} ${from_code}" | xargs)
    echo "Set output: providers='${list}'"
    if [ -n "${TF_BUILD-}" ]; then
      echo "##vso[task.setvariable variable=providers;isOutput=true]${list}"
    else
      echo "providers=${list}" >> "$GITHUB_OUTPUT"
    fi
  fi
}
if [ -n "${TF_BUILD-}" ]; then
  echo "##[group]${LOG_NAME}"
else
  echo "::group::${LOG_NAME}"
fi
if [[ $IN_TEMPLATE == http* ]]; then
  if ! test -f "${IN_TEMPLATE##*/}"; then
    echo "Run: curl -o ${IN_TEMPLATE##*/} -sSL ${IN_TEMPLATE}"
    curl -o "${IN_TEMPLATE##*/}" -sSL "${IN_TEMPLATE}" 1> >(tee -a "${log}") 2> >(tee -a "${log}" >&2)
  fi
  IN_TEMPLATE="${IN_TEMPLATE##*/}"
fi
if [[ $IN_TEMPLATE_PARAMS == http* ]]; then
  file="${IN_TEMPLATE_PARAMS%% *}"
  if ! test -f "${file##*/}"; then
    echo "Run: curl -o ${file##*/} -sSL ${file}"
    curl -o "${file##*/}" -sSL "${file}" 1> >(tee -a "${log}") 2> >(tee -a "${log}" >&2)
  fi
  IN_TEMPLATE_PARAMS="${IN_TEMPLATE_PARAMS/${file}/${file##*/}}"
fi
cmd="az deployment ${IN_SCOPE} ${SCRIPT_ACTION} --name ${LOG_NAME}_${RUN_ID}"
if [[ $IN_TEMPLATE == http* ]]; then
  cmd+=" --template-uri ${IN_TEMPLATE}"
elif [[ $IN_TEMPLATE == /subscriptions/* ]]; then
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
if [ -n "${TF_BUILD-}" ]; then
  az account set -s ${SUBSCRIPTION_ID} 1> >(tee -a "${log}") 2> >(tee -a "${log}" >&2)
fi
echo "Run: ${cmd}"
eval "${cmd}" 1> >(tee -a "${log}") 2> >(tee -a "${log}" >&2)
log_output "${log}" '' ''
