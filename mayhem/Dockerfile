# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile (SMALL form) — builds ON TOP of the org C/C++ base image
# (ghcr.io/mayhemheroes/base). cue (cuelang.org/go) is a pure-Go project, so the base
# (C/C++ only — NO Go toolchain) needs Go added here as a USER root step, then
# go114-fuzz-build to turn the legacy `func Fuzz([]byte) int` harness into a
# libFuzzer-instrumented binary linked with $LIB_FUZZING_ENGINE.
#
# Build (from the repo root):
#   DOCKER_BUILDKIT=1 docker build -f mayhem/Dockerfile \
#       --build-arg COMMIT=$(git rev-parse HEAD) \
#       [--build-arg SOURCE_DATE_EPOCH=$(date +%s)] \
#       -t cue-commit:test .

FROM ghcr.io/mayhemheroes/base:20260621

ARG COMMIT
ARG REPO_URL
# SOURCE_DATE_EPOCH stays an ARG (available to build.sh); never bake it as ENV — an
# empty value breaks clang. build.sh unsets it when empty.
ARG SOURCE_DATE_EPOCH

# The OSS-Fuzz Go path is ASan-only; build.sh handles the Go specifics.
ARG SANITIZER_FLAGS
ARG MAYHEM_JOBS=

# Pin the Go toolchain to match cue's go.mod (`go 1.25.0`) so GOTOOLCHAIN=local
# builds without any network toolchain fetch.
ARG GO_VERSION=1.25.0
ARG GO_SHA256=2852af0cb20a13139b3448992e69b868e50ed0f8a1e5940ee1de9e19a123b613

# ── Toolchain path: /opt/toolchains/go (SPEC §6.2 item 8 — HOME-independent) ──
ENV GOROOT=/opt/toolchains/go \
    GOPATH=/opt/toolchains/go-path \
    GOMODCACHE=/opt/toolchains/go-path/pkg/mod \
    GOCACHE=/opt/toolchains/go-path/cache/go-build \
    GOTOOLCHAIN=local \
    PATH=/opt/toolchains/go/bin:/opt/toolchains/go-path/bin:/usr/local/bin:/usr/bin:/bin

USER root
RUN repro-sources-list.sh 2>/dev/null || true; \
    apt-get update && apt-get install -yq --no-install-recommends wget ca-certificates git \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /opt/toolchains \
    && wget -q "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -O /tmp/go.tgz \
    && echo "${GO_SHA256}  /tmp/go.tgz" | sha256sum -c - \
    && tar -C /opt/toolchains -xzf /tmp/go.tgz && rm /tmp/go.tgz \
    && mv /opt/toolchains/go /opt/toolchains/go-${GO_VERSION} \
    && ln -s go-${GO_VERSION} /opt/toolchains/go \
    && go version \
    && mkdir -p /opt/toolchains/go-path \
    && go install github.com/mdempsky/go114-fuzz-build@latest \
    && ln -sf "/opt/toolchains/go-path/bin/go114-fuzz-build" "/opt/toolchains/go-path/bin/go-fuzz" \
    && chown -R 2000:2000 /opt/toolchains/go-path \
    && chmod -R a+rX /opt/toolchains/go

USER mayhem

# Source enters from the build CONTEXT (the CI checkout): the FULL repo (incl. .git
# history) is copied to /mayhem; build.sh builds in place.
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

# Populates $GOMODCACHE (online, first build) and builds the libFuzzer target +
# standalone reproducer + pre-compiles the test suite.
RUN bash mayhem/build.sh

# Run cue's own full Go test suite at build time (a failing suite fails the build).
RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
