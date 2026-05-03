#!/usr/bin/env python3
"""Captive portal web server for HIM Education walled garden.

Serves the landing page on HTTP (port 80) and optionally HTTPS (port 443)
with a self-signed certificate.

Routes:
  /              → www/index.html  (captive portal)
  /browse        → www/browse.html (Kolibri lesson builder)
  /kolibri-api/* → proxy to http://127.0.0.1:8080/api/*
  other paths    → www/index.html  (captive portal)
"""

import os
import re
import sys
import ssl
import threading
import subprocess
import urllib.request
import urllib.error
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

ThreadingHTTPServer.allow_reuse_address = True

ROOT     = os.path.dirname(os.path.abspath(__file__))
WWW_DIR  = os.path.join(ROOT, 'www')
CERT_DIR = os.path.join(ROOT, 'ssl')
CERT_PEM = os.path.join(CERT_DIR, 'cert.pem')
KEY_PEM  = os.path.join(CERT_DIR, 'key.pem')

KOLIBRI_URL = 'http://127.0.0.1:8080'

MIME_TYPES = {
    '.html': 'text/html; charset=utf-8',
    '.css':  'text/css',
    '.js':   'application/javascript',
    '.json': 'application/json',
    '.png':  'image/png',
    '.jpg':  'image/jpeg',
    '.ico':  'image/x-icon',
}

INDEX_BYTES = b''


def load_index():
    path = os.path.join(WWW_DIR, 'index.html')
    with open(path, 'rb') as f:
        return f.read()


class CaptiveHandler(BaseHTTPRequestHandler):
    """Captive portal + static file server + Kolibri API proxy."""

    # ------------------------------------------------------------------ dispatch

    def do_GET(self):
        if self.path.startswith('/kolibri-api/'):
            self._proxy('GET')
        elif not self._serve_static():
            self._serve_portal()

    def do_POST(self):
        if self.path.startswith('/kolibri-api/'):
            self._proxy('POST')
        else:
            self._serve_portal()

    def do_DELETE(self):
        if self.path.startswith('/kolibri-api/'):
            self._proxy('DELETE')

    def do_HEAD(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.end_headers()

    # ------------------------------------------------------------------ static files

    def _serve_static(self):
        """Serve a file from www/. Returns True if served."""
        raw = self.path.split('?')[0].lstrip('/')
        if not raw or '/' in raw:
            return False
        # Files without an extension are assumed to be .html pages
        filename = raw if ('.' in raw) else raw + '.html'
        filepath = os.path.join(WWW_DIR, filename)
        # Prevent path traversal
        real_www = os.path.realpath(WWW_DIR)
        if not os.path.realpath(filepath).startswith(real_www + os.sep):
            return False
        if not os.path.isfile(filepath):
            return False
        ext  = os.path.splitext(filename)[1]
        ctype = MIME_TYPES.get(ext, 'text/plain')
        try:
            with open(filepath, 'rb') as f:
                data = f.read()
            self.send_response(200)
            self.send_header('Content-Type', ctype)
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return True
        except Exception:
            return False

    # ------------------------------------------------------------------ proxy

    def _proxy(self, method):
        """Forward /kolibri-api/<path>?<qs> → http://127.0.0.1:8080/api/<path>?<qs>."""
        raw = self.path
        qs  = ''
        if '?' in raw:
            raw, qs = raw.split('?', 1)
        kolibri_path = '/api/' + raw[len('/kolibri-api/'):]
        url = KOLIBRI_URL + kolibri_path + ('?' + qs if qs else '')

        body = None
        if method in ('POST', 'PUT', 'PATCH'):
            n = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(n) if n else b''

        hdrs = {}
        for h in ('Cookie', 'Content-Type', 'X-CSRFToken'):
            v = self.headers.get(h)
            if v:
                hdrs[h] = v

        req = urllib.request.Request(url, data=body, headers=hdrs, method=method)
        try:
            resp = urllib.request.urlopen(req)
            self._relay(resp.status, resp.headers, resp.read())
        except urllib.error.HTTPError as e:
            self._relay(e.code, e.headers, e.read())
        except Exception as e:
            self.send_error(502, str(e))

    def _relay(self, status, headers, body):
        """Send a proxied response back to the browser."""
        self.send_response(status)
        self.send_header('Content-Type', headers.get('Content-Type', 'application/json'))
        # Strip Domain= from Set-Cookie so cookies bind to the portal origin (port 80)
        for val in (headers.get_all('Set-Cookie') or []):
            val = re.sub(r';\s*[Dd]omain=[^;,]*', '', val)
            self.send_header('Set-Cookie', val)
        self.end_headers()
        self.wfile.write(body)

    # ------------------------------------------------------------------ portal

    def _serve_portal(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate')
        self.end_headers()
        self.wfile.write(INDEX_BYTES)

    def log_message(self, fmt, *args):
        sys.stderr.write(
            '%s - - [%s] %s\n'
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
