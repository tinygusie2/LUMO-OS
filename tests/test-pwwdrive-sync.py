#!/usr/bin/python3
import http.server
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse

TOOL = pathlib.Path(__file__).resolve().parent.parent / "packages/native/lumo-desktop/data/pwwdrive/lumo-pwwdrive"


class Fake:
    def __init__(self):
        self.next_id = 100
        self.folders = [{"id": 1, "parentId": None, "naam": "Wiskunde"}]
        self.files = {}
        self.deleted = []
        self.add("oud.txt", b"server", None)
        self.add("som.txt", b"breuken", 1)

    def add(self, name, content, folder):
        self.next_id += 1
        item = {"id": self.next_id, "name": name, "path": f"p{self.next_id}", "folderId": folder,
                "size": len(content), "date": str(self.next_id)}
        self.files[item["path"]] = (item, content)
        return item

    def replace(self, path, content):
        item, _ = self.files[path]
        self.next_id += 1
        item.update(size=len(content), date=str(self.next_id))
        self.files[path] = (item, content)
        return item

    def named(self, name):
        return next(item for item, _ in self.files.values() if item["name"] == name)


fake = Fake()


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def answer(self, value, code=200, raw=None):
        body = raw if raw is not None else json.dumps(value).encode()
        self.send_response(code)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def body(self):
        return self.rfile.read(int(self.headers.get("Content-Length") or 0))

    def authorised(self):
        if self.headers.get("Authorization") == "Bearer id-token":
            return True
        self.answer({}, 401)
        return False

    def upload(self):
        boundary = self.headers["Content-Type"].split("boundary=")[1].encode()
        name = content = folder = None
        for part in self.body().split(b"--" + boundary):
            head, _, data = part.partition(b"\r\n\r\n")
            data = data[:-2]
            found = re.search(rb'filename="([^"]*)"', head)
            if found:
                name, content = found.group(1).decode(), data
            elif b'name="folderId"' in head:
                folder = int(data)
        return name, content, folder

    def do_GET(self):
        if self.path == "/api/firebase-config":
            self.answer({"apiKey": "key"})
        elif not self.authorised():
            return
        elif self.path == "/api/file-folders":
            self.answer(fake.folders)
        elif self.path == "/api/files":
            self.answer([item for item, _ in fake.files.values()])
        elif self.path.startswith("/api/user-file/"):
            path = urllib.parse.unquote(self.path.rsplit("/", 1)[1])
            self.answer(None, raw=fake.files[path][1])
        else:
            self.answer({}, 404)

    def do_POST(self):
        if self.path.startswith("/token"):
            self.body()
            self.answer({"id_token": "id-token", "expires_in": "3600"})
        elif not self.authorised():
            return
        elif self.path == "/api/files":
            name, content, folder = self.upload()
            self.answer(fake.add(name, content, folder))
        elif self.path.endswith("/overwrite"):
            _, content, _ = self.upload()
            self.answer(fake.replace(self.path.split("/")[3], content))
        elif self.path == "/api/file-folders":
            data = json.loads(self.body())
            fake.next_id += 1
            folder = {"id": fake.next_id, "parentId": data["parentId"], "naam": data["name"]}
            fake.folders.append(folder)
            self.answer(folder)
        else:
            self.answer({}, 404)

    def do_DELETE(self):
        if not self.authorised():
            return
        identifier = int(self.path.rsplit("/", 1)[1])
        for path, (item, _) in list(fake.files.items()):
            if item["id"] == identifier:
                del fake.files[path]
                fake.deleted.append(item["name"])
        self.answer({})


def check(condition, message):
    if not condition:
        print("FAIL: " + message)
        sys.exit(1)
    print("ok: " + message)


def main():
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{server.server_port}"
    work = pathlib.Path(tempfile.mkdtemp())
    root = work / "PWWDrive"
    app = work / "app"
    app.mkdir()
    (app / "config.json").write_text(json.dumps({"refresh": "r"}))
    env = dict(os.environ, PWWDRIVE_URL=base, PWWDRIVE_TOKEN_URL=base + "/token",
               PWWDRIVE_APPDIR=str(app), PWWDRIVE_MAP=str(root))

    def run(command="sync"):
        return subprocess.run([sys.executable, "-I", str(TOOL), command], env=env,
                              capture_output=True, text=True, check=False)

    def trash():
        folder = root / ".pwwdrive-prullenbak"
        return [p.name for p in folder.iterdir()] if folder.exists() else []

    result = run()
    check(result.returncode == 0, "first round runs: " + result.stdout + result.stderr)
    check((root / "oud.txt").read_bytes() == b"server", "a file comes down")
    check((root / "Wiskunde/som.txt").read_bytes() == b"breuken", "a file in a folder comes down")

    (root / "nieuw één.txt").write_bytes(b"lokaal")
    (root / "Natuurkunde").mkdir()
    (root / "Natuurkunde/krachten.txt").write_bytes(b"kracht")
    run()
    check(fake.named("nieuw één.txt") is not None, "a new local file with a non-ASCII name goes up")
    check(any(f["naam"] == "Natuurkunde" for f in fake.folders), "a new local folder goes up")
    check(fake.named("krachten.txt")["folderId"] is not None, "a file lands in its new folder")

    time.sleep(0.01)
    (root / "oud.txt").write_bytes(b"lokaal bewerkt")
    run()
    path = fake.named("oud.txt")["path"]
    check(fake.files[path][1] == b"lokaal bewerkt", "a local edit overwrites the server")
    check(any("vorige versie uit PWWDrive" in n for n in trash()), "the old server version is kept")

    fake.replace(fake.named("som.txt")["path"], b"nieuwe breuken")
    run()
    check((root / "Wiskunde/som.txt").read_bytes() == b"nieuwe breuken", "a server edit comes down")
    check(any("vorige versie" in n for n in trash()), "the old local version is kept")

    fake.replace(path, b"server wint")
    (root / "oud.txt").write_bytes(b"allebei gewijzigd")
    run()
    conflicts = list(root.glob("oud (conflict *).txt"))
    check((root / "oud.txt").read_bytes() == b"server wint", "a conflict takes the server version")
    check(len(conflicts) == 1 and conflicts[0].read_bytes() == b"allebei gewijzigd", "a conflict keeps the local version")
    run()

    (root / "nieuw één.txt").unlink()
    run()
    check("nieuw één.txt" in fake.deleted, "a local delete goes to the PWWDrive trash")

    victim = fake.named("krachten.txt")
    del fake.files[victim["path"]]
    run()
    check(not (root / "Natuurkunde/krachten.txt").exists(), "a server delete removes the local copy")
    check(any("krachten" in n for n in trash()), "a server delete keeps a local copy in the trash")

    for number in range(12):
        fake.add(f"bulk{number}.txt", b"x", None)
    run()
    for number in range(12):
        (root / f"bulk{number}.txt").unlink()
    before = len(fake.deleted)
    result = run()
    check(result.returncode == 1 and len(fake.deleted) == before, "mass deletion stops the sync")
    status = subprocess.run([sys.executable, "-I", str(TOOL), "status"], env=env, capture_output=True, text=True, check=False)
    check("status=paused" in status.stdout, "the pause is reported")
    run("allow")
    check(len(fake.deleted) == before + 12, "allowing it goes on")

    state = (app / "staat.json").read_text()
    check(not re.search(r"id-token|\"refresh\"", state), "the sync state holds no tokens")
    check(oct((app / "config.json").stat().st_mode)[-3:] in ("600", "644"), "the config exists")
    print("PWWDRIVE_SYNC_OK")


main()
