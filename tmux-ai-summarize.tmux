#!/usr/bin/env zsh

emulate -L zsh

CURRENT_DIR=$(
  CDPATH=''
  cd -- "$(dirname -- "$0")" && pwd
) || exit 1

get_tmux_option() {
  local option=$1
  local default_value=$2
  local value

  value=$(tmux show-option -gqv "$option")
  print -r -- "${value:-$default_value}"
}

main() {
  local key
  local launcher
  local quoted_launcher
  local installed_key

  key=$(get_tmux_option '@ai-summarize-key' 'S')
  installed_key=$(get_tmux_option '@ai-summarize-installed-key' '')
  launcher="$CURRENT_DIR/scripts/summarize-selection.zsh"
  quoted_launcher=$(printf '%q' "$launcher")

  if [[ -n $installed_key && $installed_key != "$key" ]]; then
    tmux unbind-key -T copy-mode-vi "$installed_key" 2>/dev/null || true
  fi
  tmux unbind-key -T copy-mode-vi "$key" 2>/dev/null || true
  tmux source-file - <<EOF
bind-key -T copy-mode-vi $key send-keys -X copy-selection-no-clear \; send-keys -X copy-selection-and-cancel ai-summarize- \; run-shell "TMUX_AI_SUMMARIZE_CLIENT=#{q:client_name} $quoted_launcher"
EOF
  tmux set-option -gq @ai-summarize-installed-key "$key"
}

main
