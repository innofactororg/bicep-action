#!/usr/bin/env bash
# Copyright (c) Innofactor Plc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause
#
set -e
mkdir -p "${LOG_PATH}"
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
  local summary=''
  if test -f "${1}"; then
    data=$(cat "${1}")
  fi
  if test -n "${2}"; then
    summary="The ${LOG_NAME/_/ } failed. ${2}❗"
    if test -n "${3}"; then
      summary+='\n\nCommand that failed:\n\n```text\n'
      summary+="$(eval echo "${3}")"
      summary+='\n```'
    fi
  elif test -z "${data}"; then
    summary="The ${LOG_NAME/_/ } failed. No output found❗"
  fi
  if test -n "${summary}"; then
    summary="\n\n${summary}"
  fi
  local output="## Resource providers${summary}"
  if test -n "${data}"; then
    output+='\n\n<details><summary>Click for details</summary>'
    output+='\n\n```text\n'
    output+="${data}\n"
    output+='```\n\n</details>'
  fi
  echo -e "${output}" > "${1/.log/.md}"
}
if test -z "${TF_BUILD-}"; then
  echo "::group::Output"
fi
IFS=',' read -ra provider_list <<< "${IN_PROVIDERS}"
provider_sorted="$(printf '%s\n' "${provider_list[@]}" | sort -u | tr '\n' ',')"
IFS=',' read -ra providers <<< "${provider_sorted}"
checkProviders=()
case "${IN_SEVERITY}" in
  ERROR)   log_severity=' --only-show-errors';;
  VERBOSE) log_severity=' --verbose';;
  DEBUG)   log_severity=' --debug';;
  *)       log_severity='';;
esac
out_option="-o tsv${log_severity}"
consent_option="--consent-to-permissions${log_severity}"
if test -n "${TF_BUILD-}"; then
  az account set -s "${SUBSCRIPTION_ID}" 1> >(tee -a "${log}") 2> >(tee -a "${log}" >&2)
fi
echo 'Check resource providers...'
checkProviders=()
cmd="az provider list --query [?registrationState=='Registered'].namespace"
cmd+=" ${out_option}"
echo "Run: ${cmd}"
IFS=',' read -ra registered_list <<< "$(printf '%s\n' "$(eval "${cmd}" 1> >(tee -a "${log}") 2> >(tee -a "${log}" >&2))" | tr '\n' ',')"
if test -z "${registered_list[*]}"; then
  echo 'Could not find any registered providers!' | tee -a "${log}"
  registered=''
else
  echo 'Currently registered:' | tee -a "${log}"
  printf '%s\n' "${registered_list[@]}" | sort | tee -a "${log}"
  registered=$(echo "${registered_list[*]}" | tr '[:upper:]' '[:lower:]')
fi
for provider in "${providers[@]}"; do
  value=$(echo " ${provider} " | tr '[:upper:]' '[:lower:]')
  if [[ ! " ${registered} " =~ ${value} ]]; then
    echo "Register ${provider}..." | tee -a "${log}"
    cmd='az provider register --namespace'
    cmd+=" ${provider}"
    cmd+=" ${consent_option}"
    echo "Run: ${cmd}"
    eval "${cmd}" 1> >(tee -a "${log}") 2> >(tee -a "${log}" >&2)
    checkProviders+=("${provider}")
  fi
done
if [ ${#checkProviders} -eq 0 ]; then
  echo 'All providers registered!' | tee -a "${log}"
else
  for provider in "${checkProviders[@]}"; do
    state='Registering'
    timesTried=0
    while [ "${state}" != 'Registered' ] || \
          [ "${timesTried}" -gt "${WAIT_COUNT}" ]
    do
      echo "Waiting for ${provider} to register..."
      cmd='az provider show --query "registrationState" --namespace'
      cmd+=" ${provider}"
      cmd+=" ${out_option}"
      echo "Run: ${cmd}"
      state=$(
        eval "${cmd}" 1> >(tee -a "${log}") 2> >(tee -a "${log}" >&2)
      )
      timesTried=$(("${timesTried}" + 1))
      sleep "${WAIT_SECONDS}"
    done
    if ! [ "${state}" = 'Registered' ]; then
      echo "Timeout: ${provider} in ${state} state..." | tee -a "${log}"
    else
      echo 'Providers successfully registered!' | tee -a "${log}"
    fi
  done
fi
log_output "${log}" '' ''
