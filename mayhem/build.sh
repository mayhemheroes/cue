#!/usr/bin/env bash
#
# cue/mayhem/build.sh — build the CUE parser fuzz harness as a sanitized libFuzzer
# binary (OSS-Fuzz Go path: go114-fuzz-build + clang link), plus a standalone
# single-input reproducer, and pre-compile the project's own test suite so
# mayhem/test.sh only RUNS it.
#
# Target: /mayhem/cue-parser-fuzz  (preserves the original fork's Mayhem target name)
# Harness: mayhem/fuzz/fuzz.go — legacy `func Fuzz([]byte) int` over parser.ParseFile,
# the same code path as the original fork's FuzzParseFile harness.
#
# AIR-GAPPED CONTRACT (SPEC §6.5): the PATCH tier re-runs THIS script OFFLINE.
# The first (online) build populates $GOMODCACHE; GOPROXY lists the in-image file
# proxy FIRST so the offline re-run resolves entirely from the cache.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
# OSS-Fuzz Go path is ASan-only for the libFuzzer link. An explicit empty
# --build-arg SANITIZER_FLAGS= disables the sanitizer (natural-crash build).
: "${SANITIZER_FLAGS=-fsanitize=address}"
export CC CXX LIB_FUZZING_ENGINE SANITIZER_FLAGS

# §6.2 item 10: DWARF < 4 (clang-19 defaults to DWARF-5) — pass -gdwarf-3 on the links.
: "${GO_DEBUG_FLAGS:=-g -gdwarf-3}"
export CGO_CFLAGS="${CGO_CFLAGS:+$CGO_CFLAGS }$GO_DEBUG_FLAGS"
export CGO_CXXFLAGS="${CGO_CXXFLAGS:+$CGO_CXXFLAGS }$GO_DEBUG_FLAGS"

# Go env pinned under /opt/toolchains (§6.2 item 8 — HOME-independent); file-proxy
# GOPROXY first so the offline re-run reads the in-image module cache.
export GOFLAGS="${GOFLAGS:--mod=mod}"
export GOTOOLCHAIN="${GOTOOLCHAIN:-local}"
export GOROOT="${GOROOT:-/opt/toolchains/go}"
export GOPATH="${GOPATH:-/opt/toolchains/go-path}"
export GOCACHE="${GOCACHE:-/opt/toolchains/go-path/cache/go-build}"
export GOMODCACHE="${GOMODCACHE:-/opt/toolchains/go-path/pkg/mod}"
export GOPROXY="${GOPROXY:-file://$(go env GOMODCACHE)/cache/download,https://proxy.golang.org,direct}"
export PATH="$GOROOT/bin:$GOPATH/bin:$PATH"
mkdir -p "$GOPATH" "$GOCACHE"

cd "$SRC"
go version
mkdir -p /mayhem "$SRC/mayhem-build"

# Warm the module cache (online first build; cache-hit no-op on the offline re-run).
go mod download all 2>&1 | tail -1 || true

TARGET="cue-parser-fuzz"
HARNESS_PKG="./mayhem/fuzz"

# ── libFuzzer archive via go114-fuzz-build (legacy []byte harness) ─────────────
echo "=== building $TARGET (go114-fuzz-build) ==="
AR="$SRC/mayhem-build/${TARGET}.a"
go-fuzz -tags gofuzz -func Fuzz -o "$AR" "$HARNESS_PKG"

# Sanitized libFuzzer binary.
$CXX $GO_DEBUG_FLAGS $SANITIZER_FLAGS $LIB_FUZZING_ENGINE "$AR" -o "/mayhem/$TARGET"
echo "built /mayhem/$TARGET"

# ── Standalone (non-fuzzer) single-input reproducer ────────────────────────────
STANDALONE_MAIN="$SRC/mayhem-build/standalone_main.c"
cat > "$STANDALONE_MAIN" <<'EOF'
#include <stdio.h>
#include <stdlib.h>
int LLVMFuzzerTestOneInput(const unsigned char *data, long size);
int main(int argc, char **argv) {
  if (argc < 2) { fprintf(stderr, "usage: %s <input-file>\n", argv[0]); return 2; }
  FILE *f = fopen(argv[1], "rb");
  if (!f) { perror("fopen"); return 2; }
  fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
  if (n < 0) { fclose(f); return 2; }
  unsigned char *buf = (unsigned char *)malloc(n ? n : 1);
  long rd = (long)fread(buf, 1, n, f); fclose(f);
  int rc = LLVMFuzzerTestOneInput(buf, rd);
  free(buf);
  return rc;
}
EOF
$CC $GO_DEBUG_FLAGS ${SANITIZER_FLAGS:-} -c "$STANDALONE_MAIN" -o "$SRC/mayhem-build/standalone_main.o"
if $CXX $GO_DEBUG_FLAGS ${SANITIZER_FLAGS:-} "$SRC/mayhem-build/standalone_main.o" "$AR" -lm \
      -o "/mayhem/${TARGET}-standalone" 2>"$SRC/mayhem-build/${TARGET}-standalone.log"; then
  echo "built /mayhem/${TARGET}-standalone"
else
  echo "WARNING: standalone link failed (see ${TARGET}-standalone.log)" >&2
  tail -5 "$SRC/mayhem-build/${TARGET}-standalone.log" >&2 || true
fi

# ── Pre-compile the project's OWN test suite (normal flags) so test.sh only RUNS it ──
echo "=== pre-compiling cue's test suite (go test -run=NONE ./...) ==="
go vet ./mayhem/fuzz >/dev/null 2>&1 || true
go test -run='^$' -count=1 ./... > /dev/null

echo "build.sh complete:"
ls -la /mayhem/cue-parser-fuzz* || true
