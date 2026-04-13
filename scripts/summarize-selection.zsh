#!/usr/bin/env zsh

emulate -L zsh

script_dir=${0:A:h}
# shellcheck source=./lib.zsh
source "$script_dir/lib.zsh"

client_name=${TMUX_AI_SUMMARIZE_CLIENT:-}
client_flag=()
message_text=
popup_runner=$(printf '%q' "$script_dir/popup.zsh")
if [[ -n $client_name ]]; then
  client_flag=(-c "$client_name")
fi

selected_buffer=$(latest_ai_summarize_buffer 2) || {
  message_text='Nothing selected.'
  popup_command="$popup_runner --message $(printf '%q' "$message_text")"
  if [[ -n $client_name ]] && tmux display-popup "${client_flag[@]}" -T 'AI Summary' -w 70% -h 60% "$popup_command"; then
    exit 0
  fi

  show_status_message 'Nothing selected.' "$client_name"
  exit 0
}

popup_command="$popup_runner $(printf '%q' "$selected_buffer")"
if tmux display-popup "${client_flag[@]}" -T 'AI Summary' -w 70% -h 60% "$popup_command"; then
  exit 0
fi

delete_ai_summarize_buffer "$selected_buffer"
show_status_message 'Popup launch failed.' "$client_name"
