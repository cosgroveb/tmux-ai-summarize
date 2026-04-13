#!/usr/bin/env zsh

emulate -L zsh

default_summary_prompt() {
  print -r -- 'Summarize the provided text as concise bullet points. Use plain language. Keep important names, commands, paths, flags, and numbers. Do not add preamble, conclusion, or markdown fencing.'
}

get_tmux_option() {
  local option_name=$1
  local default_value=${2:-}
  local option_value

  option_value=$(tmux show-option -gqv "$option_name")
  print -r -- "${option_value:-$default_value}"
}

resolve_api_key() {
  if [[ -n ${OPENAI_API_KEY:-} ]]; then
    print -r -- "$OPENAI_API_KEY"
    return 0
  fi

  get_tmux_option '@ai-summarize-api-key' ''
}

resolve_base_url() {
  if [[ -n ${OPENAI_BASE_URL:-} ]]; then
    print -r -- "$OPENAI_BASE_URL"
    return 0
  fi

  get_tmux_option '@ai-summarize-base-url' 'https://api.openai.com/v1'
}

resolve_model() {
  if [[ -n ${TMUX_AI_SUMMARIZE_MODEL:-} ]]; then
    print -r -- "$TMUX_AI_SUMMARIZE_MODEL"
    return 0
  fi

  get_tmux_option '@ai-summarize-model' 'gpt-5.4-nano'
}

resolve_prompt() {
  local configured_prompt

  configured_prompt=$(get_tmux_option '@ai-summarize-prompt' '')
  if [[ -n $configured_prompt ]]; then
    print -r -- "$configured_prompt"
    return 0
  fi

  default_summary_prompt
}

render_popup_text() {
  print -n -- $'\033[2J\033[H'
  print -r -- "$1"
}

single_line_excerpt() {
  local excerpt=$1

  excerpt=${excerpt//$'\r'/ }
  excerpt=${excerpt//$'\n'/ }
  excerpt=${excerpt//$'\t'/ }
  while [[ $excerpt == *'  '* ]]; do
    excerpt=${excerpt//'  '/' '}
  done
  excerpt=${excerpt# }
  excerpt=${excerpt% }

  print -r -- "${excerpt[1,200]}"
}

extract_summary_content() {
  jq -er '
    .choices[0].message.content as $content
    | if ($content | type) == "string" then
        $content
      elif ($content | type) == "array" then
        [ $content[] | select(.type == "text") | .text ] | join("")
      else
        empty
      end
    | select((gsub("\\s+"; "")) | length > 0)
  '
}

latest_ai_summarize_buffer() {
  local freshness_cutoff_seconds=${1:-2}
  local buffer_name newest_buffer_name='' candidate_suffix newest_suffix
  integer buffer_created newest_created=-1 now age

  now=${EPOCHSECONDS:-$(date +%s)}

  while IFS='|' read -r buffer_name buffer_created; do
    if [[ $buffer_name == ai-summarize-* ]]; then
      (( age = now - buffer_created ))
      if (( age >= 0 && age <= freshness_cutoff_seconds )); then
        if (( buffer_created > newest_created )); then
          newest_created=$buffer_created
          newest_buffer_name=$buffer_name
        elif (( buffer_created == newest_created )) && [[ -n $newest_buffer_name ]]; then
          candidate_suffix=${buffer_name##*-}
          newest_suffix=${newest_buffer_name##*-}

          if [[ $candidate_suffix =~ ^[0-9]+$ && $newest_suffix =~ ^[0-9]+$ ]]; then
            if (( candidate_suffix > newest_suffix )) || { (( candidate_suffix == newest_suffix )) && [[ $buffer_name > $newest_buffer_name ]]; }; then
              newest_buffer_name=$buffer_name
            fi
          elif [[ $buffer_name > $newest_buffer_name ]]; then
            newest_buffer_name=$buffer_name
          fi
        fi
      fi
    fi
  done < <(tmux list-buffers -F '#{buffer_name}|#{buffer_created}')

  [[ -n $newest_buffer_name ]] || return 1
  print -r -- "$newest_buffer_name"
}

delete_ai_summarize_buffer() {
  local buffer_name=$1

  [[ -n $buffer_name ]] || return 0
  tmux delete-buffer -b "$buffer_name"
}

show_status_message() {
  local message=$1
  local client_name=${2:-}

  if [[ -n $client_name ]]; then
    tmux display-message -c "$client_name" "$message"
  else
    tmux display-message "$message"
  fi
}
