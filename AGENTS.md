# ljh-sh/iperf — agent notes

> **This is the public-facing agent note** for `ljh-sh/iperf`.
>
> The full design document, decision log, audit plans, and ongoing
> development discussions live in the private **`mneme`** repository
> under [`iperf-design/`](https://github.com/ljh-sh/mneme/blob/main/iperf-design/README.md).
>
> **mneme is the design HQ** for all `ljh-sh/*` repos. The public
> repos stay clean and ship-ready; mneme holds the messy iteration.

## TL;DR for AI agents

- **What**: portable iperf3 binaries (esnet/iperf @ 3.19.1) for 5 platforms.
- **How**: vendored upstream under `upstream/iperf/`, autotools build
  in Alpine (musl) / macOS host / Windows MSYS2.
- **CI**: `.github/workflows/{build-and-test,release}.yml`.
- **Do not modify**: anything under `upstream/iperf/`.
- **All build flags**: see `scripts/build-alpine.sh` and `scripts/build.sh`.

## Issue & PR conventions

- **Public issues** here are for end-users of the binaries (install
  problems, platform bugs, etc.).
- **Design / roadmap / upstream-tracking** discussions go in
  [`ljh-sh/mneme`](https://github.com/ljh-sh/mneme) under
  `iperf-design/` or `story/YYMMDD.iperf-*`.

## License

BSD-3-Clause (see `LICENSE`). Vendored iperf3 under `upstream/iperf/`
is also BSD-3-Clause (LBNL/ESnet — see `upstream/iperf/LICENSE`).