#!/usr/bin/env python3
# ============================================================================
#  Pins the LSP workspace root to the repo root, then hands off to lspmux.
# ============================================================================
#
#  WHY THIS EXISTS:
#    lspmux keys its shared instances on InstanceKey{server, args, env,
#    workspace_root} (client.rs). workspace_root is resolved in this order
#    (select_workspace_root, client.rs:276):
#
#        1. initialize.workspaceFolders[0].uri
#        2. initialize.rootUri        (deprecated)
#        3. initialize.rootPath       (deprecated)
#        4. the client process cwd    <- LAST RESORT ONLY
#
#    Claude Code's rust-analyzer plugin announces the *nearest Cargo root* it
#    cares about (e.g. .../cvyuh-systems/am2), while nvim's rust.lua pins
#    root_dir to .../cvyuh-systems. Different workspace_root = different key =
#    two full analyzers, ~10GB each, no sharing. Launch directory is NOT the
#    cause and cd'ing cannot fix it -- cwd is only consulted when the client
#    sends no root at all.
#
#    So we rewrite the handshake: any client whose announced root falls inside
#    the repo gets rewritten to the repo root, and they all collapse onto ONE
#    instance. Clients outside the repo pass through untouched, so unrelated
#    Rust projects keep their own analyzers.
#
#    Safe because rust-analyzer auto-discovers every Cargo root beneath the
#    repo root anyway -- that is exactly what nvim has always asked for.
#
#  INVOKED BY: ./rust-analyzer (the shim). Not meant to be run by hand.
# ============================================================================

import json
import os
import subprocess
import sys
import threading
import time
from urllib.parse import unquote, urlparse

REPO = "/home/sitaram/code/cvyuh-systems"
REPO_URI = "file://" + REPO
LSPMUX = "/home/sitaram/.cargo/bin/lspmux"
REAL = "/home/sitaram/.rustup/toolchains/stable-x86_64-unknown-linux-gnu/bin/rust-analyzer"

# --- rolling log -----------------------------------------------------------
# stderr is inherited from whoever spawned the shim (nvim, or a Claude session),
# so it does NOT reach the lspmux journal -- which made "did the pin fire?"
# unanswerable. Log to a file instead, so every handshake leaves a trace.
#
# One file, one rule: never exceed 512KB. On overflow the oldest lines are
# dropped from the front. No generations, no age-out -- the ceiling is the
# whole policy.
#
# KEEP is 3/4 of the cap rather than "drop 100 lines" purely to amortise: at
# ~90 bytes/line, trimming 100 lines leaves only ~9KB of headroom, so a log
# sitting at the ceiling would rewrite the entire file every ~50 handshakes.
# Trimming to 384KB does it once per ~1400 lines instead, for identical code.
LOG_DIR = os.path.expanduser("~/.local/state/lspmux-pin")
LOG = os.path.join(LOG_DIR, "pin.log")
MAX_BYTES = 512 * 1024
KEEP_BYTES = 384 * 1024


def log(msg):
    """Best-effort. Logging must never break the LSP session, so all errors
    are swallowed -- a lost log line is strictly better than a dead analyzer.

    Many pinner processes write concurrently. Each record is a single small
    append, which is atomic under PIPE_BUF on Linux. The trim is a read-then-
    rewrite and so can race an append; losing a line or two of a diagnostic
    log roughly once per 1400 is not worth a lockfile."""
    try:
        os.makedirs(LOG_DIR, exist_ok=True)
        with open(LOG, "a") as fh:
            fh.write("%s pid=%d %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), os.getpid(), msg))

        if os.path.getsize(LOG) > MAX_BYTES:
            with open(LOG, "rb") as fh:
                data = fh.read()
            # Cut at the next newline so the file never starts mid-record.
            nl = data.find(b"\n", len(data) - KEEP_BYTES)
            with open(LOG, "wb") as fh:
                fh.write(data[nl + 1:] if nl != -1 else b"")
    except OSError:
        pass


def under_repo(path):
    """True if path is the repo root or inside it. Resolves symlinks so two
    physical paths to the same dir compare equal (same test as rust.lua)."""
    if not path:
        return False
    try:
        rp = os.path.realpath(path)
    except OSError:
        return False
    return rp == REPO or rp.startswith(REPO + os.sep)


def uri_to_path(uri):
    if not uri or not uri.startswith("file://"):
        return None
    return unquote(urlparse(uri).path)


def read_exactly(stream, n):
    buf = b""
    while len(buf) < n:
        chunk = stream.read(n - len(buf))
        if not chunk:
            return None
        buf += chunk
    return buf


def read_message(stream):
    """Read one LSP message. Returns raw bytes, or None at EOF."""
    headers = {}
    while True:
        line = stream.readline()
        if not line:
            return None
        if line in (b"\r\n", b"\n"):
            break
        if b":" in line:
            k, v = line.split(b":", 1)
            headers[k.strip().lower()] = v.strip()
    n = int(headers.get(b"content-length", b"0"))
    return read_exactly(stream, n) if n else b""


def frame(body):
    return b"Content-Length: %d\r\n\r\n%s" % (len(body), body)


def pin_root(body):
    """Rewrite initialize params to the repo root. Returns body unchanged if
    this is not an initialize, is unparseable, or points outside the repo."""
    try:
        msg = json.loads(body)
    except (ValueError, UnicodeDecodeError):
        return body
    if msg.get("method") != "initialize":
        return body
    params = msg.get("params")
    if not isinstance(params, dict):
        return body

    # Diagnostic for the "first client defines the instance config" race: only
    # a client that announces linkedProjects bounds rust-analyzer to our crates.
    # One that does not will auto-discover, which sweeps in _inspirations/ --
    # 12 vendored third-party workspaces that must never be indexed.
    opts = params.get("initializationOptions")
    has_linked = isinstance(opts, dict) and "linkedProjects" in json.dumps(opts)
    log("INIT  linkedProjects=%s" % ("yes" if has_linked else "NO"))

    # Read the root the client is announcing, in lspmux's own precedence order.
    folders = params.get("workspaceFolders")
    announced = None
    if isinstance(folders, list) and folders:
        announced = uri_to_path(folders[0].get("uri"))
    if announced is None:
        announced = uri_to_path(params.get("rootUri"))
    if announced is None:
        announced = params.get("rootPath")
    # No root announced at all: lspmux falls back to cwd, leave it alone.
    if announced is None:
        log("PASS  no root announced, lspmux will use cwd")
        return body

    if not under_repo(announced):
        log("PASS  outside repo: %s" % announced)
        return body
    if os.path.realpath(announced) == REPO:
        log("NOOP  already at repo root")
        return body

    params["rootUri"] = REPO_URI
    params["rootPath"] = REPO
    if isinstance(folders, list) and folders:
        params["workspaceFolders"] = [{"uri": REPO_URI, "name": os.path.basename(REPO)}]

    log("PIN   %s -> %s" % (announced, REPO))
    return json.dumps(msg).encode()


def pump(src, dst):
    try:
        while True:
            chunk = src.read1(65536) if hasattr(src, "read1") else src.read(65536)
            if not chunk:
                break
            dst.write(chunk)
            dst.flush()
    except (BrokenPipeError, ValueError, OSError):
        pass
    finally:
        try:
            dst.close()
        except OSError:
            pass


def main():
    child = subprocess.Popen(
        [LSPMUX, "client", "--server-path", REAL] + sys.argv[1:],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
    )

    # Patch the first message (the initialize handshake), forward the rest raw.
    first = read_message(sys.stdin.buffer)
    if first is not None:
        child.stdin.write(frame(pin_root(first)))
        child.stdin.flush()

    threading.Thread(target=pump, args=(sys.stdin.buffer, child.stdin), daemon=True).start()
    pump(child.stdout, sys.stdout.buffer)
    return child.wait()


if __name__ == "__main__":
    sys.exit(main())
