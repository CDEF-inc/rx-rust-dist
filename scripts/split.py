#!/usr/bin/env python3
"""Split an extracted rx-rust toolchain archive into rustup components.

    split.py [--host-only] ROOT HOST VERSION OUTDIR

ROOT is the extracted archive (rx-toolchain-x86_64-linux/ or
rx-toolchain-x86_64-windows/), HOST its host triple. For each component this
writes OUTDIR/COMPONENT-VERSION-HOST.tar.xz (rust-src: rust-src-VERSION.tar.xz)
in the rust-installer format that rustup installs, and prints one JSON line:
{"pkg", "target", "file", "sha256", "files"}. rust-src and rx-core (rx-none-elf's
prebuilt core, alloc and compiler_builtins) are the same for every host
(target "*"): --host-only leaves them out, for all hosts but one.

rx-core is not rust-std for rx-none-elf: rustup's profiles install only the
host's rust-std, so a user would have to add the target by hand. As a "*"
component, like rust-src, every profile installs it.

Every file of the archive goes into exactly one component; a file that no rule
matches is an error, so a new file in the archive is not dropped silently.

rustup does not unpack symbolic links, so a link becomes a copy of its target.
A shared library that is only reached through links (liblldb.so.23.1 ->
liblldb.so.23.1.5) is shipped once, under the name of the link.
"""
import hashlib
import io
import json
import os
import re
import subprocess
import sys
import tarfile

# The components that are the same for every host (target "*").
SHARED = ("rust-src", "rx-core")

# (component, pattern). The first match wins. Paths are relative to ROOT,
# with "/" separators. {host} is the host triple.
RULES = [
    ("rustc", r"(VERSIONS|SBOM\.spdx\.json|SBOM\.cdx\.json)"),
    # The licenses (rx-rust's dist-toolchain*.sh, from toolchain releases
    # after 2026-11-18): the Rust project's and llvm-project's with rustc
    # (which has rust-lld and LLVM in it), QEMU's GPL-2.0 with qemu-system-rx.
    ("rustc", r"(COPYRIGHT|LICENSE-APACHE|LICENSE-MIT|LICENSE\.TXT)"),
    ("rx-qemu", r"COPYING\.QEMU"),
    ("rustc", r"bin/(rustc|rust-lldb)(\.exe)?"),
    ("rustc", r"bin/rustc_driver-[0-9a-f]+\.dll"),
    ("rustc", r"lib/librustc_driver-[0-9a-f]+\.so"),
    ("rustc", r"lib/rustlib/{host}/bin/.*"),
    ("rustc", r"lib/rustlib/etc/.*"),
    ("rust-std", r"lib/rustlib/{host}/lib/.*"),
    ("rx-core", r"lib/rustlib/rx-none-elf/lib/.*"),
    ("cargo", r"bin/cargo(\.exe)?"),
    ("rust-src", r"lib/rustlib/src/.*"),
    ("llvm-tools", r"bin/(llvm-[a-z0-9]+|rx-elf-[a-z0-9]+|ld\.lld)(\.exe)?"),
    ("rx-lldb", r"bin/(lldb(\.exe)?|liblldb\.dll)"),
    ("rx-lldb", r"lib/liblldb\.so[.0-9]*"),
    ("rx-qemu", r"bin/qemu-system-rx(\.exe)?"),
    # The rest of the shared libraries are qemu-system-rx's (glib, pixman, ...).
    ("rx-qemu", r"bin/[^/]+\.dll"),
    ("rx-qemu", r"lib/lib[^/]+\.so[.0-9]*"),
]

# The archive's top-level files would clash between components: they go to
# share/doc/rx-toolchain/ in rustc.
DOC_DIR = "share/doc/rx-toolchain/"


def name_in_tarball(pkg, host):
    # rustup accepts the full name (rust-std-HOST) or the short one.
    return f"rust-std-{host}" if pkg == "rust-std" else pkg


def walk(root):
    for d, dirs, files in os.walk(root):
        dirs.sort()
        for f in sorted(files):
            p = os.path.join(d, f)
            yield os.path.relpath(p, root).replace(os.sep, "/")


def main():
    args = sys.argv[1:]
    host_only = args[:1] == ["--host-only"]
    if host_only:
        args = args[1:]
    root, host, version, outdir = args
    rules = [(pkg, re.compile(pat.replace("{host}", re.escape(host)) + r"\Z"))
             for pkg, pat in RULES]

    paths = list(walk(root))
    # Shared libraries reached only through links: ship them as the link.
    link_targets = set()
    for p in paths:
        full = os.path.join(root, p)
        if os.path.islink(full) and ".so" in p:
            link_targets.add(os.path.relpath(os.path.realpath(full),
                                             os.path.realpath(root)).replace(os.sep, "/"))
    by_pkg = {}
    unmatched = []
    for p in paths:
        if p in link_targets:
            continue
        pkg = next((pkg for pkg, rx in rules if rx.match(p)), None)
        if pkg is None:
            unmatched.append(p)
            continue
        dest = DOC_DIR + p if "/" not in p else p
        by_pkg.setdefault(pkg, []).append((p, dest))
    if unmatched:
        sys.exit("files that no rule puts into a component:\n  " + "\n  ".join(unmatched))

    if host_only:
        for pkg in SHARED:
            by_pkg.pop(pkg, None)
    os.makedirs(outdir, exist_ok=True)
    for pkg in sorted(by_pkg):
        name = name_in_tarball(pkg, host)
        # rust-src and rx-core are the same for every host (target "*").
        top = f"{pkg}-{version}" if pkg in SHARED else f"{pkg}-{version}-{host}"
        out = os.path.join(outdir, top + ".tar.xz")
        with open(out, "wb") as f:
            xz = subprocess.Popen(["xz", "-T0", "-6", "-c"], stdin=subprocess.PIPE, stdout=f)
            with tarfile.open(fileobj=xz.stdin, mode="w|", format=tarfile.GNU_FORMAT) as tar:
                # rustup wants an entry for every directory before its files.
                dirs = {top, f"{top}/{name}"}
                for _, dest in by_pkg[pkg]:
                    parts = f"{top}/{name}/{dest}".split("/")[:-1]
                    dirs.update("/".join(parts[:i]) for i in range(1, len(parts) + 1))
                for d in sorted(dirs):
                    info = tarfile.TarInfo(d)
                    info.type = tarfile.DIRTYPE
                    info.mode = 0o755
                    tar.addfile(info)

                def add_bytes(arcname, data):
                    info = tarfile.TarInfo(f"{top}/{arcname}")
                    info.size = len(data)
                    info.mode = 0o644
                    tar.addfile(info, io.BytesIO(data))
                add_bytes("rust-installer-version", b"3\n")
                add_bytes("components", f"{name}\n".encode())
                manifest = "".join(f"file:{dest}\n" for _, dest in by_pkg[pkg])
                add_bytes(f"{name}/manifest.in", manifest.encode())
                for src, dest in by_pkg[pkg]:
                    full = os.path.realpath(os.path.join(root, src))
                    info = tarfile.TarInfo(f"{top}/{name}/{dest}")
                    st = os.stat(full)
                    info.size = st.st_size
                    executable = st.st_mode & 0o111 or dest.endswith((".exe", ".dll"))
                    info.mode = 0o755 if executable else 0o644
                    info.mtime = int(st.st_mtime)
                    with open(full, "rb") as data:
                        tar.addfile(info, data)
            xz.stdin.close()
            if xz.wait() != 0:
                sys.exit(f"xz failed for {out}")
        h = hashlib.sha256()
        with open(out, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
        target = "*" if pkg in SHARED else host
        print(json.dumps({"pkg": pkg, "target": target, "file": os.path.basename(out),
                          "sha256": h.hexdigest(), "files": len(by_pkg[pkg])}))


if __name__ == "__main__":
    main()
