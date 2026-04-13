#!/usr/bin/env zsh

emulate -L zsh
set -eu

script_dir=${0:A:h}
repo_root=${script_dir:h}
real_tmux=${TMUX_REAL_BIN:-$(command -v tmux)}
provider_mode=${TMUX_AI_SUMMARIZE_PROVIDER_MODE:-mock}
source "$repo_root/scripts/lib.zsh"
driver_helpers_path="$script_dir/lib.zsh"
source "$driver_helpers_path"
TMUX_AI_SUMMARIZE_SOCKET=
TMUX_AI_SUMMARIZE_TMPDIR=
TMUX_AI_SUMMARIZE_WRAPPER_DIR=
TMUX_AI_SUMMARIZE_PROVIDER_PID=
TMUX_AI_SUMMARIZE_SCENARIO=

fail() {
  print -r -- "FAIL: $1" >&2
  exit 1
}

archive_tmpdir() {
  local artifact_root=${TMUX_AI_SUMMARIZE_ARTIFACT_DIR:-}
  local scenario_name=${TMUX_AI_SUMMARIZE_SCENARIO:-run}
  local destination

  [[ -n $artifact_root && -n ${TMUX_AI_SUMMARIZE_TMPDIR:-} && -d $TMUX_AI_SUMMARIZE_TMPDIR ]] || return 0

  destination="$artifact_root/$scenario_name"
  rm -rf "$destination"
  mkdir -p "$destination"
  cp -R "$TMUX_AI_SUMMARIZE_TMPDIR"/. "$destination"/
}

validate_provider_mode() {
  case "$provider_mode" in
    mock|live)
      ;;
    *)
      fail "unsupported provider mode: $provider_mode"
      ;;
  esac
}

setup_tmux_wrapper() {
  local tmpdir=$1
  local log_file=$2
  local wrapper_dir="$tmpdir/bin"

  mkdir -p "$wrapper_dir"
  cat >"$wrapper_dir/tmux" <<EOF
#!/usr/bin/env zsh
emulate -L zsh
set -eu

if [[ \${TMUX_AI_SUMMARIZE_REVERSE_LIST_BUFFERS:-0} == 1 && \$1 == list-buffers ]]; then
  output=()
  while IFS= read -r line; do
    output+=("\$line")
  done < <("$real_tmux" "\$@")

  for (( i=\${#output}; i >= 1; i-- )); do
    print -r -- "\${output[i]}"
  done

  exit 0
fi

if [[ \$1 == display-popup || \$1 == display-message || \$1 == delete-buffer ]]; then
  print -r -- "\$*" >> "$log_file"
fi

exec "$real_tmux" "\$@"
EOF
  chmod +x "$wrapper_dir/tmux"
  print -r -- "$wrapper_dir"
}

tmux_cmd() {
  local wrapper_dir=$1
  shift
  PATH="$wrapper_dir:$PATH" tmux -L "$TMUX_AI_SUMMARIZE_SOCKET" "$@"
}

teardown_scenario() {
  stop_attached_client

  if [[ -n ${TMUX_AI_SUMMARIZE_PROVIDER_PID:-} ]]; then
    kill "$TMUX_AI_SUMMARIZE_PROVIDER_PID" >/dev/null 2>&1 || true
    wait "$TMUX_AI_SUMMARIZE_PROVIDER_PID" 2>/dev/null || true
    TMUX_AI_SUMMARIZE_PROVIDER_PID=
  fi

  if [[ -n ${TMUX_AI_SUMMARIZE_WRAPPER_DIR:-} ]]; then
    tmux_cmd "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" kill-server >/dev/null 2>&1 || true
  fi

  if [[ -n ${TMUX_AI_SUMMARIZE_TMPDIR:-} ]]; then
    archive_tmpdir
    rm -rf "$TMUX_AI_SUMMARIZE_TMPDIR"
    TMUX_AI_SUMMARIZE_TMPDIR=
  fi
}

wait_for_file() {
  local file_path=$1
  local timeout=50

  while (( timeout > 0 )); do
    if [[ -s $file_path ]]; then
      return 0
    fi
    sleep 0.1
    (( timeout-- ))
  done

  return 1
}
start_mock_provider() {
  local request_log=$1
  local port_file=$2

  python3 -u - "$request_log" "$port_file" <<'PY' &
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

request_log_path, port_file_path = sys.argv[1:3]
summary_text = "- concise point one\n- concise point two\n"

class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        return

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        raw_body = self.rfile.read(length).decode("utf-8")
        try:
            body = json.loads(raw_body)
        except json.JSONDecodeError as exc:
            body = {"_raw": raw_body, "_error": str(exc)}

        with open(request_log_path, "w", encoding="utf-8") as handle:
            json.dump(
                {
                    "path": self.path,
                    "headers": dict(self.headers.items()),
                    "body": body,
                },
                handle,
            )

        # Keep the loading state visible long enough for wait_for_popup_loading.
        time.sleep(0.5)
        response = json.dumps(
            {"choices": [{"message": {"content": summary_text}}]}
        ).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(response)))
        self.end_headers()
        self.wfile.write(response)

server = HTTPServer(("127.0.0.1", 0), Handler)
with open(port_file_path, "w", encoding="utf-8") as handle:
    handle.write(str(server.server_address[1]))
server.serve_forever()
PY
  TMUX_AI_SUMMARIZE_PROVIDER_PID=$!
}

run_attached_client_scenario() {
  local fixture_text='tmux ai summarize integration fixture'
  local scenario_name="scenario: attached-client ${provider_mode} path"
  local live_base_url live_model request_url
  local quoted_fixture
  local log_file transcript request_log='' port_file='' port='' binding driver_script actual_model actual_user_content
  local runner_path

  validate_provider_mode
  print -u2 -r -- "$scenario_name"
  quoted_fixture=$(printf '%q' "$fixture_text")

  TMUX_AI_SUMMARIZE_SCENARIO="attached-${provider_mode}"
  TMUX_AI_SUMMARIZE_TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/tmux-ai-summarize.XXXXXX")
  log_file="$TMUX_AI_SUMMARIZE_TMPDIR/tmux.log"
  transcript="$TMUX_AI_SUMMARIZE_TMPDIR/client.typescript"
  runner_path="$repo_root/scripts/summarize-selection.zsh"
  TMUX_AI_SUMMARIZE_SOCKET="tmux-ai-summarize-$$-${RANDOM}"
  TMUX_AI_SUMMARIZE_WRAPPER_DIR=$(setup_tmux_wrapper "$TMUX_AI_SUMMARIZE_TMPDIR" "$log_file")
  tmux_wrapper_dir=$TMUX_AI_SUMMARIZE_WRAPPER_DIR
  tmux_socket_name=$TMUX_AI_SUMMARIZE_SOCKET
  log_path=$log_file
  transcript_path=$transcript

  trap teardown_scenario EXIT INT TERM

  if [[ $provider_mode == mock ]]; then
    request_log="$TMUX_AI_SUMMARIZE_TMPDIR/request.json"
    port_file="$TMUX_AI_SUMMARIZE_TMPDIR/port"
    start_mock_provider "$request_log" "$port_file"
    wait_for_file "$port_file" || fail "mock provider never published a port"
    port=$(cat "$port_file")
  elif [[ -z ${OPENAI_API_KEY:-} ]]; then
    fail "live provider mode requires OPENAI_API_KEY"
  else
    request_log="$TMUX_AI_SUMMARIZE_TMPDIR/request.json"
  fi

  tmux_cmd "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" -f /dev/null new-session -d -s test "printf '%s\\n' $quoted_fixture; sleep 1000" >/dev/null
  tmux_cmd "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" set-option -g mode-keys vi
  if [[ $provider_mode == mock ]]; then
    tmux_cmd "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" set-environment -g OPENAI_API_KEY 'test-key'
    tmux_cmd "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" set-environment -g OPENAI_BASE_URL "http://127.0.0.1:$port/v1"
    tmux_cmd "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" set-environment -gu TMUX_AI_SUMMARIZE_MODEL
  else
    live_base_url=${OPENAI_BASE_URL:-https://api.openai.com/v1}
    live_model=${TMUX_AI_SUMMARIZE_MODEL:-gpt-5.4-nano}
    tmux_cmd "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" set-environment -g OPENAI_API_KEY "$OPENAI_API_KEY"
    tmux_cmd "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" set-environment -g OPENAI_BASE_URL "$live_base_url"
    tmux_cmd "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" set-environment -g TMUX_AI_SUMMARIZE_MODEL "$live_model"
    tmux_cmd "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" set-environment -g TMUX_AI_SUMMARIZE_REQUEST_LOG "$request_log"
    tmux_cmd "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" set-option -g @ai-summarize-api-key 'wrong-option-key'
    tmux_cmd "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" set-option -g @ai-summarize-base-url 'http://127.0.0.1:9/v1'
    tmux_cmd "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" set-option -g @ai-summarize-model 'wrong-option-model'
  fi
  if [[ $provider_mode == mock ]]; then
    tmux_cmd "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" set-option -gu @ai-summarize-model
  fi
  tmux_cmd "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" run-shell "$repo_root/tmux-ai-summarize.tmux"

  binding=$(tmux_cmd "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" list-keys -T copy-mode-vi S)
  print -r -- "$binding" | rg -Fq -- 'copy-selection-no-clear' || fail "plugin entrypoint did not preserve tmux copy behavior"
  print -r -- "$binding" | rg -Fq -- 'copy-selection-and-cancel "ai-summarize-#{pane_id}-"' || fail "plugin entrypoint did not scope copy-mode buffers to the pane"
  print -r -- "$binding" | rg -Fq -- 'run-shell' || fail "plugin entrypoint did not install the runner"
  print -r -- "$binding" | rg -Fq -- "$repo_root/scripts/summarize-selection.zsh" || fail "binding does not point at the repo runner"

  driver_script="$TMUX_AI_SUMMARIZE_TMPDIR/attached-driver.zsh"
  cat >"$driver_script" <<'EOF'
#!/usr/bin/env zsh

emulate -L zsh
set -eu

helper_path=$1
source "$helper_path"

tmux_wrapper_dir=$2
tmux_socket_name=$3
transcript_path=$4
launcher_path=$5
log_path=$6
provider_mode=$7

trap 'stop_attached_client' EXIT INT TERM

start_attached_client test
client_name=$(find_attached_client_name) || fail_test "attached client never appeared"

pane=$(tmux_test_cmd display-message -p -t test:0.0 '#{pane_id}')
tmux_test_cmd copy-mode -t "$pane"
tmux_test_cmd send-keys -t "$pane" -X history-top
tmux_test_cmd send-keys -t "$pane" -X select-line
print -n -- 'S' >&$attached_client_input_fd

wait_for_log_line '^display-popup ' || fail_test "runner never attempted popup on attached client"
wait_for_log_line '^delete-buffer -b ai-summarize-' || fail_test "binding never consumed a fresh prefixed buffer"
if [[ $provider_mode == mock ]]; then
  wait_for_popup_loading '- concise point one' || fail_test "popup never showed an observable loading state before final output"
  wait_for_transcript_pattern '- concise point one' || fail_test "popup never rendered the first bullet prefix"
  wait_for_transcript_pattern '- concise point two' || fail_test "popup never rendered the second bullet prefix"
else
  wait_for_transcript_pattern 'Summarizing\.\.\.' || fail_test "popup never rendered the loading state in live mode"
  wait_for_live_summary || fail_test "live provider popup never rendered bullet output"
fi
EOF
  chmod +x "$driver_script"
  zsh "$driver_script" "$driver_helpers_path" "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" "$TMUX_AI_SUMMARIZE_SOCKET" "$transcript" "$runner_path" "$log_file" "$provider_mode"

  if [[ $provider_mode == mock ]]; then
    jq -e '.path == "/v1/chat/completions"' "$request_log" >/dev/null || fail "request path was not /v1/chat/completions"
    jq -e '.headers.Authorization == "Bearer test-key"' "$request_log" >/dev/null || fail "request did not include the Authorization header"
    actual_model=$(jq -r '.body.model // "<missing>"' "$request_log")
    [[ $actual_model == 'gpt-5.4-nano' ]] || fail "request used model $actual_model instead of gpt-5.4-nano"
    jq -e '.body.messages[0].role == "system"' "$request_log" >/dev/null || fail "request did not include the system prompt"
    actual_user_content=$(jq -r '.body.messages[1].content // "<missing>"' "$request_log")
    print -r -- "$actual_user_content" | rg -Fq -- "$fixture_text" || fail "request user content was: $actual_user_content"
  else
    wait_for_file "$request_log" || fail "live provider request log was not written"
    request_url=$(jq -r '.url // "<missing>"' "$request_log")
    [[ $request_url == "${live_base_url%/}/chat/completions" ]] || fail "request used url $request_url instead of ${live_base_url%/}/chat/completions"
    actual_model=$(jq -r '.body.model // "<missing>"' "$request_log")
    [[ $actual_model == "$live_model" ]] || fail "request used model $actual_model instead of $live_model"
  fi
  tmux_cmd "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" list-buffers -F '#{buffer_name}|#{buffer_sample}' | rg -Fq -- "|$fixture_text" || fail "tmux did not preserve the copied selection in the normal buffer stack"

  teardown_scenario
  trap - EXIT INT TERM
}

run_detached_cleanup_scenario() {
  print -u2 -r -- "scenario: detached cleanup path"

  local log_file pane runner_path quoted_runner_path pane_scope quoted_pane_scope scoped_buffer_name
  TMUX_AI_SUMMARIZE_SCENARIO='detached-cleanup'
  TMUX_AI_SUMMARIZE_TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/tmux-ai-summarize.XXXXXX")
  log_file="$TMUX_AI_SUMMARIZE_TMPDIR/tmux.log"
  runner_path="$repo_root/scripts/summarize-selection.zsh"
  TMUX_AI_SUMMARIZE_SOCKET="tmux-ai-summarize-$$-${RANDOM}"
  TMUX_AI_SUMMARIZE_WRAPPER_DIR=$(setup_tmux_wrapper "$TMUX_AI_SUMMARIZE_TMPDIR" "$log_file")
  tmux_wrapper_dir=$TMUX_AI_SUMMARIZE_WRAPPER_DIR
  tmux_socket_name=$TMUX_AI_SUMMARIZE_SOCKET
  log_path=$log_file
  transcript_path=

  trap teardown_scenario EXIT INT TERM

  tmux_cmd "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" -f /dev/null new-session -d -s test 'printf "hello world\n"; sleep 1000' >/dev/null
  pane=$(tmux_cmd "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" display-message -p -t test:0.0 '#{pane_id}')
  pane_scope=$pane
  quoted_pane_scope=$(printf '%q' "$pane_scope")
  tmux_cmd "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" set-buffer -b 'ai-summarize-%999-stale' 'stale selection'
  # Wait past the shared freshness window so this prefixed buffer is definitely stale.
  sleep "$((summary_buffer_fresh_window_seconds + 1))"
  quoted_runner_path=$(printf '%q' "$runner_path")
  tmux_cmd "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" run-shell "TMUX_AI_SUMMARIZE_BUFFER_SCOPE=$quoted_pane_scope $quoted_runner_path"
  wait_for_log_line '^display-message .*Nothing selected\.' || fail "stale-only prefixed buffer should fall through to Nothing selected"
  rg -q '^display-popup ' "$log_file" && fail "stale-only prefixed buffer should not launch popup"
  tmux_cmd "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" list-buffers -F '#{buffer_name}' | rg -Fxq -- 'ai-summarize-%999-stale' || fail "stale-only foreign prefixed buffer should not be consumed"
  tmux_cmd "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" copy-mode -t "$pane"
  tmux_cmd "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" send-keys -t "$pane" -X history-top
  tmux_cmd "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" send-keys -t "$pane" -X select-line
  tmux_cmd "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" send-keys -t "$pane" -X copy-selection-and-cancel "ai-summarize-$pane_scope-"
  scoped_buffer_name=$(tmux_cmd "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" list-buffers -F '#{buffer_name}' | rg "^ai-summarize-$(printf '%s' "$pane_scope" | sed 's/[.[\\*^$()+?{|]/\\\\&/g')-" | head -n 1 || true)
  [[ -n $scoped_buffer_name ]] || fail "expected copy-mode to create a pane-scoped prefixed buffer"
  tmux_cmd "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" set-buffer -b 'ai-summarize-%999-fresh' 'wrong selection'

  tmux_cmd "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" run-shell "TMUX_AI_SUMMARIZE_BUFFER_SCOPE=$quoted_pane_scope $quoted_runner_path"
  wait_for_buffer_removal "$scoped_buffer_name" || fail "pane-scoped prefixed buffer was not deleted after popup launch failed"
  wait_for_log_line '^display-popup ' || fail "runner never attempted popup"
  wait_for_log_line '^display-message .*Popup launch failed\.' || fail "runner did not fall back to a status-line message"
  tmux_cmd "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" list-buffers -F '#{buffer_name}' | rg -Fxq -- 'ai-summarize-%999-fresh' || fail "foreign fresh prefixed buffer should remain"
  tmux_cmd "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" list-buffers -F '#{buffer_name}' | rg -Fxq -- 'ai-summarize-%999-stale' || fail "stale-only foreign prefixed buffer should remain"

  teardown_scenario
  trap - EXIT INT TERM
}

run_no_selection_scenario() {
  print -u2 -r -- "scenario: no selection popup"

  local log_file transcript driver_script runner_path
  TMUX_AI_SUMMARIZE_SCENARIO='no-selection'
  TMUX_AI_SUMMARIZE_TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/tmux-ai-summarize.XXXXXX")
  log_file="$TMUX_AI_SUMMARIZE_TMPDIR/tmux.log"
  transcript="$TMUX_AI_SUMMARIZE_TMPDIR/client.typescript"
  runner_path="$repo_root/scripts/summarize-selection.zsh"
  TMUX_AI_SUMMARIZE_SOCKET="tmux-ai-summarize-$$-${RANDOM}"
  TMUX_AI_SUMMARIZE_WRAPPER_DIR=$(setup_tmux_wrapper "$TMUX_AI_SUMMARIZE_TMPDIR" "$log_file")
  tmux_wrapper_dir=$TMUX_AI_SUMMARIZE_WRAPPER_DIR
  tmux_socket_name=$TMUX_AI_SUMMARIZE_SOCKET
  log_path=$log_file
  transcript_path=$transcript

  trap teardown_scenario EXIT INT TERM

  tmux_cmd "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" -f /dev/null new-session -d -s test 'printf "hello world\n"; sleep 1000' >/dev/null
  tmux_cmd "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" set-option -g mode-keys vi
  tmux_cmd "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" set-buffer 'older default buffer'

  driver_script="$TMUX_AI_SUMMARIZE_TMPDIR/no-selection-driver.zsh"
  cat >"$driver_script" <<'EOF'
#!/usr/bin/env zsh

emulate -L zsh
set -eu

helper_path=$1
source "$helper_path"

tmux_wrapper_dir=$2
tmux_socket_name=$3
transcript_path=$4
launcher_path=$5
log_path=$6

trap 'stop_attached_client' EXIT INT TERM

start_attached_client test
client_name=$(find_attached_client_name) || fail_test "attached client never appeared"
quoted_client_name=$(printf '%q' "$client_name")
quoted_launcher_path=$(printf '%q' "$launcher_path")

pane=$(tmux_test_cmd display-message -p -t test:0.0 '#{pane_id}')
tmux_test_cmd copy-mode -t "$pane"
tmux_test_cmd send-keys -t "$pane" -X history-top
tmux_test_cmd send-keys -t "$pane" -X copy-selection-and-cancel ai-summarize-
tmux_test_cmd list-buffers -F '#{buffer_name}' | rg -q '^ai-summarize-' && fail_test "no-selection copy-mode path unexpectedly created a prefixed buffer"
tmux_test_cmd run-shell -b "TMUX_AI_SUMMARIZE_CLIENT=$quoted_client_name $quoted_launcher_path"

wait_for_log_line '^display-popup ' || fail_test "no-selection path did not launch a popup"
wait_for_transcript_pattern 'Nothing selected\.' || fail_test "no-selection popup did not render the expected message"
EOF
  chmod +x "$driver_script"
  zsh "$driver_script" "$driver_helpers_path" "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" "$TMUX_AI_SUMMARIZE_SOCKET" "$transcript" "$runner_path" "$log_file"

  teardown_scenario
  trap - EXIT INT TERM
}

run_whitespace_only_scenario() {
  print -u2 -r -- "scenario: whitespace-only popup"

  local log_file transcript driver_script runner_path
  TMUX_AI_SUMMARIZE_SCENARIO='whitespace-only'
  TMUX_AI_SUMMARIZE_TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/tmux-ai-summarize.XXXXXX")
  log_file="$TMUX_AI_SUMMARIZE_TMPDIR/tmux.log"
  transcript="$TMUX_AI_SUMMARIZE_TMPDIR/client.typescript"
  runner_path="$repo_root/scripts/summarize-selection.zsh"
  TMUX_AI_SUMMARIZE_SOCKET="tmux-ai-summarize-$$-${RANDOM}"
  TMUX_AI_SUMMARIZE_WRAPPER_DIR=$(setup_tmux_wrapper "$TMUX_AI_SUMMARIZE_TMPDIR" "$log_file")
  tmux_wrapper_dir=$TMUX_AI_SUMMARIZE_WRAPPER_DIR
  tmux_socket_name=$TMUX_AI_SUMMARIZE_SOCKET
  log_path=$log_file
  transcript_path=$transcript

  trap teardown_scenario EXIT INT TERM

  tmux_cmd "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" -f /dev/null new-session -d -s test 'printf "   \nnon-whitespace line\n"; sleep 1000' >/dev/null
  tmux_cmd "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" set-option -g mode-keys vi

  driver_script="$TMUX_AI_SUMMARIZE_TMPDIR/whitespace-driver.zsh"
  cat >"$driver_script" <<'EOF'
#!/usr/bin/env zsh

emulate -L zsh
set -eu

helper_path=$1
source "$helper_path"

tmux_wrapper_dir=$2
tmux_socket_name=$3
transcript_path=$4
launcher_path=$5
log_path=$6

trap 'stop_attached_client' EXIT INT TERM

start_attached_client test
client_name=$(find_attached_client_name) || fail_test "attached client never appeared"
quoted_client_name=$(printf '%q' "$client_name")
quoted_launcher_path=$(printf '%q' "$launcher_path")

pane=$(tmux_test_cmd display-message -p -t test:0.0 '#{pane_id}')
tmux_test_cmd copy-mode -t "$pane"
tmux_test_cmd send-keys -t "$pane" -X history-top
tmux_test_cmd send-keys -t "$pane" -X select-line
tmux_test_cmd send-keys -t "$pane" -X copy-selection-and-cancel ai-summarize-

fresh_buffer_name=$(wait_for_fresh_buffer) || fail_test "whitespace-only copy-mode path did not create a fresh prefixed buffer"
tmux_test_cmd run-shell -b "TMUX_AI_SUMMARIZE_CLIENT=$quoted_client_name $quoted_launcher_path"

wait_for_log_line '^display-popup ' || fail_test "whitespace-only path did not launch a popup"
wait_for_transcript_pattern 'Nothing to summarize\.' || fail_test "whitespace-only popup did not render the expected message"
wait_for_buffer_removal "$fresh_buffer_name" || fail_test "whitespace-only path did not delete the selected buffer"
EOF
  chmod +x "$driver_script"
  zsh "$driver_script" "$driver_helpers_path" "$TMUX_AI_SUMMARIZE_WRAPPER_DIR" "$TMUX_AI_SUMMARIZE_SOCKET" "$transcript" "$runner_path" "$log_file"

  teardown_scenario
  trap - EXIT INT TERM
}

usage() {
  print -u2 -r -- "usage: $0 [attached_mock|detached_cleanup|no_selection|whitespace_only|all]"
}

case "${1:-all}" in
  attached_mock)
    run_attached_client_scenario
    ;;
  detached_cleanup)
    run_detached_cleanup_scenario
    ;;
  no_selection)
    run_no_selection_scenario
    ;;
  whitespace_only)
    run_whitespace_only_scenario
    ;;
  all)
    run_attached_client_scenario
    run_detached_cleanup_scenario
    run_no_selection_scenario
    run_whitespace_only_scenario
    ;;
  *)
    usage
    exit 2
    ;;
esac
