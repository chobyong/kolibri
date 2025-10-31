#!/usr/bin/env python3
from http.server import HTTPServer, SimpleHTTPRequestHandler
import os
import sys

class CaptivePortalHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        # Redirect all requests to index.html
        self.path = '/index.html'
        return SimpleHTTPRequestHandler.do_GET(self)

def run(server_class=HTTPServer, handler_class=CaptivePortalHandler, port=80):
    # Change to the www directory
    os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'www'))
    
    server_address = ('', port)
    httpd = server_class(server_address, handler_class)
    print(f'Starting server on port {port}...')
    httpd.serve_forever()

if __name__ == '__main__':
    if os.geteuid() != 0:
        print('This script must be run as root to bind to port 80')
        sys.exit(1)
    run()