#!/usr/bin/env python3
"""RemoteDev PC companion server.

Claude Code の会話/進捗/スキル/MCP 設定を iOS アプリへ WiFi 経由で公開する。
Python 標準ライブラリのみ (pip 不要)。起動: python server.py [port]
"""
import json
import os
import re
import socket
import struct
import sys
import urllib.parse
import zlib
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HOME = Path.home()
CLAUDE_DIR = HOME / ".claude"
PROJECTS = CLAUDE_DIR / "projects"
SKILLS = CLAUDE_DIR / "skills"
DEFAULT_PORT = 8000
MAX_TURNS = 50
MAX_PROGRESS_LINES = 15


def lan_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


def extract_text(msg):
    """ChatMessage からテキストを取り出す (tool_use/tool_result/thinking は除外)。"""
    if not isinstance(msg, dict):
        return None
    content = msg.get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = [
            c.get("text", "").strip()
            for c in content
            if isinstance(c, dict) and c.get("type") == "text" and c.get("text")
        ]
        return "\n".join(parts).strip() or None
    return None


def parse_transcript(path, max_turns=MAX_TURNS):
    turns = []
    for line in path.open(encoding="utf-8", errors="replace"):
        line = line.strip()
        if not line:
            continue
        try:
            d = json.loads(line)
        except (json.JSONDecodeError, ValueError):
            continue
        if d.get("type") not in ("user", "assistant"):
            continue
        msg = d.get("message") or {}
        role = msg.get("role") if isinstance(msg, dict) else None
        if role not in ("user", "assistant"):
            continue
        text = extract_text(msg)
        if not text:
            continue
        turns.append({"role": role, "text": text[:4000]})
    return turns[-max_turns:]


def list_conversations():
    out = []
    if not PROJECTS.is_dir():
        return out
    files = sorted(PROJECTS.glob("*/*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)
    for f in files:
        try:
            count = 0
            preview = ""
            for line in f.open(encoding="utf-8", errors="replace"):
                line = line.strip()
                if not line:
                    continue
                try:
                    d = json.loads(line)
                except (json.JSONDecodeError, ValueError):
                    continue
                if d.get("type") not in ("user", "assistant"):
                    continue
                msg = d.get("message") or {}
                count += 1
                text = extract_text(msg)
                if text:
                    preview = text
            out.append({
                "id": f.relative_to(PROJECTS).as_posix(),
                "project": f.parent.name,
                "name": f.stem[:8],
                "mtime": datetime.fromtimestamp(f.stat().st_mtime).isoformat(timespec="seconds"),
                "messages": count,
                "preview": preview[:120],
            })
        except OSError:
            continue
    return out


def progress():
    if not PROJECTS.is_dir():
        return {"file": None, "entries": []}
    files = sorted(PROJECTS.glob("*/*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not files:
        return {"file": None, "entries": []}
    f = files[0]
    with f.open(encoding="utf-8", errors="replace") as fh:
        tail = fh.readlines()[-MAX_PROGRESS_LINES:]
    entries = []
    for line in tail:
        line = line.strip()
        if not line:
            continue
        try:
            d = json.loads(line)
        except (json.JSONDecodeError, ValueError):
            continue
        t = d.get("type")
        if t not in ("user", "assistant"):
            continue
        msg = d.get("message") or {}
        role = msg.get("role") if isinstance(msg, dict) else None
        text = extract_text(msg)
        ts = str(d.get("timestamp", ""))
        entries.append({
            "role": role or t,
            "text": (text or "")[:200],
            "timestamp": ts[11:19] if len(ts) >= 19 else ts,
        })
    return {"file": f.relative_to(PROJECTS).as_posix(), "entries": entries}


def list_skills():
    out = []
    if not SKILLS.is_dir():
        return out
    for d in sorted(SKILLS.iterdir()):
        md = d / "SKILL.md"
        if not d.is_dir() or not md.is_file():
            continue
        text = md.read_text(encoding="utf-8", errors="replace")
        name = d.name
        description = ""
        fm = re.match(r"^---\s*\n(.*?)\n---", text, re.S)
        if fm:
            for line in fm.group(1).splitlines():
                if line.startswith("name:"):
                    name = line.split(":", 1)[1].strip() or name
                elif line.startswith("description:") and not description:
                    description = line.split(":", 1)[1].strip()
        out.append({"id": d.name, "name": name, "description": description[:200]})
    return out


def get_skill(name):
    d = (SKILLS / name).resolve()
    if not d.is_relative_to(SKILLS.resolve()):
        return None
    md = d / "SKILL.md"
    if not md.is_file():
        return None
    return md.read_text(encoding="utf-8", errors="replace")


def mcp_servers():
    merged = {}
    candidates = [
        HOME / ".claude.json",
        CLAUDE_DIR / "settings.json",
        Path.cwd() / ".mcp.json",
    ]

    def ingest(d, label):
        if not isinstance(d, dict):
            return
        for k, v in d.items():
            if k == "mcpServers" and isinstance(v, dict):
                for name, cfg in v.items():
                    if isinstance(cfg, dict):
                        merged[name] = cfg
            elif isinstance(v, dict):
                ingest(v, label)

    for p in candidates:
        if p.is_file():
            try:
                ingest(json.load(open(p, encoding="utf-8")), str(p))
            except (json.JSONDecodeError, ValueError, OSError):
                continue
    return [
        {
            "name": k,
            "command": (v.get("command") if isinstance(v, dict) else None),
            "type": (v.get("type") if isinstance(v, dict) else None),
        }
        for k, v in merged.items()
    ]


# --- QR code (byte mode, ECC L, v1-6) + PNG. Pure stdlib. ---
_QR_EXP = [0] * 512
_QR_LOG = [0] * 256
_qx = 1
for _i in range(255):
    _QR_EXP[_i] = _qx
    _QR_LOG[_qx] = _i
    _qx <<= 1
    if _qx & 0x100:
        _qx ^= 0x11D
for _i in range(255, 512):
    _QR_EXP[_i] = _QR_EXP[_i - 255]

_QR_DATA = {1: 19, 2: 34, 3: 55, 4: 80, 5: 108, 6: 136}
_QR_TOTAL = {1: 26, 2: 44, 3: 70, 4: 100, 5: 134, 6: 172}
_QR_CAP = {1: 17, 2: 32, 3: 53, 4: 78, 5: 106, 6: 134}
_QR_ALIGN = {1: [], 2: [6, 18], 3: [6, 22], 4: [6, 26], 5: [6, 30], 6: [6, 34]}
_QR_MASKS = [
    lambda r, c: (r + c) % 2 == 0,
    lambda r, c: r % 2 == 0,
    lambda r, c: c % 3 == 0,
    lambda r, c: (r + c) % 3 == 0,
    lambda r, c: (r // 2 + c // 3) % 2 == 0,
    lambda r, c: (r * c) % 2 + (r * c) % 3 == 0,
    lambda r, c: ((r * c) % 2 + (r * c) % 3) % 2 == 0,
    lambda r, c: ((r + c) % 2 + (r * c) % 3) % 2 == 0,
]
_QR_FORMAT1 = [(8, 0), (8, 1), (8, 2), (8, 3), (8, 4), (8, 5), (8, 7), (8, 8),
               (7, 8), (5, 8), (4, 8), (3, 8), (2, 8), (1, 8), (0, 8)]


def _qrmul(a, b):
    if a == 0 or b == 0:
        return 0
    return _QR_EXP[(_QR_LOG[a] + _QR_LOG[b]) % 255]


def _qr_rs_generator(n):
    gen = [1]
    for i in range(n):
        nxt = [0] * (len(gen) + 1)
        for j, c in enumerate(gen):
            nxt[j] ^= c
            nxt[j + 1] ^= _qrmul(c, _QR_EXP[i])
        gen = nxt
    return gen


def _qr_rs_remainder(data, generator):
    res = data + [0] * (len(generator) - 1)
    for i in range(len(data)):
        coef = res[i]
        if coef:
            for j, g in enumerate(generator):
                res[i + j] ^= _qrmul(g, coef)
    return res[len(data):]


def _qr_format_info(mask):
    data = (0b01 << 3) | mask
    rem = data << 10
    for i in range(14, 9, -1):
        if (rem >> i) & 1:
            rem ^= 0x537 << (i - 10)
    return ((data << 10) | rem) ^ 0x5412


def _qr_matrix(version, codewords, mask):
    n = 17 + 4 * version
    m = [[None] * n for _ in range(n)]

    def finder(r0, c0):
        for r in range(-1, 8):
            for c in range(-1, 8):
                rr, cc = r0 + r, c0 + c
                if not (0 <= rr < n and 0 <= cc < n):
                    continue
                if r in (-1, 7) or c in (-1, 7):
                    m[rr][cc] = 0
                elif r in (0, 6) or c in (0, 6):
                    m[rr][cc] = 1
                elif 2 <= r <= 4 and 2 <= c <= 4:
                    m[rr][cc] = 1
                else:
                    m[rr][cc] = 0

    finder(0, 0)
    finder(0, n - 7)
    finder(n - 7, 0)
    for i in range(8, n - 8):
        m[6][i] = i % 2 == 0
        m[i][6] = i % 2 == 0
    for cr in _QR_ALIGN[version]:
        for cc in _QR_ALIGN[version]:
            if m[cr][cc] is not None:
                continue
            for r in range(-2, 3):
                for c in range(-2, 3):
                    m[cr + r][cc + c] = 1 if max(abs(r), abs(c)) != 1 else 0
    m[4 * version + 9][8] = 1
    n8 = n - 8
    fmt2 = [(8, n8 + i) for i in range(8)] + [(n8 + i, 8) for i in range(1, 8)]
    for r, c in _QR_FORMAT1 + fmt2:
        m[r][c] = 0

    bits = []
    for b in codewords:
        bits += [(b >> (7 - i)) & 1 for i in range(8)]
    mask_fn = _QR_MASKS[mask]
    idx = 0
    col = n - 1
    upward = True
    while col > 0:
        if col == 6:
            col -= 1
        rows = range(n - 1, -1, -1) if upward else range(n)
        for r in rows:
            for dc in (col, col - 1):
                if m[r][dc] is not None:
                    continue
                bit = bits[idx] if idx < len(bits) else 0
                idx += 1
                if mask_fn(r, dc):
                    bit ^= 1
                m[r][dc] = bit
        col -= 2
        upward = not upward

    fb = [(_qr_format_info(mask) >> (14 - i)) & 1 for i in range(15)]
    for (r, c), b in zip(_QR_FORMAT1, fb):
        m[r][c] = b
    for (r, c), b in zip(fmt2, fb):
        m[r][c] = b
    return m


def _qr_penalty(m):
    n = len(m)
    score = 0
    rows = ["".join("1" if x else "0" for x in row) for row in m]
    cols = ["".join("1" if m[r][c] else "0" for r in range(n)) for c in range(n)]
    for seq in rows + cols:
        for match in re.findall(r"1{5,}|0{5,}", seq):
            score += 3 + (len(match) - 5)
    for r in range(n - 1):
        for c in range(n - 1):
            if m[r][c] == m[r][c + 1] == m[r + 1][c] == m[r + 1][c + 1]:
                score += 3
    for seq in rows + cols:
        score += 40 * len(re.findall(r"10111010000|00001011101", seq))
    score += int(abs(sum(sum(row) for row in m) * 100 / (n * n) - 50) / 5) * 10
    return score


def _qr_encode(payload):
    data = list(payload)
    version = next(v for v in range(1, 7) if len(data) <= _QR_CAP[v])
    bits = [0, 1, 0, 0] + [(len(data) >> (7 - i)) & 1 for i in range(8)]
    for b in data:
        bits += [(b >> (7 - i)) & 1 for i in range(8)]
    while len(bits) % 8:
        bits.append(0)
    pad = 0xEC
    while len(bits) < _QR_DATA[version] * 8:
        bits += [(pad >> (7 - i)) & 1 for i in range(8)]
        pad = 0x11 if pad == 0xEC else 0xEC
    codewords = [int("".join(map(str, bits[i:i + 8])), 2) for i in range(0, len(bits), 8)]
    ecc = _qr_rs_remainder(codewords, _qr_rs_generator(_QR_TOTAL[version] - _QR_DATA[version]))
    codewords += ecc
    best, best_m = None, None
    for mm in range(8):
        mat = _qr_matrix(version, codewords, mm)
        score = _qr_penalty(mat)
        if best is None or score < best:
            best, best_m = score, mm
    return _qr_matrix(version, codewords, best_m)


def _qr_png(matrix, scale=12, quiet=4):
    n = len(matrix)
    size = (n + 2 * quiet) * scale
    px = [[0xFF] * size for _ in range(size)]
    for r in range(n):
        for c in range(n):
            if matrix[r][c]:
                for y in range(scale):
                    for x in range(scale):
                        px[(r + quiet) * scale + y][(c + quiet) * scale + x] = 0

    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)

    raw = b"".join(b"\x00" + bytes(row) for row in px)
    ihdr = struct.pack(">IIBBBBB", size, size, 8, 0, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def pair_payload(ip, port):
    return f"RemoteDev|1|{ip}|{port}"


class Handler(BaseHTTPRequestHandler):
    server_version = "RemoteDevPC/0.2"
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        sys.stderr.write("[%s] %s\n" % (self.log_date_time_string(), fmt % args))

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        qs = urllib.parse.parse_qs(parsed.query)
        try:
            if path == "/":
                self.send_text("RemoteDev PC companion is running. See README for API endpoints.")
            elif path == "/api/health":
                self.send_json({"ok": True, "service": "RemoteDev PC companion"})
            elif path == "/api/conversations":
                self.send_json({"conversations": list_conversations()})
            elif path == "/api/progress":
                self.send_json(progress())
            elif path == "/api/transcript":
                ids = qs.get("id")
                if not ids:
                    self.send_json({"error": "missing id"}, 400)
                    return
                full = (PROJECTS / ids[0]).resolve()
                if not full.is_relative_to(PROJECTS.resolve()) or not full.is_file():
                    self.send_json({"error": "invalid id"}, 404)
                    return
                self.send_json({"turns": parse_transcript(full)})
            elif path == "/api/skills":
                self.send_json({"skills": list_skills()})
            elif path == "/api/skill":
                names = qs.get("name")
                if not names:
                    self.send_json({"error": "missing name"}, 400)
                    return
                body = get_skill(names[0])
                if body is None:
                    self.send_json({"error": "not found"}, 404)
                    return
                self.send_json({"name": names[0], "content": body})
            elif path == "/api/mcp":
                self.send_json({"servers": mcp_servers()})
            elif path == "/api/pair":
                self.send_json({"payload": pair_payload(lan_ip(), self.server.server_port)})
            else:
                self.send_json({"error": "not found", "path": path}, 404)
        except Exception as e:  # noqa: BLE001
            self.send_json({"error": repr(e)}, 500)

    def send_json(self, obj, code=200):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_text(self, text):
        body = text.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def show_pair_qr(ip, port):
    payload = pair_payload(ip, port)
    mat = _qr_encode(payload.encode("utf-8"))
    png = _qr_png(mat)
    out = Path(__file__).resolve().parent / "pair.png"
    out.write_bytes(png)
    print()
    print("== QR ペアリング ==")
    print(f"iOS の「PC同期」タブで QR を読み取ると自動接続します (pair.png を開いています)")
    print(f"ペアリング情報: {payload}")
    print()
    for row in mat:
        print("  " + "".join("██" if x else "  " for x in row))
    print()
    try:
        os.startfile(str(out))  # Windows で画像ビューアを開く
    except (AttributeError, OSError):
        print(f"QR 画像: {out}（手動で開いてください）")


def main():
    port = DEFAULT_PORT
    if len(sys.argv) > 1:
        try:
            port = int(sys.argv[1])
        except ValueError:
            print("usage: python server.py [port]")
            sys.exit(1)
    httpd = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    httpd.daemon_threads = True
    ip = lan_ip()
    print(f"RemoteDev PC companion: http://{ip}:{port}")
    print("Ctrl+C で終了。")
    show_pair_qr(ip, port)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n停止しました。")


if __name__ == "__main__":
    main()
