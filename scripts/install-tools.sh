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
  if [ -n "${TF_BUILD-}" ]; then
    echo '##[endgroup]'
  else
    echo '::endgroup::'
  fi
}
error() {
  local msg="Error on or near line $(expr $2 + 1) (exit code $1)"
  msg+=" in ${LOG_NAME} at $(date '+%Y-%m-%d %H:%M:%S')"
  echo "${msg}"
  log_output "$4" "${msg}" "$3"
  exit $1
}
log_output() {
  local summary="${2}❗"
  if test -n "${3}"; then
    summary+="\n\nCommand that failed:\n${3}"
  fi
  local data=$(cat "${1}" 2>/dev/null || true)
  local output="## Install tools\n\n${summary}"
  if test -n "${data}"; then
    output+='\n\n```text\n'
    output+="${data}\n"
    output+='```'
  fi
  echo -e "${output}" > "${1/.log/.md}"
}
if [ -n "${TF_BUILD-}" ]; then
  echo "##[group]${LOG_NAME}"
else
  echo "::group::${LOG_NAME}"
fi
az_version=$(az version | jq -r '."azure-cli"')
echo "Azure CLI ${az_version}" | tee -a "${log}"
echo 'Installed extensions:' | tee -a "${log}"
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
