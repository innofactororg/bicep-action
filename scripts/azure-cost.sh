#!/usr/bin/env bash
# Copyright (c) Innofactor Plc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause
#
# Runs the Azure Cost Estimator (ACE) on the compiled template.
#
# The estimate is report-only unless a cost threshold (COST_THRESHOLD or
# THRESHOLD, 0 or more) is set. Report-only, a failure of the estimator
# itself (download, crash, unsupported input) is a warning and an
# "estimate unavailable" note in the PR comment, and the plan continues.
# With a threshold, it fails the plan, because without an estimate the cost
# is not known to be below the threshold; a total above it fails as well.
set -e
if test -n "${COST_THRESHOLD-}"; then
  THRESHOLD=$COST_THRESHOLD
fi
# An unset Azure DevOps variable can arrive as the literal '$(NAME)'.
# shellcheck disable=SC2016
if [[ "${IN_CURRENCY-}" == *'$('* ]] || test -z "${IN_CURRENCY// /}"; then
  IN_CURRENCY='EUR'
fi
report_only() {
  ! [[ "${THRESHOLD-}" =~ ^[0-9]+(\.[0-9]+)?$ ]]
}
notice() {
  if test -n "${TF_BUILD-}"; then
    echo "##[${1}]${2}"
  else
    echo "::${1}::${2}"
  fi
}
mkdir -p "${LOG_PATH}"
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
  fail "${msg}" "${3}" "${1}"
}
# fail MESSAGE [COMMAND] [EXIT_CODE]: report-only, a warning and exit 0;
# with a threshold, an error and a failed step.
fail() {
  trap - ERR
  if report_only; then
    notice warning "Cost estimate unavailable: ${1}"
    log_output "${log}" "${1}" "${2-}" unavailable
    exit 0
  fi
  notice error "${1}"
  log_output "${log}" "${1}" "${2-}"
  exit "${3:-1}"
}
log_output() {
  local data=''
  local output=''
  local over=''
  local summary=''
  if test -f "${1}"; then
    data=$(cat "${1}")
  fi
  if test -n "${2}" && [ "${4-}" = 'unavailable' ]; then
    summary="The cost estimate is unavailable. ${2}\n\nNo cost threshold is set, so the plan continues."
    if test -n "${3}"; then
      summary+='\n\nCommand that failed:\n\n```text\n'
      summary+="$(eval echo "${3}")"
      summary+='\n```'
    fi
  elif test -n "${2}"; then
    summary="The ${LOG_NAME/_/ } failed. ${2}❗"
    if test -n "${3}"; then
      summary+='\n\nCommand that failed:\n\n```text\n'
      summary+="$(eval echo "${3}")"
      summary+='\n```'
    fi
  elif test -z "${data}"; then
    summary="The ${LOG_NAME/_/ } failed. No output found❗"
  fi
  if test -n "${summary}"; then
    summary="\n\n${summary}"
  fi
  local output="## Cost estimate${summary}"
  local file="${LOG_NAME}.json"
  if test -f "${file}"; then
    mv -f "${file}" "${LOG_PATH}/"
    file="${LOG_PATH}/${LOG_NAME}.json"
    local currency
    local delta
    local total
    local txt=''
    total=$(jq -r '.TotalCost.Value | select (.!=null)' "${file}" 2>/dev/null || true)
    delta=$(jq -r '.Delta.Value | select (.!=null)' "${file}" 2>/dev/null || true)
    currency=$(jq -r '.Currency | select (.!=null)' "${file}" 2>/dev/null || true)
    if [ "${total}" != "${delta}" ]; then
      if [ "${delta}" = '0.00' ]; then
        txt='No cost change detected! '
      elif [[ "${delta}" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        if [ "$(echo "${delta} > 0" | bc -l)" -eq 1 ]; then
          txt="Estimated increase is +${delta} ${currency}! "
        else
          txt="Estimated decrease is -${delta} ${currency}! "
        fi
      fi
      if [[ "${total}" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        txt+="Total estimated cost is ${total} ${currency}."
      fi
    elif [ "${total}" = '0.00' ]; then
      txt='No cost detected!'
    elif [[ "${total}" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
      txt="Estimated cost increase is +${total} ${currency}!"
    fi
    if ! report_only; then
      if [[ "${THRESHOLD}" =~ ^[0-9]+(\.[0-9]+)?$ ]] && \
        [[ "${total}" =~ ^[0-9]+(\.[0-9]+)?$ ]] && \
        [ "$(echo "${total} > ${THRESHOLD}" | bc -l)" -eq 1 ]
      then
        over="Total estimated cost exceeds ${THRESHOLD} ${currency}❗"
        txt+="\n\n${over}"
      fi
    fi
    if test -n "${txt}"; then
      output+="\n\n${txt}"
    fi
  fi
  if test -n "${data}"; then
    output+='\n\n<details><summary>Click for details</summary>'
    output+='\n\n```text\n'
    output+="${data}\n"
    output+='```\n'
    output+='\n</details>'
  fi
  echo -e "${output}" > "${1/.log/.md}"
  # A run without a numeric total is an unavailable estimate (report-only)
  # or a failure (with a threshold, the cost is not known to be below it).
  if test -z "${2}" && ! [[ "${total-}" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    fail "The estimator gave no total cost."
  fi
  if test -n "${over}"; then
    if test -n "${TF_BUILD-}"; then
      echo "##[error]${over}"
    else
      echo "::error::${over}"
    fi
    if test -z "${2}"; then
      exit 1
    fi
  fi
}
if test -z "${TF_BUILD-}"; then
  echo "::group::Output"
fi
if ! test -f "${TEMPLATE_FILE}"; then
  fail "Unable to find ${TEMPLATE_FILE}."
fi
cmd='./708gyals2sgas/azure-cost-estimator'
file='linux-x64.zip'
uri='https://github.com/TheCloudTheory/arm-estimator/'
uri+="releases/download/${VERSION_ACE}/${file}"
mkdir -p "708gyals2sgas"
echo "Download ${uri}"
HTTP_CODE=$(curl -sSL --retry 4 --output "708gyals2sgas/${file}" \
  --write-out "%{response_code}" "${uri}" || true
)
if ! [[ "${HTTP_CODE}" =~ ^[0-9]+$ ]] || [ "${HTTP_CODE}" -lt 200 ] || [ "${HTTP_CODE}" -gt 299 ]; then
  fail "Unable to get ${uri} (response code ${HTTP_CODE:-none})."
fi
unzip -q "708gyals2sgas/${file}" -d '708gyals2sgas'
chmod +x ./708gyals2sgas/azure-cost-estimator
PATH=$PATH:$(readlink -f '708gyals2sgas/')
case "${IN_SCOPE}" in
  tenant) cmd+=" ${IN_SCOPE} ${TEMPLATE_FILE} ${IN_LOCATION}";;
  mg)     cmd+=" ${IN_SCOPE} ${TEMPLATE_FILE} ${IN_MANAGEMENT_GROUP} ${IN_LOCATION}";;
  sub)    cmd+=" ${IN_SCOPE} ${TEMPLATE_FILE} ${SUBSCRIPTION_ID} ${IN_LOCATION}";;
  group)  cmd+=" ${TEMPLATE_FILE} ${SUBSCRIPTION_ID} ${IN_RESOURCE_GROUP}";;
esac
if [[ "${TEMPLATE_PARAMS_FILE}" == *'.parameters.json' ]]; then
  cmd+=" --parameters ${TEMPLATE_PARAMS_FILE}"
fi
if [[ "${IN_TEMPLATE_PARAMS}" == *'='* ]]; then
  IFS=' ' read -ra param_list <<< "${IN_TEMPLATE_PARAMS}"
  for pair in "${param_list[@]}"; do
    if test -n "${pair%=*}" && [[ "${pair}" == *=* ]]; then
      cmd+=" --inline ${pair%=*}=${pair#*=}"
    fi
  done
fi
cmd+=" --currency ${IN_CURRENCY}"
cmd+=' --disable-cache'
breakingVer='1.6'
if [ "$(printf '%s\n' "${breakingVer}" "${VERSION_ACE}" | sort -V | head -n1)" = "${breakingVer}" ]; then
  cmd+=' --generate-json-output'
  cmd+=" --json-output-filename ${LOG_NAME}"
else
  cmd+=' --generateJsonOutput'
  cmd+=" --jsonOutputFilename ${LOG_NAME}"
fi
echo "Run: ${cmd}"
eval "${cmd}" 1> >(tee -a "${log}") 2> >(tee -a "${log}" >&2)
log_output "${log}" '' ''
