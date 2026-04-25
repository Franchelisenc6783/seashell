# Prompts library

Copy-paste-ready prompts for configuring Seashell + Wave Terminal + your shell stack with help from an AI assistant — Claude, ChatGPT, Gemini, or any capable LLM.

If [`examples/wave-config/`](../examples/wave-config/) is *one* opinionated way to set up Wave, this directory is the *general* way: tell your AI what you want, and it builds the config to fit.

## Available prompts

| Prompt | Use when |
|---|---|
| [install-from-scratch.md](install-from-scratch.md) | Fresh Mac — walk me through everything, end-to-end |
| [configure-wave-ui.md](configure-wave-ui.md) | I have Wave installed; pick fonts, colors, transparency, layout |
| [configure-shell-stack.md](configure-shell-stack.md) | Choosing fish/zsh, picking an Ollama model, selecting plugins |
| [configure-widgets.md](configure-widgets.md) | Design my Wave widget bar around what I actually check daily |
| [configure-workflow.md](configure-workflow.md) | The big one — describe my work, get a complete tailored config plan |

## How to use

1. Open the prompt file in this directory
2. Copy the entire **Prompt to paste** section
3. Replace each `<fill in: ...>` placeholder with your actual answer
4. Paste into a chat with your AI assistant
5. Iterate with follow-up questions until you have something you like
6. Save the resulting config files to the right paths (each prompt tells you where)

You can also run multiple prompts in sequence — `configure-wave-ui` for UI, then `configure-widgets` for the sidebar — to build up your config piece by piece.

## Why prompts and not a setup wizard?

A wizard locks you into the questions someone else thought to ask. A prompt is a starting point you can edit, delete from, or expand. Want a "prefer dark themes but keep a light one pinned for screen-share moments" rule? Just write it in. The AI will work with what you tell it.

## License

These prompts ship under the same MIT license as Seashell. Fork, modify, share.
