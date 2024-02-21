#!/usr/bin/env bash
# Copyright (c) Innofactor Plc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause
#
set -e
mkdir -p "${LOG_PATH}"
output=''
if test -n "${CONFIG_ERROR}"; then
  output='## PSRule\n\n'
  output+="${CONFIG_ERROR}❗"
elif test -f "${LOG_PATH}/psrule_analysis.md"; then
  data=$(cat "${LOG_PATH}/psrule_analysis.md")
  if test -z "${data}" || [ "${data}" = '# PSRule' ]; then
    echo 'PSRule report is empty'
  else
    current_pwd="$(pwd)/"
    output='## PSRule'
    if test -f psrule_summary.md; then
      summary=$(
        sed -e ':a' -e 'N' -e '$!ba' psrule_summary.md \
          -e 's|# PSRule result summary\n\n||g' \
          -e 's|## |### |g'
      )
      if test -n "${summary}"; then
        output+="\n\n${summary}"
        mv -f psrule_summary.md "${LOG_PATH}/"
      fi
    fi
    data=$(
      echo "${data}" | sed -e ':a' -e 'N' -e '$!ba' \
      -e 's|# PSRule\n\n||g' \
      -e 's|## |### |g' \
      -e "s|${current_pwd}||g"
    )
    if test -n "${data}"; then
      output+='\n\n<details><summary>Click for details</summary>'
      output+="\n\n${data}\n\n</details>"
    fi
    echo 'PSRule report created'
  fi
fi
if test -n "${output}"; then
  echo -e "${output}" > "${LOG_PATH}/step_${LOG_ORDER}_${LOG_NAME}.md"
fi
