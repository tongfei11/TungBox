# -*- coding: utf-8 -*-
"""Exercise generated rules against an isolated loopback core; no system proxy/TUN changes."""
import http.server
import json
import pathlib
import socket
import subprocess
import sys
import threading
import time

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'ruleset-probe-ok')
    def log_message(self, *args):
        pass

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    for name, expected in [('enabled', True), ('disabled', False), ('subscription-preserved', True)]:
        with socket.socket() as reserve:
            reserve.bind(('127.0.0.1', 0))
            port = reserve.getsockname()[1]
        path = pathlib.Path(sys.argv[1]) / (name + '.json')
        config = json.loads(path.read_text())
        config['inbounds'] = [{'type': 'mixed', 'listen': '127.0.0.1', 'listen_port': port}]
        path.write_text(json.dumps(config))
        with (path.parent / (name + '.log')).open('w') as log:
            process = subprocess.Popen([sys.argv[2], 'run', '-c', str(path)], stdout=log, stderr=log)
            try:
                deadline = time.monotonic() + 5
                while True:
                    if process.poll() is not None:
                        raise RuntimeError('core failed: ' + name)
                    try:
                        probe = socket.create_connection(('127.0.0.1', port), timeout=0.2)
                        break
                    except OSError:
                        if time.monotonic() > deadline:
                            raise
                        time.sleep(0.05)
                received = b''
                with probe:
                    probe.settimeout(3)
                    probe.sendall(('GET http://127.0.0.1:%d/ HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n' % server.server_port).encode())
                    try:
                        while True:
                            data = probe.recv(4096)
                            if not data:
                                break
                            received += data
                    except (ConnectionResetError, socket.timeout):
                        pass
                assert (b'ruleset-probe-ok' in received) == expected, name
                print('Core routing probe passed:', name)
            finally:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
finally:
    server.shutdown()
    server.server_close()
