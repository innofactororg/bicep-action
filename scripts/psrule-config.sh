#!/usr/bin/env bash
# Copyright (c) Innofactor Plc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause
#
set -e
missing=''
if test -n "${RULE_OPTION-}"; then
  OPTION=$RULE_OPTION
fi
if test -z "${OPTION-}"; then
  missing="Environment variable RULE_OPTION or OPTION is not set"
elif ! test -f "${OPTION-}"; then
  missing="Unable to find file ${OPTION}"
else
  echo "Use PSRule config at ${OPTION}"
  if test -n "${TEMPLATE_FILE}" && [[ "${TEMPLATE_PARAMS_FILE}" == *'.parameters.json' ]]; then
    file=$TEMPLATE_PARAMS_FILE
    t=$(basename "${TEMPLATE_FILE}")
    p=$(basename "${file}")
    if [ "${t/.json/}" != "${p/.parameters.json/}" ]; then
      meta=$(jq -r '.metadata | select (.!=null)' "${file}")
      if test -z "${meta}"; then
        json=$(jq --arg t "${t}" '. += {metadata:{template:$t}}' "${file}")
        if test -n "${json}"; then
          printf '%s\n' "${json}" >"${file}"
        fi
      else
        json=$(jq --arg t "${t}" '.metadata += {template:$t}' "${file}")
        if test -n "${json}"; then
          printf '%s\n' "${json}" >"${file}"
        fi
      fi
    fi
  fi
fi
echo "Set output error='${missing}'"
if test -n "${TF_BUILD-}"; then
  echo "##vso[task.setvariable variable=error;isoutput=true]${missing}"
else
  echo "error=${missing}" >> "${GITHUB_OUTPUT}"
fi
if test -n "${missing}"; then
  if test -n "${TF_BUILD-}"; then
    echo "##[error]${missing}"
  else
    echo "::error::${missing}"
  fi
  exit 1
fi
