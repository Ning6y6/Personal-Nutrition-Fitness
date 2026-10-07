"""Loopback-only Flask host for a fictional, browser-based design preview."""

from __future__ import annotations

import argparse
import json
import math
import re
from collections.abc import Sequence
from typing import Any

from flask import Flask, Response, jsonify, render_template, request
from werkzeug.exceptions import HTTPException, RequestEntityTooLarge
from werkzeug.serving import WSGIRequestHandler


MAX_DESIGN_BYTES = 8 * 1024
_COLOR_ITEMS = (
    ("green", "#2ED158"),
    ("yellow", "#FFD500"),
    ("red", "#FF4144"),
    ("lightBackground", "#F6F7F3"),
    ("lightSurface", "#FFFFFF"),
    ("darkBackground", "#111214"),
    ("darkSurface", "#202124"),
)
_DESIGN_FIELDS = frozenset(
    {"version", "theme", "colors", "warningPercent", "radius", "density"}
)
_COLOR_FIELDS = frozenset(name for name, _ in _COLOR_ITEMS)
_HEX_COLOR = re.compile(r"#[0-9A-Fa-f]{6}\Z")


def default_preview_config() -> dict[str, Any]:
    """Return a fresh value; request validation can never mutate the defaults."""
    return {
        "version": 1,
        "theme": "light",
        "colors": dict(_COLOR_ITEMS),
        "warningPercent": 80,
        "radius": 22,
        "density": 1,
    }


class InvalidDesign(ValueError):
    def __init__(self, message: str, field: str | None = None) -> None:
        super().__init__(message)
        self.field = field


def _require_fields(value: dict[str, Any], fields: frozenset[str], parent: str) -> None:
    if set(value) - fields:
        raise InvalidDesign("Unknown fields are not accepted.", parent)
    if fields - set(value):
        raise InvalidDesign("All design fields are required.", parent)


def validate_design(value: Any) -> dict[str, Any]:
    """Validate visual tokens only. This is not a health or dietary rule engine."""
    if not isinstance(value, dict):
        raise InvalidDesign("The design must be a JSON object.")
    _require_fields(value, _DESIGN_FIELDS, "config")

    if type(value["version"]) is not int or value["version"] != 1:
        raise InvalidDesign("Only design version 1 is supported.", "version")
    if not isinstance(value["theme"], str) or value["theme"] not in {"light", "dark"}:
        raise InvalidDesign("Theme must be light or dark.", "theme")

    colors = value["colors"]
    if not isinstance(colors, dict):
        raise InvalidDesign("Colors must be a JSON object.", "colors")
    _require_fields(colors, _COLOR_FIELDS, "colors")
    normalized_colors = {}
    for name, _ in _COLOR_ITEMS:
        color = colors[name]
        if not isinstance(color, str) or _HEX_COLOR.fullmatch(color) is None:
            raise InvalidDesign("Colors must use the six-digit #RRGGBB format.", f"colors.{name}")
        normalized_colors[name] = color.upper()

    for name, lower, upper in (("warningPercent", 50, 99), ("radius", 12, 32)):
        number = value[name]
        if type(number) is not int or not lower <= number <= upper:
            raise InvalidDesign(f"{name} must be an integer from {lower} to {upper}.", name)

    density = value["density"]
    if type(density) not in {int, float} or not 0.85 <= density <= 1.15 or not math.isfinite(density):
        raise InvalidDesign("Density must be a finite number from 0.85 to 1.15.", "density")

    return {
        "version": 1,
        "theme": value["theme"],
        "colors": normalized_colors,
        "warningPercent": value["warningPercent"],
        "radius": value["radius"],
        "density": density,
    }


def _reject_constant(_value: str) -> None:
    raise ValueError("Non-finite JSON numbers are not accepted.")


def _unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate JSON fields are not accepted.")
        result[key] = value
    return result


def _parse_design_json(raw: bytes | str) -> Any:
    return json.loads(raw, parse_constant=_reject_constant, object_pairs_hook=_unique_object)


class PreviewRequestHandler(WSGIRequestHandler):
    """Keep design tokens in export query strings out of local access logs."""

    def log_request(self, code: int | str = "-", size: int | str = "-") -> None:
        path = getattr(self, "path", "/").partition("?")[0]
        self.log("info", '"%s %s" %s %s', getattr(self, "command", "?"), path, code, size)


def _error_response(
    code: str, message: str, status: int, field: str | None = None
) -> tuple[Response, int]:
    error = {"code": code, "message": message}
    if field is not None:
        error["field"] = field
    return jsonify(valid=False, error=error), status


def create_app() -> Flask:
    app = Flask(__name__)
    app.config.update(
        DEBUG=False,
        TEMPLATES_AUTO_RELOAD=True,
        MAX_CONTENT_LENGTH=MAX_DESIGN_BYTES,
        TRUSTED_HOSTS=["localhost", "127.0.0.1"],
    )

    @app.after_request
    def add_security_headers(response: Response) -> Response:
        response.headers["Content-Security-Policy"] = (
            "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; "
            "img-src 'self' data:; font-src 'self'; connect-src 'self'; "
            "object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'"
        )
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
        response.headers["Cache-Control"] = "no-store"
        return response

    @app.get("/")
    def index() -> str:
        return render_template("index.html")

    @app.get("/health")
    def health() -> Response:
        return jsonify(status="ok", service="ui-preview", localOnly=True)

    @app.get("/api/preview-config")
    def preview_config() -> Response:
        return jsonify(default_preview_config())

    @app.post("/api/validate-design")
    def validate_design_request() -> Response | tuple[Response, int]:
        if request.mimetype != "application/json":
            return _error_response("unsupported_media_type", "Use application/json.", 415)
        try:
            value = _parse_design_json(request.get_data(cache=False))
        except RequestEntityTooLarge:
            raise
        except (ValueError, UnicodeDecodeError, RecursionError):
            return _error_response("malformed_json", "Provide one valid JSON object with unique fields and finite numbers.", 400)
        try:
            config = validate_design(value)
        except InvalidDesign as error:
            return _error_response("invalid_config", str(error), 400, error.field)
        return jsonify(valid=True, config=config)

    @app.get("/api/design-export")
    def design_export() -> Response | tuple[Response, int]:
        configs = request.args.getlist("config")
        if set(request.args) != {"config"} or len(configs) != 1:
            return _error_response("invalid_config", "Provide exactly one config query parameter.", 400, "config")
        raw = configs[0]
        if len(raw.encode("utf-8")) > MAX_DESIGN_BYTES:
            raise RequestEntityTooLarge()
        try:
            value = _parse_design_json(raw)
        except (ValueError, UnicodeDecodeError, RecursionError):
            return _error_response("malformed_json", "Provide one valid JSON object with unique fields and finite numbers.", 400)
        try:
            config = validate_design(value)
        except InvalidDesign as error:
            return _error_response("invalid_config", str(error), 400, error.field)
        return Response(
            json.dumps(config, ensure_ascii=False, allow_nan=False, indent=2) + "\n",
            mimetype="application/json",
            headers={"Content-Disposition": 'attachment; filename="ShiHeng-design-v1.json"'},
        )

    @app.errorhandler(RequestEntityTooLarge)
    def payload_too_large(_error: RequestEntityTooLarge) -> tuple[Response, int]:
        return _error_response("payload_too_large", "Design JSON must not exceed 8 KiB.", 413)

    @app.errorhandler(HTTPException)
    def http_error(error: HTTPException) -> tuple[Response, int]:
        # Do not echo untrusted Host headers, request bodies, or URLs in errors.
        return _error_response("http_error", error.name, error.code or 500)

    return app


def _port_number(value: str) -> int:
    try:
        port = int(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("Port must be an integer from 1 to 65535.") from error
    if not 1 <= port <= 65535:
        raise argparse.ArgumentTypeError("Port must be an integer from 1 to 65535.")
    return port


def main(argv: Sequence[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=_port_number, default=5058)
    args = parser.parse_args(argv)
    create_app().run(
        host="127.0.0.1", port=args.port, debug=False, use_reloader=False,
        request_handler=PreviewRequestHandler,
    )


if __name__ == "__main__":
    main()
