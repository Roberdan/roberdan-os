#!/usr/bin/env python3
"""Local-only refresh: report measured sync/vector changes separately from no-op checks."""
import argparse
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import re
import signal
import sys
import time
from types import SimpleNamespace


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def scoped_manifest(manifest, registered, denied):
    excluded, local = [], []
    for item in manifest["local"]:
        matches = {s["id"] for s in registered if s.get("local_path") == item["path"]}
        if item.get("pin") in denied or matches.intersection(denied):
            excluded.append(item["path"])
        else:
            local.append(item)
    return {"local": local, "remote": []}, excluded


def recovery_outcome(error):
    policy_refusals = (
        "BLOCKED: source access not granted",
        "BLOCKED: existing source requires reconciliation",
        "BLOCKED: existing source needs a full/reconcile sync",
        "BLOCKED: preview contains deletions/renames",
        "BLOCKED: isolated",
        "BLOCKED: claimed source root",
    )
    return "RINVIATO" if error.startswith(policy_refusals) else "ERRORE"


def embed_until_done(job, source, env, binary, *, passes=12):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", source):
        raise RuntimeError("Serve un identificatore di fonte esplicito e valido.")
    previous, stalls, initial_missing = None, 0, None
    for attempt in range(passes + 1):
        preview = job.command("Verifica memorie " + source,
                              [binary, "embed", "--stale", "--source", source, "--dry-run"],
                              env=env, cwd=Path.home() / ".gbrain", timeout=180)
        if preview is None:
            raise RuntimeError("Impossibile misurare le parti ancora da indicizzare: " + source)
        match = re.search(r"Would embed (\d+) (?:stale )?chunks", preview)
        if not match:
            raise RuntimeError("Conteggio delle parti da indicizzare non riconoscibile: " + source)
        missing = int(match[1])
        if initial_missing is None:
            initial_missing = missing
        if missing == 0:
            return initial_missing
        stalls = stalls + 1 if missing == previous else 0
        if stalls >= 2:
            raise RuntimeError(f"{source}: nessun progresso per due passaggi; restano {missing} parti.")
        if attempt == passes:
            raise RuntimeError(f"{source}: limite di passaggi raggiunto; restano {missing} parti.")
        previous = missing
        if job.command("Indicizzazione locale " + source,
                       [binary, "embed", "--stale", "--source", source], change=True,
                       env=env, cwd=Path.home() / ".gbrain", timeout=1800) is None:
            raise RuntimeError("Indicizzazione locale fallita: " + source)


def verified_refresh_result(row, *, run_started=None):
    required = {"sync_changed", "indexed_before", "indexed_after"}
    if not required.issubset(row):
        return ("RINVIATO",
                "Ricevuta precedente senza misure prima/dopo; aggiornamento attuale non verificato.")
    if run_started is not None and (
            not isinstance(row.get("started"), (int, float)) or row["started"] < run_started):
        return ("RINVIATO",
                "Ricevuta di un recupero precedente; fonte non verificata in questo giro.")
    changed = row["sync_changed"] or (row.get("embedded_chunks") or 0) > 0
    detail = (f"Revisione indicizzata: {row['indexed_before'] or 'nessuna'} -> "
              f"{row['indexed_after']}; zero parti da indicizzare.")
    if changed:
        return "ESEGUITO", "Memoria aggiornata. " + detail
    return "INVARIATO", "Memoria gia allineata; nessun aggiornamento necessario. " + detail


def report_recovery_results(job, records, state):
    for record in records:
        row = state["repos"].get(record["key"], {})
        if row.get("status") == "verified":
            outcome, detail = verified_refresh_result(row, run_started=state["started"])
        else:
            detail = row.get("error", "Recupero non completato.")
            outcome = recovery_outcome(detail)
        job.row(outcome, Path(record["local_path"]).name, detail)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--active-root", type=Path, default=Path.home() / "GitHub")
    parser.add_argument("--backup", type=Path)
    parser.add_argument("--state-dir", type=Path,
                        default=Path.home() / ".roberdan-os/gbrain-recovery/active")
    parser.add_argument("--blocked-source", action="append", default=[])
    parser.add_argument("--embed-source")
    parser.add_argument("--plan", action="store_true")
    parser.add_argument("--require-ac", action="store_true")
    parser.add_argument("--result-file", type=Path)
    parser.add_argument("--full-sync-proofs", type=Path)
    args = parser.parse_args(argv)
    if not args.plan and not args.embed_source and args.backup is None:
        parser.error("Il recupero richiede --backup con una copia gia ripristinata e verificata.")
    if args.embed_source in args.blocked_source:
        parser.error("La fonte richiesta e esclusa dai permessi concessi.")
    if args.result_file and (args.result_file.exists() or not args.result_file.parent.is_dir()):
        parser.error("--result-file richiede un file nuovo in una cartella esistente.")
    os.umask(0o077)
    directory = Path(__file__).resolve().parent
    recovery = load("active_recovery", directory / "gbrain-recover-repos.py")
    audit = load("active_audit", directory / "gbrain-repo-audit.py")
    manifest = (recovery.active_manifest(args.active_root, audit.inspect)
                if not args.embed_source or args.plan else {"local": [], "remote": []})
    if args.plan:
        print(json.dumps(recovery.plan(manifest), indent=2))
        return 0
    scripts = Path.home() / ".claude/scripts"
    sys.path.insert(0, str(scripts))
    import buongiorno
    import buongiorno_gbrain as dependencies
    job = buongiorno.Maintenance(
        SimpleNamespace(check=False, plain=True, nightly=False, only=["memory"]),
        root=Path.home() / "Library/Logs/gbrain-refresh")
    lock = (job.root / "run.lock").open("a")

    def save_result():
        if args.result_file:
            with args.result_file.open("x") as output:
                json.dump(job.data(), output, indent=2)

    def finish():
        try:
            code = job.finish()
            save_result()
            return code
        finally:
            lock.close()

    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        job.row("RINVIATO", "Memorie", "Un'altra manutenzione delle memorie e gia in corso.")
        job.exit_code = 0
        job.finished = time.time()
        job.save()
        save_result()
        lock.close()
        print("RINVIATO: un'altra manutenzione delle memorie e gia in corso.", flush=True)
        return 0
    try:
        if args.require_ac:
            power = job.command("Alimentazione", ["/usr/bin/pmset", "-g", "ps"], timeout=10)
            if power is None:
                raise RuntimeError("Non riesco a verificare l'alimentazione.")
            if "AC Power" not in power:
                job.row("RINVIATO", "Memorie", "Computer a batteria: nessuna elaborazione avviata.")
                return finish()
        for key in ("DATABASE_URL", "GBRAIN_DATABASE_URL", "GBRAIN_SOURCE"):
            job.env.pop(key, None)
        # This runner's sync guarantees were exercised against this exact upstream revision.
        installed = job.command("Versione codice gbrain",
                                ["git", "-C", Path.home() / "gbrain", "rev-parse", "HEAD"])
        dirty = job.command("Modifiche codice gbrain",
                            ["git", "-C", Path.home() / "gbrain", "status", "--porcelain"])
        reviewed = {"a6be012a3bcfac42e279630aedec5cda4a450e29",
                    "668b9bac302705f3bca0ae4792a49fab0a79a74e",
                    "d13aa742fd68b71bfd6c98be3dda5813791f1d6c",
                    # v0.54.1.1, reviewed 2026-09-24 after pg_dump backup + migrations + doctor.
                    "31f257a0a7b218b40e03d302bc6913c99f26f0ec"}
        if installed is None or installed.strip() not in reviewed or dirty != "":
            raise RuntimeError("Versione gbrain non ancora validata per questa manutenzione; nessuna modifica.")
        config = dependencies.configuration(job)
        with dependencies.ollama_for_operation(job, config, needed=True) as env:
            host = dependencies.local_url(config["ollama_url"]).hostname
            env["NO_PROXY"] = ",".join(filter(None, [env.get("NO_PROXY"), "localhost",
                                                    "127.0.0.1", "::1", host]))
            if args.embed_source:
                if args.embed_source not in {source["id"] for source in recovery.sources()}:
                    raise RuntimeError("La fonte richiesta non esiste: " + args.embed_source)
                embedded = embed_until_done(job, args.embed_source, env, recovery.GB)
                job.row("ESEGUITO" if embedded else "INVARIATO", args.embed_source,
                        f"Parti indicizzate: {embedded}; zero parti ancora da indicizzare con il modello locale.")
            else:
                manifest, excluded = scoped_manifest(manifest, recovery.sources(), set(args.blocked_source))
                for path in excluded:
                    job.row("INVARIATO", "Fonti escluse",
                            Path(path).name + ": escluso dai permessi concessi; nessun contenuto letto.")

                class ManagedRecovery(recovery.Recovery):
                    def local_vectors(self, source):
                        return embed_until_done(job, source, self.env, recovery.GB)

                runner = ManagedRecovery(manifest, args.state_dir, args.backup,
                                         args.blocked_source, args.active_root,
                                         full_sync_proofs=args.full_sync_proofs)
                runner.env.update(env)
                for key in ("DATABASE_URL", "GBRAIN_DATABASE_URL", "GBRAIN_SOURCE"):
                    runner.env.pop(key, None)
                result = runner.run()
                report_recovery_results(job, recovery.plan(manifest), runner.state)
                if result and not any(row["state"] in ("ERRORE", "RINVIATO") for row in job.rows):
                    raise RuntimeError("Il recupero non ha confermato il completamento.")
    except BlockingIOError:
        job.row("RINVIATO", "Memorie", "Un altro recupero detiene il blocco; nessun lavoro duplicato.")
    except (dependencies.Deferred, dependencies.Failed, OSError, ValueError, KeyError, RuntimeError) as exc:
        job.row("ERRORE", "Memorie", str(exc))
    except KeyboardInterrupt:
        job.row("ERRORE", "Memorie", "Interrotto; stato parziale e registri conservati.")
    return finish()


if __name__ == "__main__":
    def terminate(_signum, _frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, terminate)
    sys.exit(main())
