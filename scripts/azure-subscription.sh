#!/usr/bin/env bash
# Copyright (c) Innofactor Plc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause
#
# Sourced by the scripts that need a subscription (az-login.sh, az-deploy.sh,
# azure-providers.sh).
#
# select_subscription selects SUBSCRIPTION_ID for the signed-in identity.
#
# A new role assignment, or a subscription that was just created or moved
# between management groups, can be invisible to the identity for a while,
# and can disappear again after being visible ("The subscription of '<id>'
# doesn't exist in cloud 'AzureCloud'"). Only that error is retried: the
# subscription list is refreshed and logged on every attempt, for up to
# SUBSCRIPTION_WAIT_MINUTES (default 30). Any other error fails at once.
#
# In Azure DevOps this only helps when the AzureCLI@2 task does not select the
# subscription itself, that is with a service connection scoped to a
# management group: the task then signs in at tenant level and this function
# selects the subscription.
#
# On failure it returns 1 and sets SUBSCRIPTION_ERROR.
# shellcheck disable=SC2034 # SUBSCRIPTION_ERROR is read by the caller

select_subscription() {
  local sub="${1:-${SUBSCRIPTION_ID-}}"
  local wait_minutes="${SUBSCRIPTION_WAIT_MINUTES:-30}"
  local interval="${SUBSCRIPTION_WAIT_SECONDS:-30}"
  local start attempt=0 elapsed out visible
  SUBSCRIPTION_ERROR=''
  if test -z "${sub}"; then
    return 0
  fi
  if ! [[ "${wait_minutes}" =~ ^[0-9]+$ ]]; then
    wait_minutes=30
  fi
  if [ "$(az account show --query id -o tsv 2>/dev/null)" = "${sub}" ]; then
    echo "Subscription ${sub} is selected"
    return 0
  fi
  start=$(date +%s)
  while true; do
    attempt=$((attempt + 1))
    if out=$(az account set --subscription "${sub}" 2>&1); then
      echo "Subscription ${sub} selected (attempt ${attempt})"
      return 0
    fi
    if [[ "${out}" != *"doesn't exist in cloud"* ]] && [[ "${out}" != *"does not exist in cloud"* ]]; then
      SUBSCRIPTION_ERROR="Unable to select subscription ${sub}: ${out}"
      return 1
    fi
    elapsed=$(( $(date +%s) - start ))
    visible=$(az account list --refresh --query "[].id" -o tsv 2>/dev/null | paste -sd ',' - || true)
    echo "Subscription ${sub} is not visible to the signed-in identity (attempt ${attempt}, ${elapsed}s of $((wait_minutes * 60))s). Visible subscriptions: ${visible:-none}"
    if [ "${elapsed}" -ge $((wait_minutes * 60)) ]; then
      SUBSCRIPTION_ERROR="Subscription ${sub} was not visible to the signed-in identity after ${wait_minutes} min (${attempt} attempts). Check the role assignment; if it was just created, this is Azure propagation and a later run will succeed."
      return 1
    fi
    # Retry at once when the refresh already lists it; otherwise wait.
    if [[ ",${visible}," != *",${sub},"* ]]; then
      sleep "${interval}"
    fi
  done
}
