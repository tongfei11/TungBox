#!/usr/bin/env python3
"""Verify real process-rule routing from a GUI-launched Core, loopback only."""
import ctypes
import http.server
import json
import os
import pwd
from pathlib import Path
import re
import socket
import subprocess
import sys
import tempfile
import threading
import time

core = str(Path(sys.argv[1]).resolve())
expect_failure = '--expect-failure' in sys.argv

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Length', '2')
        self.end_headers()
        self.wfile.write(b'OK')
    def log_message(self, *args):
        pass

with tempfile.TemporaryDirectory(prefix='TungBox-ProcessFixture-') as folder:
    root = Path(folder)
    app = root / 'ProcessFixture.app'
    macos = app / 'Contents/MacOS'
    macos.mkdir(parents=True)
    source = root / 'Host.swift'
    source.write_text('''import Foundation
let args = CommandLine.arguments
FileManager.default.createFile(atPath: args[3], contents: nil)
let file = try FileHandle(forWritingTo: URL(fileURLWithPath: args[3]))
let child = Process()
child.executableURL = URL(fileURLWithPath: args[1])
child.arguments = ["run", "-c", args[2]]
child.currentDirectoryURL = URL(fileURLWithPath: args[2]).deletingLastPathComponent()
child.standardOutput = file
child.standardError = file
try child.run()
Thread.sleep(forTimeInterval: 8)
if child.isRunning { child.terminate() }
child.waitUntilExit()
''')
    subprocess.run(['swiftc', str(source), '-o', str(macos / 'Host')], check=True)
    (app / 'Contents/Info.plist').write_text('''<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.tungbox.isolated-process-fixture</string>
<key>CFBundleExecutable</key><string>Host</string><key>LSUIElement</key><true/>
</dict></plist>''')
    subprocess.run(['codesign', '-s', '-', str(app)], check=True, capture_output=True)
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    target = server.server_address[1]
    with socket.socket() as reserve:
        reserve.bind(('127.0.0.1', 0))
        port = reserve.getsockname()[1]
    config = root / 'config.json'
    # Python's executable basename determines the process_name rule.
    pathbuf = ctypes.create_string_buffer(4096)
    assert ctypes.CDLL('/usr/lib/libproc.dylib').proc_pidpath(os.getpid(), pathbuf, len(pathbuf)) > 0
    name = Path(os.fsdecode(pathbuf.value)).name
    config.write_text(json.dumps({
        'log': {'level': 'debug', 'timestamp': True},
        'inbounds': [{'type': 'mixed', 'tag': 'fixture', 'listen': '127.0.0.1', 'listen_port': port}],
        'outbounds': [{'type': 'direct', 'tag': 'process-matched'}, {'type': 'direct', 'tag': 'fallback'}],
        'route': {'rules': [{'process_name': name, 'outbound': 'process-matched'}], 'final': 'fallback'}
    }))
    log = root / 'core.log'
    host = subprocess.Popen(['/usr/bin/open', '-g', '-n', '-W', str(app), '--args', core, str(config), str(log)])
    try:
        for _ in range(100):
            if log.exists() and 'tcp server started' in log.read_text():
                break
            time.sleep(.05)
        else:
            raise AssertionError('Fixture Core did not listen')
        for _ in range(6):
            with socket.create_connection(('127.0.0.1', port), timeout=3) as client:
                client.sendall(f'CONNECT 127.0.0.1:{target} HTTP/1.1\r\nHost: fixture\r\n\r\n'.encode())
                response = client.recv(4096)
                assert b'200' in response, response
                client.sendall(b'GET / HTTP/1.1\r\nHost: fixture\r\nConnection: close\r\n\r\n')
                response = b''
                while True:
                    part = client.recv(4096)
                    if not part:
                        break
                    response += part
                assert response.endswith(b'OK'), response
        host.wait(timeout=12)
        text = re.sub(r'\x1b\[[0-9;]*m', '', log.read_text())
        matched = text.count('outbound/direct[process-matched]: outbound connection')
        failures = text.count('failed to search process')
        if expect_failure:
            assert failures == 6 and matched == 0, text
        else:
            assert matched == 6 and failures == 0, text
            assert text.count('user: ' + pwd.getpwuid(os.getuid()).pw_name) == 6, text
        print(f'GUI Core fixture: {matched}/6 process rules matched; {failures} process-search failures; all HTTP responses OK')
    finally:
        # The temporary app owns/stops only its child Core after eight seconds.
        if host.poll() is None:
            host.wait(timeout=12)
        server.shutdown()
