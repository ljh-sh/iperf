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
CONFIGURE_ARGS="--disable-dependency-tracking --disable-silent-rules --with-openssl --without-sctp --disable-shared --enable-static"

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
		# frameworks — that's the Apple distribution model. We only
		# verify no Homebrew dylibs leak (see release.yml otool check).
		# Homebrew openssl is keg-only; point pkg-config at it so iperf3's
		# ax_check_openssl.m4 finds it. Without this, configure falls
		# back to Apple's deprecated /usr/include/openssl (3.0-only,
		# removed in newer SDKs).
		OPENSSL_PREFIX="$(brew --prefix openssl@3 2>/dev/null || brew --prefix openssl 2>/dev/null || true)"
		if [ -n "$OPENSSL_PREFIX" ]; then
			export PKG_CONFIG_PATH="$OPENSSL_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
		fi
		export CC=clang
		export CFLAGS="-arch $TARGET_ARCH -O2 -D_FORTIFY_SOURCE=2"
		export LDFLAGS="-arch $TARGET_ARCH"
		;;
	windows)
		# MinGW cross-toolchain. iperf3 on MinGW has a long-standing
		# portability gap: sys/socket.h (and friends) require winsock2.h
		# to be included first. Force-include winsock2.h via CFLAGS so
		# every TU gets it before its first network header. Also define
		# _WIN32_WINNT=0x0601 (Windows 7+) so newer MinGW headers
		# expose the full API surface iperf3 needs.
		export CC="${TARGET_ARCH}-w64-mingw32-gcc"
		export CXX="${TARGET_ARCH}-w64-mingw32-g++"
		export CFLAGS="-O2 -static -D_WIN32_WINNT=0x0601 -include winsock2.h"
		export LDFLAGS="-static"
		# iperf3's configure checks for socket() etc. via AC_SEARCH_LIBS
		# — MinGW ships socket() in -lws2_32 and process APIs in -lpsapi.
		# These MUST be in LIBS (not LDFLAGS) so autoconf's compile+link
		# test programs find them during configure.
		export LIBS="-lws2_32 -lpsapi"
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