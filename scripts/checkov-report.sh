#!/usr/bin/env bash
# Copyright (c) Innofactor Plc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause
#
set -e
trap cleanup EXIT
cleanup() {
  if [ -n "${TF_BUILD-}" ]; then
    echo '##[endgroup]'
  else
    echo '::endgroup::'
  fi
}
output=''
if [ -n "${TF_BUILD-}" ]; then
  echo "##[group]${LOG_NAME}"
else
  echo "::group::${LOG_NAME}"
fi
if test -f 'checkov.sarif'; then
  mv -f 'checkov.sarif' "${LOG_PATH}/"
fi
if test -f 'checkov.json'; then
  mv -f 'checkov.json' "${LOG_PATH}/"
  data=$(cat "${LOG_PATH}/checkov.json")
  if test -z "${data}"; then
    echo 'Checkov report is empty'
  else
    output='## Checkov analysis'
    output+='\n\n<details><summary>Click for details</summary>\n'
    output+='\n```json\n'
    output+="${data}\n"
    output+='```\n\n</details>'
    echo 'Checkov report created'
  fi
fi
if test -n "${output}"; then
  echo -e "${output}" > "${LOG_PATH}/step_${LOG_ORDER}_${LOG_NAME}.md"
fi
