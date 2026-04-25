#!/usr/bin/env python3
"""
Natural language → shell command handler.
Called by __nl_enter with CWD as argv[1], query tokens as argv[2+].
Outputs: QUESTION:<answer>  |  COMMAND:<shell command>  |  FAIL
"""
import json, os, subprocess, sys, difflib

OLLAMA = "http://localhost:11434/api/chat"
MODEL  = "qwen2.5-coder:1.5b"
cwd    = sys.argv[1] if len(sys.argv) > 1 else "~"
query  = " ".join(sys.argv[2:]) if len(sys.argv) > 2 else ""

# Verbs that mean "do something TO a path" — not pure navigation
NAV_BLOCKLIST = {
    "list", "ls", "show", "find", "search", "delete", "remove", "rm",
    "move", "mv", "copy", "cp", "cat", "read", "edit", "open", "create",
    "make", "mkdir", "touch", "chmod", "kill", "stop", "start", "run",
    "install", "uninstall", "print", "count", "wc", "grep",
    # Question / sentence starters — never treat as directory navigation
    "what", "which", "who", "why", "when", "where", "how",
    "is", "are", "does", "can", "do", "did", "will", "would", "should",
    "tell", "give", "explain", "describe", "duplicate", "rename",
}

def fuzzy_dir_match(q, directory):
    """
    Try to match query q against directory entries in `directory`.
    Returns the best-matching entry name, or None.
    Strategy: score each entry by how many query words appear in it (case-insensitive).
    """
    try:
        entries = os.listdir(directory)
    except Exception:
        return None

    q_clean = q.lower().strip("/\\").strip()
    q_words = [w for w in q_clean.split() if len(w) > 1]  # skip single chars
    if not q_words:
        return None

    scored = []
    for entry in entries:
        e_lower = entry.lower()
        score = sum(1 for w in q_words if w in e_lower)
        if score > 0:
            is_dir = os.path.isdir(os.path.join(directory, entry))
            scored.append((score, is_dir, entry))

    if not scored:
        # Fall back to difflib on the full query vs entry names
        names = [e.lower() for e in entries]
        close = difflib.get_close_matches(q_clean, names, n=1, cutoff=0.4)
        if close:
            for entry in entries:
                if entry.lower() == close[0]:
                    return entry
        return None

    # Sort: highest score first, prefer directories
    scored.sort(key=lambda x: (x[0], x[1]), reverse=True)
    best_score, _, best_entry = scored[0]

    # Require at least half the query words to match
    if best_score >= max(1, len(q_words) // 2):
        return best_entry

    return None


def is_nav_query(q):
    """Return True if query looks like a bare directory navigation attempt."""
    words = q.lower().split()
    if not words:
        return False
    # If first word is a command verb, it's not pure navigation
    if words[0] in NAV_BLOCKLIST:
        return False
    # Short queries with no verb are likely navigation
    if len(words) <= 5:
        return True
    return False


def ollama(messages, timeout=10):
    payload = json.dumps({"model": MODEL, "stream": False, "messages": messages})
    r = subprocess.run(
        ["curl", "-s", "--max-time", str(timeout), OLLAMA,
         "-H", "content-type: application/json", "-d", payload],
        capture_output=True, text=True, timeout=timeout + 2
    )
    return json.loads(r.stdout)["message"]["content"].strip()


def strip_fences(s):
    s = s.strip().strip("`").strip()
    for prefix in ("sh\n", "bash\n", "fish\n", "zsh\n", "shell\n"):
        if s.startswith(prefix):
            s = s[len(prefix):]
    line = s.splitlines()[0].strip() if s else ""
    return line.rstrip("\\").strip()


# ── Fast path: fuzzy directory navigation (no Ollama needed) ─────────────────
if is_nav_query(query):
    match = fuzzy_dir_match(query, cwd)
    if match:
        quoted = match.replace('"', '\\"')
        print(f'COMMAND:cd "{cwd}/{quoted}"')
        sys.exit(0)

# ── Step 1: classify via Ollama ───────────────────────────────────────────────
try:
    items = sorted(os.listdir(cwd))
    cwd_listing = ", ".join(f'"{x}"' for x in items[:40])
except Exception:
    cwd_listing = ""

classify_msg = [{"role": "user", "content": (
    "Classify as SHELL or QUESTION.\n"
    "SHELL = requires checking or changing THIS computer's local state.\n"
    "QUESTION = facts about the world that exist independently of this machine.\n"
    "\n"
    "SHELL examples: 'how many files on my desktop', 'list downloads folder', "
    "'what processes are running', 'show disk space', 'find large files'.\n"
    "QUESTION examples: 'how many planets in the solar system', 'what is Python', "
    "'who invented the internet', 'what is the capital of France', 'how does TCP work'.\n"
    "\n"
    "Key rule: 'how many X' is SHELL only if X is files/folders/processes/apps on this machine. "
    "If X is anything in the real world (planets, countries, people, animals, etc.) it is QUESTION.\n"
    "\n"
    "Always SHELL if query contains: desktop, downloads, my files, my folder, my disk, "
    "running process, installed app, my clipboard, my network, my RAM, my battery.\n"
    "Always SHELL if query starts with: list, find, show, open, delete, move, copy, "
    "create, make, run, start, stop, install, kill, rename.\n"
    "\n"
    "Reply with ONE word only: SHELL or QUESTION\n\n"
    f"Input: {query}"
)}]

try:
    intent = ollama(classify_msg, timeout=6).upper()
    intent = "QUESTION" if "QUESTION" in intent else "SHELL"
except Exception:
    intent = "SHELL"

# ── Step 2a: answer questions ─────────────────────────────────────────────────
if intent == "QUESTION":
    answer_msg = [
        {"role": "system", "content": "Answer concisely in 1-3 sentences. Plain text only."},
        {"role": "user",   "content": query}
    ]
    try:
        print(f"QUESTION:{ollama(answer_msg, timeout=10)}")
    except Exception:
        print("FAIL")
    sys.exit(0)

# ── Step 2b: generate shell command ──────────────────────────────────────────
cwd_ctx = f" Items in CWD: {cwd_listing}." if cwd_listing else ""
cmd_msg = [
    {"role": "system", "content": (
        f"You generate macOS fish shell commands. CWD: {cwd}.{cwd_ctx} "
        "When the user refers to a file or directory by a partial name, "
        "match it to the closest real item in the CWD listing and use that exact name. "
        "ALWAYS double-quote paths and filenames that contain spaces. "
        "NEVER end a command with a backslash. "
        "Output ONLY the raw command. No backticks, no explanation, no markdown. "
        "If the user asks to both list AND count items, show the listing. "
        "Combine multiple requests with && or ; rather than omitting any part."
    )},
    {"role": "user", "content": query}
]
try:
    print(f"COMMAND:{strip_fences(ollama(cmd_msg, timeout=10))}")
except Exception:
    print("FAIL")
