#!/usr/bin/env python3
"""Write the rustup channel manifest for one toolchain.

    manifest.py DATE BASE_URL RUSTC_VERSION CARGO_VERSION COMPONENTS.jsonl > channel-rust-X.Y.Z.toml

COMPONENTS.jsonl holds the lines that split.py printed, for every host.
BASE_URL is where the component tarballs are (the GitHub release of the
toolchain). The toolchain is installed as X.Y.Z-DATE: rustup then reads
dist/DATE/channel-rust-X.Y.Z.toml from RUSTUP_DIST_SERVER.
"""
import json
import sys

# What each profile installs. rx-core is rx-none-elf's prebuilt core, alloc
# and compiler_builtins (from toolchain-2026-11-18 on), so programs build
# without -Zbuild-std; rust-src is for -Zbuild-std.
MINIMAL = ["rustc", "rust-std", "cargo", "rust-src", "rx-core"]
DEFAULT = MINIMAL + ["llvm-tools", "rx-qemu", "rx-lldb"]
# The same for every host (target "*").
SHARED = ("rust-src", "rx-core")
# Releases before toolchain-2026-11-18 have no rx-core.
OPTIONAL = ("rx-core",)


def q(s):
    return json.dumps(s)  # a TOML basic string


def main():
    date, base, rustc_version, cargo_version, components = sys.argv[1:6]
    comps = [json.loads(line) for line in open(components) if line.strip()]
    present = {c["pkg"] for c in comps}
    minimal = [p for p in MINIMAL if p in present or p not in OPTIONAL]
    default = [p for p in DEFAULT if p in present or p not in OPTIONAL]
    hosts = sorted({c["target"] for c in comps if c["target"] != "*"})
    versions = {"rustc": rustc_version, "cargo": cargo_version}
    out = ['manifest-version = "2"', f"date = {q(date)}", ""]

    pkgs = {}
    for c in comps:
        pkgs.setdefault(c["pkg"], []).append(c)
    for pkg in sorted(pkgs):
        out.append(f"[pkg.{pkg}]")
        out.append(f"version = {q(versions.get(pkg, rustc_version))}")
        out.append("")
        for c in sorted(pkgs[pkg], key=lambda c: c["target"]):
            out.append(f"[pkg.{pkg}.target.{q(c['target'])}]")
            out.append("available = true")
            out.append(f"xz_url = {q(base + '/' + c['file'])}")
            out.append(f"xz_hash = {q(c['sha256'])}")
            out.append("")

    out.append("[pkg.rust]")
    out.append(f"version = {q(rustc_version)}")
    out.append("")
    for host in hosts:
        out.append(f"[pkg.rust.target.{q(host)}]")
        out.append("available = true")
        out.append("")
        for pkg in default:
            target = "*" if pkg in SHARED else host
            if not any(c["pkg"] == pkg and c["target"] == target for c in comps):
                sys.exit(f"no {pkg} for {target}")
            kind = "components" if pkg in minimal else "extensions"
            out.append(f"[[pkg.rust.target.{q(host)}.{kind}]]")
            out.append(f"pkg = {q(pkg)}")
            out.append(f"target = {q(target)}")
            out.append("")

    out.append("[profiles]")
    out.append(f"minimal = {json.dumps(minimal)}")
    out.append(f"default = {json.dumps(default)}")
    out.append(f"complete = {json.dumps(default)}")
    out.append("")
    out.append("[renames.llvm-tools-preview]")
    out.append('to = "llvm-tools"')
    print("\n".join(out))


if __name__ == "__main__":
    main()
