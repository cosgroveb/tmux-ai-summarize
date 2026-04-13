#!/usr/bin/env zsh

tmux_wrapper_dir=
tmux_socket_name=
log_path=
transcript_path=
attached_client_pid=
attached_client_input_fd=
attached_client_pipe_dir=
attached_client_pipe_path=

fail_test() {
  print -u2 -r -- "FAIL: $1"
  exit 1
}

tmux_test_cmd() {
  PATH="$tmux_wrapper_dir:$PATH" tmux -L "$tmux_socket_name" "$@"
}

wait_for_log_line() {
  local pattern=$1
  local timeout=50
  local content

  while (( timeout > 0 )); do
    content=$(cat "$log_path" 2>/dev/null || true)
    if print -r -- "$content" | rg -q -- "$pattern"; then
      return 0
    fi
    sleep 0.1
    (( timeout-- ))
  done

  return 1
}

wait_for_fresh_buffer() {
  local pattern=${1:-'^ai-summarize-'}
  local timeout=50
  local buffer_name

  while (( timeout > 0 )); do
    buffer_name=$(tmux_test_cmd list-buffers -F '#{buffer_name}' 2>/dev/null | rg "$pattern" | head -n 1 || true)
    if [[ -n $buffer_name ]]; then
      print -r -- "$buffer_name"
      return 0
    fi
    sleep 0.1
    (( timeout-- ))
  done

  return 1
}

wait_for_buffer_removal() {
  local buffer_name=$1
  local timeout=50
  local buffers

  while (( timeout > 0 )); do
    buffers=$(tmux_test_cmd list-buffers -F '#{buffer_name}' 2>/dev/null || true)
    if ! print -r -- "$buffers" | rg -Fxq -- "$buffer_name"; then
      return 0
    fi
    sleep 0.1
    (( timeout-- ))
  done

  return 1
}

normalize_transcript() {
  local file_path=${1:-$transcript_path}

  [[ -r $file_path ]] || return 0
  perl -0pe 's/\e\[[0-9;?]*[ -\/]*[@-~]//g; s/\e\][^\a]*(?:\a|\e\\)//g; s/\r/\n/g; s/\x0f|\x0e//g' -- "$file_path"
}

wait_for_transcript_pattern() {
  local pattern=$1
  local timeout=50
  local content

  while (( timeout > 0 )); do
    content=$(normalize_transcript 2>/dev/null || true)
    if print -r -- "$content" | rg -q -- "$pattern"; then
      return 0
    fi
    sleep 0.1
    (( timeout-- ))
  done

  return 1
}

wait_for_popup_loading() {
  local final_pattern=$1
  local timeout=50
  local content

  while (( timeout > 0 )); do
    content=$(normalize_transcript 2>/dev/null || true)
    if print -r -- "$content" | rg -q -- 'Summarizing\.\.\.'; then
      if ! print -r -- "$content" | rg -q -- "$final_pattern"; then
        return 0
      fi
    fi
    sleep 0.1
    (( timeout-- ))
  done

  return 1
}

wait_for_live_summary() {
  local timeout=200
  local content
  local reason=

  # Poll for up to 20 seconds so slower live-provider runs still surface a reason on failure.
  while (( timeout > 0 )); do
    content=$(normalize_transcript 2>/dev/null || true)
    reason=$(print -r -- "$content" | rg -o -- 'Nothing selected\.|Nothing to summarize\.|Missing API key\..*|Request failed.*|Request timed out\.|Provider returned no summary content\.' | head -n 1 || true)
    if [[ -n $reason ]]; then
      reason="live summary failed early: $reason"
      print -u2 -r -- "$reason"
      return 1
    fi
    # script(1) can flatten popup redraws into one long line, with border or margin characters before the bullet.
    if print -r -- "$content" | rg -q -- '(^|[^[:alnum:]])[*-] [^[:space:]]'; then
      return 0
    fi
    sleep 0.1
    (( timeout-- ))
  done

  reason='timed out waiting for live summary output'
  print -u2 -r -- "$reason"
  return 1
}

start_attached_client() {
  local session_name=${1:-test}
  local quoted_tmux_socket_name quoted_session_name

  attached_client_pipe_dir=$(mktemp -d "${TMPDIR:-/tmp}/tmux-ai-summarize-input.XXXXXX")
  attached_client_pipe_path="$attached_client_pipe_dir/input"
  mkfifo "$attached_client_pipe_path"
  quoted_tmux_socket_name=$(printf '%q' "$tmux_socket_name")
  quoted_session_name=$(printf '%q' "$session_name")

  TERM="${TERM:-screen-256color}" PATH="$tmux_wrapper_dir:$PATH" \
    script -qefc "TERM=screen-256color tmux -L $quoted_tmux_socket_name attach-session -t $quoted_session_name" \
    "$transcript_path" < "$attached_client_pipe_path" >/dev/null 2>&1 &
  attached_client_pid=$!
  exec {attached_client_input_fd}> "$attached_client_pipe_path"
}

stop_attached_client() {
  if [[ -n ${attached_client_input_fd:-} ]]; then
    exec {attached_client_input_fd}>&-
    attached_client_input_fd=
  fi

  if [[ -n ${attached_client_pid:-} ]]; then
    kill "$attached_client_pid" >/dev/null 2>&1 || true
    wait "$attached_client_pid" 2>/dev/null || true
    attached_client_pid=
  fi

  if [[ -n ${attached_client_pipe_path:-} ]]; then
    rm -f "$attached_client_pipe_path"
    attached_client_pipe_path=
  fi

  if [[ -n ${attached_client_pipe_dir:-} ]]; then
    rmdir "$attached_client_pipe_dir" >/dev/null 2>&1 || true
    attached_client_pipe_dir=
  fi
}

dump_attached_client_debug() {
  ps -ef | rg -- "script -qefc|tmux -L ${tmux_socket_name}|${transcript_path}" >&2 || true
  head -n 40 "$transcript_path" >&2 || true
}

find_attached_client_name() {
  local client_name=

  for _ in {1..50}; do
    client_name=$(tmux_test_cmd list-clients -F '#{client_name}' 2>/dev/null | head -n 1 || true)
    [[ -n $client_name ]] && break
    sleep 0.1
  done

  if [[ -z $client_name ]]; then
    dump_attached_client_debug
    return 1
  fi

  print -r -- "$client_name"
}
