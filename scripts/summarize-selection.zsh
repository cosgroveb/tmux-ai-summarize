#!/usr/bin/env zsh

emulate -L zsh
set -eu

script_dir=${0:A:h}
source "$script_dir/lib.zsh"

client_name=${TMUX_AI_SUMMARIZE_CLIENT:-}
client_flag=()
popup_runner=$(printf '%q' "$script_dir/popup.zsh")
fresh_buffer_window_seconds=$summary_buffer_fresh_window_seconds
if [[ -n $client_name ]]; then
  client_flag=(-c "$client_name")
fi

selected_buffer=$(latest_ai_summarize_buffer "$fresh_buffer_window_seconds") || {
  popup_command="$popup_runner --message $(printf '%q' 'Nothing selected.')"
  # Without a client there is nowhere to open a popup, so fall back to the status line.
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
