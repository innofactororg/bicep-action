#!/usr/bin/env bash
# Copyright (c) Innofactor Plc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause
#
set -e
mkdir -p "${LOG_PATH}"
log="${LOG_PATH}/step_${LOG_ORDER}_${LOG_NAME}.log"
trap 'error $? $LINENO "$BASH_COMMAND" $log' ERR
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
  local summary="${2}❗"
  if test -n "${3}"; then
    summary+='\n\nCommand that failed:\n\n```text\n'
    summary+="${3}"
    summary+='\n```'
  fi
  local data
  data=$(cat "${1}" 2>/dev/null || true)
  local output="## Install tools\n\n${summary}"
  if test -n "${data}"; then
    output+='\n\n```text\n'
    output+="${data}\n"
    output+='```'
  fi
  echo -e "${output}" > "${1/.log/.md}"
}
az_version=$(az version | jq -r '."azure-cli"')
echo "Azure CLI ${az_version} with extensions:" | tee -a "${log}"
az version --query extensions -o yaml | tee -a "${log}"
if [[ $IN_TEMPLATE == *.bicep ]]; then
  az config set bicep.use_binary_from_path=False >/dev/null 2>&1
  cmd="az bicep install"
  case "${IN_SEVERITY}" in
    ERROR)   cmd+=' --only-show-errors';;
    VERBOSE) cmd+=' --verbose';;
    DEBUG)   cmd+=' --debug';;
  esac
  echo "Run: ${cmd}"
  eval "${cmd}" 1> >(tee -a "${log}") 2> >(tee -a "${log}" >&2)
fi
