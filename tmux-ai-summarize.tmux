#!/usr/bin/env zsh

emulate -L zsh

PLUGIN_DIR=$(
  CDPATH=''
  cd -- "$(dirname -- "$0")" && pwd
) || exit 1

get_tmux_option() {
  local option=$1
  local fallback=$2
  local value

  value=$(tmux show-option -gqv "$option")
  print -r -- "${value:-$fallback}"
}

main() {
  local key
  local runner_path
  local quoted_runner_path
  local installed_key

  key=$(get_tmux_option '@ai-summarize-key' 'S')
  installed_key=$(get_tmux_option '@ai-summarize-installed-key' '')
  runner_path="$PLUGIN_DIR/scripts/summarize-selection.zsh"
  quoted_runner_path=$(printf '%q' "$runner_path")

  if [[ -n $installed_key && $installed_key != "$key" ]]; then
    tmux unbind-key -T copy-mode-vi "$installed_key" 2>/dev/null || true
  fi
  tmux unbind-key -T copy-mode-vi "$key" 2>/dev/null || true
  tmux source-file - <<EOF
bind-key -T copy-mode-vi $key send-keys -X copy-selection-no-clear \; send-keys -X copy-selection-and-cancel "ai-summarize-#{pane_id}-" \; run-shell "TMUX_AI_SUMMARIZE_CLIENT=#{q:client_name} TMUX_AI_SUMMARIZE_BUFFER_SCOPE=#{q:pane_id} $quoted_runner_path"
EOF
  tmux set-option -gq @ai-summarize-installed-key "$key"
}

main
