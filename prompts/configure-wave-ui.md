# Configure Wave Terminal UI

Paste this prompt to have your AI assistant suggest fonts, colors, transparency, and layout settings tailored to your screen and taste — no more imitating someone else's setup.

The assistant will return a `~/.config/waveterm/settings.json` patch you can save directly.

---

## Prompt to paste

I'm setting up Wave Terminal (https://github.com/wavetermdev/waveterm) and want help choosing UI settings. Please give me a `settings.json` block I can merge into `~/.config/waveterm/settings.json`.

Here's the schema reference (Wave settings keys you can use):

| Key | Type | Notes |
|---|---|---|
| `term:fontfamily` | string | "JetBrains Mono", "SF Mono", "Fira Code", "Cascadia Code", "Iosevka", "Berkeley Mono" |
| `term:fontsize` | integer 8–24 | terminal font size |
| `term:cursor` | "bar" \| "block" \| "underline" | |
| `term:cursorblink` | boolean | |
| `term:theme` | string | "github-light", "dracula", "tokyo-night", "monokai", "solarized-dark", etc. |
| `term:transparency` | number 0.0–1.0 | 0 opaque, 1 fully transparent |
| `term:macoptionismeta` | boolean | treat option key as meta (true if you use ⌥-shortcuts) |
| `term:scrollback` | integer | scrollback buffer lines |
| `app:tabbar` | "top" \| "bottom" | tab bar position |
| `app:confirmquit` | boolean | confirm before quitting |
| `window:bgcolor` | hex string | window background (when transparency > 0) |
| `window:opacity` | number 0–1 | window opacity |
| `window:tilegapsize` | integer | pixel gap between blocks |
| `telemetry:enabled` | boolean | Wave's telemetry — set false for privacy |

My setup:

- **Screen**: <fill in: e.g. 14" laptop, 27" 4K monitor, dual monitors>
- **Lighting**: <fill in: bright office, low-light den, varies by time of day>
- **My work is mostly**: <fill in: backend / frontend / data / ops / writing / mixed>
- **I prefer aesthetics**: <fill in: minimal / dense, light / dark, transparent / opaque, sharp / soft>
- **Typography I like elsewhere**: <fill in: e.g. "VS Code with JetBrains Mono 13", "Mac Mail at default">
- **Things to avoid**: <fill in: e.g. "no blinking cursors, gives me headaches" / "nothing too dim — I'm in sunlight">

Suggest **2–3 distinct setting profiles** that match my preferences, each with a one-line rationale. After I pick one, give me the final `settings.json` patch ready to save.

If I haven't said anything that suggests a clear answer for something, default to: dark theme, JetBrains Mono 13, bar cursor with blink, 0.0 transparency, telemetry off. Don't ask me — just pick.
