"""cost_report_copilot.py — read ~/.copilot/session-store.db (read-only) for one time window.

Read-only sqlite3 (file:...?mode=ro): this process never writes to the store. Degrades to
{"available": False, "reason": ...} instead of raising, so a missing/locked/corrupt store never
crashes the caller — bin/cost-report.sh must print "non disponibile", not a traceback.

Definitions (verified against the real store 2026-09-24, see docs/plan-2026-09-24-ottimizzazione.md
§ 1 and the card's advisor review):
  - list-equivalent USD  = SUM(total_nano_aiu) / 1e11  (verified by hand on one row).
  - premium requests     = SUM(request_multiplier) WHERE initiator='user'. Only a user-initiated
    call consumes the premium-request budget; 'agent'/'sub-agent'/'compaction' rows do not.
  - sub-agent            = initiator='sub-agent' (the store's own vocabulary — confirmed distinct
    from 'user'/'agent'/'compaction').
  - avg context/call     = avg(input_tokens). Verified cache_read_tokens <= input_tokens on every
    row in the store, so input_tokens already IS the full prompt size (cache-read is a subset of
    it, not additional) — averaging it separately would double-count.
  - top-5 repos by spend = sessions.repository (already "org/repo", not a worktree path), joined
    on session_id. Rows with no repository are counted in totals but excluded from the ranking.
"""
from pathlib import Path
import sqlite3


def _connect(db_path):
    p = Path(db_path)
    if not p.exists():
        return None, "non disponibile: file assente (%s)" % db_path
    try:
        conn = sqlite3.connect(p.resolve().as_uri() + "?mode=ro", uri=True, timeout=5)
        conn.execute("SELECT 1 FROM assistant_usage_events LIMIT 1")
        return conn, None
    except sqlite3.Error as exc:
        return None, "non disponibile: errore di lettura SQLite (%s)" % exc


def _empty_model():
    return {
        "calls": 0, "usd": 0.0, "premium": 0.0,
        "tokens_in": 0, "tokens_out": 0, "tokens_cache_read": 0, "tokens_cache_write": 0,
        "duration_ms_sum": 0, "duration_calls": 0,
        "subagent_calls": 0, "subagent_usd": 0.0,
    }


def collect(db_path, since_iso, until_iso):
    """One window's Copilot usage, keyed by model. since/until are ISO 'YYYY-MM-DDTHH:MM:SS.000Z'
    (matches assistant_usage_events.created_at's own format — verified against the live store)."""
    conn, reason = _connect(db_path)
    if conn is None:
        return {"available": False, "reason": reason}
    try:
        rows = conn.execute(
            "SELECT e.model, e.initiator, e.request_multiplier, e.total_nano_aiu, "
            "       e.input_tokens, e.output_tokens, e.cache_read_tokens, e.cache_write_tokens, "
            "       e.duration_ms, s.repository "
            "FROM assistant_usage_events e LEFT JOIN sessions s ON e.session_id = s.id "
            "WHERE e.created_at >= ? AND e.created_at < ?",
            (since_iso, until_iso),
        ).fetchall()
    except sqlite3.Error as exc:
        return {"available": False, "reason": "non disponibile: interrogazione fallita (%s)" % exc}
    finally:
        conn.close()

    models = {}
    usd_total = 0.0
    subagent_usd_total = 0.0
    repo_usd = {}
    for model, initiator, mult, nano, tin, tout, tcr, tcw, dur, repo in rows:
        model = model or "(sconosciuto)"
        m = models.setdefault(model, _empty_model())
        usd = (nano or 0) / 1e11
        m["calls"] += 1
        m["usd"] += usd
        usd_total += usd
        if initiator == "user":
            m["premium"] += mult or 0.0
        m["tokens_in"] += tin or 0
        m["tokens_out"] += tout or 0
        m["tokens_cache_read"] += tcr or 0
        m["tokens_cache_write"] += tcw or 0
        if dur is not None:
            m["duration_ms_sum"] += dur
            m["duration_calls"] += 1
        if initiator == "sub-agent":
            m["subagent_calls"] += 1
            m["subagent_usd"] += usd
            subagent_usd_total += usd
        if repo:
            repo_usd[repo] = repo_usd.get(repo, 0.0) + usd

    top_repos = sorted(repo_usd.items(), key=lambda kv: kv[1], reverse=True)[:5]
    return {
        "available": True,
        "models": models,
        "usd_total": usd_total,
        "subagent_usd_total": subagent_usd_total,
        "top_repos": top_repos,
        "calls_total": len(rows),
    }
