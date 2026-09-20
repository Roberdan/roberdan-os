from unittest import mock

from test_jev_support import Fixture, client, core, profiles, sample


COLLECTIONS = (("twin", "options"), ("retrieval", "candidates"), ("wanda", "items"),
               ("thor", "requirements"), ("thor", "evidence"), ("thor", "requirement_ids"))


def sized_input(profile, field, count):
    data = sample(profile)
    if field == "requirement_ids":
        data["requirements"] = [{"id": f"r{i}", "text": "Synthetic criterion."}
                                for i in range(core.MAX_ITEMS)]
        data["evidence"][0][field] = [f"r{i % core.MAX_ITEMS}" for i in range(count)]
    else:
        data[field] = [dict(data[field][0], id=f"i{i}") for i in range(count)]
        if field == "requirements":
            data["evidence"][0]["requirement_ids"] = ["i0"]
    return data


class LimitTests(Fixture):
    def test_profiles_exposes_enforced_item_and_string_limits(self):
        code, result = self.invoke(["profiles"])
        self.assertEqual(code, 0)
        self.assertEqual(result["max_items"], 8)
        self.assertEqual(result["max_text_chars"], 1200)
        self.assertEqual(result["max_context_chars"], 2400)
        self.assertEqual(result["max_id_chars"], 24)
        self.assertEqual(result["max_payload_utf8_bytes"], 12000)

    def test_all_collection_overflows_return_distinct_reason_without_calls(self):
        with mock.patch.object(client, "Area", side_effect=AssertionError("private access")):
            with mock.patch.object(client, "transport") as network:
                for profile, field in COLLECTIONS:
                    with self.subTest(profile=profile, field=field):
                        data = sized_input(profile, field, core.MAX_ITEMS + 1)
                        path = self.input_file(profile, data)
                        code, result = self.invoke(["evaluate", profile, "--input", str(path)])
                        self.assertEqual((code, result), (2, core.not_evaluated("too_many_items")))
                network.assert_not_called()
        self.assertFalse((self.home / ".roberdan-os").exists())

    def test_eight_items_remain_intact_for_every_collection(self):
        for profile, field in COLLECTIONS:
            with self.subTest(profile=profile, field=field):
                data = sized_input(profile, field, core.MAX_ITEMS)
                normalized = profiles.normalize(profile, data)
                actual = (normalized["evidence"][0][field] if field == "requirement_ids"
                          else normalized[field])
                expected = data["evidence"][0][field] if field == "requirement_ids" else data[field]
                self.assertEqual(len(actual), 8)
                self.assertEqual(actual, expected)

    def test_nonlist_and_required_empty_collections_keep_invalid_input_reason(self):
        for profile, field in COLLECTIONS:
            for invalid in (None, {}, "not a list", []):
                if field == "evidence" and invalid == []:
                    continue
                data = sample(profile)
                if field == "requirement_ids":
                    data["evidence"][0][field] = invalid
                else:
                    data[field] = invalid
                with self.subTest(profile=profile, field=field, invalid=invalid):
                    with self.assertRaisesRegex(core.JevError, "^invalid_input$"):
                        profiles.normalize(profile, data)

    def test_text_and_id_limits_match_exact_boundaries(self):
        data = sample("wanda")
        item = data["items"][0]
        for field, limit in (("text", core.MAX_TEXT_CHARS), ("id", core.MAX_ID_CHARS)):
            original = item[field]
            item[field] = "a" * limit
            profiles.prepare("wanda", data)
            item[field] += "a"
            with self.assertRaisesRegex(core.JevError, "invalid_input"):
                profiles.prepare("wanda", data)
            item[field] = original
        for profile, field in (("twin", "situation"), ("retrieval", "query")):
            data = sample(profile)
            data[field] = "a" * core.MAX_CONTEXT_CHARS
            profiles.prepare(profile, data)
            data[field] += "a"
            with self.assertRaisesRegex(core.JevError, "invalid_input"):
                profiles.prepare(profile, data)
