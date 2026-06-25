"""
Stop the Paper server after IDLE_MINUTES of zero players.
Run via a systemd timer every 5 minutes.
"""
import os
import re
import socket
import struct
import subprocess
import sys
import time

RCON_HOST     = "127.0.0.1"
RCON_PORT     = 25575
RCON_PASSWORD = "mc-rcon-local"
IDLE_MINUTES  = 15
IDLE_FILE     = "/tmp/mc-paper-idle-since"
SERVICE       = "minecraft-server-paper"


def rcon_packet(req_id, req_type, payload):
    body = struct.pack("<ii", req_id, req_type) + payload.encode("utf-8") + b"\x00\x00"
    return struct.pack("<i", len(body)) + body


def rcon_recv(s):
    length = struct.unpack("<i", s.recv(4))[0]
    data = b""
    while len(data) < length:
        chunk = s.recv(length - len(data))
        if not chunk:
            raise EOFError
        data += chunk
    req_id = struct.unpack("<i", data[:4])[0]
    return req_id, data[8:-2].decode("utf-8")


def player_count():
    s = socket.create_connection((RCON_HOST, RCON_PORT), timeout=3)
    s.sendall(rcon_packet(1, 3, RCON_PASSWORD))
    rcon_recv(s)  # auth response
    s.sendall(rcon_packet(2, 2, "list"))
    _, response = rcon_recv(s)
    s.close()
    m = re.search(r"There are (\d+)", response)
    return int(m.group(1)) if m else None


def server_is_active():
    result = subprocess.run(
        ["systemctl", "is-active", "--quiet", SERVICE],
        capture_output=True,
    )
    return result.returncode == 0


def main():
    if not server_is_active():
        try:
            os.unlink(IDLE_FILE)
        except FileNotFoundError:
            pass
        sys.exit(0)

    try:
        count = player_count()
    except Exception as e:
        print(f"RCON error: {e}", flush=True)
        sys.exit(0)

    if count is None or count > 0:
        try:
            os.unlink(IDLE_FILE)
        except FileNotFoundError:
            pass
        sys.exit(0)

    now = time.time()
    if not os.path.exists(IDLE_FILE):
        with open(IDLE_FILE, "w") as f:
            f.write(str(now))
        print("Server empty — idle timer started.", flush=True)
        sys.exit(0)

    idle_secs = now - float(open(IDLE_FILE).read().strip())
    print(f"Server empty for {idle_secs / 60:.1f} min (limit: {IDLE_MINUTES} min)", flush=True)

    if idle_secs >= IDLE_MINUTES * 60:
        print("Stopping server due to inactivity.", flush=True)
        subprocess.run(["systemctl", "stop", SERVICE])
        try:
            os.unlink(IDLE_FILE)
        except FileNotFoundError:
            pass


if __name__ == "__main__":
    main()
