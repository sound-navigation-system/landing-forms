#!/usr/bin/env python3

import json
import logging
import os
import re
import smtplib
import ssl
import time
from collections import defaultdict, deque
from email.message import EmailMessage
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


HOST = "127.0.0.1"
PORT = int(os.environ.get("PORT", "3001"))
MAX_BODY_BYTES = 16 * 1024
RATE_LIMIT_COUNT = 5
RATE_LIMIT_WINDOW_SECONDS = 10 * 60
ALLOWED_ORIGINS = {
    origin.strip()
    for origin in os.environ.get(
        "ALLOWED_ORIGINS",
        "https://ngopie.com.ua,https://www.ngopie.com.ua",
    ).split(",")
    if origin.strip()
}

SMTP_HOST = os.environ.get("SMTP_HOST", "smtp.gmail.com")
SMTP_PORT = int(os.environ.get("SMTP_PORT", "465"))
SMTP_USER = os.environ.get("SMTP_USER", "")
SMTP_PASSWORD = os.environ.get("SMTP_PASSWORD", "")
MAIL_TO = os.environ.get("MAIL_TO", "")

EMAIL_RE = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")
PHONE_RE = re.compile(r"^\+?[0-9 ()-]{7,24}$")
REQUESTS_BY_IP: dict[str, deque[float]] = defaultdict(deque)

FORM_CONFIG = {
    "ngopie-access": {
        "subject": "[NGO PIE] Заявка на участь у майбутніх проєктах",
        "fields": (
            ("firstName", "Ім’я", 2, 100),
            ("lastName", "Прізвище", 2, 100),
            ("phone", "Телефон", 7, 30),
            ("email", "Email", 5, 254),
        ),
    },
    "ngopie-psychological-support": {
        "subject": "[NGO PIE] Звернення до психолога",
        "fields": (
            ("name", "Ім’я", 2, 100),
            ("phone", "Телефон", 7, 30),
        ),
    },
    "ngopie-volunteer": {
        "subject": "[NGO PIE] Заявка волонтера",
        "fields": (
            ("name", "Ім’я", 2, 100),
            ("phone", "Телефон", 7, 30),
        ),
    },
    "ngopie-complaint": {
        "subject": "[NGO PIE] Нова скарга",
        "fields": (
            ("name", "Ім’я", 2, 100),
            ("message", "Текст звернення", 3, 4000),
        ),
    },
}

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)


def validate_payload(payload: object) -> tuple[dict[str, str], dict] | tuple[None, str]:
    if not isinstance(payload, dict):
        return None, "Invalid JSON object"
    if payload.get("website"):
        return None, "Rejected"

    form_id = payload.get("formId")
    config = FORM_CONFIG.get(form_id)
    if config is None:
        return None, "Unknown form"

    values: dict[str, str] = {}
    for key, _label, minimum, maximum in config["fields"]:
        value = payload.get(key)
        if not isinstance(value, str):
            return None, f"Missing field: {key}"
        value = value.strip()
        if not minimum <= len(value) <= maximum:
            return None, f"Invalid field: {key}"
        values[key] = value

    if "email" in values and not EMAIL_RE.fullmatch(values["email"]):
        return None, "Invalid field: email"
    if "phone" in values and not PHONE_RE.fullmatch(values["phone"]):
        return None, "Invalid field: phone"

    return values, config


def send_message(form_id: str, values: dict[str, str], config: dict) -> None:
    if not SMTP_USER or not SMTP_PASSWORD or not MAIL_TO:
        raise RuntimeError("SMTP configuration is incomplete")

    message = EmailMessage()
    message["From"] = f"NGO PIE website <{SMTP_USER}>"
    message["To"] = MAIL_TO
    message["Subject"] = config["subject"]
    if "email" in values:
        message["Reply-To"] = values["email"]

    lines = ["Нове звернення з ngopie.com.ua", ""]
    for key, label, _minimum, _maximum in config["fields"]:
        lines.append(f"{label}: {values[key]}")
    message.set_content("\n".join(lines))

    context = ssl.create_default_context()
    with smtplib.SMTP_SSL(SMTP_HOST, SMTP_PORT, context=context, timeout=20) as smtp:
        smtp.login(SMTP_USER, SMTP_PASSWORD)
        smtp.send_message(message)


class Handler(BaseHTTPRequestHandler):
    server_version = "LandingForms/1.0"

    def log_message(self, fmt: str, *args: object) -> None:
        logging.info("%s %s", self.client_address[0], fmt % args)

    def send_json(self, status: HTTPStatus, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        if self.path == "/health":
            self.send_json(HTTPStatus.OK, {"status": "ok"})
        else:
            self.send_json(HTTPStatus.NOT_FOUND, {"error": "Not found"})

    def do_POST(self) -> None:
        if self.path != "/api/forms":
            self.send_json(HTTPStatus.NOT_FOUND, {"error": "Not found"})
            return

        origin = self.headers.get("Origin", "")
        if origin not in ALLOWED_ORIGINS:
            self.send_json(HTTPStatus.FORBIDDEN, {"error": "Origin not allowed"})
            return

        forwarded_for = self.headers.get("X-Forwarded-For", "")
        client_ip = forwarded_for.split(",", 1)[0].strip() or self.client_address[0]
        now = time.monotonic()
        requests = REQUESTS_BY_IP[client_ip]
        while requests and now - requests[0] > RATE_LIMIT_WINDOW_SECONDS:
            requests.popleft()
        if len(requests) >= RATE_LIMIT_COUNT:
            self.send_json(HTTPStatus.TOO_MANY_REQUESTS, {"error": "Too many requests"})
            return

        content_type = self.headers.get("Content-Type", "")
        if not content_type.startswith("application/json"):
            self.send_json(HTTPStatus.UNSUPPORTED_MEDIA_TYPE, {"error": "JSON required"})
            return

        try:
            content_length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            content_length = 0
        if content_length <= 0 or content_length > MAX_BODY_BYTES:
            self.send_json(HTTPStatus.REQUEST_ENTITY_TOO_LARGE, {"error": "Invalid request size"})
            return

        try:
            payload = json.loads(self.rfile.read(content_length))
        except (json.JSONDecodeError, UnicodeDecodeError):
            self.send_json(HTTPStatus.BAD_REQUEST, {"error": "Invalid JSON"})
            return

        result, config_or_error = validate_payload(payload)
        if result is None:
            self.send_json(HTTPStatus.BAD_REQUEST, {"error": config_or_error})
            return

        form_id = payload["formId"]
        try:
            send_message(form_id, result, config_or_error)
        except Exception:
            logging.exception("Email delivery failed for form %s", form_id)
            self.send_json(
                HTTPStatus.BAD_GATEWAY,
                {"error": "Message could not be sent"},
            )
            return

        requests.append(now)
        logging.info("Email accepted for form %s", form_id)
        self.send_json(HTTPStatus.OK, {"status": "sent"})


if __name__ == "__main__":
    logging.info("Landing forms listening on http://%s:%s", HOST, PORT)
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
