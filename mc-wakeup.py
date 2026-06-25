"""
Minecraft wakeup proxy.
- Paper sleeping: shows "Sleeping" MOTD; starts Paper on login.
- Paper starting: shows "Starting... X%" in the server list (updates each ping).
- Paper up: transparent TCP proxy to localhost:25566.
"""
import json
import socket
import subprocess
import threading
import time

LISTEN_PORT          = 25565
PAPER_PORT           = 25566
SERVICE              = "minecraft-server-paper"
EXPECTED_STARTUP_SEC = 25   # tune if Paper is consistently faster/slower
STARTUP_TIMEOUT_SEC  = 90   # reset start time if server never came up

_start_time      = None
_start_time_lock = threading.Lock()


def _mark_starting():
    global _start_time
    with _start_time_lock:
        if _start_time is None:
            _start_time = time.monotonic()


def _clear_start_time():
    global _start_time
    with _start_time_lock:
        _start_time = None


def _startup_progress():
    """Return 0-95 while starting, None when idle/sleeping."""
    with _start_time_lock:
        if _start_time is None:
            return None
        elapsed = time.monotonic() - _start_time
        if elapsed > STARTUP_TIMEOUT_SEC:
            # Server never came up — reset so next attempt works cleanly
            _start_time = None
            return None
        return min(95, int(elapsed / EXPECTED_STARTUP_SEC * 100))


# ── Protocol helpers ──────────────────────────────────────────────────────────

def _recv_exact(s, n):
    buf = b""
    while len(buf) < n:
        chunk = s.recv(n - len(buf))
        if not chunk:
            raise EOFError
        buf += chunk
    return buf


def _read_varint_raw(s):
    raw, n, shift = bytearray(), 0, 0
    for _ in range(5):
        b = s.recv(1)
        if not b:
            raise EOFError
        raw += b
        byte = b[0]
        n |= (byte & 0x7F) << shift
        if not (byte & 0x80):
            return n, bytes(raw)
        shift += 7
    raise ValueError("VarInt too long")


def read_raw_packet(s):
    length, raw_len = _read_varint_raw(s)
    payload = _recv_exact(s, length)
    i, pid, shift = 0, 0, 0
    while True:
        byte = payload[i]; i += 1
        pid |= (byte & 0x7F) << shift
        if not (byte & 0x80):
            break
        shift += 7
    return raw_len + payload, pid, payload[i:]


def _encode_varint(n):
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            b |= 0x80
        out.append(b)
        if not n:
            return bytes(out)


def _encode_string(s):
    b = s.encode("utf-8")
    return _encode_varint(len(b)) + b


def _encode_packet(pid, *parts):
    body = _encode_varint(pid) + b"".join(parts)
    return _encode_varint(len(body)) + body


# ── Handshake parsing ─────────────────────────────────────────────────────────

def parse_next_state(payload):
    i = 0
    while payload[i] & 0x80:
        i += 1
    i += 1
    slen, shift = 0, 0
    while True:
        b = payload[i]; i += 1
        slen |= (b & 0x7F) << shift
        if not (b & 0x80):
            break
        shift += 7
    i += slen + 2
    return payload[i] & 0x7F


# ── Responses ─────────────────────────────────────────────────────────────────

def send_status(s):
    progress = _startup_progress()
    if progress is not None:
        desc = f"§aStarting... {progress}%"
        version_name = f"Starting {progress}%"
    else:
        desc = "§6Sleeping §8— §aconnect to wake up"
        version_name = "Sleeping"

    status = {
        "version": {"name": version_name, "protocol": -1},
        "players": {"max": 0, "online": 0, "sample": []},
        "description": {"text": desc},
    }
    s.sendall(_encode_packet(0x00, _encode_string(json.dumps(status))))
    try:
        s.settimeout(2)
        raw, pid, payload = read_raw_packet(s)
        if pid == 0x01:
            s.sendall(_encode_packet(0x01, payload))
    except OSError:
        pass


def send_disconnect(s, message):
    s.sendall(_encode_packet(0x00, _encode_string(json.dumps({"text": message}))))


# ── Proxy ─────────────────────────────────────────────────────────────────────

def _pipe(src, dst):
    try:
        while data := src.recv(4096):
            dst.sendall(data)
    except OSError:
        pass
    finally:
        for sock in (src, dst):
            try:
                sock.close()
            except OSError:
                pass


def proxy_connection(client, initial_raw):
    try:
        backend = socket.create_connection(("127.0.0.1", PAPER_PORT), timeout=5)
    except OSError:
        client.close()
        return
    backend.sendall(initial_raw)
    t1 = threading.Thread(target=_pipe, args=(client, backend), daemon=True)
    t2 = threading.Thread(target=_pipe, args=(backend, client), daemon=True)
    t1.start()
    t2.start()
    t1.join()
    t2.join()


def paper_is_up():
    try:
        s = socket.create_connection(("127.0.0.1", PAPER_PORT), timeout=0.5)
        s.close()
        return True
    except OSError:
        return False


# ── Client handler ────────────────────────────────────────────────────────────

def handle(client):
    try:
        client.settimeout(10)
        raw, pid, payload = read_raw_packet(client)
        if pid != 0x00:
            return
        next_state = parse_next_state(payload)

        if paper_is_up():
            _clear_start_time()
            proxy_connection(client, raw)
            return

        if next_state == 1:  # Status ping
            read_raw_packet(client)
            send_status(client)
        elif next_state == 2:  # Login
            read_raw_packet(client)
            _mark_starting()
            subprocess.Popen(["systemctl", "start", SERVICE])
            send_disconnect(
                client,
                "§aServer is waking up!\n§7Watch the progress in the server list\n§7and reconnect when it hits 100%.",
            )
    except Exception:
        pass
    finally:
        try:
            client.close()
        except OSError:
            pass


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("0.0.0.0", LISTEN_PORT))
    srv.listen(50)
    print(f"mc-wakeup listening on :{LISTEN_PORT} → :{PAPER_PORT}", flush=True)
    while True:
        client, _ = srv.accept()
        threading.Thread(target=handle, args=(client,), daemon=True).start()


if __name__ == "__main__":
    main()
