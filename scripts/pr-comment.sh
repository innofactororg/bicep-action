#!/usr/bin/env bash
# Copyright (c) Innofactor Plc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause
#
set -e
mkdir -p "${LOG_PATH}"
add_output() {
  local data=''
  local name=''
  local output=''
  while read -r file; do
    data=$(cat "${file}")
    if test -n "${data}"; then
      name=$(basename "${file}")
      name=${name:8}
      name=${name/_/ }
      name=${name/psrule/PSRule}
      name=${name/.md/}
      name="$(tr '[:lower:]' '[:upper:]' <<< "${name:0:1}")${name:1}"
      if [ ${#data} -gt 63900 ]; then
        data=$(echo -e "## ${name}\n\nThe ${name} output is too long!")
      fi
      if test -z "${output}"; then
        output="${data}"
      else
        output+="$(echo -e "\n\n${data}")"
      fi
    fi
  done
  echo "${output}"
}
output=$(find "${LOG_PATH}" -name 'step_*.md' -maxdepth 1 -type f | sort | add_output)
case "${JOB_STATUS}" in
  cancelled|Canceled) summary='The job was cancelled ❎';;
  failed|Failed)      summary='The job failed ⛔';;
  *)                  summary='The job completed successfully ✅';;
esac
if test -z "${output}"; then
  summary+=' Output is missing ⭕'
fi
summary+='\n\nPR | Commit | Run | Actor | Action\n'
summary+='---|---|---|---|---\n'
summary+="${EVENT_NO} | ${COMMIT_SHA} | [${RUN_NUMBER}](${JOB_URL}) |"
summary+=" ${EVENT_ACTOR} | ${EVENT_ACTION}\n\n"
if [ "${LOG_NAME}" = 'plan_comment' ]; then
  output="# Plan for ${JOB_NAME}\n\n${summary}${output}"
else
  output="# ${JOB_NAME}\n\n${summary}${output}"
fi
output=$(echo -e "${output}")
echo "Comment has ${#output} characters."
echo "${output}" > "${LOG_PATH}/${LOG_NAME}.md"
if test -n "${TF_BUILD-}"; then
  echo "##vso[task.uploadsummary]${LOG_PATH}/${LOG_NAME}.md"
  data=$(jq --arg content "${output}" '.comments[0].content = $content' <<< '{"comments": [{"parentCommentId": 0,"content": "","commentType": 1}],"status": 1}')
else
  echo "${output}" >> "$GITHUB_STEP_SUMMARY"
  data=$(jq --arg body "${output}" '.body = $body' <<< '{"body": ""}')
fi
HTTP_CODE=$(curl --request POST --data "${data}" \
  --write-out "%{response_code}" --silent --retry 4 \
  --header 'Accept: application/json' \
  --header "Authorization: Bearer ${TOKEN}" \
  --header 'Content-Type: application/json' \
  --output "${LOG_PATH}/comment.log" \
  --url "${COMMENTS_URL// /%20}"
)
if [ "${HTTP_CODE}" -lt 200 ] || [ "${HTTP_CODE}" -gt 299 ]; then
  if test -n "${TF_BUILD-}"; then
    echo "##[error]Unable to create comment! Response code: ${HTTP_CODE}}"
  else
    echo "::error::Unable to create comment! Response code: ${HTTP_CODE}"
  fi
  if test -f "${LOG_PATH}/comment.log"; then
    cat "${LOG_PATH}/comment.log"
  fi
  exit 1
fi
