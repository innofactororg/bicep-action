#!/usr/bin/env bash
# Copyright (c) Innofactor Plc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause
#
set -e
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
  local msg
  msg="Error on or near line $(("${2}" + 1)) (exit code ${1})"
  msg+=" in ${LOG_NAME/_/ } at $(date '+%Y-%m-%d %H:%M:%S')"
  echo "${msg}"
  log_output "${4}" "${msg}" "${3}"
  exit "${1}"
}
log_output() {
  local data=''
  local output=''
  local over=''
  local summary=''
  if test -f "${1}"; then
    data=$(cat "${1}")
  fi
  if test -n "${2}"; then
    summary="The ${LOG_NAME/_/ } failed. ${2}❗"
    if test -n "${3}"; then
      summary+='\n\nCommand that failed:\n\n```text\n'
      summary+="${3}"
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
    total=$(jq -r '.TotalCost.Value | select (.!=null)' "${file}")
    delta=$(jq -r '.Delta.Value | select (.!=null)' "${file}")
    currency=$(jq -r '.Currency | select (.!=null)' "${file}")
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
    if [[ "${THRESHOLD}" =~ ^[0-9]+(\.[0-9]+)?$ ]] && \
      [[ "${total}" =~ ^[0-9]+(\.[0-9]+)?$ ]] && \
      [ "$(echo "${total} > ${THRESHOLD}" | bc -l)" -eq 1 ]
    then
      over="Total estimated cost exceeds ${THRESHOLD} ${currency}❗"
      txt+="\n\n${over}"
    fi
    output+="\n\n${txt}"
  fi
  if test -n "${data}"; then
    output+='\n\n<details><summary>Click for details</summary>'
    output+='\n\n```text\n'
    output+="${data}\n"
    output+='```\n'
    output+='\n</details>'
  fi
  echo -e "${output}" > "${1/.log/.md}"
  if test -n "${over}"; then
    echo "::error::${over}"
    if test -z "${2}"; then
      exit 1
    fi
  fi
}
if [ -n "${TF_BUILD-}" ]; then
  echo "##[group]${LOG_NAME}"
else
  echo "::group::${LOG_NAME}"
fi
if ! test -f "${TEMPLATE_FILE}"; then
  echo "Skip: Unable to find ${TEMPLATE_FILE}."
  exit 1
fi
cmd='./708gyals2sgas/azure-cost-estimator'
file='linux-x64.zip'
url='https://github.com/TheCloudTheory/arm-estimator/'
url+="releases/download/${VERSION_ACE}/${file}"
mkdir -p "708gyals2sgas"
echo "Run: curl -o 708gyals2sgas/${file} -sSL ${url}"
curl -o "708gyals2sgas/${file}" -sSL "${url}"
unzip -q "708gyals2sgas/${file}" -d 708gyals2sgas
chmod +x ./708gyals2sgas/azure-cost-estimator
PATH=$PATH:$(readlink -f 708gyals2sgas/)
case "${IN_SCOPE}" in
  tenant) cmd+=" ${IN_SCOPE} ${TEMPLATE_FILE} ${IN_LOCATION}";;
  mg)     cmd+=" ${IN_SCOPE} ${TEMPLATE_FILE} ${IN_MANAGEMENT_GROUP} ${IN_LOCATION}";;
  sub)    cmd+=" ${IN_SCOPE} ${TEMPLATE_FILE} ${SUBSCRIPTION_ID} ${IN_LOCATION}";;
  group)  cmd+=" ${TEMPLATE_FILE} ${SUBSCRIPTION_ID} ${IN_RESOURCE_GROUP}";;
esac
if [[ $TEMPLATE_PARAMS_FILE == *.parameters.json ]]; then
  cmd+=" --parameters ${TEMPLATE_PARAMS_FILE}"
fi
if [[ $IN_TEMPLATE_PARAMS == *=* ]]; then
  IFS=' ' read -ra param_list <<< "${IN_TEMPLATE_PARAMS}"
  for pair in "${param_list[@]}"; do
    if test -n "${pair%=*}" && [[ "${pair}" == *=* ]]; then
      cmd+=" --inline ${pair%=*}=${pair#*=}"
    fi
  done
fi
cmd+=" --currency ${IN_CURRENCY}"
cmd+=' --disable-cache --generateJsonOutput'
cmd+=" --jsonOutputFilename ${LOG_NAME}"
echo "Run: ${cmd}"
eval "${cmd}" 1> >(tee -a "${log}") 2> >(tee -a "${log}" >&2)
log_output "${log}" '' ''
