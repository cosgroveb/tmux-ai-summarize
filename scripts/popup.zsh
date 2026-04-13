#!/usr/bin/env zsh

emulate -L zsh
set -eu

script_dir=${0:A:h}
source "$script_dir/lib.zsh"

hold_open_and_exit() {
  # Replaces this shell with cat so the popup stays open.
  exec cat >/dev/null
}

if [[ ${1:-} == --message ]]; then
  render_popup_text "${2:-}"
  hold_open_and_exit
fi

source_buffer=${1:-}
buffer_text=
response_body=
curl_output=
status_sentinel='__TMUX_AI_SUMMARIZE_HTTP_STATUS__:'

cleanup_source_buffer() {
  delete_ai_summarize_buffer "$source_buffer" >/dev/null 2>&1 || true
}

trap cleanup_source_buffer EXIT HUP INT TERM

if [[ -n $source_buffer ]]; then
  if ! buffer_text=$(tmux show-buffer -b "$source_buffer" 2>/dev/null); then
    cleanup_source_buffer
    render_popup_text 'Failed to read tmux buffer.'
    hold_open_and_exit
  fi
  cleanup_source_buffer
fi

stripped_text=${buffer_text//[[:space:]]/}
if [[ -z $stripped_text ]]; then
  render_popup_text 'Nothing to summarize.'
  hold_open_and_exit
fi

render_popup_text 'Summarizing...'

api_key=$(resolve_api_key) || {
  render_popup_text 'Failed to read API key configuration.'
  hold_open_and_exit
}
if [[ -z $api_key ]]; then
  render_popup_text 'Missing API key. Set OPENAI_API_KEY or @ai-summarize-api-key.'
  hold_open_and_exit
fi

base_url=$(resolve_base_url) || {
  render_popup_text 'Failed to read base URL configuration.'
  hold_open_and_exit
}
model=$(resolve_model) || {
  render_popup_text 'Failed to read model configuration.'
  hold_open_and_exit
}
prompt=$(resolve_prompt) || {
  render_popup_text 'Failed to read prompt configuration.'
  hold_open_and_exit
}

request_body=$(
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
  render_popup_text 'Failed to build request body.'
  hold_open_and_exit
}

if [[ -n ${TMUX_AI_SUMMARIZE_REQUEST_LOG:-} ]]; then
  jq -n \
    --arg url "${base_url%/}/chat/completions" \
    --argjson body "$request_body" \
    '{
      url: $url,
      headers: {
        Authorization: "Bearer <redacted>",
        "Content-Type": "application/json"
      },
      body: $body
    }' >"$TMUX_AI_SUMMARIZE_REQUEST_LOG" 2>/dev/null || true
fi

curl_status=0
curl_output=$(
  curl \
    --silent \
    --show-error \
    --max-time 20 \
    --write-out "\n${status_sentinel}%{http_code}" \
    --header "Authorization: Bearer $api_key" \
    --header 'Content-Type: application/json' \
    --data "$request_body" \
    "${base_url%/}/chat/completions"
) || curl_status=$?
if (( curl_status != 0 )); then
  if (( curl_status == 28 )); then
    render_popup_text 'Request timed out.'
  else
    render_popup_text 'Request failed.'
  fi
  hold_open_and_exit
fi

response_body=${curl_output%$'\n'"${status_sentinel}"*}
http_status=${curl_output##*"${status_sentinel}"}
if [[ $http_status != 2* ]]; then
  body_excerpt=$(single_line_excerpt "$response_body")
  if [[ -n $body_excerpt ]]; then
    render_popup_text $'Request failed: HTTP '"$http_status"$'\n'"$body_excerpt"
  else
    render_popup_text "Request failed: HTTP $http_status"
  fi
  hold_open_and_exit
fi

summary_text=$(print -r -- "$response_body" | extract_summary_content) || {
  render_popup_text 'Provider returned no summary content.'
  hold_open_and_exit
}

render_popup_text "$summary_text"
hold_open_and_exit
