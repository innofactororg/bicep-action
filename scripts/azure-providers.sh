#!/usr/bin/env bash
# Copyright (c) Innofactor Plc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause
#
set -e
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
  local summary=''
  if test -f "${1}"; then
    data=$(cat "${1}")
  fi
  if test -n "${2}"; then
    summary="The ${LOG_NAME/_/ } failed. ${2}❗"
    if test -n "${3}"; then
      summary+='\n\nCommand that failed:\n\n```text\n'
      summary+="${3}"
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
if [ -n "${TF_BUILD-}" ]; then
  echo "##[group]${LOG_NAME}"
else
  echo "::group::${LOG_NAME}"
fi
providers=($(echo "${IN_PROVIDERS}" | tr ',' '\n' | sort -u))
declare -a checkProviders=()
case "${IN_SEVERITY}" in
  ERROR)   log_severity=' --only-show-errors';;
  VERBOSE) log_severity=' --verbose';;
  DEBUG)   log_severity=' --debug';;
  *)       log_severity='';;
esac
if [ -n "${TF_BUILD-}" ]; then
  az account set -s ${SUBSCRIPTION_ID} 1> >(tee -a "${log}") 2> >(tee -a "${log}" >&2)
fi
echo 'Check resource providers...'
registered=($(
  az provider list \
    --query "[?registrationState=='Registered'].namespace" \
    -o tsv $log_severity
))
if test -z "${registered[*]}"; then
  echo 'Could not find any registered providers!' | tee -a "${log}"
else
  echo 'Currently registered:' | tee -a "${log}"
  echo -e "- $(echo "${registered[*]}" | sed 's/ /\n- /g')\n" | tee -a "${log}"
  registered=$(echo "${registered[*]}" | tr '[:upper:]' '[:lower:]')
fi
for provider in "${providers[@]}"; do
  value=$(echo " ${provider} " | tr '[:upper:]' '[:lower:]')
  if [[ ! " ${registered} " =~ ${value} ]]; then
    echo "Register ${provider}..." | tee -a "${log}"
    az provider register \
      --consent-to-permissions --namespace $provider \
      ${log_severity} 1> >(tee -a "${log}") 2> >(tee -a "${log}" >&2)
    checkProviders+=($provider)
  fi
done
if [ ${#checkProviders} -eq 0 ]; then
  echo 'All providers registered!' | tee -a "${log}"
else
  for provider in "${checkProviders[@]}"; do
    state='Registering'
    timesTried=0
    while [ "${state}" != 'Registered' ] || \
          [ $timesTried -gt $WAIT_COUNT ]
    do
      echo "Waiting for ${provider} to register..."
      state=$(
        az provider show --namespace $provider \
          --query 'registrationState' -o tsv \
          $log_severity 1> >(tee -a "${log}") 2> >(tee -a "${log}" >&2)
      )
      timesTried=$(expr $timesTried + 1)
      sleep $WAIT_SECONDS
    done
    if ! [ "${state}" = 'Registered' ]; then
      echo "Timeout: ${provider} in ${state} state..." | tee -a "${log}"
    else
      echo 'Providers successfully registered!' | tee -a "${log}"
    fi
  done
fi
log_output "${log}" '' ''
