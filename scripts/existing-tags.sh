#!/usr/bin/env bash
# Copyright (c) Innofactor Plc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause
#
# Reads the values of selected tags from the resources that already exist at
# the deployment target, and exposes them to every later step of the job as
# the environment variable EXISTING_TAGS (a compact JSON object):
#
#   { "<lower-cased resource id>": { "<tag name>": "<value>" }, ... }
#
# Only resources that carry at least one of the requested tags are listed.
# Tag names are matched without regard to case (Azure treats them that way)
# and are written with the spelling given in EXISTING_TAGS_KEYS.
#
# A template reads it in its parameter file, for example to keep a createdOn
# tag stable across deployments:
#
#   param existingTags = json(readEnvironmentVariable('EXISTING_TAGS'))
#
# Inputs:
#   EXISTING_TAGS_KEYS  Comma separated tag names. Empty: the step is skipped.
#   IN_SCOPE            sub: the resource groups and resources of the
#                       subscription. group: the resource group and its
#                       resources. Other scopes are skipped with a warning,
#                       and EXISTING_TAGS is not set.
#   IN_RESOURCE_GROUP   The resource group, for the group scope.
#   SUBSCRIPTION_ID     The subscription.
#
# ARM list calls are used, not Azure Resource Graph, which can lag newly
# created resources by minutes. A failure to read is an error: an empty
# object would let the template stamp new values on existing resources.
set -e
set -o pipefail
mkdir -p "${LOG_PATH}"
log="${LOG_PATH}/step_${LOG_ORDER}_${LOG_NAME}.log"
trap 'error $? $LINENO "$BASH_COMMAND" $log' ERR
trap cleanup EXIT
cleanup() {
  if test -z "${TF_BUILD-}"; then
    echo '::endgroup::'
  fi
}
print_error() {
  if test -n "${TF_BUILD-}"; then
    echo "##[error]${1}"
  else
    echo "::error::${1}"
  fi
}
print_warning() {
  if test -n "${TF_BUILD-}"; then
    echo "##[warning]${1}"
  else
    echo "::warning::${1}"
  fi
}
error() {
  local msg
  msg="Error on or near line $(("${2}" + 1)) (exit code ${1})"
  msg+=" in ${LOG_NAME/_/ } at $(date '+%Y-%m-%d %H:%M:%S')"
  print_error "${msg}"
  log_output "${4}" "${msg}" "${3}"
  exit "${1}"
}
log_output() {
  local data=''
  local summary="${2}❗"
  if test -n "${3}"; then
    summary+='\n\nCommand that failed:\n\n```text\n'
    summary+="${3}"
    summary+='\n```'
  fi
  if test -f "${1}"; then
    data=$(cat "${1}")
  fi
  local output="## Existing tags\n\n${summary}"
  if test -n "${data}"; then
    output+='\n\n```text\n'
    output+="${data:0:5000}\n"
    output+='```'
  fi
  echo -e "${output}" > "${1/.log/.md}"
}
fail() {
  print_error "${1}"
  log_output "${log}" "${1}" ''
  exit 1
}
if test -z "${TF_BUILD-}"; then
  echo "::group::Output"
fi
keys=$(
  jq -Rc 'split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))' \
    <<< "${EXISTING_TAGS_KEYS-}"
)
if [ "${keys}" = '[]' ]; then
  echo 'Skip! EXISTING_TAGS_KEYS is empty.'
  exit 0
fi
echo "Requested tags: ${keys}" | tee -a "${log}"
case "${IN_SCOPE}" in
  sub|group) ;;
  *)
    print_warning "Existing tags are read only for the sub and group scopes, not '${IN_SCOPE}'. EXISTING_TAGS is not set."
    exit 0
    ;;
esac
if test -z "${SUBSCRIPTION_ID-}"; then
  fail 'SUBSCRIPTION_ID is not set.'
fi
if [ "${IN_SCOPE}" = 'group' ] && test -z "${IN_RESOURCE_GROUP-}"; then
  fail 'IN_RESOURCE_GROUP is not set for the group scope.'
fi
# shellcheck source=azure-subscription.sh
source "$(dirname "${BASH_SOURCE[0]}")/azure-subscription.sh"
if ! select_subscription "${SUBSCRIPTION_ID}"; then
  fail "${SUBSCRIPTION_ERROR}"
fi
query='[].{id: id, tags: tags}'
if [ "${IN_SCOPE}" = 'sub' ]; then
  echo "List the resource groups and resources of subscription ${SUBSCRIPTION_ID}" | tee -a "${log}"
  groups=$(az group list --subscription "${SUBSCRIPTION_ID}" \
    --query "${query}" -o json --only-show-errors 2>> "${log}")
  resources=$(az resource list --subscription "${SUBSCRIPTION_ID}" \
    --query "${query}" -o json --only-show-errors 2>> "${log}")
else
  echo "List resource group ${IN_RESOURCE_GROUP} and its resources" | tee -a "${log}"
  # The group itself can be absent before the first deployment.
  if out=$(az group show --subscription "${SUBSCRIPTION_ID}" \
    --name "${IN_RESOURCE_GROUP}" --query '{id: id, tags: tags}' \
    -o json --only-show-errors 2>&1); then
    groups="[${out}]"
    resources=$(az resource list --subscription "${SUBSCRIPTION_ID}" \
      --resource-group "${IN_RESOURCE_GROUP}" \
      --query "${query}" -o json --only-show-errors 2>> "${log}")
  elif [[ "${out}" == *'ResourceGroupNotFound'* ]]; then
    echo "Resource group ${IN_RESOURCE_GROUP} does not exist yet" | tee -a "${log}"
    groups='[]'
    resources='[]'
  else
    echo "${out}" >> "${log}"
    fail "Unable to read resource group ${IN_RESOURCE_GROUP}."
  fi
fi
existing=$(
  jq -cn --argjson keys "${keys}" --argjson g "${groups}" --argjson r "${resources}" '
    [ ($g + $r)[]
      | select(.tags != null and .tags != {})
      | .tags as $t
      | {
          key: (.id | ascii_downcase),
          value: (reduce $keys[] as $k ({};
            ([$t | to_entries[] | select((.key | ascii_downcase) == ($k | ascii_downcase))] | first) as $m
            | if $m then . + {($k): $m.value} else . end))
        }
      | select(.value != {})
    ] | from_entries'
)
count=$(jq 'length' <<< "${existing}")
size=${#existing}
echo "Resources that carry a requested tag: ${count} (${size} bytes)" | tee -a "${log}"
# One environment variable cannot be larger than 128 KiB on Linux.
if [ "${size}" -gt 120000 ]; then
  fail "EXISTING_TAGS is ${size} bytes, above the 120000 byte limit of one environment variable. Request fewer tags, or deploy to a resource group scope."
fi
if test -n "${TF_BUILD-}"; then
  echo "##vso[task.setvariable variable=EXISTING_TAGS]${existing}"
else
  echo "EXISTING_TAGS=${existing}" >> "${GITHUB_ENV}"
fi
echo 'EXISTING_TAGS is set for the next steps'
