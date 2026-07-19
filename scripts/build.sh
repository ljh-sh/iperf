#!/usr/bin/env sh
# Build iperf3 on host (macOS) or cross-compile to MinGW from a
# POSIX shell. Out-of-tree build into BUILD_DIR (default ./build).
#
# Used by:
#   - .github/workflows/build-and-test.yml + release.yml on:
#       macos-14            (host arch = aarch64-macos; cross to x86_64)
#       windows-latest      (MSYS2/mingw64 x86_64)
#   - Local development on any POSIX host with autotools.
#
# Cross-compile: set IPERF_TARGET_ARCH + IPERF_TARGET_OS (or
# IPERF_TRIPLET) + IPERF_OS_HINT (darwin | windows).
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SRC="${IPERF_SRC:-$ROOT/upstream/iperf}"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"

[ -f "$SRC/configure.ac" ] || { echo "error: $SRC/configure.ac not found" >&2; exit 1; }
command -v autoreconf >/dev/null 2>&1 \
	|| { echo "error: autoreconf not found in PATH (install autoconf + automake + libtool)" >&2; exit 1; }

JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.nproc 2>/dev/null || echo 4)"

# Minimal configure args. By default:
#   --disable-dependency-tracking   (one-shot CI build, no dep graph)
#   --disable-silent-rules          (so `make` logs each step — CI shows it)
#   --with-openssl                  (RSA auth features; static-link only)
#   --without-sctp                  (SCTP rare on portable targets)
#   --disable-shared --enable-static (build static lib only, no .dylib)
# iperf3's --disable-openssl and --disable-zc are unrecognized and just
# emit warnings — use --with-openssl (without value = detect) and let
# zerocopy auto-disable. NOTE: --enable-static-bin is musl-only (adds
# --static to LDFLAGS via iperf_config_static_bin.m4; macOS ld rejects
# --static). On macOS/Windows we set --enable-static (default=yes per
# iperf3 help) so libiperf.a is built, but the binary itself links
# dynamically to system frameworks (Apple model) or to ws2_32 (MinGW).
CONFIGURE_ARGS="--disable-dependency-tracking --disable-silent-rules --without-sctp --disable-shared --enable-static"

# Cross-compile: IPERF_TARGET_ARCH (x86_64 / aarch64), IPERF_TARGET_OS
# (apple-darwin / w64-mingw32), IPERF_TRIPLET.
HOST_ARCH="$(uname -m 2>/dev/null || echo unknown)"
TARGET_ARCH="${IPERF_TARGET_ARCH:-$HOST_ARCH}"
TRIPLET="${IPERF_TRIPLET:-}"
if [ -n "${IPERF_TARGET_OS:-}" ]; then
	TRIPLET="${TRIPLET:-${IPERF_TARGET_ARCH}-${IPERF_TARGET_OS}}"
fi
if [ "$TARGET_ARCH" != "$HOST_ARCH" ] || [ -n "${IPERF_TARGET_OS:-}" ]; then
	[ -z "$TRIPLET" ] && TRIPLET="$TARGET_ARCH"
	case "${IPERF_OS_HINT:-}" in
	darwin)
		# Apple SDK is shared between arches; clang auto-discovers via xcrun.
		# macOS binaries dynamically link to /usr/lib + /System/Library
		# frameworks — that's the Apple distribution model.
		#
		# To stay self-contained (per the user's preference), we
		# force-link Homebrew's openssl .a archives via
		# -Wl,-force_load. macOS ld rejects -static (unlike Linux),
		# so -Wl,-force_load,<archive> is the canonical way to make
		# the linker include every symbol from the archive instead
		# of letting -lssl resolve to libssl.dylib at install_name
		# lookup time. We force-load libssl.a (which transitively
		# pulls libcrypto.a through its .o references).
		OPENSSL_PREFIX="$(brew --prefix openssl@3 2>/dev/null || brew --prefix openssl 2>/dev/null || true)"
		if [ -n "$OPENSSL_PREFIX" ]; then
			export PKG_CONFIG_PATH="$OPENSSL_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
			SSL_A="$OPENSSL_PREFIX/lib/libssl.a"
			CRYPTO_A="$OPENSSL_PREFIX/lib/libcrypto.a"
			FORCE_LOAD_OPENSSL="-Wl,-force_load,$SSL_A -Wl,-force_load,$CRYPTO_A"
		else
			FORCE_LOAD_OPENSSL=""
		fi
		export CC=clang
		export CFLAGS="-arch $TARGET_ARCH -O2 -D_FORTIFY_SOURCE=2"
		export LDFLAGS="-arch $TARGET_ARCH $FORCE_LOAD_OPENSSL"
		;;
	msys)
		# MSYS (msystem: MSYS in setup-msys2) provides a full POSIX
		# environment, so iperf3 builds cleanly with no source patches.
		# The resulting iperf3.exe depends on msys-2.0.dll — users need
		# MSYS2 installed (or runtime dll bundled). iperf3's upstream
		# doesn't formally support Windows, but MSYS is the closest
		# POSIX layer setup-msys2@v2 offers (CYGWIN64 isn't supported).
		# WIN32_LEAN_AND_MEAN skips wincrypt.h's deprecated X509_NAME
		# numeric define that conflicts with OpenSSL's typedef.
		export CC="gcc"
		export CXX="g++"
		export CFLAGS="-O2 -D_FORTIFY_SOURCE=2 -DWIN32_LEAN_AND_MEAN"
		export LDFLAGS=""
		;;
	*)
		# Generic clang fallback.
		export CC=clang
		export CFLAGS="-arch $TARGET_ARCH -O2"
		export LDFLAGS="-arch $TARGET_ARCH"
		;;
	esac
	CONFIGURE_ARGS="$CONFIGURE_ARGS --host=$TRIPLET"
	[ -n "${IPERF_BUILD_TRIPLET:-}" ] && CONFIGURE_ARGS="$CONFIGURE_ARGS --build=$IPERF_BUILD_TRIPLET"
	echo "==> cross-compile: host=$HOST_ARCH → target=$TARGET_ARCH ($TRIPLET)"
fi

# Clean stale state from prior builds (defensive)
( cd "$SRC" \
	&& find . -maxdepth 2 -name Makefile -delete -o -name 'config.h' -delete -o -name 'config.status' -delete 2>/dev/null || true )

# Windows builds via Cygwin (msystem: CYGWIN64 in setup-msys2) provide
# full POSIX headers (sys/socket.h, netdb.h, etc.) so no source patch
# is needed. We previously tried MinGW-w64 but its runtime is missing
# the POSIX-style wrappers iperf3 expects (only winsock2.h, no
# sys/socket.h). Cygwin is iperf3's de-facto Windows build env.

mkdir -p "$BUILD_DIR"

echo "==> configure"
( cd "$BUILD_DIR" && "$SRC/configure" --srcdir="$SRC" $CONFIGURE_ARGS )

echo "==> make"
( cd "$BUILD_DIR" && make -j"$JOBS" )

echo "==> built:"
if [ "${IPERF_OS_HINT:-}" = "windows" ]; then
	ls -l "$BUILD_DIR/src/.libs/iperf3.exe" 2>/dev/null || ls -l "$BUILD_DIR/src/iperf3.exe"
else
	ls -l "$BUILD_DIR/src/iperf3"
fi