# rustup で入れた RX ツールチェーンの使い方

rustup で CDEF-inc の RX ツールチェーン（rustc 1.100.0 + RX、`rx-none-elf`）を
入れた後、RX 向けのプログラムをビルドするまでの手順。

出典: [rx-rust](https://github.com/CDEF-inc/rx-rust) の README（"Writing a program",
"Floating point"）、`test/rust/qemu-demo`、`examples/blinky`、このリポジトリの
`scripts/check-install.sh`。以下のパスは、断りがなければ rx-rust のもの。

## 1. インストールの確認

```sh
rustup toolchain list            # 入れた名前（例: 1.100.0-2026-11-18）。以下 <TC>
rustup run <TC> rustc -V
rustup component list --toolchain <TC> --installed
```

参考: インストールは dist サーバを指定して行う。

```sh
RUSTUP_DIST_SERVER=https://cdef-inc.github.io/rx-rust-dist rustup toolchain install 1.100.0-2026-11-18
```

`1.100.0-2026-11-18` 以降は、`rx-none-elf` 用のビルド済み `core`、`alloc`、
`compiler_builtins`（コンポーネント `rx-core`）がどのプロファイルにも入る。
installed の一覧に `rx-core` があることを確かめる。

`1.100.0-2026-11-17` 以前のツールチェーンには `rx-core` がなく、4 章の
`-Zbuild-std` と `RUSTC_BOOTSTRAP=1` が必須になる。そのときは `rust-src` も要る。

## 2. プロジェクトでツールチェーンを選ぶ

プロジェクトのディレクトリで次のどちらかを行う。

```sh
rustup override set <TC>
```

またはプロジェクト直下に `rust-toolchain.toml` を置く。

```toml
[toolchain]
channel = "<TC>"
```

一回だけなら `cargo +<TC> build` でもよい。

## 3. プロジェクトの構成

`test/rust/qemu-demo`（QEMU、RX62N）と `examples/blinky`（AP-RX72M-0A）が
雛形になる。

```
my-app/
├── .cargo/config.toml
├── Cargo.toml
├── build.rs
├── memory.x
└── src/main.rs
```

### `.cargo/config.toml`

```toml
[build]
target = "rx-none-elf"

[target.rx-none-elf]
# target-cpu: QEMU の RX62N は rxv1、RX72M は rxv3、RX74N / RX74M は rxv3e
rustflags = ["-C", "link-arg=-Tlink.x", "-C", "target-cpu=rxv3"]
```

`[unstable] build-std` は書かない。書いても `RUSTC_BOOTSTRAP` なしでは cargo が
黙って無視し、ビルド済みの `core` を使う。

### `Cargo.toml`

```toml
[package]
name = "my-app"
version = "0.1.0"
edition = "2024"

[dependencies]
# rx-rust リポジトリのクレート。rev を固定する。
rx-rt = { git = "https://github.com/CDEF-inc/rx-rust", rev = "<commit>" }
# ボード用 HAL を使う場合（PAC を含む）。チップの feature を一つだけ選ぶ:
# rx72-hal は rx72m / rx72n、rx74-hal は rx74m / rx74n。
# rx72-hal = { git = "https://github.com/CDEF-inc/rx-rust", rev = "<commit>", features = ["rx72m"] }

[[bin]]
name = "my-app"
test = false
bench = false

[profile.release]
opt-level = "s"
debug = true
```

- **git 依存:** rx-rust が非公開のリポジトリなら、cargo がそのリポジトリを取得できる認証が要る（`net.git-fetch-with-cli = true` で git の認証を使うなど）。
- **HAL:** HAL の PAC は e² studio の `.sfrx` ファイルから生成する（`docs/NOTES-hal.md`）。PAC にデバッグ情報を付けるとビルドに 10 分以上かかるので、`examples/blinky/Cargo.toml` のように `[profile.*.package.rx72-pac] debug = false` を付ける（RX74 なら `rx74-pac`）。
- **クレート名:** 実際の名前は `rx72-hal` / `rx72-pac` と `rx74-hal` / `rx74-pac`。`rx72m-hal` のようにチップ名を付けた名前のクレートはない。チップは feature で選ぶ。

### `build.rs`

`memory.x` を rx-rt の `link.x` から見えるリンカ探索パスに置く。

```rust
fn main() {
    let out = std::path::PathBuf::from(std::env::var_os("OUT_DIR").unwrap());
    std::fs::copy("memory.x", out.join("memory.x")).unwrap();
    println!("cargo:rustc-link-search={}", out.display());
    println!("cargo:rerun-if-changed=memory.x");
}
```

### `memory.x`（QEMU の RX62N の例）

```
MEMORY
{
  RAM (rwx) : ORIGIN = 0x00000004, LENGTH = 96K - 4
  ROM (rx)  : ORIGIN = 0xFFF80000, LENGTH = 512K
}
```

ボードの値は `examples/*` の `memory.x` を参照する。

### `src/main.rs`

`#![no_std]` / `#![no_main]` で、エントリは rx-rt が用意する。
`test/rust/qemu-demo/src/main.rs` と `examples/blinky/src/main.rs` を参照。

`#![feature(...)]` は書かない。`asm!`、RX のターゲット機能（`#[target_feature]`、
`cfg(target_feature = "fpu")` など）、C の可変長引数の定義は、このツールチェーンでは
安定版の機能なので feature ゲートは要らない。`RUSTC_BOOTSTRAP` なしで
`#![feature]` を書くとエラーになる。古い版で付けていた
`#![feature(asm_experimental_arch)]` と `#![feature(c_variadic_experimental_arch)]`
は消す。

## 4. ビルド

```sh
cargo build --release
```

- **ビルド済みの core:** RXv1 のコードなので、どの RX コアでも動く。自分のクレートのコードは `target-cpu` と `target-feature` に従う。
- **ツールチェーンを替えたとき:** 前の版でビルドしたものは混ぜられないので、一度 `cargo clean` する。
- **core もソースからビルドしたい場合:** `target-cpu` に合わせた `core` が欲しいときは `-Zbuild-std` を使う。不安定なオプションなので `RUSTC_BOOTSTRAP=1` と `rust-src` が要る（`1.100.0-2026-11-17` 以前はこの方法しかない）。

  ```sh
  rustup component add rust-src --toolchain <TC>
  RUSTC_BOOTSTRAP=1 cargo build --release -Zbuild-std=core -Zbuild-std-features=compiler-builtins-mem
  ```

  PowerShell の場合:

  ```powershell
  $env:RUSTC_BOOTSTRAP = 1; cargo build --release -Zbuild-std=core -Zbuild-std-features=compiler-builtins-mem
  ```

- **リンカ:** ツールチェーン付属の `rust-lld` を使う。GNU binutils は要らない。
- **ビルドスクリプト:** ホストの C コンパイラ / リンカが要る。Windows では MSVC のリンカ（Visual Studio Build Tools）。
- **出力:** `target/rx-none-elf/release/my-app`。

## 5. 付属ツール

`qemu-system-rx`、`lldb`、`ld.lld`、`llvm-objdump` などのツールは sysroot の
`bin` にある。rustup のプロキシ経由では PATH に入らないので、自分で足す。

```sh
export PATH="$(rustup run <TC> rustc --print sysroot)/bin:$PATH"
llvm-objdump -d target/rx-none-elf/release/my-app
qemu-system-rx -cpu help
```

PowerShell の場合:

```powershell
$env:PATH = "$(rustup run <TC> rustc --print sysroot)\bin;$env:PATH"
```

## 6. 補足

- **C 関数名:** RX では先頭に `_` が付く（`extern "C" fn add_mul` → `_add_mul`）。
- **浮動小数点:** 既定は soft-float。FPU / DFPU を使うには rustflags に `"-C", "target-feature=+flush-denormals"` を足す（RX62N の FPU なら `+fpu,+flush-denormals`）。非正規化数は ±0 になる。詳細は README の "Floating point"。
- **コードサイズ:** `-C target-feature=+relax` でリンカ緩和が効き、`.text` が約 3 % 減る。
- **ABI:** ターゲットと ABI の説明は CDEF-inc/rust の `src/doc/rustc/src/platform-support/rx-none-elf.md`。
