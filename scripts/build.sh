#!/bin/bash
# Turns an rx-rust release into rustup components and a channel manifest:
#
#   build.sh TAG OUT     (TAG: an rx-rust release, toolchain-YYYY-MM-DD)
#
# It downloads the release's Linux and Windows archives (gh), splits each into
# components (split.py) and writes into OUT
#   files/                   the component tarballs
#   files/components.jsonl   what split.py printed
#   toolchain                the rustup toolchain name, X.Y.Z-YYYY-MM-DD
#   rustc-version, cargo-version
#
# The toolchain name is rustc's version and the date of the tag. A tag with a
# suffix (toolchain-2026-11-13.1) has no name: rustup names allow only a date.
# Needs gh, python3, xz and a Linux host (it runs the Linux rustc and cargo).
set -eu
tag=$1 out=$2
here=$(cd "$(dirname "$0")" && pwd)
case $tag in
toolchain-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) date=${tag#toolchain-} ;;
*) echo "$tag: not toolchain-YYYY-MM-DD; rustup names cannot express it" >&2; exit 2 ;;
esac

mkdir -p "$out/files" "$out/in"
gh release download "$tag" -R CDEF-inc/rx-rust -D "$out/in" --clobber \
  -p rx-toolchain-x86_64-linux.tar.xz -p rx-toolchain-x86_64-windows.zip
tar -C "$out/in" -xJf "$out/in/rx-toolchain-x86_64-linux.tar.xz"
python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' \
  "$out/in/rx-toolchain-x86_64-windows.zip" "$out/in"

linux=$out/in/rx-toolchain-x86_64-linux
rustc_version=$("$linux/bin/rustc" -V | sed 's/^rustc //')
cargo_version=$("$linux/bin/cargo" -V | sed 's/^cargo //')
version=${rustc_version%% *}
case $version in
[0-9].[0-9]*.[0-9]*) ;;
*) echo "rustc $version: not a release version (X.Y.Z)" >&2; exit 2 ;;
esac

python3 "$here/split.py" "$linux" x86_64-unknown-linux-gnu "$version" "$out/files" \
  > "$out/files/components.jsonl"
python3 "$here/split.py" --no-rust-src "$out/in/rx-toolchain-x86_64-windows" \
  x86_64-pc-windows-msvc "$version" "$out/files" >> "$out/files/components.jsonl"
rm -rf "$out/in"

echo "$version-$date" > "$out/toolchain"
echo "$rustc_version" > "$out/rustc-version"
echo "$cargo_version" > "$out/cargo-version"
cat "$out/files/components.jsonl"
echo "toolchain $version-$date: rustc $rustc_version, cargo $cargo_version"
