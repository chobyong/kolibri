#!/usr/bin/env python3
"""Captive portal server with optional HTTPS endpoint.

This server serves the landing page for any HTTP GET and provides
explicit handlers for common captive-detection endpoints. It can run
both an HTTP server on port 80 and an optional HTTPS server on port 443
using a self-signed certificate (useful to show a landing page when
clients attempt HTTPS; note browsers will show a certificate warning).

Limitations: HTTPS cannot be made transparent for HSTS-protected domains
or without a valid certificate for the requested hostname. The HTTPS
listener only improves UX for users who proceed through the browser
warning; it does not eliminate TLS errors.
"""

import os
import sys
import ssl
import threading
import subprocess
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler


ROOT = os.path.dirname(os.path.abspath(__file__))
WWW_DIR = os.path.join(ROOT, 'www')
CERT_DIR = os.path.join(ROOT, 'ssl')
CERT_PEM = os.path.join(CERT_DIR, 'cert.pem')
KEY_PEM = os.path.join(CERT_DIR, 'key.pem')


def load_index():
    path = os.path.join(WWW_DIR, 'index.html')
    with open(path, 'rb') as f:
        return f.read()


INDEX_BYTES = b''


class CaptiveHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        # respond 200 with landing page for any request (helps captive detection)
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate')
        self.end_headers()
        self.wfile.write(INDEX_BYTES)

    def log_message(self, format, *args):
        sys.stderr.write("%s - - [%s] %s\n" % (self.client_address[0], self.log_date_time_string(), format % args))


def ensure_self_signed_cert(hostname='10.42.0.1'):
    # Create a self-signed certificate for the portal IP if not present
    if os.path.exists(CERT_PEM) and os.path.exists(KEY_PEM):
        return
    os.makedirs(CERT_DIR, exist_ok=True)
    subj = f"/CN={hostname}"
    cmd = [
        'openssl', 'req', '-x509', '-nodes', '-days', '3650',
        '-newkey', 'rsa:2048',
        '-keyout', KEY_PEM,
        '-out', CERT_PEM,
        '-subj', subj,
    ]
    try:
        subprocess.check_call(cmd)
    except Exception as e:
        print('Failed to create self-signed cert with openssl:', e, file=sys.stderr)


def run_http(port=80):
    httpd = ThreadingHTTPServer(('', port), CaptiveHandler)
    httpd.allow_reuse_address = True
    print(f'HTTP captive portal listening on port {port}')
    httpd.serve_forever()


def run_https(port=443):
    ensure_self_signed_cert()
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(certfile=CERT_PEM, keyfile=KEY_PEM)
    httpd = ThreadingHTTPServer(('', port), CaptiveHandler)
    httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
    print(f'HTTPS captive portal listening on port {port} (self-signed cert)')
    httpd.serve_forever()


def main(start_https=False):
    global INDEX_BYTES
    if os.geteuid() != 0:
        print('This script must be run as root to bind to low ports', file=sys.stderr)
        sys.exit(1)

    INDEX_BYTES = load_index()

    # Start HTTP server thread
    t_http = threading.Thread(target=run_http, args=(80,), daemon=True)
    t_http.start()

    # Optionally start HTTPS server
    if start_https:
        try:
            t_https = threading.Thread(target=run_https, args=(443,), daemon=True)
            t_https.start()
        except Exception as e:
            print('Failed to start HTTPS server:', e, file=sys.stderr)

    # Keep main thread alive
    try:
        while True:
            threading.Event().wait(3600)
    except KeyboardInterrupt:
        print('Shutting down')


if __name__ == '__main__':
    # start HTTPS listener to improve UX when clients hit https (cert warning expected)
    main(start_https=True)
