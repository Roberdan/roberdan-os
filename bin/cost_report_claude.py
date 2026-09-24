"""cost_report_claude.py — read Claude Code transcripts (~/.claude/projects/*/*.jsonl) for one
time window. Read-only: opens files, never writes.

No USD, no premium-request count and no per-call duration: the transcript records tokens and a
timestamp per assistant message, nothing about price or wall-clock spent generating it. Every
number this module cannot derive is simply absent from its dict — the caller prints "non
disponibile" for it, never a fabricated zero.

Two things the naive "glob *.jsonl and count usage" approach gets wrong, both confirmed by hand
against the real transcripts on 2026-09-24 (see the card's advisor review):
  1. Duplicate usage: one assistant TURN can be split across several JSONL LINES (one per content
     block — e.g. a thinking block and a tool_use block), and each line repeats the SAME
     message.usage. Counting lines double- (or triple-) counts tokens. Fix: dedupe globally by
     message.id (a resumed/forked session can copy the same message.id into a second file, so the
     dedupe set is global, not per-file).
  2. Sub-agent transcripts do not live inline in the parent file with isSidechain:true — they live
     in a SEPARATE file one level deeper, under <project>/<session-id>/subagents/*.jsonl. A glob
     of only *.jsonl at the project root therefore reports zero sub-agent share even when
     sub-agents ran. Fix: also read <project>/*/subagents/*.jsonl, tagged as sub-agent activity.
"""
from datetime import datetime, timezone
import json
from pathlib import Path
import re

_WT_RE = re.compile(r"/worktrees/([^/]+)/")
_GH_RE = re.compile(r"/GitHub/([^/]+)")


def _repo_from_cwd(cwd):
    if not cwd:
        return None
    m = _WT_RE.search(cwd)
    if m:
        return m.group(1)
    m = _GH_RE.search(cwd)
    if m and m.group(1) != "worktrees":
        return m.group(1)
    return None


def _parse_ts(s):
    if not s:
        return None
    try:
        return datetime.strptime(s[:19], "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc).timestamp()
    except ValueError:
        return None


def _empty_model():
    return {
        "calls": 0, "tokens_in": 0, "tokens_out": 0,
        "tokens_cache_read": 0, "tokens_cache_create": 0,
        "subagent_calls": 0, "subagent_tokens": 0,
    }


def _files(projects_dir):
    for proj in sorted(projects_dir.iterdir()):
        if not proj.is_dir():
            continue
        for f in sorted(proj.glob("*.jsonl")):
            yield f, False
        # Sub-agent transcripts live one level DEEPER than the project dir, under a directory
        # named after the session id: <project>/<session-id>/subagents/*.jsonl (verified on disk
        # 2026-09-24 — NOT <project>/subagents/, which is always empty).
        for f in sorted(proj.glob("*/subagents/*.jsonl")):
            yield f, True


def collect(root, since_epoch, until_epoch):
    projects_dir = Path(root)
    if not projects_dir.is_dir():
        return {"available": False, "reason": "non disponibile: cartella assente (%s)" % root}

    # Phase 1: one candidate record per message.id, keeping the LARGEST usage seen for it — a
    # duplicate line's usage is not always identical to the first (measured on the real
    # transcripts: ~0.16% of ids vary across their repeated lines, output_tokens growing as the
    # stream progresses). Records with no id (rare) get a unique per-line key instead.
    candidates = {}
    n_anon = 0
    for f, is_sub in _files(projects_dir):
        try:
            if f.stat().st_mtime < since_epoch:
                continue  # the file's last write is older than the window: every line is too
        except OSError:
            continue
        try:
            fh = f.open(encoding="utf-8", errors="replace")
        except OSError:
            continue
        with fh:
            for line in fh:
                try:
                    o = json.loads(line)
                except (json.JSONDecodeError, ValueError):
                    continue
                if o.get("type") != "assistant":
                    continue
                msg = o.get("message") or {}
                model = msg.get("model")
                if not model or model == "<synthetic>":
                    continue
                epoch = _parse_ts(o.get("timestamp"))
                if epoch is None or not (since_epoch <= epoch < until_epoch):
                    continue
                usage = msg.get("usage") or {}
                tin = usage.get("input_tokens", 0) or 0
                tout = usage.get("output_tokens", 0) or 0
                tcr = usage.get("cache_read_input_tokens", 0) or 0
                tcc = usage.get("cache_creation_input_tokens", 0) or 0
                tot = tin + tout + tcr + tcc
                mid = msg.get("id")
                if not mid:
                    n_anon += 1
                    mid = "__anon_%d" % n_anon
                prev = candidates.get(mid)
                if prev is None or tot > prev[0]:
                    candidates[mid] = (tot, model, tin, tout, tcr, tcc, is_sub, o.get("cwd"))

    models = {}
    tokens_total = 0
    subagent_tokens_total = 0
    repo_tokens = {}
    for tot, model, tin, tout, tcr, tcc, is_sub, cwd in candidates.values():
        m = models.setdefault(model, _empty_model())
        m["calls"] += 1
        m["tokens_in"] += tin
        m["tokens_out"] += tout
        m["tokens_cache_read"] += tcr
        m["tokens_cache_create"] += tcc
        tokens_total += tot
        if is_sub:
            m["subagent_calls"] += 1
            m["subagent_tokens"] += tot
            subagent_tokens_total += tot
        repo = _repo_from_cwd(cwd)
        if repo:
            repo_tokens[repo] = repo_tokens.get(repo, 0) + tot

    top_repos = sorted(repo_tokens.items(), key=lambda kv: kv[1], reverse=True)[:5]
    return {
        "available": True,
        "models": models,
        "tokens_total": tokens_total,
        "subagent_tokens_total": subagent_tokens_total,
        "top_repos": top_repos,
    }
