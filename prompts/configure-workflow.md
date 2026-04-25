# Configure Seashell end-to-end

This is the deep-end prompt — paste it to have your AI design your entire Seashell + Wave + fish + LLM stack from a free-form description of how you work. The AI delivers a personalized configuration plan, asks for confirmation at each stage, and produces ready-to-paste configs at the end.

---

## Prompt to paste

I'm setting up Seashell (https://github.com/M-Pineapple/seashell) — an MCP server that bridges Claude Desktop and Wave Terminal — together with Wave Terminal, fish shell, and a local LLM (Ollama). 

I want a configuration tailored to me, not a generic template. Please act as my assistant and walk me through it stage by stage, getting my OK before moving on.

Here's everything you need to know about me:

```
WHO I AM:
<fill in: role, languages, OS, years of experience>

WHAT I'M BUILDING:
<fill in: current projects, side projects, daily work>

HOW I WORK:
<fill in: solo / team, sync / async, deep focus / interrupts, hours, timezone>

WHAT FRUSTRATES ME ABOUT MY TERMINAL:
<fill in: typing the same paths, forgetting flags, slow startup, tab management, etc.>

WHAT I WANT TO BE FASTER AT:
<fill in: navigating projects, running tests, deploying, searching history>

MY MACHINE:
<fill in: model, RAM, disk space, M-series or Intel, single or multi-monitor>

WHAT I ALREADY HAVE INSTALLED:
<fill in: brew packages, IDE, editors, anything relevant>

WHAT I REFUSE TO INSTALL OR USE:
<fill in: anything off the table, e.g., "no Vim", "no oh-my-zsh", "no telemetry">

PRIVACY/SECURITY POSTURE:
<fill in: e.g. "I work with client code under NDA, nothing should phone home" / "fine with telemetry">
```

Walk me through the configuration in this order, asking me to confirm before moving on:

1. **Shell choice** (fish vs zsh) — one paragraph of reasoning specific to what I told you
2. **Brew install plan** — ordered list with rationale per package
3. **Local LLM model** — pick the right `qwen2.5-coder:*` size for my RAM
4. **fish (or zsh) config** — `config.fish`, plus exactly which `conf.d/` and `functions/` files to enable
5. **Wave Terminal settings** — `~/.config/waveterm/settings.json` (font, theme, transparency, cursor)
6. **Wave widgets** — 5–8 widget definitions matching my workflow (`~/.config/waveterm/widgets.json`)
7. **Theme strategy** — auto-switch with macOS appearance, fixed dark, fixed light, or time-based
8. **Seashell-specific tools** — should I enable the helper block (helper-block tools) or stick to direct config (direct-config tools)?
9. **Optional polish** — fastfetch banner, daylight widget, custom prompt, atuin sync

For each step, give me:
- **Ready-to-paste config or commands**
- **One-line rationale** tying back to what I told you
- **A check command** I can run to verify it worked

Be opinionated. Don't ask "what do you want?" if my context already suggests an answer. Surface trade-offs only when there's a real choice and my preferences don't decide it.

At the end, give me a single shell script that does everything I've approved, in order, that I can run and walk away.
