#!/usr/bin/env python3
"""Pre-build every linked Rust crate, so nothing compiles when it is needed.

WHY THIS EXISTS
    The dev pods run `cargo watch -x run` against the bind-mounted repo, and
    ~/code/cvyuh-systems/.cargo/config.toml collapses all crates onto ONE
    target/. One target/ means one build-dir lock, so the pods compile strictly
    one at a time — and the order is whichever kubelet started first.

    boot.py has its own order (align → bao → pg → dj → am2 → idm2 → am), and
    bao's k8s-auth step waits on the `provision` pod. Those two orderings know
    nothing about each other. Measured 2026-08-09 on a cold target: `fabrik2`
    took the lock, `provision` queued behind it and two fabrik replicas, and
    boot failed on its 300s readiness wait while the pod it needed had not
    started compiling. Nothing was broken; the build order simply did not match
    the boot order.

    Building here removes the race rather than arbitrating it. Every pod then
    starts against a warm tree and `cargo run` returns in seconds, so boot's
    timing stops depending on compile scheduling. Measured: a cold serial build
    of all eight crates is ~4min, against a 300s-per-workload boot wait that a
    cold pod build loses roughly every time.

    Serial on purpose. Parallel `cargo build` invocations would contend on the
    same lock and gain nothing — the lock is the whole reason this exists.

THE CRATE LIST
    Read from rust-analyzer.toml's `linkedProjects`, the single source this
    repo already declares (see the ⚠️ note in that file). nvim/nvchad/lua/
    configs/lang/rust.lua reads the same array; this is the third reader and
    deliberately not a fourth copy. Add a crate there and everything follows.

USAGE
    warm-rust.py                # build every linked crate
    warm-rust.py --check        # report what is stale, build nothing
    warm-rust.py --quiet        # only failures and the summary

    Called by infra/_utils/server-dev.py before boot, and safe to run by hand.
    Idempotent: an already-warm tree finishes in seconds.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import time
from collections import deque
from pathlib import Path

# This file lives at <repo>/nvim/rust-lsp/, so the repo root is two up. Derived
# rather than hardcoded: the file is versioned and must carry nobody's $HOME.
REPO_ROOT = Path(__file__).resolve().parent.parent.parent
RA_TOML = REPO_ROOT / "nvim" / "rust-lsp" / "rust-analyzer.toml"

# Crates that are libraries only, or not run by a dev pod. Building them still
# warms the shared dependency graph, so they are included — the cost is small
# and a service that later depends on one finds it already built.
SKIP: set[str] = set()


def linked_projects() -> list[Path]:
    """The `linkedProjects` paths from rust-analyzer.toml, repo-relative.

    Deliberately a minimal slice rather than a TOML parser: it stops at the
    closing bracket so the `[files]` table below it is never picked up. Same
    approach as rust.lua's reader, for the same reason — no dependency on a
    TOML library being present.
    """
    if not RA_TOML.is_file():
        sys.exit(f"[warm] missing {RA_TOML} — the crate list lives there")

    out: list[Path] = []
    inside = False
    for raw in RA_TOML.read_text().splitlines():
        line = raw.strip()
        if line.startswith("#"):
            continue
        if not inside:
            if re.match(r"^linkedProjects\s*=\s*\[", line):
                inside = True
            continue
        if "]" in line:
            break
        m = re.search(r'"([^"]+)"', line)
        if m:
            # The array holds paths to Cargo.toml; cargo wants the directory.
            out.append(Path(m.group(1)).parent)

    if not out:
        sys.exit(f"[warm] no linkedProjects found in {RA_TOML}")
    return out


def build(crate: Path, quiet: bool) -> tuple[bool, float, str]:
    d = REPO_ROOT / crate
    if not (d / "Cargo.toml").is_file():
        return True, 0.0, "skipped (no Cargo.toml)"

    # STREAM, don't capture. Follows _tools/kind/kind_core.py's split: sh()
    # streams what you watch, out() captures what you parse. A cold build of
    # this tree is the longest step in the bring-up — measured 20min+ when the
    # disk is the constraint — and a captured one prints nothing until the
    # crate finishes, which is indistinguishable from hung. cargo's own
    # "Compiling <crate>" lines are the progress indicator; let them through.
    #
    # Still tee'd into a small ring buffer: on failure the last lines carry the
    # cause, and scrolling back through a full cold build to find them is worse
    # than keeping twelve of them here.
    t0 = time.monotonic()
    tail: deque[str] = deque(maxlen=12)
    compiled = False

    p = subprocess.Popen(
        ["cargo", "build"], cwd=d, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    )
    assert p.stdout is not None
    for line in p.stdout:
        line = line.rstrip()
        tail.append(line)
        if "Compiling" in line:
            compiled = True
        if not quiet:
            print(f"    {line}", flush=True)
    rc = p.wait()
    dt = time.monotonic() - t0

    if rc != 0:
        return False, dt, "\n".join(tail)

    # "Finished" vs "Compiling" tells warm-from-cache apart from real work,
    # which is the number worth seeing on a re-run.
    return True, dt, "compiled" if compiled else "cached"


def main() -> int:
    ap = argparse.ArgumentParser(description="Pre-build linked Rust crates")
    ap.add_argument("--check", action="store_true",
                    help="list the crates and exit; build nothing")
    ap.add_argument("--quiet", action="store_true",
                    help="print only failures and the summary")
    args = ap.parse_args()

    crates = linked_projects()

    if args.check:
        print(f"[warm] {len(crates)} linked crates from {RA_TOML.name}:")
        for c in crates:
            print(f"         {c}")
        return 0

    print(f"[warm] building {len(crates)} crates serially "
          f"(one shared target/, one lock)", flush=True)

    t0 = time.monotonic()
    failed: list[str] = []
    for c in crates:
        if not args.quiet:
            # Own line, not `end=" "` — cargo's streamed output lands between
            # this and the result, so a dangling prefix would be orphaned.
            print(f"[warm] {c} ...", flush=True)
        ok, dt, note = build(c, args.quiet)
        if ok:
            if not args.quiet:
                print(f"[warm] {c} {note} ({dt:.0f}s)", flush=True)
        else:
            failed.append(str(c))
            print(f"\n[warm] FAILED {c} ({dt:.0f}s)\n{note}\n", flush=True)

    total = time.monotonic() - t0
    if failed:
        print(f"[warm] {len(failed)} of {len(crates)} failed: "
              f"{', '.join(failed)} — total {total:.0f}s", flush=True)
        return 1

    print(f"[warm] {len(crates)} crates warm in {total:.0f}s", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
