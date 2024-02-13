#!/usr/bin/env bash
# Copyright (c) Innofactor Plc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause
#
set -e
log="${LOG_PATH}/step_${LOG_ORDER}_${LOG_NAME}.log"
trap 'error $? $LINENO "$BASH_COMMAND" $log' ERR
error() {
  local msg="Error on or near line $(expr $2 + 1) (exit code $1)"
  msg+=" in ${LOG_NAME} at $(date '+%Y-%m-%d %H:%M:%S')"
  echo "${msg}"
  log_output "$4" "${msg}" "$3"
  exit $1
}
log_output() {
  local data=''
  local summary="${2}❗"
  if test -n "${3}"; then
    summary+="\n\nCommand that failed:\n${3}"
  fi
  if test -f "${1}"; then
    data=$(
      sed -r 's/^([[:space:]]+)([-+~x])[[:space:]]/\2\1/g' "${1}" | \
      sed -e 's/^~/!/g'
    )
  fi
  local output="## Azure login\n\n${summary}"
  if test -n "${data}"; then
    if [ ${#data} -gt 5000 ]; then
      output+='\n\n<details><summary>Click for details</summary>'
    fi
    output+='\n\n```text\n'
    output+="${data}\n"
    output+='```'
    if [ ${#data} -gt 5000 ]; then
      output+='\n\n</details>'
    fi
  fi
  echo -e "${output}" > "${1/.log/.md}"
}
case "${IN_SEVERITY}" in
  ERROR)   log_severity=' --only-show-errors';;
  VERBOSE) log_severity=' --verbose';;
  DEBUG)   log_severity=' --debug';;
  *)       log_severity='';;
esac
cmd="az login --service-principal -t ${TENANT_ID} -u ${CLIENT_ID}"
if test -n "${CLIENT_SECRET}"; then
  cmd+=" -p ${CLIENT_SECRET}"
else
  token=$(
    curl -sSL \
      -H 'Accept: application/json; api-version=2.0' \
      -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" \
      -H 'Content-Type: application/json' \
      -G --data-urlencode "audience=api://AzureADTokenExchange" \
      "${ACTIONS_ID_TOKEN_REQUEST_URL}" | jq -r '.value'
  )
  echo "::add-mask::${token}"
  cmd+=" --federated-token ${token}"
fi
cmd+=" --allow-no-subscriptions ${log_severity}"
echo "Run: ${cmd}"
eval "${cmd}" 1> >(tee -a "${log}") 2> >(tee -a "${log}" >&2)
az account set -s ${SUBSCRIPTION_ID} 1> >(tee -a "${log}") 2> >(tee -a "${log}" >&2)

