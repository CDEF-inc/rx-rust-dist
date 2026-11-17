#!/bin/bash
# Writes the channel manifest of a toolchain that build.sh made into a dist
# server tree:
#
#   site.sh OUT BASE_URL SITE
#
# SITE/dist/YYYY-MM-DD/channel-rust-X.Y.Z.toml (and .sha256) is what rustup
# reads for toolchain X.Y.Z-YYYY-MM-DD from RUSTUP_DIST_SERVER=SITE's URL.
# BASE_URL is where the tarballs of OUT/files are served: the GitHub release,
# or a local server for check-install.sh.
set -eu
out=$1 base=$2 site=$3
here=$(cd "$(dirname "$0")" && pwd)
tc=$(cat "$out/toolchain")
version=${tc%%-*} date=${tc#*-}
d=$site/dist/$date
mkdir -p "$d"
python3 "$here/manifest.py" "$date" "$base" "$(cat "$out/rustc-version")" \
  "$(cat "$out/cargo-version")" "$out/files/components.jsonl" > "$d/channel-rust-$version.toml"
(cd "$d" && sha256sum "channel-rust-$version.toml" > "channel-rust-$version.toml.sha256")
echo "$d/channel-rust-$version.toml"
