# iperf3 便携二进制 (ljh-sh/iperf)

打包自 ESnet / LBNL 的 **[iperf3](https://github.com/esnet/iperf) 3.19.1**，以 5 个平台的便携静态二进制分发：Linux (musl × 2)、macOS (× 2)、Windows (× 1)。

## 安装

```sh
# macOS / Linux（有 `x` 命令）：
x eget ljh-sh/iperf --to /usr/local/bin/iperf3

# 手动：
# 1. 打开 https://github.com/ljh-sh/iperf/releases
# 2. 下载匹配你平台的 asset
# 3. 解压，把 `iperf3` 放到 PATH
```

### 资产命名

| 文件 | 平台 |
|---|---|
| `iperf3-linux-musl-x64.tar.xz` | x86_64 Linux（Alpine / glibc，静态链接）|
| `iperf3-linux-musl-arm64.tar.xz` | aarch64 Linux（Graviton / RPi 4/5）|
| `iperf3-darwin-x64.tar.xz` | x86_64 macOS |
| `iperf3-darwin-arm64.tar.xz` | Apple Silicon macOS |
| `iperf3-windows-x64.zip` | x86_64 Windows（MinGW）|

每个压缩包都包含 `bin/iperf3`（Windows 是 `iperf3.exe`）以及 `LICENSE`、`NOTICE.md` 和本 README。

## 使用

```sh
# 服务端
iperf3 -s

# 客户端（在另一台机器上跑）
iperf3 -c <server-ip>

# UDP，100 Mbit/s 跑 10 秒
iperf3 -c <server-ip> -u -b 100M -t 10

# JSON 输出（方便脚本处理）
iperf3 -c <server-ip> -J | jq '.end.sum_received.bits_per_second'
```

## 为什么要这个 fork

iperf3 官方在 <https://downloads.es.net/pub/iperf/> 提供源码和部分预编译二进制，但跨架构覆盖不均（特别是 Apple Silicon 和 aarch64 Linux），二进制也不是总静态链接（在老 glibc 系统或 musl distro 如 Alpine 上会炸）。

这个仓库解决这俩问题：每个二进制都静态链接，覆盖用户实际运行 iperf3 的五个平台，每个 release tag 都从 CI 走一遍。

## 许可证

- **本发行版** (`ljh-sh/iperf`): BSD-3-Clause —— 见 `LICENSE`。
- **iperf3 本身**: BSD-3-Clause (LBNL/ESnet) —— 见 `upstream/iperf/LICENSE`。

我们对 `upstream/iperf/` 下的 vendored 源码不做任何修改。完整归因见 `NOTICE.md`。

## 另见

- iperf3 文档：<https://software.es.net/iperf>
- 上游源码：<https://github.com/esnet/iperf>
- English README: [README.md](README.md)