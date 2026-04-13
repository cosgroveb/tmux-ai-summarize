# tmux-ai-summarize

`tmux-ai-summarize` adds one copy-mode action to tmux: press `S` in `copy-mode-vi`, copy the current selection into the normal tmux buffer stack, and open a popup with a short bullet summary from an OpenAI-compatible API.

The popup is read-only. You can enter copy mode inside it and copy the summary out.

v1 binds only `copy-mode-vi`. Set `mode-keys` to `vi` if you are not already using it.

## Requirements

- `tmux >= 3.2`
- `zsh`
- `curl`
- `jq`

## Install with TPM

Add this to `tmux.conf`:

```tmux
set -g mode-keys vi
set -g @plugin 'clnkr-ai/tmux-ai-summarize'
set -g @ai-summarize-key 'S'
run '~/.tmux/plugins/tpm/tpm'
```

Reload tmux, then install the plugin with TPM.

## Manual install

Clone the repo into `~/.tmux/plugins/tmux-ai-summarize`, then add:

```tmux
run-shell '~/.tmux/plugins/tmux-ai-summarize/tmux-ai-summarize.tmux'
```

Reload tmux after updating `tmux.conf`.

## Usage

1. Enter copy mode with vi keys.
2. Select text.
3. Press `S`.

tmux copies the selection first. The plugin then opens a popup, shows `Summarizing...`, and replaces it with bullet output.

## Configuration

tmux options:

- `@ai-summarize-key`: copy-mode keybinding. Default: `S`
- `@ai-summarize-api-key`: API key fallback when `OPENAI_API_KEY` is unset
- `@ai-summarize-base-url`: base URL fallback when `OPENAI_BASE_URL` is unset
- `@ai-summarize-model`: model fallback when `TMUX_AI_SUMMARIZE_MODEL` is unset
- `@ai-summarize-prompt`: full prompt override

Environment variables:

- `OPENAI_API_KEY`
- `OPENAI_BASE_URL`
- `TMUX_AI_SUMMARIZE_MODEL`

Precedence:

- API key: `OPENAI_API_KEY`, then `@ai-summarize-api-key`
- Base URL: `OPENAI_BASE_URL`, then `@ai-summarize-base-url`, then `https://api.openai.com/v1`
- Model: `TMUX_AI_SUMMARIZE_MODEL`, then `@ai-summarize-model`, then `gpt-5.4-nano`
- Prompt: `@ai-summarize-prompt`, else the built-in prompt
- Binding key: `@ai-summarize-key`, else `S`

Default model: `gpt-5.4-nano`.

## Compatible providers

The plugin speaks OpenAI-compatible `POST /chat/completions`. By default it uses `https://api.openai.com/v1`.

For a compatible local or proxy endpoint:

```tmux
set -g @ai-summarize-base-url 'http://localhost:8000/v1'
set -g @ai-summarize-api-key 'dummy-key'
```

## Example config

```tmux
set -g mode-keys vi
set -g @plugin 'clnkr-ai/tmux-ai-summarize'
set -g @ai-summarize-key 'S'
set -g @ai-summarize-model 'gpt-5.4-nano'
run '~/.tmux/plugins/tpm/tpm'
```

## Maintainer note

`./test/integration.sh` runs the mock harness by default. The live-provider path uses the same harness with `TMUX_AI_SUMMARIZE_PROVIDER_MODE=live`.

The GitHub `Live Provider` workflow requires a repo or org `OPENAI_API_KEY` secret. If it is missing, the workflow fails.

The repo does not publish GitHub Releases. Release flow is simple: keep `main` green, run the live-provider workflow on `main`, then create a semver tag like `v0.1.0`.
