#!/bin/bash
# Installs a toolchain with rustup from a dist server and checks it:
#
#   check-install.sh SERVER TOOLCHAIN     (e.g. http://127.0.0.1:8765 1.100.0-2026-11-14)
#
# It uses its own RUSTUP_HOME and CARGO_HOME, so the rustup setup of the
# machine is not touched. Needs rustup (any toolchain or none).
#
# The checks: rustup installs the default profile; rustc -V names the fork;
# a no_std crate builds for rx-none-elf with -Zbuild-std=core and links with
# the toolchain's rust-lld; llvm-objdump disassembles it; qemu-system-rx and
# lldb start.
set -eu
server=$1 tc=$2
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# Git Bash on Windows: rustup.exe needs a Windows path.
command -v cygpath > /dev/null && tmp=$(cygpath -m "$tmp")
export RUSTUP_HOME=$tmp/rustup CARGO_HOME=$tmp/cargo RUSTUP_DIST_SERVER=$server
rustup=$(command -v rustup)

"$rustup" toolchain install "$tc" --profile default --no-self-update
"$rustup" component list --toolchain "$tc" --installed
sysroot=$("$rustup" run "$tc" rustc --print sysroot)
bin=$sysroot/bin

# FORK_NAME= (empty) skips the check, for releases older than rx-rust#184.
fork_name=${FORK_NAME-CDEF-inc RX fork}
v=$("$rustup" run "$tc" rustc -V)
echo "$v"
if [ -n "$fork_name" ]; then
  case $v in
  *"($fork_name)") ;;
  *) echo "rustc -V does not end in ($fork_name)" >&2; exit 1 ;;
  esac
fi
"$rustup" run "$tc" cargo -V

# A no_std crate for RX, built through rustup's cargo proxy.
mkdir -p "$tmp/demo/src"
cat > "$tmp/demo/Cargo.toml" <<'EOF'
[package]
name = "demo"
version = "0.1.0"
edition = "2024"

[lib]
crate-type = ["staticlib"]

[profile.release]
panic = "abort"
EOF
cat > "$tmp/demo/src/lib.rs" <<'EOF'
#![no_std]

#[unsafe(no_mangle)]
pub extern "C" fn add_mul(a: u32, b: u32) -> u64 {
    (a as u64 + b as u64) * (a as u64)
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}
EOF
(cd "$tmp/demo" && RUSTC_BOOTSTRAP=1 "$rustup" run "$tc" cargo build --release \
  --target rx-none-elf -Zbuild-std=core)
# C names get a leading _ on RX.
lib=$tmp/demo/target/rx-none-elf/release/libdemo.a
"$bin/ld.lld" --version
"$bin/ld.lld" -e _add_mul -u _add_mul --gc-sections -o "$tmp/demo.elf" "$lib"
"$bin/llvm-readelf" -h "$tmp/demo.elf" | grep -E 'Machine|Flags'
"$bin/llvm-objdump" -d "$tmp/demo.elf" | grep -A8 '<_add_mul>:'
"$bin/rx-elf-nm" "$tmp/demo.elf" | grep -q ' T _add_mul$'

"$bin/qemu-system-rx" --version
"$bin/qemu-system-rx" -cpu help | grep -w rxv3
"$bin/lldb" --version
echo "check-install: ok ($tc from $server)"
