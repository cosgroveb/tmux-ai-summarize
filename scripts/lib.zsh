#!/usr/bin/env zsh

typeset -gr summary_buffer_fresh_window_seconds=2
typeset -gr default_summary_model='gpt-5.4-nano'

default_summary_prompt() {
  emulate -L zsh
  print -r -- 'Summarize the provided text as concise bullet points. Use plain language. Keep important names, commands, paths, flags, and numbers. Do not add preamble, conclusion, or markdown fencing.'
}

get_tmux_option() {
  emulate -L zsh
  local name=$1
  local fallback=${2:-}
  local value

  value=$(tmux show-option -gqv "$name")
  print -r -- "${value:-$fallback}"
}

resolve_api_key() {
  emulate -L zsh
  if [[ -n ${OPENAI_API_KEY:-} ]]; then
    print -r -- "$OPENAI_API_KEY"
    return 0
  fi

  get_tmux_option '@ai-summarize-api-key' ''
}

resolve_base_url() {
  emulate -L zsh
  if [[ -n ${OPENAI_BASE_URL:-} ]]; then
    print -r -- "$OPENAI_BASE_URL"
    return 0
  fi

  get_tmux_option '@ai-summarize-base-url' 'https://api.openai.com/v1'
}

resolve_model() {
  emulate -L zsh
  if [[ -n ${TMUX_AI_SUMMARIZE_MODEL:-} ]]; then
    print -r -- "$TMUX_AI_SUMMARIZE_MODEL"
    return 0
  fi

  get_tmux_option '@ai-summarize-model' "$default_summary_model"
}

resolve_prompt() {
  emulate -L zsh
  local prompt_override

  prompt_override=$(get_tmux_option '@ai-summarize-prompt' '')
  if [[ -n $prompt_override ]]; then
    print -r -- "$prompt_override"
    return 0
  fi

  default_summary_prompt
}

resolve_buffer_prefix() {
  emulate -L zsh
  local buffer_scope=${TMUX_AI_SUMMARIZE_BUFFER_SCOPE:-}

  if [[ -n $buffer_scope ]]; then
    print -r -- "ai-summarize-$buffer_scope-"
    return 0
  fi

  print -r -- 'ai-summarize-'
}

render_popup_text() {
  emulate -L zsh
  print -n -- $'\033[2J\033[H'
  print -r -- "$1"
}

single_line_excerpt() {
  emulate -L zsh
  setopt extended_glob
  local excerpt=$1

  excerpt=${excerpt//$'\r'/ }
  excerpt=${excerpt//$'\n'/ }
  excerpt=${excerpt//$'\t'/ }
  excerpt=${excerpt// ##/ }
  # Collapsing above leaves at most one leading or trailing space.
  excerpt=${excerpt# }
  excerpt=${excerpt% }

  print -r -- "${excerpt[1,200]}"
}

extract_summary_content() {
  emulate -L zsh
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
  emulate -L zsh
  local fresh_window_seconds=${1:-$summary_buffer_fresh_window_seconds}
  local buffer_prefix
  local buffer_name freshest_buffer='' buffer_created_text candidate_tail freshest_tail
  integer buffer_created newest_created=-1 now age

  now=${EPOCHSECONDS:-$(date +%s)}
  buffer_prefix=$(resolve_buffer_prefix)

  while IFS='|' read -r buffer_name buffer_created_text; do
    if [[ $buffer_name == "$buffer_prefix"* ]]; then
      [[ $buffer_created_text == <-> ]] || continue
      buffer_created=$buffer_created_text
      (( age = now - buffer_created ))
      if (( age >= 0 && age <= fresh_window_seconds )); then
        if (( buffer_created > newest_created )); then
          newest_created=$buffer_created
          freshest_buffer=$buffer_name
        elif (( buffer_created == newest_created )) && [[ -n $freshest_buffer ]]; then
          candidate_tail=${buffer_name##*-}
          freshest_tail=${freshest_buffer##*-}

          if [[ $candidate_tail =~ ^[0-9]+$ && $freshest_tail =~ ^[0-9]+$ ]]; then
            if (( candidate_tail > freshest_tail )) || { (( candidate_tail == freshest_tail )) && [[ $buffer_name > $freshest_buffer ]]; }; then
              freshest_buffer=$buffer_name
            fi
          elif [[ $buffer_name > $freshest_buffer ]]; then
            freshest_buffer=$buffer_name
          fi
        fi
      fi
    fi
  done < <(tmux list-buffers -F '#{buffer_name}|#{buffer_created}')

  [[ -n $freshest_buffer ]] || return 1
  print -r -- "$freshest_buffer"
}

delete_ai_summarize_buffer() {
  emulate -L zsh
  local buffer_name=$1

  [[ -n $buffer_name ]] || return 0
  tmux delete-buffer -b "$buffer_name"
}

show_status_message() {
  emulate -L zsh
  local message=$1
  local client_name=${2:-}

  if [[ -n $client_name ]]; then
    tmux display-message -c "$client_name" "$message"
  else
    tmux display-message "$message"
  fi
}
