#!/usr/bin/env python3
"""RemoteDev PC companion server.

Claude Code の会話/進捗/スキル/MCP 設定を iOS アプリへ WiFi 経由で公開する。
Python 標準ライブラリのみ (pip 不要)。起動: python server.py [port]
"""
import json
import re
import socket
import sys
import urllib.parse
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
    print(f"RemoteDev PC companion: http://{lan_ip()}:{port}")
    print("iOS の「設定 > PC」にこの IP:ポートを入力してください。Ctrl+C で終了。")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n停止しました。")


if __name__ == "__main__":
    main()
