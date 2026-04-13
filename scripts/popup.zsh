#!/usr/bin/env zsh

emulate -L zsh

script_dir=${0:A:h}
# shellcheck source=./lib.zsh
source "$script_dir/lib.zsh"

hold_popup_open() {
  exec cat >/dev/null
}

if [[ ${1:-} == --message ]]; then
  render_popup_text "${2:-}"
  hold_popup_open
fi

buffer_name=${1:-}
buffer_text=
response_body=
response_with_status=
response_status_marker='__TMUX_AI_SUMMARIZE_HTTP_STATUS__:'

cleanup_named_buffer() {
  delete_ai_summarize_buffer "$buffer_name" >/dev/null 2>&1 || true
}

trap cleanup_named_buffer EXIT HUP INT TERM

if [[ -n $buffer_name ]]; then
  if ! buffer_text=$(tmux show-buffer -b "$buffer_name" 2>/dev/null); then
    render_popup_text 'Failed to read tmux buffer.'
    hold_popup_open
  fi
  cleanup_named_buffer
fi

non_whitespace=${buffer_text//[[:space:]]/}
if [[ -z $non_whitespace ]]; then
  render_popup_text 'Nothing to summarize.'
  hold_popup_open
fi

render_popup_text 'Summarizing...'

api_key=$(resolve_api_key)
if [[ -z $api_key ]]; then
  render_popup_text 'Missing API key. Set OPENAI_API_KEY or @ai-summarize-api-key.'
  hold_popup_open
fi

base_url=$(resolve_base_url)
model=$(resolve_model)
prompt=$(resolve_prompt)

payload=$(
  jq -n \
    --arg model "$model" \
    --arg prompt "$prompt" \
    --arg text "$buffer_text" \
    '{
      model: $model,
      messages: [
        {
          role: "system",
          content: $prompt
        },
        {
          role: "user",
          content: ("Text to summarize:\n\n" + $text)
        }
      ]
    }'
) || {
  render_popup_text 'Failed to encode request payload.'
  hold_popup_open
}

if [[ -n ${TMUX_AI_SUMMARIZE_REQUEST_LOG:-} ]]; then
  jq -n \
    --arg url "${base_url%/}/chat/completions" \
    --arg payload "$payload" \
    '{
      url: $url,
      headers: {
        Authorization: "Bearer <redacted>",
        "Content-Type": "application/json"
      },
      body: ($payload | fromjson)
    }' >"$TMUX_AI_SUMMARIZE_REQUEST_LOG" 2>/dev/null || true
fi

response_with_status=$(
  curl \
    --silent \
    --show-error \
    --max-time 20 \
    --write-out "\n${response_status_marker}%{http_code}" \
    --header "Authorization: Bearer $api_key" \
    --header 'Content-Type: application/json' \
    --data "$payload" \
    "${base_url%/}/chat/completions"
) 
curl_status=$?
if (( curl_status != 0 )); then
  if (( curl_status == 28 )); then
    render_popup_text 'Request timed out.'
  else
    render_popup_text 'Request failed.'
  fi
  hold_popup_open
fi

response_body=${response_with_status%$'\n'"${response_status_marker}"*}
http_status=${response_with_status##*"${response_status_marker}"}
if [[ $http_status != 2* ]]; then
  body_excerpt=$(single_line_excerpt "$response_body")
  if [[ -n $body_excerpt ]]; then
    render_popup_text $'Request failed: HTTP '"$http_status"$'\n'"$body_excerpt"
  else
    render_popup_text "Request failed: HTTP $http_status"
  fi
  hold_popup_open
fi

summary_text=$(print -r -- "$response_body" | extract_summary_content) || {
  render_popup_text 'Provider returned no summary content.'
  hold_popup_open
}

render_popup_text "$summary_text"
hold_popup_open
