"""Synthetic fixtures only. No remote calls or reads of real private state."""

import contextlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "bin"))

from jevlib import cli, client, core, ledger, profiles  # noqa: E402

FAKE_KEY = "-".join(("test", "only", "not", "a", "real", "credential"))


def sample(profile):
    if profile == "twin":
        return {"classification": "synthetic", "situation": "Una scelta per la comunit\u00e0.",
                "options": [{"id": "uno", "text": "Piccolo incontro accessibile.", "eligible": True},
                            {"id": "due", "text": "EXCLUDED_LOCAL_TEXT", "eligible": False}]}
    if profile == "retrieval":
        return {"classification": "synthetic", "query": "Accessibilit\u00e0 a scuola?",
                "candidates": [
                    {"id": "uno", "text": "Prima proposta.", "exact_match": False},
                    {"id": "due", "text": "Corrispondenza esatta.", "exact_match": True},
                    {"id": "tre", "text": "Seconda corrispondenza.", "exact_match": True},
                    {"id": "quattro", "text": "Ultima proposta.", "exact_match": False}]}
    if profile == "wanda":
        return {"classification": "synthetic",
                "items": [{"id": "uno", "text": "Serve una decisione per proseguire."}]}
    return {"classification": "synthetic", "criteria_recorded": True,
            "requirements": [{"id": "uno", "text": "Il pulsante ha un nome accessibile."},
                             {"id": "due", "text": "La pagina funziona da tastiera."}],
            "evidence": [{"id": "prova", "text": "Nome del pulsante osservato.",
                          "requirement_ids": ["uno"]}]}


def reply(payload, key=FAKE_KEY, input_tokens=100):
    answers = {}
    for ident, question in payload["questions"].items():
        kind = question["type"]
        if kind == "score":
            levels = question["criteria"]
            answers[ident] = {"score": 2, "confidence": 0.7,
                              "probabilities": {"0": 0.1, "1": 0.1, "2": 0.7, "3": 0.1},
                              "legend": {str(i): v for i, v in enumerate(levels)}}
        elif kind == "choice":
            answers[ident] = {"choice": "decision_needed", "confidence": 1.0,
                              "probabilities": {k: float(k == "decision_needed")
                                                for k in question["criteria"]}}
        else:
            answers[ident] = {"noul": 1.0}
        answers[ident]["type"] = kind
    return {"model": payload["model"], "answers": answers,
            "usage": {"input_tokens": input_tokens, "output_tokens": 20}}


class Fixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="jev-test-")
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name).resolve()
        self.env = {"HOME": str(self.home), "TYPESAFE_API_KEY": FAKE_KEY,
                    "PYTHONDONTWRITEBYTECODE": "1"}
        self.area = self.home / ".roberdan-os/private/jev"
        self.settings = {"enabled_profiles": list(core.PROFILES), "max_requests": 50,
                         "budget_usd": 1, "approval": "synthetic fixture approval"}

    def write_private(self, path, value):
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        for parent in (path.parent, *path.parent.parents):
            if parent == self.home:
                break
            parent.chmod(0o700)
        path.write_text(value if isinstance(value, str) else json.dumps(value), encoding="utf-8")
        path.chmod(0o600)

    def configure(self, **changes):
        self.settings.update(changes)
        self.write_private(self.area / "config.json", self.settings)

    def live(self, profile="wanda", data=None, **kwargs):
        data = sample(profile) if data is None else data
        approval = profiles.prepare(profile, data)["sha256"]
        return client.evaluate(profile, data, live=True, approved_sha256=approval,
                               home=self.home, environ=self.env, **kwargs)

    def state(self):
        return json.loads((self.area / "state.json").read_text())

    def invoke(self, args):
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.dict(os.environ, self.env, clear=True):
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                code = cli.main(args)
        self.assertEqual(err.getvalue(), "")
        return code, json.loads(out.getvalue())

    def input_file(self, profile, data=None):
        path = self.home / f"{profile}.json"
        path.write_text(json.dumps(sample(profile) if data is None else data), encoding="utf-8")
        return path
