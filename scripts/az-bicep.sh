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
  local errors=''
  local summary=''
  local warnings=''
  if test -f "${1}"; then
    local data=$(cat "${1}")
    data=$(echo "${data//${SOURCE_PATH}/}")
    warnings=$(echo "${data}" | sed -n -e '/) : Warning /p')
    warnings=$(echo "${warnings//WARNING: /}")
    errors=$(echo "${data}" | sed -n -e '/) : Error /p')
    errors=$(echo "${errors//ERROR: /}")
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
if [ -n "${TF_BUILD-}" ]; then
  echo "##[group]${LOG_NAME}"
else
  echo "::group::${LOG_NAME}"
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
  echo "Download ${IN_TEMPLATE}"
  curl -o "${IN_TEMPLATE##*/}" -sSL "${IN_TEMPLATE}" 1> >(tee -a "${log}") 2> >(tee -a "${log}" >&2)
  IN_TEMPLATE="${IN_TEMPLATE##*/}"
fi
if [[ $IN_TEMPLATE == *.${src_file_extension} ]]; then
  out_file=$(readlink -f "${IN_TEMPLATE/.${src_file_extension}/.${out_file_extension}}")
  echo "Set output: file='${out_file}'"
  if [ -n "${TF_BUILD-}" ]; then
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
    cp ${out_file} ${LOG_PATH}/
  fi
else
  echo "Skip bicep ${SCRIPT_ACTION}, not a ${src_file_extension} file: ${IN_TEMPLATE}"
fi
log_output "${log}" '' ''
