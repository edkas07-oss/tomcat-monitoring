#!/usr/bin/env python3
"""Capture a bounded number of synthetic Alertmanager webhook requests."""

import argparse
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from threading import Thread


class WebhookServer(HTTPServer):
    def __init__(self, server_address, handler, output_directory, max_requests):
        super().__init__(server_address, handler)
        self.output_directory = output_directory
        self.max_requests = max_requests
        self.request_count = 0


class WebhookHandler(BaseHTTPRequestHandler):
    server: WebhookServer

    def do_POST(self):
        if self.path != "/alerts":
            self.send_error(404)
            return

        try:
            content_length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self.send_error(400)
            return

        if content_length < 1 or content_length > 1_048_576:
            self.send_error(413)
            return

        try:
            payload = json.loads(self.rfile.read(content_length))
        except (UnicodeDecodeError, json.JSONDecodeError):
            self.send_error(400)
            return

        if not isinstance(payload, dict):
            self.send_error(400)
            return

        self.server.request_count += 1
        output_path = self.server.output_directory / (
            f"webhook-{self.server.request_count:03d}.json"
        )
        output_path.write_text(
            json.dumps(payload, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"accepted":true}\n')

        if self.server.request_count >= self.server.max_requests:
            Thread(target=self.server.shutdown, daemon=True).start()

    def log_message(self, format_string, *args):
        return


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--output-directory", type=Path, required=True)
    parser.add_argument("--max-requests", type=int, default=2)
    return parser.parse_args()


def main():
    args = parse_args()
    if not 1 <= args.port <= 65535:
        raise SystemExit("port must be between 1 and 65535")
    if args.max_requests < 1:
        raise SystemExit("max-requests must be positive")

    args.output_directory.mkdir(parents=True, exist_ok=True)
    server = WebhookServer(
        (args.host, args.port),
        WebhookHandler,
        args.output_directory,
        args.max_requests,
    )
    server.serve_forever()


if __name__ == "__main__":
    main()
