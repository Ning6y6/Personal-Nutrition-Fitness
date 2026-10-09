"""HTTP contract tests for the isolated local preview host."""

from __future__ import annotations

import copy
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app import MAX_DESIGN_BYTES, PreviewRequestHandler, create_app, default_preview_config, main  # noqa: E402


class PreviewHostTests(unittest.TestCase):
    def setUp(self) -> None:
        self.app = create_app()
        self.app.config["TESTING"] = True
        self.client = self.app.test_client()
        self.config = default_preview_config()

    def post_config(self, config):
        return self.client.post("/api/validate-design", json=config)

    def assert_invalid(self, response, code="invalid_config", status=400):
        self.assertEqual(response.status_code, status)
        payload = response.get_json()
        self.assertFalse(payload["valid"])
        self.assertEqual(payload["error"]["code"], code)

    def test_index_renders_local_preview(self):
        response = self.client.get("/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.mimetype, "text/html")
        self.assertIn(b"<!doctype html", response.data.lower())

    def test_optional_water_preview_controls_and_script_are_local(self):
        response = self.client.get("/")
        self.assertIn(b'data-energy-mode="ring"', response.data)
        self.assertIn(b'data-energy-mode="water"', response.data)
        self.assertIn(b'/static/energy-visual.js', response.data)
        script = self.client.get("/static/energy-visual.js")
        self.assertEqual(script.status_code, 200)
        self.assertIn(b"waterFillState", script.data)
        script.close()

    def test_water_mode_does_not_extend_design_json_contract(self):
        self.config["energyVisualMode"] = "water"
        self.assert_invalid(self.post_config(self.config))

    def test_health_is_local_preview_status(self):
        response = self.client.get("/health")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json(), {"status": "ok", "service": "ui-preview", "localOnly": True})

    def test_default_config_contract(self):
        response = self.client.get("/api/preview-config")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json(), {
            "version": 1,
            "theme": "light",
            "colors": {
                "green": "#2ED158", "yellow": "#FFD500", "red": "#FF4144",
                "lightBackground": "#F6F7F3", "lightSurface": "#FFFFFF",
                "darkBackground": "#111214", "darkSurface": "#202124",
            },
            "warningPercent": 80, "radius": 22, "density": 1,
        })

    def test_default_design_is_valid(self):
        response = self.post_config(self.config)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json(), {"valid": True, "config": self.config})

    def test_custom_tokens_are_normalized_without_changing_defaults(self):
        changed = copy.deepcopy(self.config)
        changed.update(theme="dark", warningPercent=99, radius=32, density=1.15)
        changed["colors"]["green"] = "#abcdef"
        response = self.post_config(changed)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()["config"]["colors"]["green"], "#ABCDEF")
        self.assertEqual(self.client.get("/api/preview-config").get_json(), self.config)
        self.assertEqual(self.post_config(self.config).get_json()["config"], self.config)

    def test_default_values_are_independent(self):
        first = default_preview_config()
        first["colors"]["green"] = "#000000"
        first["radius"] = 12
        self.assertEqual(default_preview_config(), self.config)

    def test_lower_numeric_boundaries_are_valid(self):
        self.config.update(warningPercent=50, radius=12, density=0.85)
        self.assertEqual(self.post_config(self.config).status_code, 200)

    def test_upper_numeric_boundaries_are_valid(self):
        self.config.update(warningPercent=99, radius=32, density=1.15)
        self.assertEqual(self.post_config(self.config).status_code, 200)

    def test_non_object_designs_are_rejected(self):
        for value in [None, [], "design", 1, True]:
            with self.subTest(value=value):
                response = self.client.post("/api/validate-design", data=json.dumps(value), content_type="application/json")
                self.assert_invalid(response)

    def test_unknown_top_level_fields_are_rejected(self):
        self.config["healthRules"] = {"allow": True}
        self.assert_invalid(self.post_config(self.config))

    def test_missing_top_level_fields_are_rejected(self):
        for field in self.config:
            with self.subTest(field=field):
                incomplete = copy.deepcopy(self.config)
                del incomplete[field]
                self.assert_invalid(self.post_config(incomplete))

    def test_version_requires_integer_one(self):
        for value in [True, 1.0, "1", 0, 2, None]:
            with self.subTest(value=value):
                self.config["version"] = value
                self.assert_invalid(self.post_config(self.config))

    def test_theme_requires_exact_supported_string(self):
        for value in ["auto", "Light", "", True, [], None]:
            with self.subTest(value=value):
                self.config["theme"] = value
                self.assert_invalid(self.post_config(self.config))

    def test_colors_require_an_object(self):
        for value in [None, [], "#123456", True]:
            with self.subTest(value=value):
                self.config["colors"] = value
                self.assert_invalid(self.post_config(self.config))

    def test_unknown_color_fields_are_rejected(self):
        self.config["colors"]["script"] = "#000000"
        self.assert_invalid(self.post_config(self.config))

    def test_missing_color_fields_are_rejected(self):
        for field in self.config["colors"]:
            with self.subTest(field=field):
                incomplete = copy.deepcopy(self.config)
                del incomplete["colors"][field]
                self.assert_invalid(self.post_config(incomplete))

    def test_colors_require_six_digit_hex(self):
        for value in ["red", "#FFF", "#12345678", "123456", "#GG0000", "#123456\n", "url(https://example.com)", 123456, None]:
            with self.subTest(value=value):
                self.config["colors"]["green"] = value
                self.assert_invalid(self.post_config(self.config))

    def test_integer_fields_reject_types_and_out_of_range_values(self):
        for field, values in {
            "warningPercent": [49, 100, 80.0, "80", True, None, []],
            "radius": [11, 33, 22.0, "22", False, None, {}],
        }.items():
            for value in values:
                with self.subTest(field=field, value=value):
                    changed = copy.deepcopy(self.config)
                    changed[field] = value
                    self.assert_invalid(self.post_config(changed))

    def test_density_rejects_types_and_out_of_range_values(self):
        for value in [0.849, 1.151, 10**400, "1", True, False, None, [], {}]:
            with self.subTest(value=value):
                self.config["density"] = value
                self.assert_invalid(self.post_config(self.config))

    def test_non_finite_json_numbers_are_rejected(self):
        for token in ["NaN", "Infinity", "-Infinity"]:
            with self.subTest(token=token):
                raw = json.dumps(self.config).replace('"density": 1', f'"density": {token}')
                response = self.client.post("/api/validate-design", data=raw, content_type="application/json")
                self.assert_invalid(response, "malformed_json")

    def test_overflowing_json_number_is_rejected(self):
        raw = json.dumps(self.config).replace('"density": 1', '"density": 1e999')
        response = self.client.post("/api/validate-design", data=raw, content_type="application/json")
        self.assert_invalid(response)

    def test_malformed_json_is_rejected_without_echoing_body(self):
        for raw in [b"", b"{", b'{"private-health-export":', b"\xff"]:
            with self.subTest(raw=raw):
                response = self.client.post("/api/validate-design", data=raw, content_type="application/json")
                self.assert_invalid(response, "malformed_json")
                self.assertNotIn(b"private-health-export", response.data)

    def test_duplicate_json_fields_are_rejected(self):
        for raw in [
            json.dumps(self.config).replace('"version": 1', '"version": 1, "version": 1'),
            json.dumps(self.config).replace('"green": "#2ED158"', '"green": "#2ED158", "green": "#000000"'),
        ]:
            with self.subTest(raw=raw):
                self.assert_invalid(self.client.post("/api/validate-design", data=raw, content_type="application/json"), "malformed_json")

    def test_deeply_nested_json_is_rejected(self):
        response = self.client.post("/api/validate-design", data="[" * 1100 + "0" + "]" * 1100, content_type="application/json")
        self.assertEqual(response.status_code, 400)
        self.assertFalse(response.get_json()["valid"])
        self.assertIn(response.get_json()["error"]["code"], {"malformed_json", "invalid_config"})

    def test_oversized_json_is_rejected(self):
        response = self.client.post("/api/validate-design", data=" " * (MAX_DESIGN_BYTES + 1), content_type="application/json")
        self.assert_invalid(response, "payload_too_large", 413)

    def test_non_json_requests_are_rejected(self):
        for content_type in ["text/plain", "application/x-www-form-urlencoded", "application/octet-stream"]:
            with self.subTest(content_type=content_type):
                response = self.client.post("/api/validate-design", data=json.dumps(self.config), content_type=content_type)
                self.assert_invalid(response, "unsupported_media_type", 415)

    def test_only_loopback_hosts_are_trusted(self):
        for host in ["localhost:5058", "127.0.0.1:5058"]:
            with self.subTest(host=host):
                self.assertEqual(self.client.get("/health", headers={"Host": host}).status_code, 200)
        for host in ["example.com", "localhost.example.com", "192.168.1.2:5058", "[::1]:5058"]:
            with self.subTest(host=host):
                response = self.client.get("/health", headers={"Host": host})
                self.assert_invalid(response, "http_error")
                self.assertNotIn(host.encode(), response.data)

    def test_security_headers_cover_success_and_error_responses(self):
        for response in [self.client.get("/health"), self.client.get("/not-a-route"), self.post_config({})]:
            with self.subTest(status=response.status_code):
                self.assertEqual(response.headers["X-Content-Type-Options"], "nosniff")
                self.assertEqual(response.headers["X-Frame-Options"], "DENY")
                self.assertEqual(response.headers["Referrer-Policy"], "no-referrer")
                self.assertEqual(response.headers["Cache-Control"], "no-store")
                self.assertIn("script-src 'self'", response.headers["Content-Security-Policy"])
                self.assertIn("connect-src 'self'", response.headers["Content-Security-Policy"])
                self.assertNotIn("Access-Control-Allow-Origin", response.headers)

    def test_validation_endpoint_does_not_accept_get(self):
        self.assertEqual(self.client.get("/api/validate-design").status_code, 405)

    def test_export_returns_design_json_attachment(self):
        self.config["theme"] = "dark"
        self.config["colors"]["green"] = "#abcdef"
        response = self.client.get("/api/design-export", query_string={"config": json.dumps(self.config)})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.mimetype, "application/json")
        self.assertEqual(response.headers["Content-Disposition"], 'attachment; filename="ShiHeng-design-v1.json"')
        self.config["colors"]["green"] = "#ABCDEF"
        self.assertEqual(response.get_json(), self.config)
        self.assertEqual(response.headers["Cache-Control"], "no-store")

    def test_export_rejects_invalid_configuration(self):
        for field, value in [("theme", "auto"), ("radius", True), ("density", 1.2), ("version", 2)]:
            with self.subTest(field=field):
                changed = copy.deepcopy(self.config)
                changed[field] = value
                self.assert_invalid(self.client.get("/api/design-export", query_string={"config": json.dumps(changed)}))

    def test_export_rejects_unknown_fields(self):
        self.config["healthRules"] = {"allow": True}
        self.assert_invalid(self.client.get("/api/design-export", query_string={"config": json.dumps(self.config)}))

    def test_export_rejects_malformed_and_nonfinite_json(self):
        for raw in ["", "{", json.dumps(self.config).replace('"density": 1', '"density": NaN'), json.dumps(self.config).replace('"density": 1', '"density": Infinity')]:
            with self.subTest(raw=raw):
                self.assert_invalid(self.client.get("/api/design-export", query_string={"config": raw}), "malformed_json")

    def test_export_rejects_duplicate_json_fields(self):
        raw = json.dumps(self.config).replace('"version": 1', '"version": 1, "version": 1')
        self.assert_invalid(self.client.get("/api/design-export", query_string={"config": raw}), "malformed_json")

    def test_export_requires_exactly_one_config_parameter(self):
        raw = json.dumps(self.config)
        for query in [{}, {"config": raw, "extra": "unexpected"}, [("config", raw), ("config", raw)]]:
            with self.subTest(query=query):
                self.assert_invalid(self.client.get("/api/design-export", query_string=query))

    def test_export_rejects_config_over_utf8_byte_limit(self):
        for raw in [" " * (MAX_DESIGN_BYTES + 1), "食" * (MAX_DESIGN_BYTES // 3 + 1)]:
            with self.subTest(multibyte=raw.startswith("食")):
                self.assert_invalid(self.client.get("/api/design-export", query_string={"config": raw}), "payload_too_large", 413)

    def test_export_never_changes_default_configuration(self):
        changed = copy.deepcopy(self.config)
        changed.update(theme="dark", radius=12, warningPercent=50)
        self.assertEqual(self.client.get("/api/design-export", query_string={"config": json.dumps(changed)}).status_code, 200)
        self.assertEqual(self.client.get("/api/preview-config").get_json(), self.config)
        self.assertEqual(default_preview_config(), self.config)

    def test_access_log_omits_export_query_string(self):
        handler = object.__new__(PreviewRequestHandler)
        handler.command = "GET"
        handler.path = "/api/design-export?config=design-tokens-must-not-be-logged"
        with patch.object(handler, "log") as log:
            handler.log_request(200, 321)
            level, message, *args = log.call_args.args
            rendered = message % tuple(args)
            self.assertEqual(level, "info")
            self.assertIn("/api/design-export", rendered)
            self.assertNotIn("config", rendered)
            self.assertNotIn("design-tokens", rendered)

    def test_debug_is_disabled_by_default(self):
        self.assertFalse(self.app.debug)

    def test_launcher_uses_loopback_without_debug_or_reloader(self):
        with patch("app.create_app") as factory:
            main([])
            factory.return_value.run.assert_called_once_with(host="127.0.0.1", port=5058, debug=False, use_reloader=False, request_handler=PreviewRequestHandler)

    def test_launcher_accepts_custom_port(self):
        with patch("app.create_app") as factory:
            main(["--port", "5060"])
            self.assertEqual(factory.return_value.run.call_args.kwargs["port"], 5060)

    def test_launcher_rejects_invalid_ports(self):
        for value in ["0", "65536", "abc"]:
            with self.subTest(value=value), patch("sys.stderr"), patch("app.create_app") as factory:
                with self.assertRaises(SystemExit) as raised:
                    main(["--port", value])
                self.assertEqual(raised.exception.code, 2)
                factory.assert_not_called()


if __name__ == "__main__":
    unittest.main()
