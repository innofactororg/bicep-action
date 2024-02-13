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
add_output() {
  local add=''
  local data=''
  local name=''
  local step=''
  local output=''
  while read -r file; do
    data=$(cat "${file}")
    if test -n "${data}"; then
      name=$(basename "${file}")
      name=${name:8}
      name=${name/_/ }
      name=${name/psrule/PSRule}
      name=${name/.md/}
      name="$(tr '[:lower:]' '[:upper:]' <<< ${name:0:1})${name:1}"
      step=$(printf '%20s' "'${name}'")
      add=$(printf '%5d' ${#data})
      if [ ${#data} -gt 63900 ]; then
        data=$(echo -e "## ${name}\n\nThe ${name} output is too long!")
      fi
      if test -z "${output}"; then
        output=$data
      else
        output+=$(echo -e "\n\n${data}")
      fi
    fi
  done
  echo "$output"
}
if [ -n "${TF_BUILD-}" ]; then
  echo "##[group]${LOG_NAME}"
else
  echo "::group::${LOG_NAME}"
fi
output=$(find $LOG_PATH -name 'step_*.md' -maxdepth 1 -type f | sort | add_output)
case "${JOB_STATUS}" in
  cancelled|Canceled) title='The job was cancelled ❎';;
  failed|Failed)      title='The job failed ⛔';;
  *)                  title='The job completed successfully ✅';;
esac
if test -z "${output}"; then
  title+=' Output is missing ⭕'
fi
title+='\n\nPR | Commit | Run | Actor | Action'
title+='---|---|---|---|---'
title+="#${EVENT_NO} | ${COMMIT_SHA} | [${RUN_NUMBER}](${JOB_URL}) |"
title+=" ${EVENT_ACTOR} | ${EVENT_ACTION}"
output="${output/_JOB_STATUS_/${title}}"
echo "Comment has ${#output} characters."
echo "${output}" > "${LOG_PATH}/comment.md"
if [ -n "${TF_BUILD-}" ]; then
  echo "##vso[task.uploadsummary]${LOG_PATH}/comment.md"
  data=$(jq --arg content "${output}" '.comments[0].content = $content' <<< '{"comments": [{"parentCommentId": 0,"content": "","commentType": 1}],"status": 1}')
else
  echo "${output}" >> "$GITHUB_STEP_SUMMARY"
  data=$(jq --arg body "${output}" '.body = $body' <<< '{"body": ""}')
fi
HTTP_CODE=$(curl --request POST \
  --write-out "%{http_code}" \
  --header 'Accept: application/json' \
  --header "Authorization: Bearer ${TOKEN}" \
  --header 'Content-Type: application/json' \
  --data "${data}" \
  --url "$( echo "${COMMENTS_URL}" | sed 's/ /%20/g' )" \
  --output "${LOG_PATH}/comment.log" --silent
)
if [[ ${HTTP_CODE} -lt 200 || ${HTTP_CODE} -gt 299 ]]; then
  echo "Unable to create comment! Response code: ${HTTP_CODE}"
  if test -f "${LOG_PATH}/comment.log"; then
    cat "${LOG_PATH}/comment.log"
  fi
  exit 1
fi
