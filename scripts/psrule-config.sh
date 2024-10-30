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
    t=$(realpath --relative-to="$(pwd)" "${TEMPLATE_FILE}")
    p=$(realpath --relative-to="$(pwd)" "${file}")
    if [ "${t/.json/}" != "${p/.parameters.json/}" ]; then
      echo "Template name '${t/.json/}' differ from parameters '${p/.parameters.json/}'"
      meta=$(jq -r '.metadata | select (.!=null)' "${file}")
      if test -z "${meta}"; then
        json=$(jq --arg t "${t}" '. += {metadata:{template:$t}}' "${file}")
        if test -n "${json}"; then
          printf '%s\n' "${json}" >"${file}"
          echo "Added metadata to ${file}"
          cp "${file}" "${LOG_PATH}/"
        fi
      else
        json=$(jq --arg t "${t}" '.metadata += {template:$t}' "${file}")
        if test -n "${json}"; then
          printf '%s\n' "${json}" >"${file}"
          echo "Updated metadata in ${file}"
          cp "${file}" "${LOG_PATH}/"
        fi
      fi
    else
      echo "No need to set metadata in ${file}"
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
