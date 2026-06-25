"""
Minecraft wakeup proxy.
- Paper sleeping: shows "Sleeping" MOTD on status ping; starts Paper and
  kicks the player with a reconnect message on login.
- Paper up: transparent TCP proxy to localhost:25566.
"""
import json
import socket
import subprocess
import threading

LISTEN_PORT = 25565
PAPER_PORT  = 25566
SERVICE     = "minecraft-server-paper"


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
    """Read a VarInt from socket; return (value, raw_bytes)."""
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
    """Return (raw_bytes, packet_id, payload) for one packet."""
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
    # Skip protocol version (varint)
    while payload[i] & 0x80:
        i += 1
    i += 1
    # Skip server address string (varint length + bytes)
    slen, shift = 0, 0
    while True:
        b = payload[i]; i += 1
        slen |= (b & 0x7F) << shift
        if not (b & 0x80):
            break
        shift += 7
    i += slen + 2  # string bytes + port (u16)
    return payload[i] & 0x7F


# ── Responses ─────────────────────────────────────────────────────────────────

def send_status(s):
    status = {
        "version": {"name": "Sleeping", "protocol": -1},
        "players": {"max": 0, "online": 0, "sample": []},
        "description": {"text": "§6Server sleeping §8— §aconnect to wake it up"},
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
            proxy_connection(client, raw)
            return

        if next_state == 1:  # Status ping
            read_raw_packet(client)  # consume Status Request
            send_status(client)
        elif next_state == 2:  # Login
            read_raw_packet(client)  # consume Login Start
            subprocess.Popen(["systemctl", "start", SERVICE])
            send_disconnect(
                client,
                "§aServer is waking up!\n§7Reconnect in about 20 seconds.",
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
