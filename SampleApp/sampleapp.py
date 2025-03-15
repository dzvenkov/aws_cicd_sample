#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer
import urllib.request
import os


class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            try:
                with urllib.request.urlopen("http://example.com") as resp:
                    content = resp.read()
                self.send_response(200)
                self.send_header("Content-Type", "text/html")
                self.end_headers()
                buildTag = os.environ.get("BUILD_TAG", "unknown_tag")
                envName = os.environ.get("ENVIRONMENT", "unknown_env") 
                self.wfile.write(f"[1] Server tag: {buildTag}; Env: {envName}\n".encode('utf-8') + content)
            except Exception as e:
                self.send_response(500)
                self.send_header("Content-Type", "text/plain")
                self.end_headers()
                self.wfile.write(str(e).encode("utf-8"))
        else:
            self.send_response(404)
            self.end_headers()

def run(server_class=HTTPServer, handler_class=HealthHandler, port=80):
    server_address = ("", port)
    httpd = server_class(server_address, handler_class)
    print(f"Server running on port {port}...")
    httpd.serve_forever()

if __name__ == "__main__":
    run()