#!/usr/bin/env python3
"""TEST ONLY: minimal Galaxy v3 server for `ansible-galaxy collection publish` (stands in for Nexus
ansible-hosted). Saves every uploaded artifact in <dir> and logs its sha256. Usage: fake-galaxy.py <dir> [port]"""
import email, hashlib, http.server, json, os, sys

STORE = sys.argv[1]
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8000


class Handler(http.server.BaseHTTPRequestHandler):
    def reply(self, code, data):
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if "/imports/" in self.path:   # import task: always completed
            self.reply(200, {"state": "completed", "finished_at": "2026-01-01T00:00:00Z", "messages": []})
        else:                          # API discovery
            self.reply(200, {"available_versions": {"v3": "v3/"}})

    def do_POST(self):
        raw = self.rfile.read(int(self.headers["Content-Length"]))
        msg = email.message_from_bytes(b"Content-Type: " + self.headers["Content-Type"].encode() + b"\r\n\r\n" + raw)
        for part in msg.get_payload():
            if part.get_param("name", header="content-disposition") == "file":
                name = os.path.basename(part.get_filename())
                data = part.get_payload(decode=True)
                with open(os.path.join(STORE, name), "wb") as f:
                    f.write(data)
                print(f"uploaded {name} sha256 {hashlib.sha256(data).hexdigest()}", flush=True)
        self.reply(202, {"task": f"http://{self.headers['Host']}/v3/imports/collections/1/"})


http.server.ThreadingHTTPServer(("", PORT), Handler).serve_forever()
