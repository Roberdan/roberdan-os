import json
import os
from pathlib import Path
import stat
from unittest import mock

from test_jev_support import FAKE_KEY, Fixture, client, core, profiles, reply, sample
from jevlib.private import credential


class SecurityTests(Fixture):
    def test_dry_run_never_opens_private_area_with_or_without_key(self):
        path = self.input_file("wanda")
        with mock.patch.object(client, "Area", side_effect=OSError("must stay unopened")) as area:
            with mock.patch.object(client, "credential") as secret:
                with mock.patch.object(client, "transport") as network:
                    for present in (True, False):
                        if not present:
                            self.env.pop("TYPESAFE_API_KEY")
                        code, result = self.invoke(["evaluate", "wanda", "--input", str(path)])
                        self.assertEqual((code, result["status"]), (0, "dry_run"))
                    area.assert_not_called()
                    secret.assert_not_called()
                    network.assert_not_called()
        self.assertFalse((self.home / ".roberdan-os").exists())

    def test_missing_and_disabled_config_make_zero_calls(self):
        with mock.patch.object(client, "transport") as network:
            with mock.patch.object(client, "credential", side_effect=AssertionError("read")):
                with self.assertRaisesRegex(core.JevError, "missing_config"):
                    self.live()
                self.configure(enabled_profiles=[])
                with self.assertRaisesRegex(core.JevError, "profile_disabled"):
                    self.live()
            network.assert_not_called()
        self.assertFalse((self.area / "state.json").exists())
        self.assertFalse((self.area / "lock").exists())

    def test_hash_required_and_bound_to_exact_payload_before_credential_load(self):
        self.configure()
        data = sample("wanda")
        for approved in (None, "wrong", "a" * 64):
            with mock.patch.object(client, "credential", side_effect=AssertionError("read")):
                with self.assertRaisesRegex(core.JevError, "payload_not_approved"):
                    client.evaluate("wanda", data, live=True, approved_sha256=approved,
                                    home=self.home, environ=self.env)
        approved = profiles.prepare("wanda", data)["sha256"]
        data["items"][0]["text"] += " Changed."
        with self.assertRaisesRegex(core.JevError, "payload_not_approved"):
            client.evaluate("wanda", data, live=True, approved_sha256=approved)
        with self.assertRaisesRegex(core.JevError, "approval_requires_live"):
            client.evaluate("wanda", data, approved_sha256=approved)

    def test_config_schema_rejects_unknown_bool_nan_infinite_and_blank(self):
        cases = [
            {"max_requests": True}, {"max_requests": 0}, {"max_requests": 1.5},
            {"budget_usd": True}, {"budget_usd": float("nan")},
            {"budget_usd": float("inf")}, {"budget_usd": -1},
            {"budget_usd": 10**1000}, {"budget_usd": 1e-20},
            {"approval": " "}, {"approval": 4}, {"approval": "\ud800"},
            {"enabled_profiles": ["other"]},
            {"enabled_profiles": ["twin", "twin"]}, {"enabled_profiles": "twin"},
            {"extra": "not allowed"},
        ]
        initial = dict(self.settings)
        with mock.patch.object(client, "transport") as network:
            for changes in cases:
                self.settings = dict(initial)
                self.configure(**changes)
                with self.subTest(changes=changes):
                    with self.assertRaisesRegex(core.JevError, "invalid_config"):
                        self.live()
            network.assert_not_called()

    def test_config_file_and_directory_permissions(self):
        self.configure()
        for path, unsafe, secure in ((self.area / "config.json", 0o644, 0o600),
                                     (self.area, 0o755, 0o700),
                                     (self.area.parent, 0o755, 0o700)):
            path.chmod(unsafe)
            with mock.patch.object(client, "transport", side_effect=reply) as network:
                with self.assertRaisesRegex(core.JevError, "unsafe_private_permissions"):
                    self.live()
                network.assert_not_called()
            path.chmod(secure)

    def test_symlink_and_hardlink_rejected(self):
        self.configure()
        config = self.area / "config.json"
        real = self.home / "saved-config"
        config.rename(real)
        config.symlink_to(real)
        with self.assertRaises(OSError):
            self.live()
        config.unlink()
        os.link(real, config)
        with self.assertRaisesRegex(core.JevError, "unsafe_private_path"):
            self.live()
        config.unlink()
        real.rename(config)
        self.area.rename(self.area.with_name("real-jev"))
        self.area.symlink_to("real-jev")
        with self.assertRaisesRegex(core.JevError, "unsafe_private_path"):
            self.live()

    def test_home_symlink_and_git_ancestor_rejected(self):
        self.configure()
        linked = self.home / "alias"
        linked.symlink_to(self.home, target_is_directory=True)
        with self.assertRaisesRegex(core.JevError, "unsafe_private_path"):
            client.status(home=linked)
        (self.home / ".git").write_text("gitdir: synthetic")
        with self.assertRaisesRegex(core.JevError, "private_path_in_git"):
            self.live()

    def test_bare_git_directory_rejected(self):
        self.configure()
        (self.home / "HEAD").write_text("ref: refs/heads/synthetic")
        (self.home / "objects").mkdir()
        (self.home / "refs").mkdir()
        with self.assertRaisesRegex(core.JevError, "private_path_in_git"):
            self.live()

    def test_wrong_owner_is_rejected(self):
        self.configure()
        with mock.patch("jevlib.private.os.getuid", return_value=os.getuid() + 1):
            with self.assertRaisesRegex(core.JevError, "unsafe_private_path"):
                self.live()

    def test_strict_credential_parser_and_env_priority(self):
        path = self.area.parent / "credentials/typesafe.env"
        self.write_private(path, f"# test only\nTYPESAFE_API_KEY='{FAKE_KEY}'\n")
        self.assertEqual(credential(self.home, {}), FAKE_KEY)
        path.chmod(0o644)
        self.assertEqual(credential(self.home, self.env), FAKE_KEY)
        with self.assertRaisesRegex(core.JevError, "unsafe_private_permissions"):
            credential(self.home, {})
        cases = [f"export TYPESAFE_API_KEY={FAKE_KEY}",
                 f"TYPESAFE_API_KEY={FAKE_KEY}\nOTHER=bad",
                 f"TYPESAFE_API_KEY={FAKE_KEY}\nTYPESAFE_API_KEY={FAKE_KEY}",
                 "TYPESAFE_API_KEY=$(touch marker)",
                 "TYPESAFE_API_KEY=`touch marker`",
                 'TYPESAFE_API_KEY="value with spaces"', "TYPESAFE_API_KEY="]
        for content in cases:
            self.write_private(path, content)
            with self.subTest(content=content), self.assertRaises(core.JevError):
                credential(self.home, {})
        self.assertFalse((Path.cwd() / "marker").exists())

    def test_credential_symlink_and_missing_are_rejected(self):
        with self.assertRaisesRegex(core.JevError, "missing_credential"):
            credential(self.home, {})
        path = self.area.parent / "credentials/typesafe.env"
        self.write_private(path, f"TYPESAFE_API_KEY={FAKE_KEY}")
        real = self.home / "synthetic-credential"
        path.rename(real)
        path.symlink_to(real)
        with self.assertRaises(OSError):
            credential(self.home, {})

    def test_status_never_loads_key_or_echoes_approval(self):
        self.configure()
        with mock.patch.object(client, "credential", side_effect=AssertionError("read")):
            code, output = self.invoke(["status"])
        self.assertEqual(code, 0)
        self.assertEqual(output["enabled_profiles"], list(core.PROFILES))
        self.assertEqual(output["consumption"]["requests"], 0)
        self.assertNotIn(FAKE_KEY, json.dumps(output))
        self.assertNotIn(self.settings["approval"], json.dumps(output))
        self.assertFalse((self.area / "lock").exists())

    def test_persisted_cache_contains_only_hash_typed_numbers_and_registry_ids(self):
        self.configure()
        with mock.patch.object(client, "transport", side_effect=reply):
            result = self.live("twin")
        raw = (self.area / "state.json").read_text()
        self.assertNotIn(FAKE_KEY, raw)
        self.assertNotIn(sample("twin")["situation"], raw)
        self.assertNotIn("legend", raw)
        self.assertNotIn("model", raw)
        self.assertNotIn("uno", raw)
        self.assertNotIn(self.settings["approval"], raw)
        self.assertEqual(result["consumption"]["requests"], 1)
        for name in ("state.json", "lock", "config.json"):
            self.assertEqual(stat.S_IMODE((self.area / name).stat().st_mode), 0o600)
        self.assertEqual(list(self.area.glob(".jev-*.tmp")), [])

    def test_cli_errors_are_json_and_never_print_payload_or_exception_body(self):
        self.configure()
        path = self.input_file("wanda")
        approval = profiles.prepare("wanda", sample("wanda"))["sha256"]
        with mock.patch.object(client, "transport", side_effect=OSError("secret-body-" + FAKE_KEY)):
            code, result = self.invoke(["evaluate", "wanda", "--input", str(path),
                                       "--live", "--approved-sha256", approval])
        self.assertEqual(code, 2)
        self.assertEqual(result, core.not_evaluated("local_io_error"))
        self.assertNotIn(FAKE_KEY, json.dumps(result))
        self.assertEqual(self.state()["uncertain_requests"], 1)
        code, result = self.invoke(["evaluate", "secret-body-" + FAKE_KEY])
        self.assertEqual((code, result["reason"]), (2, "invalid_arguments"))

    def test_duplicate_keys_and_invalid_json_are_rejected(self):
        path = self.input_file("wanda")
        for raw in ('{"classification":"public","classification":"synthetic"}',
                    '{"classification":NaN}', "{bad", "[" * 2000):
            path.write_text(raw)
            code, result = self.invoke(["evaluate", "wanda", "--input", str(path)])
            self.assertEqual((code, result["reason"]), (2, "invalid_json"))
        path.write_text(" " * (core.MAX_INPUT_BYTES + 1))
        self.assertEqual(self.invoke(["evaluate", "wanda", "--input", str(path)])[1]["reason"],
                         "input_too_large")
