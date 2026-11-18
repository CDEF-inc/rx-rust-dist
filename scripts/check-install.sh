#!/bin/bash
# Installs a toolchain with rustup from a dist server and checks it:
#
#   check-install.sh SERVER TOOLCHAIN     (e.g. http://127.0.0.1:8765 1.100.0-2026-11-14)
#
# It uses its own RUSTUP_HOME and CARGO_HOME, so the rustup setup of the
# machine is not touched. Needs rustup (any toolchain or none).
#
# The checks: rustup installs the default profile, with rx-core (rx-none-elf's
# prebuilt core); rustc -V names the fork; a no_std crate builds for
# rx-none-elf without RUSTC_BOOTSTRAP (on the prebuilt core; with an asm! and
# an RX target feature, both stable in the fork), and again with
# -Zbuild-std=core (RUSTC_BOOTSTRAP=1), and links with the toolchain's
# rust-lld; llvm-objdump disassembles it; qemu-system-rx and lldb start.
#
# Releases before toolchain-2026-11-18 have no rx-core: then
# the build without RUSTC_BOOTSTRAP is skipped, unless PREBUILT_STD=1 asks
# for it (and fails).
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

#[cfg(prebuilt_std)]
#[unsafe(no_mangle)]
#[target_feature(enable = "rxv2")]
pub unsafe extern "C" fn psw() -> u32 {
    let r: u32;
    unsafe { core::arch::asm!("mvfc psw, {0}", out(reg) r) };
    r
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}
EOF
prebuilt=${PREBUILT_STD:-}
if ls "$sysroot"/lib/rustlib/rx-none-elf/lib/libcore-*.rlib > /dev/null 2>&1; then
  prebuilt=1
elif [ -n "$prebuilt" ]; then
  echo "rx-core (rx-none-elf's prebuilt core) is not installed" >&2; exit 1
else
  echo "no rx-core (a release before toolchain-2026-11-18): skipping the build without RUSTC_BOOTSTRAP"
fi
if [ -n "$prebuilt" ]; then
  # No RUSTC_BOOTSTRAP, no -Z: what a user of a stable toolchain runs.
  (cd "$tmp/demo" && env -u RUSTC_BOOTSTRAP RUSTFLAGS="--cfg prebuilt_std --check-cfg cfg(prebuilt_std)" \
    "$rustup" run "$tc" cargo build --release --target rx-none-elf --target-dir target-prebuilt) \
    2>&1 | tee "$tmp/prebuilt.log"
  [ "${PIPESTATUS[0]}" = 0 ] || exit 1
  if grep -q "Compiling core " "$tmp/prebuilt.log"; then
    echo "cargo built core from source instead of using the prebuilt one" >&2; exit 1
  fi
  lib=$tmp/demo/target-prebuilt/rx-none-elf/release/libdemo.a
  "$bin/ld.lld" -e _psw -u _psw -u _add_mul --gc-sections -o "$tmp/prebuilt.elf" "$lib"
  "$bin/llvm-objdump" -d "$tmp/prebuilt.elf" | grep -A4 '<_psw>:' | grep -q 'mvfc'
  echo "ok: built without RUSTC_BOOTSTRAP on the prebuilt rx-none-elf core"
fi
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
