#!/usr/bin/env python3
"""Captive portal web server for HIM Education walled garden.

Serves the landing page on HTTP (port 80) and optionally HTTPS (port 443)
with a self-signed certificate. All requests return the landing page,
which triggers captive portal detection on client devices.
"""

import os
import sys
import ssl
import threading
import subprocess
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

ThreadingHTTPServer.allow_reuse_address = True

ROOT = os.path.dirname(os.path.abspath(__file__))
WWW_DIR = os.path.join(ROOT, 'www')
CERT_DIR = os.path.join(ROOT, 'ssl')
CERT_PEM = os.path.join(CERT_DIR, 'cert.pem')
KEY_PEM = os.path.join(CERT_DIR, 'key.pem')

INDEX_BYTES = b''


def load_index():
    path = os.path.join(WWW_DIR, 'index.html')
    with open(path, 'rb') as f:
        return f.read()


class CaptiveHandler(BaseHTTPRequestHandler):
    """Serve the landing page for every request."""

    def _serve_portal(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate')
        self.end_headers()
        self.wfile.write(INDEX_BYTES)

    def do_GET(self):
        self._serve_portal()

    def do_POST(self):
        self._serve_portal()

    def do_HEAD(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.end_headers()

    def log_message(self, fmt, *args):
        sys.stderr.write(
            "%s - - [%s] %s\n"
            % (self.client_address[0], self.log_date_time_string(), fmt % args)
        )


def ensure_self_signed_cert(hostname='10.42.0.1'):
    if os.path.exists(CERT_PEM) and os.path.exists(KEY_PEM):
        return
    os.makedirs(CERT_DIR, exist_ok=True)
    cmd = [
        'openssl', 'req', '-x509', '-nodes', '-days', '3650',
        '-newkey', 'rsa:2048',
        '-keyout', KEY_PEM,
        '-out', CERT_PEM,
        '-subj', f'/CN={hostname}',
    ]
    try:
        subprocess.check_call(cmd)
    except Exception as e:
        print(f'Failed to create self-signed cert: {e}', file=sys.stderr)


def run_http(port=80):
    httpd = ThreadingHTTPServer(('', port), CaptiveHandler)
    print(f'HTTP captive portal listening on port {port}')
    httpd.serve_forever()


def run_https(port=443):
    ensure_self_signed_cert()
    if not (os.path.exists(CERT_PEM) and os.path.exists(KEY_PEM)):
        print('SSL certificate not available, skipping HTTPS', file=sys.stderr)
        return
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(certfile=CERT_PEM, keyfile=KEY_PEM)
    httpd = ThreadingHTTPServer(('', port), CaptiveHandler)
    httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
    print(f'HTTPS captive portal listening on port {port} (self-signed cert)')
    try:
        httpd.serve_forever()
    except Exception as e:
        print(f'HTTPS server error: {e}', file=sys.stderr)


def main():
    global INDEX_BYTES
    if os.geteuid() != 0:
        print('This script must be run as root to bind to low ports.', file=sys.stderr)
        sys.exit(1)

    INDEX_BYTES = load_index()

    t_http = threading.Thread(target=run_http, args=(80,), daemon=True)
    t_http.start()

    try:
        t_https = threading.Thread(target=run_https, args=(443,), daemon=True)
        t_https.start()
    except Exception as e:
        print(f'HTTPS server failed to start: {e}', file=sys.stderr)

    try:
        threading.Event().wait()
    except KeyboardInterrupt:
        print('Shutting down captive portal server.')


if __name__ == '__main__':
    main()
