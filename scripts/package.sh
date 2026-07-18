#!/usr/bin/env sh
# Package iperf3 for distribution: per-target tar.xz archive
# containing bin/iperf3 + LICENSE + NOTICE.md + README.md + README.cn.md.
#
# Used by release.yml after build completes.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TARGET="${TARGET:?TARGET env var required (e.g. linux-musl-x64)}"
SRC_BIN="$ROOT/build/src/iperf3"

[ -x "$SRC_BIN" ] || { echo "error: $SRC_BIN not found" >&2; exit 1; }

OUT_DIR="$ROOT/dist/iperf3-$TARGET"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/bin"

# Copy binary + LICENSE/NOTICE/README
cp "$SRC_BIN" "$OUT_DIR/bin/iperf3"
cp "$ROOT/LICENSE"    "$OUT_DIR/LICENSE"
cp "$ROOT/NOTICE.md"  "$OUT_DIR/NOTICE.md"
cp "$ROOT/README.md"  "$OUT_DIR/README.md"
cp "$ROOT/README.cn.md" "$OUT_DIR/README.cn.md"

# Create tar.xz archive
TARBALL="$ROOT/dist/iperf3-$TARGET.tar.xz"
( cd "$ROOT/dist" && tar -cJf "$TARBALL" "iperf3-$TARGET" )

# Per-archive sha256 (basename only, for portability per release-pipeline memory)
SHA_FILE="$ROOT/dist/iperf3-$TARGET.tar.xz.sha256"
if command -v sha256sum >/dev/null 2>&1; then
	( cd "$ROOT/dist" && sha256sum "iperf3-$TARGET.tar.xz" > "$SHA_FILE" )
elif command -v shasum >/dev/null 2>&1; then
	( cd "$ROOT/dist" && shasum -a 256 "iperf3-$TARGET.tar.xz" > "$SHA_FILE" )
else
	echo "error: neither sha256sum nor shasum available" >&2
	exit 1
fi

echo "==> packaged:"
ls -la "$TARBALL"
cat "$SHA_FILE"