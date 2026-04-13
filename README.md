# tmux-ai-summarize

[![CI](https://github.com/clnkr-ai/tmux-ai-summarize/actions/workflows/ci.yml/badge.svg)](https://github.com/clnkr-ai/tmux-ai-summarize/actions/workflows/ci.yml)

Press `S` in copy mode. tmux copies the text. You get an AI summary in a popup.

The popup stays open. Enter copy mode there if you want to copy the summary back out.

## Requirements

- `tmux >= 3.2`
- `zsh`
- `curl`
- `jq`

## Install with TPM

If you already use TPM, add this to `tmux.conf`:

```tmux
set -g mode-keys vi
set -g @plugin 'clnkr-ai/tmux-ai-summarize'
set -g @ai-summarize-key 'S'
# set -g @ai-summarize-model 'gpt-5.4-nano' # default
run '~/.tmux/plugins/tpm/tpm'
```

`run '~/.tmux/plugins/tpm/tpm'` is TPM's own line. Keep it at the bottom of `tmux.conf`.

If tmux is already running, reload your config:

```sh
tmux source-file ~/.tmux.conf
```

Use the path to your `tmux.conf` if it lives somewhere else.

Install the plugin with `prefix` + `I`. From the shell, `~/.tmux/plugins/tpm/bin/install_plugins` does the same thing.

## Usage

Enter copy mode. Select text. Press `S`.

## Settings

- API key: `OPENAI_API_KEY` or `@ai-summarize-api-key`
- Base URL: `OPENAI_BASE_URL` or `@ai-summarize-base-url` (default: `https://api.openai.com/v1`)
- Model: `TMUX_AI_SUMMARIZE_MODEL` or `@ai-summarize-model` (default: `gpt-5.4-nano`)
- Prompt: `@ai-summarize-prompt`
- Key: `@ai-summarize-key` (default: `S`)

Environment variables win over tmux options.

## OpenAI-Compatible API

Use any OpenAI-compatible API by setting a different base URL. Default: `https://api.openai.com/v1`.

Set the API root, including `/v1` if your provider expects it.

For a local or proxy API:

```tmux
set -g @ai-summarize-base-url 'http://localhost:8000/v1'
set -g @ai-summarize-api-key 'dummy-key'
```

TODO: Support emacs copy mode too.
