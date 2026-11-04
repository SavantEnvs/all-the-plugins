#!/usr/bin/env bash
#
# mayhem/build.sh — build this repo's fuzz harness(es). EDIT per repo.
#
# Runs inside the commit image (mayhem/Dockerfile) as `mayhem` in /mayhem. The base image
# (ghcr.io/savantenvs/base) already exports the build contract — use these, don't redefine:
#   CC, CXX             stock clang / clang++
#   LIB_FUZZING_ENGINE  -fsanitize=fuzzer   (link into each harness that has a LLVMFuzzer entry)
#   SANITIZER_FLAGS     -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer
#                       (ASan + UBSan, both set to HALT — so Mayhem catches memory AND UB defects)
#   DEBUG_FLAGS         -g -gdwarf-3   (DWARF debug info — always on for fuzz/standalone builds,
#                       independent of the sanitizer off-switch; DWARF version must be < 4)
#   RUST_DEBUG_FLAGS    -C debuginfo=2 -C force-frame-pointers=yes -C llvm-args=-gdwarf-3
#                       (thread through RUSTFLAGS on every cargo-fuzz build)
#   GO_DEBUG_FLAGS      -gcflags=all=-N -l
#                       (thread through go build / go-fuzz-build so the linked ELF keeps symbols)
#   SRC                 /mayhem (the repo source)
#
# Contract: build EVERYTHING here — one runnable binary per fuzz harness, AND the project's test
# suite (so mayhem/test.sh only has to RUN it, never compile). Keep it ADDITIVE (build upstream as
# upstream documents; don't edit upstream files). IMPORTANT: build the PROJECT ITSELF with
# $SANITIZER_FLAGS and $DEBUG_FLAGS (not just the harness) so the fuzzed code is instrumented
# AND carries DWARF < 4 symbols — otherwise ASan/UBSan only see the harness, not the library
# you're trying to find bugs in, and backtraces won't resolve project source lines. Build the TEST
# suite with the project's NORMAL flags (a clean, independent build) so test.sh stays an honest
# functional oracle and won't false-fail on benign UB. Leave the test binary/runner where test.sh
# expects it.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — it must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# Build knobs come from the ENVIRONMENT (overridable), with sane defaults — no if-statements,
# just parameter-expansion fallbacks. Default sanitizers are the base's ASan+UBSan (halting); override
# per build via the Dockerfile's `--build-arg SANITIZER_FLAGS="..."`.
# NB: SANITIZER_FLAGS uses `=` (no colon) on purpose — `=` only fills when the var is UNSET, so an
# explicit EMPTY value (`--build-arg SANITIZER_FLAGS=`) is honored and builds with NO sanitizers
# (useful when you want the program's natural crash / full backtrace, not an ASan report). The other
# knobs use `:=` (default on empty too). MAYHEM_JOBS sets build parallelism (falls back to nproc).
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
# DEBUG_FLAGS carries DWARF debug info INDEPENDENTLY of the sanitizer off-switch (so an empty
# SANITIZER_FLAGS still yields DWARF symbols). DWARF MUST be < 4 (Mayhem triage can't read >=4); clang-19's
# plain `-g` emits DWARF-5, so `-gdwarf-3` is explicit. Apply $DEBUG_FLAGS to the fuzz/harness/standalone
# builds (NOT the test/oracle build). Rust/Go carry the same intent via their language flags below.
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${RUST_DEBUG_FLAGS:=-C debuginfo=2 -C force-frame-pointers=yes -C llvm-args=-gdwarf-3}"
: "${GO_DEBUG_FLAGS:=-gcflags=all=-N -l}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
# COVERAGE_FLAGS: empty by default → no effect on the normal oracle build. Set it via the Dockerfile's
# `--build-arg COVERAGE_FLAGS="-fprofile-instr-generate -fcoverage-mapping"` to instrument the TEST
# build for source-coverage measurement (how much of the project the test suite actually exercises —
# a quality signal for the oracle; complements the anti-reward-hack sabotage check). APPEND it to the
# test build's compile+link flags in step 3 (NOT the fuzz build); after `test.sh` runs, merge with
# `llvm-profdata` and report with `llvm-cov`. Empty value is honored (`=`, not `:=`).
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS RUST_DEBUG_FLAGS GO_DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# The repo is a collection of Flipper Zero apps with no host build. The fuzzed code is the
# platform-independent core of three of them, compiled unmodified; mayhem/stubs/ stands in for the
# parts of the Flipper firmware SDK (furi, furi_hal) those sources include.
CALC=apps_source_code/calculator
DCF=apps_source_code/flipper-dcf77
UHF=apps_source_code/uhf_rfid
INC="-Imayhem/stubs -I$CALC -I$DCF/src -I$UHF"

OBJ=build/obj
mkdir -p "$OBJ"
FUZZ_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link -O1"

# 1) The project sources, sanitized and carrying DWARF 3, one object per source file.
# NB: object names use the source's directory so same-named files can't collide.
obj_of() { echo "$OBJ/$(echo "${1%.*}" | tr '/' '_').o"; }
# Relaxed UBSan check, per file (everything else stays halting):
#  - tinyexpr.c allocates te_expr with its trailing parameters[] array trimmed for leaf nodes, which
#    trips object-size on the first node of every parse.
relax_for() {
  case "$1" in
    "$CALC/tinyexpr.c") echo "-fno-sanitize=object-size" ;;
  esac
}
compile_c() {
  local o; o=$(obj_of "$1")
  $CC $FUZZ_FLAGS $(relax_for "$1") $INC -c "$1" -o "$o"
}

TINYEXPR_SRCS="$CALC/tinyexpr.c mayhem/fuzz_tinyexpr.c"
DCF_SRCS="$DCF/src/radio_clock_protocol.c $DCF/src/bsf_util.c $DCF/src/bpc_util.c
  $DCF/src/pair_timecode.c $DCF/src/dcf77_util.c $DCF/src/hbg_util.c $DCF/src/jjy_util.c
  $DCF/src/msf_util.c $DCF/src/wwvb_util.c mayhem/fuzz_dcf77.c"
UHF_SRCS="$UHF/uhf_module.c $UHF/uhf_uart.c $UHF/uhf_buffer.c $UHF/uhf_tag.c
  mayhem/stubs/furi_stubs.c mayhem/fuzz_uhf_m100.c"

for s in $TINYEXPR_SRCS $DCF_SRCS $UHF_SRCS; do compile_c "$s"; done

# LeakSanitizer is off for every target (leaks aren't the bug class fuzzed here).
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c mayhem/lsan_off.cc -o "$OBJ/lsan_off.o"

# Run-once driver for the standalone reproducers, compiled as C.
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -O1 -c "$STANDALONE_FUZZ_MAIN" -o "$OBJ/standalone_main.o"

objs() { local r=""; for s in "$@"; do r="$r $(obj_of "$s")"; done; echo "$r"; }

# 2) Per target: the libFuzzer binary and the -standalone reproducer.
link_target() { # <name> <linker> <objects...>
  local name="$1" ld="$2"; shift 2
  $ld $SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link $LIB_FUZZING_ENGINE "$@" "$OBJ/lsan_off.o" -lm -o "/mayhem/$name"
  $ld $SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link "$@" "$OBJ/standalone_main.o" "$OBJ/lsan_off.o" -lm -o "/mayhem/$name-standalone"
}
link_target fuzz_tinyexpr "$CC" $(objs $TINYEXPR_SRCS)
link_target fuzz_dcf77 "$CC" $(objs $DCF_SRCS)
link_target fuzz_uhf_m100 "$CC" $(objs $UHF_SRCS)

# 3) Test oracle with the project's NORMAL flags (clean, unsanitized, independent of the above):
#    flipper-dcf77's own host tests plus a known-answer probe over the calculator and UHF code.
make -C "$DCF/tests" -j"$MAYHEM_JOBS" all CC="$CC" \
  CFLAGS="-std=c11 -Wall -Wextra -Werror -I../src -O2 $COVERAGE_FLAGS" LDFLAGS="$COVERAGE_FLAGS"

$CC -O2 $COVERAGE_FLAGS $INC mayhem/kat_c.c "$CALC/tinyexpr.c" "$UHF/uhf_module.c" "$UHF/uhf_uart.c" \
  "$UHF/uhf_buffer.c" "$UHF/uhf_tag.c" mayhem/stubs/furi_stubs.c -lm -o /mayhem/kat_c
