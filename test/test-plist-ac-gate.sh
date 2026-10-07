#!/usr/bin/env bash
# test-plist-ac-gate.sh — ogni LaunchAgent spedito dal repo parte SOLO a corrente (batteria = priorità 1).
# Controlla che ProgramArguments inizi con il gate pmset (fail-closed) e che il gate si comporti davvero.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$ROOT" <<'PY'
import glob, plistlib, subprocess, sys, os, tempfile
root = sys.argv[1]
GATE = '''/usr/bin/pmset -g ps 2>/dev/null | head -1 | grep -q "'AC Power'" || exit 0; exec "$0" "$@"'''
plists = sorted(glob.glob(f"{root}/scheduling/*.plist") + glob.glob(f"{root}/*/com.roberdan.*.plist"))
plists = sorted(set(plists))
fail = 0
if not plists:
    print("FAIL: no plists found"); sys.exit(1)
for p in plists:
    a = plistlib.load(open(p, "rb")).get("ProgramArguments", [])
    ok = a[:3] == ["/bin/sh", "-c", GATE] and len(a) > 3
    print(("ok   " if ok else "FAIL ") + os.path.relpath(p, root))
    fail += not ok
# behavioural: gate with a fake pmset must run on AC, skip on battery/error
gate_for = lambda ps: GATE.replace("/usr/bin/pmset", ps)
d = tempfile.mkdtemp()
def fake(name, body):
    f = f"{d}/{name}"; open(f, "w").write("#!/bin/sh\n" + body); os.chmod(f, 0o755); return f
cases = {"ac": ("echo \"Now drawing from 'AC Power'\"", True),
         "batt": ("echo \"Now drawing from 'Battery Power'\"", False),
         "ups": ("echo \"Now drawing from 'UPS Power'\"", False),
         "err": ("exit 1", False)}
for n, (body, runs) in cases.items():
    r = subprocess.run(["/bin/sh", "-c", gate_for(fake("pm_" + n, body)), "/bin/echo", "RAN"], capture_output=True, text=True)
    ok = (r.stdout.strip() == "RAN") == runs and r.returncode == 0
    print(("ok   " if ok else "FAIL ") + f"behaviour {n}"); fail += not ok
sys.exit(1 if fail else 0)
PY
rc=$?; [ $rc -eq 0 ] && echo "test-plist-ac-gate: PASS" || echo "test-plist-ac-gate: FAIL"; exit $rc
