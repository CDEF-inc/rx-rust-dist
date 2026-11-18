# rx-rust-dist

A rustup dist server for the [rx-rust](https://github.com/CDEF-inc/rx-rust) toolchain: Rust for Renesas RX (`rx-none-elf`), for x86-64 Linux and x86-64 Windows. rustup installs it next to your other toolchains.

> **This is not an official Rust release.** CDEF, Inc. builds it from [CDEF-inc/rust](https://github.com/CDEF-inc/rust), a fork of [rust-lang/rust](https://github.com/rust-lang/rust) that adds the RX target. The Rust project does not make it, endorse it or support it. Report problems here or in [rx-rust](https://github.com/CDEF-inc/rx-rust/issues), not to the Rust project.

## Install

Set `RUSTUP_DIST_SERVER` for the install only, and name the toolchain with its date (the list is in [Toolchains](#toolchains)):

```bash
RUSTUP_DIST_SERVER=https://cdef-inc.github.io/rx-rust-dist rustup toolchain install 1.100.0-2026-11-18
```

In PowerShell:

```powershell
$env:RUSTUP_DIST_SERVER = "https://cdef-inc.github.io/rx-rust-dist"
rustup toolchain install 1.100.0-2026-11-18
Remove-Item Env:RUSTUP_DIST_SERVER
```

- Do not set `RUSTUP_DIST_SERVER` for good. While it is set, rustup looks for official toolchains (`rustup update stable`) on this server too, and fails.
- Using the toolchain does not need the variable: `cargo +1.100.0-2026-11-18 build`, or a `rust-toolchain.toml`:

  ```toml
  [toolchain]
  channel = "1.100.0-2026-11-18"
  ```

  If the toolchain is not installed, rustup tries to fetch it from the official server, where it does not exist: the build stops with an error, and you install it as above.
- To remove it: `rustup toolchain uninstall 1.100.0-2026-11-18`.

## Build for RX

From `1.100.0-2026-11-18` on, the toolchain has a prebuilt `core`, `alloc` and `compiler_builtins` for `rx-none-elf` (the `rx-core` component, in every profile). They are built for RXv1, so they run on every RX core; your crate's own code follows its `target-cpu`. Inline assembly (`asm!`), c-variadic definitions and the RX target features (`fpu`, `dfpu`, `rxv2`, `rxv3`, `rxv3e`, `flush-denormals`, `relax`) are stable in this toolchain. A plain build works, with no `RUSTC_BOOTSTRAP`:

```bash
cargo +1.100.0-2026-11-18 build --release --target rx-none-elf
```

To build `core` from source for your `target-cpu` instead, use `-Zbuild-std`. It is unstable, so on this stable-channel toolchain it needs `RUSTC_BOOTSTRAP=1`:

```bash
RUSTC_BOOTSTRAP=1 cargo +1.100.0-2026-11-18 build --release --target rx-none-elf -Zbuild-std=core
```

Older toolchains (up to `1.100.0-2026-11-17`) have no prebuilt `core`: they need `-Zbuild-std` and `RUSTC_BOOTSTRAP=1`, and `#![feature(asm_experimental_arch)]` for `asm!`.

rx-rust's README covers the rest: linker scripts, start-up code, the calling conventions, QEMU and the boards.

## Toolchains

A toolchain is named after the Rust release that rustc is based on and the date of the rx-rust release: `1.100.0-2026-11-18` is rx-rust's [toolchain-2026-11-18](https://github.com/CDEF-inc/rx-rust/releases/tag/toolchain-2026-11-18), based on Rust 1.100.0. rustup does not allow other names, and the official server has no toolchain of that name: an official `1.100.0` is dated the day it came out.

`rustc -V` says which one you have: `rustc 1.100.0 (c8a526039 2026-11-18) (CDEF-inc RX fork)`.

The toolchains and their components are in [Releases](https://github.com/CDEF-inc/rx-rust-dist/releases).

## Components

| Component | What | Profile |
|---|---|---|
| `rustc` | rustc, rust-lld, rust-lldb and rustc's LLDB formatters | minimal |
| `rust-std` | the host's standard library, for build scripts and proc macros | minimal |
| `rx-core` | `rx-none-elf`'s prebuilt `core`, `alloc` and `compiler_builtins` (RXv1 code; from `1.100.0-2026-11-18`) | minimal |
| `cargo` | cargo | minimal |
| `rust-src` | the library sources, for `-Zbuild-std` | minimal |
| `llvm-tools` | `ld.lld`, `llvm-objdump`, `llvm-objcopy`, `llvm-nm`, ... and the same as `rx-elf-*` | default |
| `rx-qemu` | `qemu-system-rx` ([CDEF-inc/qemu](https://github.com/CDEF-inc/qemu): RXv1, v2, v3, v3e) and its libraries | default |
| `rx-lldb` | `lldb` with RX support | default |

`rustup toolchain install` installs the default profile. `--profile minimal` leaves out the last three, and `rustup component add rx-qemu --toolchain ...` adds one later.

The commits the toolchain was built from (`VERSIONS`) and its SBOMs are in `share/doc/rx-toolchain/` of the toolchain (`rustc --print sysroot`).

## How it is made

[`dist.yml`](.github/workflows/dist.yml) does not build the compiler: it takes the archives of an [rx-rust release](https://github.com/CDEF-inc/rx-rust/releases), which rx-rust's CI built and tested.

1. `scripts/build.sh` splits each archive into the components (`scripts/split.py`), in the format rustup installs. Every file of the archive goes into one component.
2. `scripts/check-install.sh` installs the toolchain with rustup from a local server, on Linux and Windows. It checks `rustc -V`, builds a `no_std` crate for `rx-none-elf` without `RUSTC_BOOTSTRAP` on the prebuilt `core` and again with `-Zbuild-std=core`, links it with `ld.lld`, and starts `qemu-system-rx` and `lldb`.
3. When publishing, the tarballs go to a release of this repository named after the toolchain. The channel manifest (`dist/DATE/channel-rust-VERSION.toml`) goes to the `gh-pages` branch, which GitHub Pages serves.

To publish an rx-rust release: Actions > dist > Run workflow, with the release's tag and "publish" ticked.

## Licenses

Each component of a toolchain keeps its own license: Rust and LLVM under theirs, QEMU under GPL-2.0, libxml2 (in LLDB) under MIT. The SBOMs list them.
