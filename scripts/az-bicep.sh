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
  local summary=''
  local warnings=''
  if test -f "${1}"; then
    data=$(cat "${1}")
    data="${data//${SOURCE_PATH}/}"
    warnings=$(echo "${data}" | sed -n -e '/) : Warning /p')
    warnings="${warnings//WARNING: /}"
    errors=$(echo "${data}" | sed -n -e '/) : Error /p')
    errors="${errors//ERROR: /}"
  fi
  if test -n "${errors}" || test -n "${2}"; then
    summary="The ${LOG_NAME/_/ } failed. ${2}❗"
    if test -n "${3}"; then
      summary+='\n\nCommand that failed:\n\n```text\n'
      summary+="${3}"
      summary+='\n```'
    fi
  fi
  if test -n "${summary}"; then
    local output="## Bicep ${SCRIPT_ACTION}\n\n${summary}"
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
    echo -e "${output}" > "${1/.log/.md}"
  fi
}
if test -z "${TF_BUILD-}"; then
  echo "::group::Output"
fi
if [ "${SCRIPT_ACTION}" = 'build-params' ]; then
  IN_TEMPLATE="${IN_TEMPLATE%% *}"
  src_file_extension='bicepparam'
  out_file_extension='parameters.json'
else
  src_file_extension='bicep'
  out_file_extension='json'
fi
if [[ $IN_TEMPLATE == http* ]]; then
  file="${IN_TEMPLATE##*/}"
  uri="${IN_TEMPLATE}"
  echo "Download ${uri}"
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
  IN_TEMPLATE="${IN_TEMPLATE##*/}"
fi
if [[ $IN_TEMPLATE == *.${src_file_extension} ]]; then
  out_file=$(readlink -f "${IN_TEMPLATE/.${src_file_extension}/.${out_file_extension}}")
  echo "Set output: file='${out_file}'"
  if test -n "${TF_BUILD-}"; then
    echo "##vso[task.setvariable variable=file;isoutput=true]${out_file}"
  else
    echo "file=${out_file}" >> "$GITHUB_OUTPUT"
  fi
  cmd="az bicep ${SCRIPT_ACTION} --file ${IN_TEMPLATE} --outfile ${out_file}"
  case "${IN_SEVERITY}" in
    ERROR)   cmd+=' --only-show-errors';;
    VERBOSE) cmd+=' --verbose';;
    DEBUG)   cmd+=' --debug';;
  esac
  echo "Run: ${cmd}"
  eval "${cmd}" 1> >(tee -a "${log}") 2> >(tee -a "${log}" >&2)
  if test -f "${out_file}"; then
    cp "${out_file}" "${LOG_PATH}/"
  fi
else
  echo "Skip bicep ${SCRIPT_ACTION}, not a ${src_file_extension} file: ${IN_TEMPLATE}"
fi
log_output "${log}" '' ''
