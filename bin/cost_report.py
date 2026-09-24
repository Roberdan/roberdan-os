#!/usr/bin/env python3
"""cost_report.py — costo/spesa per host+modello su una finestra, con la finestra precedente per
la freccia. Legge ~/.copilot/session-store.db (Copilot, read-only) e i transcript di Claude Code
(~/.claude/projects/*/*.jsonl). Non somma MAI le due fonti in un unico numero: Copilot ha un
prezzo (USD a listino), Claude Code no (models.sh: "questo repo non tiene dati di prezzo").

Uso: python3 cost_report.py [--days N] [--root ROOT] [--store PATH] [--projects PATH]
Stampa un referto in italiano su stdout, non scrive niente. Ogni riga di numeri dice la fonte.
"""
import argparse
from datetime import datetime, timedelta, timezone
import os
import subprocess
import sys

_ROOT_DEFAULT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, __file__.rsplit("/", 1)[0])
import cost_report_claude as claude_src   # noqa: E402
import cost_report_copilot as copilot_src  # noqa: E402

_class_cache = {}


def _model_class(model, root):
    """frontier|mid|cheap|unknown via bin/models.sh class — the one reviewed registry (README
    § Model selection). Unreviewed/unresolvable counts as frontier, same rule the registry uses
    for a caller that must pick a side (bin/lib-models.sh)."""
    if model in _class_cache:
        return _class_cache[model]
    try:
        out = subprocess.run(
            [os.path.join(root, "bin", "models.sh"), "class", model],
            capture_output=True, text=True, timeout=5,
        ).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        out = "unknown"
    cls = out if out in ("frontier", "mid", "cheap") else "unknown"
    _class_cache[model] = cls
    return cls


def _frontier_subagent_share_usd(cur, root):
    """Share of Copilot sub-agent SPEND that ran on a frontier (or unreviewed) model — the
    plan's finding #A: sub-agents defaulted to Astra, a frontier model, for no reviewed reason."""
    total = cur.get("subagent_usd_total", 0.0)
    if total <= 0:
        return None
    frontier = 0.0
    for model, m in cur.get("models", {}).items():
        if _model_class(model, root) in ("frontier", "unknown"):
            frontier += m.get("subagent_usd", 0.0)
    return frontier / total * 100


def _iso(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%S.000Z")


def _windows(days):
    now = datetime.now(timezone.utc)
    cur_since = now - timedelta(days=days)
    prev_since = now - timedelta(days=2 * days)
    return (cur_since, now), (prev_since, cur_since)


def _arrow(cur, prev):
    # No own parens: every caller wraps this in "(%s)" — see _fmt_copilot/_fmt_claude.
    if prev <= 0:
        return "non confrontabile: la finestra precedente e' vuota" if cur > 0 else ""
    delta = (cur - prev) / prev * 100
    if abs(delta) < 1:
        return "→ stabile"
    return "%s %.0f%%" % ("↑" if delta > 0 else "↓", abs(delta))


def _num(n):
    n = n or 0
    if n >= 1_000_000:
        return "%.1fM" % (n / 1_000_000)
    if n >= 1_000:
        return "%dk" % (n / 1_000)
    return str(int(n))


def _fmt_copilot(cur, prev):
    lines = []
    if not cur.get("available"):
        return ["  Copilot: %s" % cur.get("reason", "non disponibile")]
    lines.append("  Copilot — spesa a listino totale: $%.2f (%s) — %d chiamate" % (
        cur["usd_total"], _arrow(cur["usd_total"], prev.get("usd_total", 0) if prev.get("available") else 0),
        cur["calls_total"]))
    if cur["usd_total"] > 0:
        share = cur["subagent_usd_total"] / cur["usd_total"] * 100
        lines.append("  quota sotto-agenti sulla spesa: %.0f%%" % share)
    lines.append("  %-18s %10s %8s %10s %9s %9s %10s" % (
        "modello", "USD/list.", "chiam.", "premium", "s/chiam.", "contesto", "token tot"))
    prev_models = prev.get("models", {}) if prev.get("available") else {}
    for model, m in sorted(cur["models"].items(), key=lambda kv: kv[1]["usd"], reverse=True):
        pm = prev_models.get(model, {})
        sec = (m["duration_ms_sum"] / m["duration_calls"] / 1000) if m["duration_calls"] else None
        ctx = (m["tokens_in"] / m["calls"]) if m["calls"] else 0
        tot = m["tokens_in"] + m["tokens_out"] + m["tokens_cache_read"] + m["tokens_cache_write"]
        lines.append("  %-18s %10.2f %8d %10.1f %9s %9s %10s  %s" % (
            model, m["usd"], m["calls"], m["premium"],
            ("%.1f" % sec) if sec is not None else "-", _num(ctx), _num(tot),
            _arrow(m["usd"], pm.get("usd", 0))))
    if cur["top_repos"]:
        lines.append("  top 5 repo per spesa: " + ", ".join(
            "%s ($%.2f)" % (r, u) for r, u in cur["top_repos"]))
    return lines


def _fmt_claude(cur, prev):
    lines = []
    if not cur.get("available"):
        return ["  Claude Code: %s" % cur.get("reason", "non disponibile")]
    lines.append("  Claude Code — nessun prezzo nel repo (models.sh): solo token e chiamate")
    if cur["tokens_total"] > 0:
        share = cur["subagent_tokens_total"] / cur["tokens_total"] * 100
        lines.append("  quota sotto-agenti sui token: %.0f%%" % share)
    lines.append("  %-28s %8s %10s %9s %10s" % ("modello", "chiam.", "token tot", "contesto", "output"))
    prev_models = prev.get("models", {}) if prev.get("available") else {}
    for model, m in sorted(cur["models"].items(),
                            key=lambda kv: kv[1]["tokens_in"] + kv[1]["tokens_out"], reverse=True):
        pm = prev_models.get(model, {})
        ctx = (m["tokens_in"] + m["tokens_cache_read"] + m["tokens_cache_create"]) / m["calls"] if m["calls"] else 0
        tot = m["tokens_in"] + m["tokens_out"] + m["tokens_cache_read"] + m["tokens_cache_create"]
        ptot = pm.get("tokens_in", 0) + pm.get("tokens_out", 0) + pm.get("tokens_cache_read", 0) + pm.get("tokens_cache_create", 0)
        lines.append("  %-28s %8d %10s %9s %10s  %s" % (
            model, m["calls"], _num(tot), _num(ctx), _num(m["tokens_out"]), _arrow(tot, ptot)))
    lines.append("  s/chiamata: non disponibile (il transcript non registra la durata)")
    if cur["top_repos"]:
        lines.append("  top 5 repo per token: " + ", ".join(
            "%s (%s)" % (r, _num(t)) for r, t in cur["top_repos"]))
    return lines


def run(days, store, projects, root=_ROOT_DEFAULT):
    (cs, cu), (ps, pu) = _windows(days)
    cop_cur = copilot_src.collect(store, _iso(cs), _iso(cu))
    cop_prev = copilot_src.collect(store, _iso(ps), _iso(pu))
    cl_cur = claude_src.collect(projects, cs.timestamp(), cu.timestamp())
    cl_prev = claude_src.collect(projects, ps.timestamp(), pu.timestamp())

    out = ["COSTO — ultimi %d giorni (confronto con i %d precedenti)" % (days, days), ""]
    out += _fmt_copilot(cop_cur, cop_prev)
    frontier_share = None
    if cop_cur.get("available"):
        frontier_share = _frontier_subagent_share_usd(cop_cur, root)
        if frontier_share is not None:
            out.append("  quota sotto-agenti su modelli frontier (spesa): %.0f%%" % frontier_share)
    out.append("")
    out += _fmt_claude(cl_cur, cl_prev)
    print("\n".join(out))
    # Riga leggibile da una macchina (system-health.sh, i test): mai stampata come prosa.
    print("@@METRIC copilot_available %d" % (1 if cop_cur.get("available") else 0))
    print("@@METRIC claude_available %d" % (1 if cl_cur.get("available") else 0))
    if frontier_share is not None:
        print("@@METRIC subagent_frontier_share_pct %.1f" % frontier_share)
    return cop_cur, cl_cur


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=7)
    ap.add_argument("--store", default=None)
    ap.add_argument("--projects", default=None)
    ap.add_argument("--root", default=_ROOT_DEFAULT)
    args = ap.parse_args()
    if args.days < 1:
        print("cost-report: --days deve essere >= 1", file=sys.stderr)
        return 2
    store = args.store or os.path.expanduser("~/.copilot/session-store.db")
    projects = args.projects or os.path.expanduser("~/.claude/projects")
    run(args.days, store, projects, args.root)
    return 0


if __name__ == "__main__":
    sys.exit(main())
