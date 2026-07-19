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
		export LDFLAGS="-static -lws2_32 -lpsapi"
		export LIBS="-lws2_32 -lpsapi"
		# iperf3 3.19.1's configure.ac does:
		#   AC_SEARCH_LIBS(socket, [socket], [], [echo "socket()"; exit 1])
		#   AC_SEARCH_LIBS(inet_ntop, [nsl], [], [echo "inet_ntop()"; exit 1])
		#   AC_SEARCH_LIBS(clock_gettime, [rt posix4])
		#   AC_SEARCH_LIBS(nanosleep, [rt posix4])
		#   AC_SEARCH_LIBS(clock_nanosleep, [rt posix4])
		# AC_SEARCH_LIBS only searches its explicit list — it does NOT
		# honor user-supplied LIBS for the lookup. So even with LIBS=
		# -lws2_32 in env, configure falls through to "exit 1" because
		# -lsocket / -lnsl don't exist on MinGW. Pre-seed the autoconf
		# cache so the searches short-circuit with the correct answer.
		# On MinGW: socket/inet_ntop/clock_gettime/nanosleep are all in
		# ws2_32; clock_nanosleep is not available, but the iperf3 source
		# only uses it conditionally so "no" (skip) is safe.
		export ac_cv_search_socket="ws2_32"
		export ac_cv_search_inet_ntop="ws2_32"
		export ac_cv_search_clock_gettime="ws2_32"
		export ac_cv_search_nanosleep="ws2_32"
		export ac_cv_search_clock_nanosleep="no"
		# MinGW's <stdatomic.h> AC_LINK_IFELSE test fails under -static
		# (the always_lock_free intrinsic check can't link a libatomic
		# shim cleanly). iperf3 has a fallback (typedef uint64_t
		# atomic_uint_fast64_t) when HAVE_STDATOMIC_H is undefined —
		# pre-seed the cache to take that fallback path.
		export ac_cv_header_stdatomic_h="no"
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

# MinGW portability patch: iperf3's POSIX includes (sys/socket.h,
# netdb.h, etc.) require <winsock2.h> to be included first on
# MSYS2/MinGW. Force-include via CFLAGS works for the build itself
# but autotools-generated compile rules emit explicit -I paths that
# shadow the system MinGW includes, so the force-include can't find
# winsock2.h either. The robust fix is to sed-patch each affected
# source file to prepend <winsock2.h> before its first network
# header. Idempotent — safe to re-run.
if [ "${IPERF_OS_HINT:-}" = "windows" ]; then
	echo "==> windows patch: prepend <winsock2.h> before POSIX network headers"
	( cd "$SRC/src" && \
		for f in *.c *.h; do
			[ -f "$f" ] || continue
			# Skip if already patched
			grep -q '__IPERF_WIN32_WS2_PATCH__' "$f" 2>/dev/null && continue
			# Skip files that don't have network headers (e.g. main.c does)
			grep -qE '#include[[:space:]]*<sys/socket\.h>|<netinet/in\.h>|<netdb\.h>' "$f" || continue
			# Insert winsock2.h right before the first such include
			awk '
				/^#include[[:space:]]*<sys\/socket\.h>|^#include[[:space:]]*<netinet\/in\.h>|^#include[[:space:]]*<netdb\.h>/ \
					&& !done { \
					print "#define __IPERF_WIN32_WS2_PATCH__"; \
					print "#ifdef _WIN32"; \
					print "#  ifndef _WINSOCK2_H_"; \
					print "#    include <winsock2.h>"; \
					print "#    include <ws2tcpip.h>"; \
					print "#  endif"; \
					print "#endif"; \
					done=1 \
				} \
				{ print }
			' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
		done \
	)
fi

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