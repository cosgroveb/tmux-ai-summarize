#!/usr/bin/env zsh

emulate -L zsh

script_dir=${0:A:h}
# shellcheck source=./lib.zsh
source "$script_dir/lib.zsh"

client_name=${TMUX_AI_SUMMARIZE_CLIENT:-}
popup_target=()
popup_message=
popup_script=$(printf '%q' "$script_dir/popup.zsh")
if [[ -n $client_name ]]; then
  popup_target=(-c "$client_name")
fi

buffer_name=$(latest_ai_summarize_buffer 2) || {
  popup_message='Nothing selected.'
  popup_command="$popup_script --message $(printf '%q' "$popup_message")"
  if [[ -n $client_name ]] && tmux display-popup "${popup_target[@]}" -T 'AI Summary' -w 70% -h 60% "$popup_command"; then
    exit 0
  fi

  show_status_message 'Nothing selected.' "$client_name"
  exit 0
}

popup_command="$popup_script $(printf '%q' "$buffer_name")"
if tmux display-popup "${popup_target[@]}" -T 'AI Summary' -w 70% -h 60% "$popup_command"; then
  exit 0
fi

delete_ai_summarize_buffer "$buffer_name"
show_status_message 'Popup launch failed.' "$client_name"
