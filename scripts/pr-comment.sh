#!/usr/bin/env bash
# Copyright (c) Innofactor Plc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause
#
set -e
mkdir -p "${LOG_PATH}"
# GitHub rejects comment bodies over 65536 characters. Keep the whole comment
# below that, leaving room for the heading and the run summary table.
MAX_COMMENT=65000
MAX_SECTIONS=60000
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
      if [ $(( ${#output} + ${#data} + 2 )) -gt ${MAX_SECTIONS} ]; then
        data=$(echo -e "## ${name}\n\nThe ${name} output is too long for a comment. See the job summary or the logs artifact.")
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
if test -n "${VERSION_BICEP_CLI-}" && [[ "${VERSION_BICEP_CLI}" != *'$('* ]]; then
  summary+="Bicep CLI ${VERSION_BICEP_CLI}\n\n"
fi
if [ "${LOG_NAME}" = 'plan_comment' ]; then
  output="# Plan for ${JOB_NAME}\n\n${summary}${output}"
else
  output="# ${JOB_NAME}\n\n${summary}${output}"
fi
output=$(echo -e "${output}")
if [ ${#output} -gt ${MAX_COMMENT} ]; then
  echo "Comment has ${#output} characters, truncating to ${MAX_COMMENT}."
  output="${output:0:$(( MAX_COMMENT - 200 ))}"
  output+=$'\n\n---\n\nThe comment was truncated. See the job summary or the logs artifact for the full output.'
fi
echo "Comment has ${#output} characters."
comment_file="${LOG_PATH}/${LOG_NAME}.md"
echo "${output}" > "${comment_file}"
# The body is read from a file: passing it as an argument fails above 128 KiB
# on Linux ("Argument list too long").
_tmp_data=$(mktemp)
if test -n "${TF_BUILD-}"; then
  echo "##vso[task.uploadsummary]${comment_file}"
  jq --rawfile content "${comment_file}" '.comments[0].content = ($content | rtrimstr("\n"))' \
    <<< '{"comments": [{"parentCommentId": 0,"content": "","commentType": 1}],"status": 1}' > "${_tmp_data}"
else
  echo "${output}" >> "$GITHUB_STEP_SUMMARY"
  jq --rawfile body "${comment_file}" '.body = ($body | rtrimstr("\n"))' <<< '{"body": ""}' > "${_tmp_data}"
fi
HTTP_CODE=$(curl --request POST --data "@${_tmp_data}" \
  --write-out "%{response_code}" --silent --retry 4 \
  --header 'Accept: application/json' \
  --header "Authorization: Bearer ${TOKEN}" \
  --header 'Content-Type: application/json' \
  --output "${LOG_PATH}/comment.log" \
  --url "${COMMENTS_URL// /%20}"
)
rm -f "${_tmp_data}"
# The comment is a convenience; the plan and its logs are already published.
# A failed comment is reported but does not fail the job.
if [ "${HTTP_CODE}" -lt 200 ] || [ "${HTTP_CODE}" -gt 299 ]; then
  if test -n "${TF_BUILD-}"; then
    echo "##[warning]Unable to create comment! Response code: ${HTTP_CODE}"
  else
    echo "::warning::Unable to create comment! Response code: ${HTTP_CODE}"
  fi
  if test -f "${LOG_PATH}/comment.log"; then
    cat "${LOG_PATH}/comment.log"
  fi
fi
