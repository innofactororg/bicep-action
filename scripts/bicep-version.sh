#!/usr/bin/env bash
# Copyright (c) Innofactor Plc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause
#
# Sourced by the scripts that compile Bicep (az-bicep.sh, az-deploy.sh).
#
# select_bicep makes az use the Bicep CLI it manages, at the version for this
# run. In CI, az otherwise uses the Bicep CLI on PATH (the runner image's).
#
# - BICEP_VERSION set (a deployment): use the version the plan used, so the
#   deployment compiles exactly what the what-if showed.
# - VERSION_BICEP_CLI set by an earlier step of the same job: use that, so
#   every step of a plan compiles with the same version.
# - Neither: install or upgrade to the latest release.
#
# On success it sets BICEP_SELECTED, exports VERSION_BICEP_CLI to later steps
# and sets the bicep_version step output. On failure it returns 1 and sets
# BICEP_ERROR.
# shellcheck disable=SC2034 # BICEP_SELECTED and BICEP_ERROR are read by the caller

bicep_installed() {
  az bicep version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true
}

select_bicep() {
  local target="${BICEP_VERSION-}"
  local found=''
  BICEP_SELECTED=''
  BICEP_ERROR=''
  if test -z "${target}" && test -n "${VERSION_BICEP_CLI-}" && \
     [[ "${VERSION_BICEP_CLI}" != *'$('* ]]; then
    target="${VERSION_BICEP_CLI}"
  fi
  # Without this, az in CI compiles with the Bicep CLI on PATH, and every
  # version check below would describe that binary instead of the managed one.
  if ! az config set bicep.use_binary_from_path=False >/dev/null 2>&1 || \
     [ "$(az config get bicep.use_binary_from_path --query value -o tsv 2>/dev/null)" != 'False' ]; then
    BICEP_ERROR='Unable to make az use its managed Bicep CLI (az config set bicep.use_binary_from_path=False failed), so the Bicep version cannot be controlled.'
    return 1
  fi
  if test -n "${target}"; then
    if [ "$(bicep_installed)" != "${target}" ]; then
      echo "Install Bicep CLI ${target}"
      az bicep install --version "v${target}" >/dev/null 2>&1 || true
    fi
    found=$(bicep_installed)
    if [ "${found}" != "${target}" ]; then
      if test -n "${BICEP_VERSION-}"; then
        BICEP_ERROR="The plan was made with Bicep CLI ${target}, but that version could not be installed (found ${found:-none}). The reviewed what-if no longer describes this deployment. Run the plan again."
      else
        BICEP_ERROR="Bicep CLI ${target}, used by an earlier step of this job, could not be installed (found ${found:-none})."
      fi
      return 1
    fi
  else
    local cmd='az bicep install'
    if test -n "$(bicep_installed)"; then
      cmd='az bicep upgrade'
    fi
    if ! ${cmd} >/dev/null 2>&1; then
      sleep 10
      if ! ${cmd} >/dev/null 2>&1; then
        BICEP_ERROR="Unable to get the latest Bicep CLI ('${cmd}' failed twice). A plan does not continue with an older or missing compiler."
        return 1
      fi
    fi
    found=$(bicep_installed)
    if test -z "${found}"; then
      BICEP_ERROR='No Bicep CLI is available after installing it.'
      return 1
    fi
  fi
  BICEP_SELECTED="${found}"
  echo "Bicep CLI ${BICEP_SELECTED}"
  if test -n "${TF_BUILD-}"; then
    echo "##vso[task.setvariable variable=bicep_version;isOutput=true]${BICEP_SELECTED}"
    echo "##vso[task.setvariable variable=VERSION_BICEP_CLI]${BICEP_SELECTED}"
  else
    echo "bicep_version=${BICEP_SELECTED}" >> "${GITHUB_OUTPUT:-/dev/null}"
    echo "VERSION_BICEP_CLI=${BICEP_SELECTED}" >> "${GITHUB_ENV:-/dev/null}"
  fi
}
