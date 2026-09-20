#!/usr/bin/env python3
"""Local-only active-repository refresh, or explicitly source-scoped embeddings."""
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


def embed_until_done(job, source, env, binary, *, passes=12):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", source):
        raise RuntimeError("Serve un identificatore di fonte esplicito e valido.")
    previous, stalls = None, 0
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
        if missing == 0:
            return
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
        if installed is None or installed.strip() != "a6be012a3bcfac42e279630aedec5cda4a450e29" or dirty != "":
            raise RuntimeError("Versione gbrain non ancora validata per questa manutenzione; nessuna modifica.")
        config = dependencies.configuration(job)
        with dependencies.ollama_for_operation(job, config, needed=True) as env:
            host = dependencies.local_url(config["ollama_url"]).hostname
            env["NO_PROXY"] = ",".join(filter(None, [env.get("NO_PROXY"), "localhost",
                                                    "127.0.0.1", "::1", host]))
            if args.embed_source:
                if args.embed_source not in {source["id"] for source in recovery.sources()}:
                    raise RuntimeError("La fonte richiesta non esiste: " + args.embed_source)
                embed_until_done(job, args.embed_source, env, recovery.GB)
                job.row("ESEGUITO", args.embed_source, "Zero parti ancora da indicizzare con il modello locale.")
            else:
                manifest, excluded = scoped_manifest(manifest, recovery.sources(), set(args.blocked_source))
                for path in excluded:
                    job.row("INVARIATO", "Fonti escluse",
                            Path(path).name + ": escluso dai permessi concessi; nessun contenuto letto.")

                class ManagedRecovery(recovery.Recovery):
                    def local_vectors(self, source):
                        embed_until_done(job, source, self.env, recovery.GB)

                runner = ManagedRecovery(manifest, args.state_dir, args.backup,
                                         args.blocked_source, args.active_root)
                runner.env.update(env)
                for key in ("DATABASE_URL", "GBRAIN_DATABASE_URL", "GBRAIN_SOURCE"):
                    runner.env.pop(key, None)
                result = runner.run()
                for record in recovery.plan(manifest):
                    row = runner.state["repos"].get(record["key"], {})
                    if row.get("status") == "verified":
                        job.row("ESEGUITO", Path(record["local_path"]).name,
                                "Memoria allineata alla versione Git attuale; zero parti da indicizzare.")
                    else:
                        job.row("ERRORE", Path(record["local_path"]).name,
                                row.get("error", "Recupero non completato."))
                if result and not any(row["state"] == "ERRORE" for row in job.rows):
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
