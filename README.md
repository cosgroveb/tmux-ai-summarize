# tmux-ai-summarize

[![CI](https://github.com/clnkr-ai/tmux-ai-summarize/actions/workflows/ci.yml/badge.svg)](https://github.com/clnkr-ai/tmux-ai-summarize/actions/workflows/ci.yml)

Press `S` in `copy-mode-vi`, tmux copies the selection, then opens a popup with a short bullet summary from an OpenAI-compatible API.

The popup stays open. Enter copy mode there if you want to copy the summary back out.

v1 only binds `copy-mode-vi`. If you are not already using vi keys, set `mode-keys` to `vi`.

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

Reload tmux. Then install the plugin with TPM.

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

tmux copies first. The plugin opens a popup, prints `Summarizing...`, then swaps in bullet output.

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

## OpenAI-Compatible Endpoints

The plugin sends `POST /chat/completions` to an OpenAI-compatible endpoint. Default: `https://api.openai.com/v1`.

For a local or proxy endpoint:

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

The default test path is mock-only. The live workflow runs the same harness with `TMUX_AI_SUMMARIZE_PROVIDER_MODE=live`.

The GitHub `Live Provider` workflow requires a repo or org `OPENAI_API_KEY` secret. If it is missing, the workflow fails.

This repo does not publish GitHub Releases. Release flow: keep `main` green, run the live-provider workflow on `main`, then tag `v0.1.0`.
