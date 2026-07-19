#!/usr/bin/env sh
# Build iperf3 as a true musl-static binary inside an Alpine container.
# Out-of-tree build into /w/build so host-side state never leaks in.
#
# CI invokes:
#   docker run --rm --platform linux/$ARCH -v "$PWD":/w -w /w \
#     alpine:3.20 sh -c 'apk add --no-cache bash >/dev/null && bash /w/scripts/build-alpine.sh'
#
# Alpine's musl + alpine's gcc → fully static iperf3 that runs on
# Alpine AND every glibc distro (Ubuntu/Debian/Fedora/Arch).
set -eu

echo "==> apk add: build deps (musl-native toolchain + openssl)"
apk add --no-cache \
	build-base \
	autoconf \
	automake \
	libtool \
	linux-headers \
	bash \
	python3 \
	openssl-dev

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SRC="$ROOT/upstream/iperf"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"

[ -f "$SRC/configure.ac" ] || { echo "error: $SRC/configure.ac not found" >&2; exit 1; }
[ -x "$SRC/configure" ] || { echo "error: $SRC/configure not executable; rerun autoreconf" >&2; exit 1; }

mkdir -p "$BUILD_DIR"

# iperf3 ships a `configure` script in its tarball — no autoreconf needed
# for our unmodified upstream. If configure is missing, bootstrap.sh:
[ -x "$SRC/configure" ] || { echo "==> running bootstrap.sh"; ( cd "$SRC" && sh bootstrap.sh ); }

# Make distclean is a no-op on a fresh checkout, but defensive: if a
# prior build left Makefile/config.h in the source tree, drop it so
# configure regenerates cleanly.
( cd "$SRC" \
	&& find . -maxdepth 2 -name Makefile -delete -o -name 'config.h' -delete -o -name 'config.status' -delete 2>/dev/null || true )

echo "==> configure (musl-static + with-openssl + without-sctp)"
# v0.2.0: enable OpenSSL (RSA-based auth features). iperf3 3.19.1
# only uses libcrypto (RSA + PEM); no TLS/SSL data channel.
# --enable-static-bin adds --static to LDFLAGS via iperf_config_static_bin.m4
# so the resulting binary is fully self-contained (no .so, no interpreter).
( cd "$BUILD_DIR" && "$SRC/configure" \
		--srcdir="$SRC" \
		--disable-dependency-tracking \
		--disable-silent-rules \
		--disable-shared \
		--enable-static \
		--enable-static-bin \
		--with-openssl=yes \
		--without-sctp )

echo "==> make"
( cd "$BUILD_DIR" && make -j"$(getconf _NPROCESSORS_ONLN)" )

echo "==> built:"
ls -l "$BUILD_DIR/src/iperf3"
file "$BUILD_DIR/src/iperf3"