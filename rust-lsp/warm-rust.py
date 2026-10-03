#!/usr/bin/env python3
"""Build, once, exactly what every Rust dev pod will build — so a pod links rather than compiles.

WHY THIS EXISTS
    The dev pods run `cargo watch -x 'run …'` against the bind-mounted repo, and
    ~/code/cvyuh-systems/.cargo/config.toml collapses all crates onto ONE
    target/. One target/ means one build-dir lock, so the pods compile strictly
    one at a time — and the order is whichever kubelet started first.

    boot.py has its own order (align → bao → pg → dj → am → idm → am1), and
    bao's k8s-auth step waits on the `provision` pod. Those two orderings know
    nothing about each other. Measured 2026-08-09 on a cold target: `fabrik`
    took the lock, `provision` queued behind it and two fabrik1 replicas, and
    boot failed on its 300s readiness wait while the pod it needed had not
    started compiling. Nothing was broken; the build order simply did not match
    the boot order.

    Building here removes the race rather than arbitrating it. Every pod then
    starts against a warm tree and `cargo run` returns in seconds, so boot's
    timing stops depending on compile scheduling.

WHERE IT BUILDS — THE POD'S OWN IMAGE
    Each build runs in the image its pod runs (`<registry>/<path>:dev`, the path
    from git-ops/values/images.yaml keyed by the build's directory, as
    lib/templates/workload/_dev.tpl resolves it), as uid 1000, with the pod's
    HOME, CARGO_HOME, RUSTUP_HOME and PATH, and with every bind mount of the
    site's app node — so it reads and writes exactly what a pod does. On Linux
    that is the host's own repo and caches; on a mac it is the VM-backed copies
    the node mounts, which the host's tree is not.

    The host's toolchain is never used. A build script that reads system
    headers records their paths, and a host clang that differs from the
    image's leaves the pod recompiling — pgdog's `pg_raw_parse` against clang 18
    on the host and 19 in the image, 2026-10-02, three crates every time either
    side built. Building in the image makes the host's toolchain irrelevant to
    the pods; the editor keeps its own, under target/rust-analyzer and
    target/flycheck*.

    Serial on purpose. Parallel `cargo build` invocations would contend on the
    same lock and gain nothing — the lock is the whole reason this exists.

WHAT IS BUILT — THE PODS' OWN DECLARATIONS
    A build is reused only when it is the same build: cargo keys an artifact by
    profile, features and flags, and a pod asking for a different one compiles
    its own. So the builds are not chosen here. They are read from where the
    pods get them — every `rustDevTemplate` in git-ops/values/local/override.yaml
    — and resolved the way lib/templates/workload/_dev-rust.tpl resolves them:

        dir        the component's name unless `dir` says otherwise
        --release  always — every pod runs `run --release`
        --bin      `bin`, when set
        --features `features`, when set

    Identical invocations are built once — link's three components share one.
    A component added to override.yaml is warmed with no edit here.

    It was once the crate list in rust-analyzer.toml, built bare and in debug.
    On 2026-10-02 a fresh dev-0 showed what that cost: every pod runs
    `run --release`, half of them with features, so the warm tree matched none
    of them and router rebuilt 357 crates, link 81, scribe 41.

WHEN
    Before the delivery layer — infra/_common/sequence.yaml — because that layer
    starts ArgoCD and with it the pods. Run after it, this races the pods for the
    lock instead of finishing before they ask.

USAGE
    Run through infra's local/warm-rust.py --site <site>, which names the node
    and the registry:

    warm-rust.py --node <oem>-<site>-worker2 --registry <host>              # every build
    warm-rust.py --node … --registry … replication                          # only these directories
    warm-rust.py --check                                                     # list the builds
    warm-rust.py --node … --registry … --quiet                              # failures and the summary

    Idempotent: an already-warm tree finishes in seconds.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import time
from collections import deque
from pathlib import Path

import json

import yaml

# This file lives at <repo>/nvim/rust-lsp/, so the repo root is two up. Derived
# rather than hardcoded: the file is versioned and must carry nobody's $HOME.
REPO_ROOT = Path(__file__).resolve().parent.parent.parent
OVERRIDE = REPO_ROOT / "git-ops" / "values" / "local" / "override.yaml"
IMAGES = REPO_ROOT / "git-ops" / "values" / "images.yaml"
# The node's mounts that are the node's own, not the pods' source and caches.
NODE_ONLY = ("/lib/modules", "/var/lib/containerd", "/var")


def declared(node, name: str = "") -> list[tuple[str, dict]]:
    """Every `(component, rustDevTemplate)` in the values tree, in file order."""
    out: list[tuple[str, dict]] = []
    if isinstance(node, dict):
        if "rustDevTemplate" in node:
            out.append((name, node["rustDevTemplate"] or {}))
        for key, child in node.items():
            if key != "rustDevTemplate":
                out += declared(child, key)
    return out


def invocations() -> list[tuple[str, tuple[str, ...], list[str]]]:
    """`(dir, cargo args, components)` for every distinct build a pod runs."""
    if not OVERRIDE.is_file():
        sys.exit(f"[warm] missing {OVERRIDE} — the pods' builds are declared there")
    seen: dict[tuple[str, tuple[str, ...]], list[str]] = {}
    for comp, opts in declared(yaml.safe_load(OVERRIDE.read_text())):
        args = ["build", "--release"]
        if opts.get("bin"):
            args += ["--bin", str(opts["bin"])]
        if opts.get("features"):
            args += ["--features", str(opts["features"])]
        seen.setdefault((str(opts.get("dir") or comp), tuple(args)), []).append(comp)
    if not seen:
        sys.exit(f"[warm] no rustDevTemplate in {OVERRIDE}")
    return [(d, a, comps) for (d, a), comps in seen.items()]


def image_of(crate: str, registry: str) -> str:
    """The pod's dev image for a build directory — `<registry>/<path>:dev`."""
    rows = (yaml.safe_load(IMAGES.read_text()) or {}).get("images") or {}
    path = (rows.get(crate) or {}).get("path") or crate
    return f"{registry}/{path}:dev"


def node_mounts(node: str) -> list[tuple[str, str]]:
    """`(source, destination)` of every bind mount the app node carries for its pods."""
    p = subprocess.run(["docker", "inspect", node, "--format", "{{json .Mounts}}"],
                       capture_output=True, text=True)
    if p.returncode != 0:
        sys.exit(f"[warm] no node {node}: {p.stderr.strip()} — is the site's cluster up?")
    return [(m["Source"], m["Destination"]) for m in json.loads(p.stdout)
            if m.get("Type") == "bind" and m["Destination"] not in NODE_ONLY]


def container(mounts: list[tuple[str, str]], image: str, workdir: Path) -> list[str]:
    """`docker run …` up to the image: the node's mounts, and the pod's user and environment."""
    cargo = next((dst for _, dst in mounts if dst.endswith("/.cargo")), None)
    if cargo is None:
        sys.exit("[warm] the node mounts no .cargo — the pods' cache is not where this expects it")
    home = str(Path(cargo).parent)
    argv = ["docker", "run", "--rm", "--user", "1000:1000", "-w", str(workdir),
            "-e", f"HOME={home}", "-e", f"CARGO_HOME={home}/.cargo", "-e", f"RUSTUP_HOME={home}/.rustup",
            "-e", f"PATH={home}/.cargo/bin:/usr/local/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"]
    for src, dst in mounts:
        argv += ["-v", f"{src}:{dst}"]
    return argv + ["--entrypoint", "cargo", image]


def build(crate: str, args: tuple[str, ...], quiet: bool, node: list[tuple[str, str]], registry: str) -> tuple[bool, float, str]:
    d = REPO_ROOT / crate
    if not (d / "Cargo.toml").is_file():
        return True, 0.0, "skipped (no Cargo.toml)"
    image = image_of(crate, registry)
    if subprocess.run(["docker", "image", "inspect", image], capture_output=True).returncode != 0:
        return False, 0.0, f"no image {image} — app-images.py builds it, and runs first"

    # STREAM, don't capture. A cold build of this tree is the longest step in
    # the bring-up — measured 20min+ when the disk is the constraint — and a
    # captured one prints nothing until the crate finishes, which is
    # indistinguishable from hung. cargo's own "Compiling <crate>" lines are the
    # progress indicator; let them through.
    #
    # Still tee'd into a small ring buffer: on failure the last lines carry the
    # cause, and scrolling back through a full cold build to find them is worse
    # than keeping twelve of them here.
    t0 = time.monotonic()
    tail: deque[str] = deque(maxlen=12)
    compiled = False

    p = subprocess.Popen(
        [*container(node, image, d), *args], text=True,
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
    ap = argparse.ArgumentParser(description="Pre-build what every Rust dev pod builds")
    ap.add_argument("--check", action="store_true",
                    help="list the invocations and exit; build nothing")
    ap.add_argument("--quiet", action="store_true",
                    help="print only failures and the summary")
    ap.add_argument("--node", help="the site's app node, whose mounts the builds take")
    ap.add_argument("--registry", help="the local registry host the dev images are tagged under")
    ap.add_argument("crates", nargs="*", metavar="DIR",
                    help="build only the invocations in these directories. "
                         "Default is all of them")
    args = ap.parse_args()

    builds = invocations()
    if args.crates:
        wanted = set(args.crates)
        builds = [b for b in builds if b[0] in wanted]
        if missing := wanted - {b[0] for b in builds}:
            sys.exit(f"[warm] no pod builds in: {', '.join(sorted(missing))}")

    if args.check:
        print(f"[warm] {len(builds)} builds from {OVERRIDE.relative_to(REPO_ROOT)}:")
        for d, a, comps in builds:
            print(f"         {d}: cargo {' '.join(a)}   ({', '.join(comps)})")
        return 0

    if not (args.node and args.registry):
        sys.exit("[warm] --node and --registry are required to build — run it through "
                 "infra's local/warm-rust.py --site <site>")
    mounts = node_mounts(args.node)

    print(f"[warm] {len(builds)} builds serially in the pods' images, "
          f"mounts of {args.node} (one shared target/, one lock)", flush=True)

    t0 = time.monotonic()
    failed: list[str] = []
    for d, a, comps in builds:
        what = f"{d}: cargo {' '.join(a)}"
        if not args.quiet:
            # Own line, not `end=" "` — cargo's streamed output lands between
            # this and the result, so a dangling prefix would be orphaned.
            print(f"[warm] {what} ...", flush=True)
        ok, dt, note = build(d, a, args.quiet, mounts, args.registry)
        if ok:
            if not args.quiet:
                print(f"[warm] {what} {note} ({dt:.0f}s)", flush=True)
        else:
            failed.append(what)
            print(f"\n[warm] FAILED {what} ({dt:.0f}s)\n{note}\n", flush=True)

    total = time.monotonic() - t0
    if failed:
        print(f"[warm] {len(failed)} of {len(builds)} failed: "
              f"{'; '.join(failed)} — total {total:.0f}s", flush=True)
        return 1

    print(f"[warm] {len(builds)} builds warm in {total:.0f}s", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
