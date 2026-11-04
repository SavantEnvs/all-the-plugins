#!/usr/bin/env bash
#
# mayhem/test.sh — RUN this repo's OWN functional test suite (already built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# Oracle for the code under fuzz, in two parts (both built by mayhem/build.sh with normal flags):
#  1. flipper-dcf77's own host test programs; each must exit 0 AND print its `<name>: OK` line.
#     test_experimental_time is built but not run: upstream's own test is stale (it expects
#     speedup 5 after normalizing 9, which the code, correctly per its clamp, leaves at 9).
#  2. mayhem/kat_c.c: known-answer probes for the calculator's tinyexpr (evaluated values) and the
#     UHF M100 driver (frame checksum, CRC-16/GENIBUS check value, response parsing into a tag).
#     Its output is compared line by line against fixed expected values below.
passed=0 ; failed=0

DCF_TESTS="$SRC/apps_source_code/flipper-dcf77/tests"
for t in set_dcf_message set_msf_message set_wwvb_message set_jjy_message set_bpc_message \
         set_bsf_message hbg_util radio_clock_protocol subghz_settings debug_settings \
         tx_ratio; do
  name="test_$t"
  if [ ! -x "$DCF_TESTS/$name" ]; then
    echo "FAIL $name: missing (mayhem/build.sh builds it)" >&2
    failed=$((failed+1)) ; continue
  fi
  out=$(cd "$DCF_TESTS" && "./$name" 2>&1) ; rc=$?
  if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -Eqx "$name: (OK|ok)"; then
    echo "PASS $name"
    passed=$((passed+1))
  else
    echo "FAIL $name (exit $rc): $out" >&2
    failed=$((failed+1))
  fi
done

KAT="$SRC/kat_c"
if [ ! -x "$KAT" ]; then
  echo "FAIL kat_c: missing (mayhem/build.sh builds it)" >&2
  failed=$((failed+1))
else
  actual=$("$KAT" 2>&1)
  expected='expr[2+3*4]=14.000000 err=0
expr[sqrt(16)+2^3]=12.000000 err=0
expr[-(1+2)*3]=-9.000000 err=0
expr[5%3+10/4]=4.500000 err=0
expr[2+]=nan err=2
checksum=04
crc16_genibus=d64e
poll=0 size=12 pc=3000 crc=3d47 epc=e2801160600002054a3b1c2d
poll_corrupt=5
poll_empty=4
hw=M100v1.0'
  while IFS= read -r line; do
    if printf '%s\n' "$actual" | grep -qxF -- "$line"; then
      echo "PASS kat: $line"
      passed=$((passed+1))
    else
      echo "FAIL kat: expected '$line'" >&2
      failed=$((failed+1))
    fi
  done <<< "$expected"
  if [ "$(printf '%s\n' "$actual" | wc -l)" -ne "$(printf '%s\n' "$expected" | wc -l)" ]; then
    echo "FAIL kat: unexpected extra or missing output lines" >&2
    failed=$((failed+1))
  fi
fi

emit_ctrf "all-the-plugins-oracle" "$passed" "$failed" 0
