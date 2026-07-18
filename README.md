# iperf3 portable binaries (ljh-sh/iperf)

Vendored **[iperf3](https://github.com/esnet/iperf) @ 3.19.1** from
ESnet/LBNL, packaged as portable static binaries across 5 platforms:
Linux (musl × 2), macOS (× 2), Windows (× 1).

## Install

```sh
# macOS / Linux (anywhere with `x`):
x eget ljh-sh/iperf --to /usr/local/bin/iperf3

# Manual:
# 1. Go to https://github.com/ljh-sh/iperf/releases
# 2. Download the asset matching your platform
# 3. Unpack; put `iperf3` on your PATH
```

### Asset naming

| File | Platform |
|---|---|
| `iperf3-linux-musl-x64.tar.xz` | x86_64 Linux (Alpine / glibc, statically linked) |
| `iperf3-linux-musl-arm64.tar.xz` | aarch64 Linux (Graviton / RPi 4/5) |
| `iperf3-darwin-x64.tar.xz` | x86_64 macOS |
| `iperf3-darwin-arm64.tar.xz` | Apple Silicon macOS |
| `iperf3-windows-x64.zip` | x86_64 Windows (MinGW) |

Each archive contains `bin/iperf3` (or `bin/iperf3.exe`) plus `LICENSE`,
`NOTICE.md`, and this README.

## Use

```sh
# Server
iperf3 -s

# Client (run on another machine)
iperf3 -c <server-ip>

# UDP, 100 Mbit/s for 10 seconds
iperf3 -c <server-ip> -u -b 100M -t 10

# JSON output for scripting
iperf3 -c <server-ip> -J | jq '.end.sum_received.bits_per_second'
```

## Why this fork

The official iperf3 project ships source and a few pre-built binaries at
<https://downloads.es.net/pub/iperf/>, but coverage is uneven across
architectures (especially Apple Silicon and aarch64 Linux) and the
binaries are not always statically linked (broken on older glibc systems
or musl-based distros like Alpine).

This repo fixes that: every binary is statically linked, covers the
five platforms users actually run iperf3 on, and ships from CI on every
release tag.

## License

- **This distribution** (`ljh-sh/iperf`): BSD-3-Clause — see `LICENSE`.
- **iperf3 itself**: BSD-3-Clause (LBNL/ESnet) — see `upstream/iperf/LICENSE`.

We make no modifications to the vendored iperf3 source under
`upstream/iperf/`. See `NOTICE.md` for full attribution.

## See also

- iperf3 documentation: <https://software.es.net/iperf>
- Upstream source: <https://github.com/esnet/iperf>
- 中文 README: [README.cn.md](README.cn.md)