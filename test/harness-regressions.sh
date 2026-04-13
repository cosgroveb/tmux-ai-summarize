#!/usr/bin/env zsh

emulate -L zsh
set -eu

script_dir=${0:A:h}
integration_script="$script_dir/integration.sh"
helpers_script="$script_dir/lib.zsh"
plugin_lib="$script_dir/../scripts/lib.zsh"
selector_script="$script_dir/../scripts/summarize-selection.zsh"
popup_script="$script_dir/../scripts/popup.zsh"
plugin_entrypoint="$script_dir/../tmux-ai-summarize.tmux"

fail() {
  print -u2 -r -- "FAIL: $1"
  exit 1
}

[[ -f $helpers_script ]] || fail "expected shared driver helpers at $helpers_script"

! rg -q '^set -u$' "$integration_script" || fail "embedded drivers should fail fast with set -eu"
! rg -q '^TMUX_AI_SUMMARIZE_CLIENT_PID=' "$integration_script" || fail "outer harness still carries an unused client pid"
! rg -q '^cleanup_detached_cleanup\(\)' "$integration_script" || fail "cleanup function still has the old misleading name"
! rg -q '^wait_for_loading_only\(\)' "$integration_script" || fail "dead outer loading helper should be gone"
! rg -q "rg -q -- 'Summarizing...'" "$integration_script" || fail "loading-state regexes should escape literal dots"
! rg -q 'mktemp -u' "$integration_script" || fail "drivers should not rely on mktemp -u for FIFOs"
! rg -q 'head -1' "$integration_script" || fail "use head -n 1 for consistency"

! rg -q '^emulate -L zsh$' "$plugin_lib" || fail "sourced plugin lib should not rely on a top-level emulate -L zsh"
rg -q '^set -eu$' "$selector_script" || fail "summarize-selection should fail fast with set -eu"
! rg -q '^message_text=$' "$selector_script" || fail "summarize-selection still carries a dead message_text initializer"
rg -q 'summary_buffer_fresh_window_seconds' "$selector_script" || fail "summarize-selection should use the shared buffer freshness constant"
rg -q 'hold_open_and_exit' "$popup_script" || fail "popup helper should make its non-returning behavior obvious"
rg -q 'cleanup_source_buffer$' "$popup_script" || fail "popup should explicitly clean up the tmux buffer on the read-failure path"
rg -q '^set -eu$' "$popup_script" || fail "popup should fail fast with set -eu"
! rg -q '^PLUGIN_DIR=\$\(' "$plugin_entrypoint" || fail "plugin entrypoint should use the zsh path modifier for PLUGIN_DIR"
! rg -q '^get_tmux_option\(\)' "$plugin_entrypoint" || fail "plugin entrypoint should source shared option helpers instead of redefining them"
rg -q 'quoted_key=\$\(printf '\''%q'\'' "\$key"\)' "$plugin_entrypoint" || fail "plugin entrypoint should quote the configured key before installing the binding"
! rg -q 'bind-key -T copy-mode-vi \$key ' "$plugin_entrypoint" || fail "plugin entrypoint should not inject the raw key into the binding command"
rg -q '^set -eu$' "$plugin_entrypoint" || fail "plugin entrypoint should fail fast with set -eu"
rg -q "typeset -gr default_summary_model='gpt-5.4-nano'" "$plugin_lib" || fail "plugin lib should expose the default model as a shared constant"
rg -q '\[\[ \$actual_model == "\$default_summary_model" \]\]' "$integration_script" || fail "mock-mode model assertion should use the shared default model"
rg -q 'rg -q '\''\^display-popup '\''' "$integration_script" || fail "expected the stale-popup assertion to remain in the detached cleanup scenario"
rg -q 'rg -q '\''\^display-popup '\'' "\$log_file" 2>/dev/null' "$integration_script" || fail "stale-popup assertion should not print rg errors when the log file is absent"
! rg -q 'script -qefc "TERM=screen-256color tmux -L \$tmux_socket_name attach-session -t \$session_name"' "$helpers_script" || fail "attached client helper should quote socket and session names before embedding them in the script command"

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/tmux-ai-summarize-regressions.XXXXXX")
transcript_file="$tmpdir/live-transcript.txt"
error_log="$tmpdir/live-transcript.err"
print -r -- $'provider output\n- bullet one\n' >"$transcript_file"

if ! (
  sleep() { :; }
  source "$helpers_script"
  transcript_path="$transcript_file"
  wait_for_live_summary
) >/dev/null 2>"$error_log"; then
  sed -n '1,80p' "$error_log" >&2 || true
  rm -rf "$tmpdir"
  fail "live summary detector should accept bullet output"
fi

rm -rf "$tmpdir"
