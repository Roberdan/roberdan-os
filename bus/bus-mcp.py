#!/usr/bin/env python3
"""bus-mcp.py — the bus as a closed set of typed tools, over MCP stdio.

WHY THIS EXISTS
    Two agent sessions need to talk to each other. Everything else an agent
    could do while "talking" is attack surface, and eight rounds of textual
    checks failed to enumerate it: `git -c alias.z='!claude' z` starts an agent
    session and does not contain the word `claude` in any position a grep was
    looking. The lesson was not "write a better grep". It was that a channel
    reached through a SHELL STRING can express anything the shell can express,
    so the shell string is the defect.

    Here an agent never composes a command. It calls `bus_send` with named,
    typed, individually validated arguments, and this process dispatches a
    fixed executable with an argv ARRAY. There is no shell anywhere on the
    path: no `shell=True`, no `os.system`, no string ever interpreted as a
    command. A metacharacter in an argument is data, because nothing is left
    that could read it as syntax.

    This is the same shape already carried in VirtualBPM's assistant: a closed
    registry of typed read tools where no shell, filesystem, generic HTTP or
    raw query is reachable. It is not "no subprocess" - it is "no ARBITRARY
    subprocess". Exactly one program can be started, and its arguments are
    drawn from a validated schema rather than from model output.

WHY IT DOES NOT REIMPLEMENT THE STORE
    `bus.sh` gates a send on eight invariants: slug hygiene, the kind enum, the
    role registry, body-as-file, non-empty body, the scope heuristic, the
    approval-needs-a-citation rule, a fail-closed leak check, UTF-8
    validation, and the closed-thread refusal. A second implementation in this
    file would be a divergence machine: two definitions of "a legal message",
    drifting, with the privacy gate on the side nobody runs. So this file adds
    a surface and subtracts capability. It stores nothing and decides nothing.

WHAT IS DELIBERATELY NOT EXPOSED
    `close`, `open` and `roles` are absent. Closing a thread is a decision
    about the work, and this file exists so that an agent's reach is exactly
    "say something, read what was said". A human still has the whole CLI.

    `hello`, `bye`, `who` and `owed` were ADDED on 2026-09-22 and belong on the
    same side of that line rather than widening it: the first two say something
    about THIS SESSION, the last two read what was said. Before them an agent
    reaching the bus only through this surface could not announce itself, could
    not see who else was there, and could not discover what had been asked of it
    and never answered — which is exactly how a channel becomes a noticeboard.

Transport: MCP over stdio, JSON-RPC 2.0, standard library only.
"""

import json
import os
import re
import subprocess
import sys
import tempfile

PROTOCOL_VERSION = "2024-11-05"
SERVER_NAME = "roberdan-os-bus"
SERVER_VERSION = "1.0.0"

# The one program this process is allowed to start, resolved from this file's
# own location rather than from PATH: a PATH lookup is an injection point, and
# the whole point of this file is not to have any.
BUS_SH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bus.sh")

# Same grammar bus.sh enforces (`_slug`). Duplicated here on purpose: this is a
# tightening, not a second source of truth. Anything that passes here is still
# re-validated downstream, and anything rejected here never reaches a process.
SLUG_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
KINDS = ("request", "verdict", "note", "question")
BROADCAST = "all"

# A body is text. This bound is not about correctness - bus.sh streams the body
# through a file precisely so size is bounded by disk - it is about a model
# looping and filling a disk one 4GB "note" at a time.
MAX_BODY_BYTES = 4 * 1024 * 1024

SUBPROCESS_TIMEOUT = 120


class ToolError(Exception):
    """A refusal the caller should see and can act on."""


def _slug(field: str, value, *, allow_broadcast: bool = False) -> str:
    if not isinstance(value, str) or not value:
        raise ToolError(f"{field}: required, must be a non-empty string")
    if allow_broadcast and value == BROADCAST:
        return value
    if not SLUG_RE.match(value):
        raise ToolError(
            f"{field}: {value!r} is not a plain name "
            "([A-Za-z0-9._-], no slashes, no leading dash)"
        )
    return value


def _run_bus(args, *, stdin_path=None):
    """Start bus.sh with an argv ARRAY. No shell, ever.

    shell=False is the default and is stated explicitly because it is the
    single most load-bearing line in this file.
    """
    if not os.path.isfile(BUS_SH):
        raise ToolError(f"bus.sh not found at {BUS_SH}")

    stdin_handle = subprocess.DEVNULL
    opened = None
    try:
        if stdin_path is not None:
            opened = open(stdin_path, "rb")
            stdin_handle = opened
        proc = subprocess.run(
            ["bash", BUS_SH, *args],
            shell=False,
            stdin=stdin_handle,
            capture_output=True,
            text=True,
            timeout=SUBPROCESS_TIMEOUT,
        )
    except subprocess.TimeoutExpired:
        raise ToolError(
            f"bus did not answer within {SUBPROCESS_TIMEOUT}s. "
            "Another writer may be holding the lock; retry."
        )
    finally:
        if opened is not None:
            opened.close()

    if proc.returncode != 0:
        # bus.sh's refusals are written for a human to act on ("body carries
        # acceptance criteria", "thread is closed"), so they are passed
        # through: swallowing them would leave the caller guessing and retrying
        # blind, which is worse than the message itself.
        detail = (proc.stderr or proc.stdout or "").strip()
        raise ToolError(detail or f"bus exited {proc.returncode}")

    # SUCCESS IS NOT SILENCE. bus.sh writes real information to stderr on a
    # SUCCESSFUL run — "you still owe an answer to 3 messages", "this thread is
    # damaged and was skipped", "you left with mail unanswered" — and this
    # function used to return stdout alone, so a caller on the typed surface got
    # the reassuring half of the answer and never the warning (@baccio,
    # adversarial review, reproduced). Dropping the part that says "I could not
    # read everything" is how a zero stops meaning zero.
    warnings = (proc.stderr or "").strip()
    if warnings:
        return proc.stdout + ("\n" if proc.stdout and not proc.stdout.endswith("\n") else "") \
             + "--- bus also said, on stderr ---\n" + warnings + "\n"
    return proc.stdout


def tool_bus_send(args):
    repo = _slug("repo", args.get("repo"))
    card = _slug("card", args.get("card"))
    sender = _slug("from_role", args.get("from_role"))
    to = _slug("to_role", args.get("to_role"), allow_broadcast=True)

    kind = args.get("kind")
    if kind not in KINDS:
        raise ToolError(f"kind: must be one of {', '.join(KINDS)}")

    body = args.get("body")
    if not isinstance(body, str) or not body.strip():
        raise ToolError("body: required, must be non-empty text")
    encoded = body.encode("utf-8")
    if len(encoded) > MAX_BODY_BYTES:
        raise ToolError(
            f"body: {len(encoded)} bytes exceeds the {MAX_BODY_BYTES} byte limit"
        )

    ref = args.get("ref")
    if ref is not None:
        if not isinstance(ref, str) or not ref.strip():
            raise ToolError("ref: must be a non-empty string when given")
        # Citations are resolved by bus.sh against git/kb. Constrain the shape
        # here so a free-form string cannot be smuggled through as one.
        if not re.match(r"^(git|kb):[A-Za-z0-9][A-Za-z0-9._/-]*$", ref):
            raise ToolError("ref: must look like git:<sha> or kb:<card>")

    # `re` is what turns a reply into an ANSWER. Without it the asker cannot tell
    # an answer from silence, which is the state the whole store was in: a
    # question stays listed by bus_owed until a message of the addressee cites
    # it. Validated as a record number here and validated AGAIN against the
    # thread by bus.sh, which is the only side that can know how deep it is.
    answers = args.get("re")
    if answers is not None:
        if isinstance(answers, bool) or not isinstance(answers, int) or answers < 1:
            raise ToolError("re: must be the number of a record in this thread (1 or more)")

    # The body travels as a FILE, never as an argument. bus.sh chose this
    # because a 3MB verdict through argv hit ARG_MAX; it is also why no body
    # content is ever visible in a process listing.
    fd, path = tempfile.mkstemp(prefix="bus-mcp-body-")
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(encoded)
        argv = ["send", "--repo", repo, "--card", card, "--from", sender,
                "--to", to, "--kind", kind, "--body-file", path]
        if ref is not None:
            argv += ["--ref", ref]
        if answers is not None:
            argv += ["--re", str(answers)]
        return _run_bus(argv)
    finally:
        # The body may be the only copy of a verdict; it must not be left in
        # the temp directory either.
        try:
            os.unlink(path)
        except OSError:
            pass


def _read_like(args, *, peek):
    repo = _slug("repo", args.get("repo"))
    card = _slug("card", args.get("card"))
    as_role = _slug("as_role", args.get("as_role"))
    argv = ["read", "--repo", repo, "--card", card, "--as", as_role]
    if peek:
        argv.append("--peek")
    return _run_bus(argv)


def tool_bus_read(args):
    return _read_like(args, peek=False)


def tool_bus_peek(args):
    return _read_like(args, peek=True)


def tool_bus_log(args):
    repo = _slug("repo", args.get("repo"))
    card = _slug("card", args.get("card"))
    return _run_bus(["log", "--repo", repo, "--card", card])


# --- presence and debt ------------------------------------------------------
# Added 2026-09-22. An agent that reaches the bus only through this surface could
# not announce itself, could not see who else was there, and could not find out
# what had been asked of it and never answered. It could therefore reproduce, on
# its own, every failure measured on the real store that day: 13 threads with one
# sender, 14 nobody ever opened.
#
# These four fit the rule this file already states — "say something, read what
# was said" — rather than widening it. `hello` and `bye` say something about THIS
# SESSION, not about the work; `who` and `owed` read what was said. `close`,
# `open` and `roles` stay absent for the reason given above: closing a thread is a
# decision about the work.
def tool_bus_hello(args):
    repo = _slug("repo", args.get("repo"))
    as_role = _slug("as_role", args.get("as_role"))
    argv = ["hello", "--repo", repo, "--as", as_role]
    session = args.get("session")
    if session:
        argv += ["--session", _slug("session", session)]
    card = args.get("card")
    if card:
        argv += ["--card", _slug("card", card)]
    doing = args.get("doing")
    if doing is not None:
        if not isinstance(doing, str):
            raise ValueError("doing: must be a string")
        # Free text, never a slug — but it is one line of a record, so a newline
        # would split it across fields for every later reader.
        argv += ["--doing", doing.replace("\n", " ").strip()]
    return _run_bus(argv)


def tool_bus_bye(args):
    repo = _slug("repo", args.get("repo"))
    as_role = _slug("as_role", args.get("as_role"))
    argv = ["bye", "--repo", repo, "--as", as_role]
    # THE SESSION NAME, which `bus_hello` accepted and this did not. Without it
    # the goodbye is addressed to a session id minted one instant earlier, the
    # session that actually said hello is never withdrawn, and `bus who` carries
    # it as present forever (@baccio, adversarial review; the same defect @rex
    # reproduced on the CLI side). An asymmetry between the two ends of a
    # lifecycle is not a missing convenience, it is a leak in the lifecycle.
    session = args.get("session")
    if session:
        argv += ["--session", _slug("session", session)]
    why = args.get("why")
    if why is not None:
        if not isinstance(why, str):
            raise ValueError("why: must be a string")
        argv += ["--why", why.replace("\n", " ").strip()]
    return _run_bus(argv)


def tool_bus_owed(args):
    repo = _slug("repo", args.get("repo"))
    as_role = _slug("as_role", args.get("as_role"))
    argv = ["owed", "--repo", repo, "--as", as_role]
    card = args.get("card")
    if card:
        argv += ["--card", _slug("card", card)]
    return _run_bus(argv)


def tool_bus_who(args):
    repo = _slug("repo", args.get("repo"))
    return _run_bus(["who", "--repo", repo])


TOOLS = {
    "bus_send": {
        "handler": tool_bus_send,
        "description": (
            "Append a message to an agent-to-agent thread on a kanban card. "
            "Carries text only: it starts nothing and changes no kanban state. "
            "Scope belongs to the card, so a body that reads as acceptance "
            "criteria is refused."
        ),
        "schema": {
            "type": "object",
            "properties": {
                "repo": {"type": "string", "description": "Repository slug, e.g. roberdan-os"},
                "card": {"type": "string", "description": "Kanban card id, e.g. 260727-171633"},
                "from_role": {"type": "string", "description": "Sending role, must exist in bus/roles/"},
                "to_role": {"type": "string", "description": f"Receiving role, or '{BROADCAST}' to broadcast"},
                "kind": {"type": "string", "enum": list(KINDS)},
                "body": {"type": "string", "description": "The message text"},
                "ref": {"type": "string", "description": "Optional citation: git:<sha> or kb:<card>. Required when the body claims a human approval."},
                "re": {"type": "integer", "description": "The number of the record this message answers. Citing it is what clears the question from bus_owed; without it the asker cannot tell an answer from silence.", "minimum": 1},
            },
            "required": ["repo", "card", "from_role", "to_role", "kind", "body"],
        },
    },
    "bus_read": {
        "handler": tool_bus_read,
        "description": "Read messages addressed to a role and ADVANCE its cursor, so each message is delivered once.",
        "schema": {
            "type": "object",
            "properties": {
                "repo": {"type": "string"},
                "card": {"type": "string"},
                "as_role": {"type": "string", "description": "Read as this role; its cursor advances"},
            },
            "required": ["repo", "card", "as_role"],
        },
    },
    "bus_peek": {
        "handler": tool_bus_peek,
        "description": "Same as bus_read but leaves the cursor where it is, so nothing is consumed.",
        "schema": {
            "type": "object",
            "properties": {
                "repo": {"type": "string"},
                "card": {"type": "string"},
                "as_role": {"type": "string"},
            },
            "required": ["repo", "card", "as_role"],
        },
    },
    "bus_log": {
        "handler": tool_bus_log,
        "description": "Read the whole thread, oldest first, without touching any cursor.",
        "schema": {
            "type": "object",
            "properties": {
                "repo": {"type": "string"},
                "card": {"type": "string"},
            },
            "required": ["repo", "card"],
        },
    },
    "bus_hello": {
        "handler": tool_bus_hello,
        "description": (
            "Announce this session on a repo, once, at the start: which role it plays, "
            "which card it is on, and what it is doing. Presence is an append-only "
            "record about the session itself — it delivers nothing, starts nothing, "
            "and gives the session no capability it did not already have."
        ),
        "schema": {
            "type": "object",
            "properties": {
                "repo": {"type": "string", "description": "Repository slug, e.g. roberdan-os"},
                "as_role": {"type": "string", "description": "The role this session plays, must exist in bus/roles/"},
                "session": {"type": "string", "description": "A unique name for this session. Omitted, one is generated."},
                "card": {"type": "string", "description": "Optional kanban card id this session is working"},
                "doing": {"type": "string", "description": "One line: what this session is doing"},
            },
            "required": ["repo", "as_role"],
        },
    },
    "bus_bye": {
        "handler": tool_bus_bye,
        "description": (
            "Declare this session finished, so whoever arrives next does not address "
            "an agent that is gone. It reports anything addressed to this role that "
            "was never answered, and never blocks."
        ),
        "schema": {
            "type": "object",
            "properties": {
                "repo": {"type": "string"},
                "as_role": {"type": "string"},
                "session": {"type": "string", "description": "The SAME name passed to bus_hello. Without it the goodbye lands on a different session and this one is never withdrawn."},
                "why": {"type": "string", "description": "One line: why this session is stopping"},
            },
            "required": ["repo", "as_role"],
        },
    },
    "bus_owed": {
        "handler": tool_bus_owed,
        "description": (
            "List the questions and requests addressed to a role that no message of "
            "that role cites. A question read once used to vanish behind the cursor; "
            "this is what survives it. Answer by sending with 're' set to its number."
        ),
        "schema": {
            "type": "object",
            "properties": {
                "repo": {"type": "string"},
                "as_role": {"type": "string", "description": "Whose unanswered mail to list"},
                "card": {"type": "string", "description": "Optional: only this card"},
            },
            "required": ["repo", "as_role"],
        },
    },
    "bus_who": {
        "handler": tool_bus_who,
        "description": (
            "Who else is working this repo: OBSERVED activity (an append or a read is "
            "the evidence) and DECLARED presence (what a session said about itself). "
            "The two are printed separately and never merged — a session that was "
            "killed cannot retract what it declared."
        ),
        "schema": {
            "type": "object",
            "properties": {
                "repo": {"type": "string"},
            },
            "required": ["repo"],
        },
    },
}


def _result(request_id, payload):
    return {"jsonrpc": "2.0", "id": request_id, "result": payload}


def _error(request_id, code, message):
    return {"jsonrpc": "2.0", "id": request_id, "error": {"code": code, "message": message}}


def handle(request):
    method = request.get("method")
    request_id = request.get("id")
    params = request.get("params") or {}

    if method == "initialize":
        return _result(request_id, {
            "protocolVersion": PROTOCOL_VERSION,
            "capabilities": {"tools": {}},
            "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
        })

    if method in ("notifications/initialized", "initialized"):
        return None  # notification: no reply

    if method == "tools/list":
        return _result(request_id, {
            "tools": [
                {"name": name, "description": spec["description"], "inputSchema": spec["schema"]}
                for name, spec in TOOLS.items()
            ]
        })

    if method == "tools/call":
        name = params.get("name")
        spec = TOOLS.get(name)
        if spec is None:
            # The registry is CLOSED: an unknown name is refused rather than
            # interpreted. This is the property the whole file exists for.
            return _error(request_id, -32602, f"unknown tool: {name!r}")
        try:
            output = spec["handler"](params.get("arguments") or {})
        except ToolError as exc:
            return _result(request_id, {
                "content": [{"type": "text", "text": str(exc)}],
                "isError": True,
            })
        except Exception as exc:  # noqa: BLE001 - a crash here kills the session
            return _result(request_id, {
                "content": [{"type": "text", "text": f"bus tool failed: {exc.__class__.__name__}"}],
                "isError": True,
            })
        return _result(request_id, {"content": [{"type": "text", "text": output}]})

    if request_id is None:
        return None  # unknown notification: ignore
    return _error(request_id, -32601, f"method not found: {method}")


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            request = json.loads(line)
        except json.JSONDecodeError:
            sys.stdout.write(json.dumps(_error(None, -32700, "parse error")) + "\n")
            sys.stdout.flush()
            continue
        response = handle(request)
        if response is not None:
            sys.stdout.write(json.dumps(response) + "\n")
            sys.stdout.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
