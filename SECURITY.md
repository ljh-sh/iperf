# Security Policy

## Reporting a vulnerability

iperf3 is upstream software. For vulnerabilities in iperf3 itself, please
report to <iperf@es.net> (per upstream SECURITY policy). They coordinate
CVE assignment and patches.

For vulnerabilities **specific to this distribution** (build scripts,
CI pipelines, release artifacts, packaging):

- **Email**: open an issue at <https://github.com/ljh-sh/iperf/issues>
- **GitHub Security Advisories**: <https://github.com/ljh-sh/iperf/security/advisories/new>

We follow responsible disclosure: please give us 90 days before
public disclosure, or coordinate a faster timeline if the issue is
already being exploited in the wild.

## Audit status

This distribution's `upstream/iperf/` source is unmodified from
[esnet/iperf @ 3.19.1](https://github.com/esnet/iperf/releases/tag/3.19.1)
(commit pinned at release tarball SHA).

The build scripts under `scripts/` and `.github/workflows/` are
open-source and reviewable in this repository. Notable security choices:

- **OpenSSL**: NOT linked in v0.1.0. iperf3's `--auth`/`--crypto` modes
  are unavailable; we trade that for a smaller, easier-to-audit binary
  (~150 KB vs ~3 MB).
- **Static linking** on musl: no runtime loader resolution, no DT_RPATH
  hijack surface.
- **Reproducible builds**: CI builds each platform on a fixed-image
  runner with pinned toolchains. See `.github/workflows/` for the exact
  image tags.

## CVE history for iperf3

- **CVE-2023-38403** (iperf3 3.14+ mbed TLS heap overflow): fixed in
  iperf3 3.14. Our 3.19.1 includes the fix.
- For full history, see
  <https://github.com/esnet/iperf/security/advisories>.