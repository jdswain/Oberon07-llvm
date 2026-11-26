#!/bin/bash
# run_self_tests.sh — oc816's golden suite, each test run on OS16 under
# em16 (make test, in self/s816). It came from 65Tools' oc/test, where
# the C compiler it was first written for still is.
#
# Usage:
#   ./test/run_self_tests.sh [level ...]
#     OC     compiler binary (default: oc816, beside test/)
#     OCFLAGS  more options for it: -x, code for the core's extension after
#            WDM (MUL, DIV, the shifts by n), which em16 -fpga runs
#     TOOLS  65Tools, for bin/em16 and bin/as (default: ../65/65Tools,
#            beside this repository); EM16 and AS name the two themselves
#     OS16   OS16, for its build and tools/mkfloppy.py (default:
#            ../65/OS16, beside this repository); OS16B its build
#     TIMEOUT_SECS  seconds of em16 a test may take (default 30), wall clock:
#            raise it on a loaded machine
#     args   optional list of level prefixes to run (e.g. L1 L5); default all
#
# Each test runs on OS16, booted as on the board: em16 -fpga with OS16's
# boot ROM and a floppy (OS16/tools/mkfloppy.py) holding the kernel image,
# /Library/Settings/Startup.txt naming the test, and the test's module with the modules it
# imports. OS16 must be built first (cd $OS16 && make): the tests link
# to the kernel's modules (Out, HeapManager, ...) by its symbol files, and
# their output is what follows Out's "OK" as the kernel starts.
#
# A helper module (no .expected) is compiled with OCFLAGS, but one whose
# name ends in 816 (L19_Stock816) with -816, code for a stock 65C816; a
# *.s helper (L19_StockRun) is assembled to its .816 and .smb.
#
# Parity note: oc816 uses the shared (latest) Oberon frontend. Its REAL
# literal conversion is correctly-rounded and can differ in the last
# printed digit from the C compiler's (e.g. 3.14159 vs 3.14158) — oc816 is
# the accurate one. Such REAL-precision goldens predate the switchover.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

OC="${OC:-$PROJECT_DIR/oc816}"
OCFLAGS="${OCFLAGS:-}"
TOOLS="${TOOLS:-$PROJECT_DIR/../../../65/65Tools}"
OS16="${OS16:-$PROJECT_DIR/../../../65/OS16}"
EM16="${EM16:-$TOOLS/bin/em16}"
AS="${AS:-$TOOLS/bin/as}"
OS16B="${OS16B:-$OS16/build}"
TIMEOUT_SECS="${TIMEOUT_SECS:-30}"

if [ ! -x "$OC" ];   then echo "ERROR: compiler not found/executable at $OC (make)"; exit 1; fi
if [ ! -x "$EM16" ]; then echo "ERROR: emulator not found at $EM16"; exit 1; fi
if [ ! -x "$AS" ];   then echo "ERROR: assembler not found at $AS"; exit 1; fi
if [ ! -f "$OS16B/Kernel.img" ]; then echo "ERROR: no OS16 kernel at $OS16B (cd $OS16 && make)"; exit 1; fi
KERNEL="$(cat "$OS16B/KERNEL.TXT")"
MKFLOPPY="$OS16/tools/mkfloppy.py"

# Work in a scratch dir, so that the tests' .816 and .smb files never
# land in test/.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp "$SCRIPT_DIR"/*.Mod "$WORK"/ 2>/dev/null
cp "$SCRIPT_DIR"/*.expected "$WORK"/ 2>/dev/null
cp "$SCRIPT_DIR"/*.s "$WORK"/ 2>/dev/null
cd "$WORK" || exit 1
# the kernel's modules are the kernel's: its symbol files, not compiled here
for k in $KERNEL; do rm -f "$k.Mod"; cp "$OS16B/$k.smb" .; done
cp "$OS16B/Kernel.img" "$OS16B/boot.rom" .

# Assemble the *.s helpers: as writes each one's .816 and .smb.
for s in *.s; do
  [ -f "$s" ] && "$AS" -o "${s%.s}.816" "$s" >/dev/null 2>&1
done

# Pre-compile library modules so dependencies resolve.
for lib in Runtime TestTool; do
  [ -f "$lib.Mod" ] && "$OC" "$lib.Mod" -s $OCFLAGS >/dev/null 2>&1
done

# Pre-compile helper/dependency modules — any *.Mod that is not a library and
# has no *.expected of its own (e.g. the cross-module OO base/extension, or
# L*_Lib helpers). Two passes so an extension picks up its base's fresh .smb.
for pass in 1 2; do
  for m in *.Mod; do
    bn="${m%.Mod}"
    case "$bn" in Runtime|TestTool) continue;; esac
    [ -f "$bn.expected" ] && continue   # a test driver — compiled+run below
    case "$bn" in *816) flags=-816;; *) flags="$OCFLAGS";; esac
    "$OC" "$m" -s $flags >/dev/null 2>&1
  done
done

LEVELS=("$@")
if [ ${#LEVELS[@]} -eq 0 ]; then
  # Discover level prefixes present as *.expected (L0..L15, sorted numerically).
  LEVELS=($(ls L*.expected 2>/dev/null | sed -E 's/^(L[0-9]+)_.*/\1/' | sort -u -t L -k2 -n))
fi

TOTAL=0; PASS=0; FAIL=0; SKIP=0
for lvl in "${LEVELS[@]}"; do
  for exp in "${lvl}"_*.expected; do
    [ -f "$exp" ] || continue
    TOTAL=$((TOTAL + 1))
    bn="$(basename "$exp" .expected)"
    marker="$(head -1 "$exp")"

    # "!skip <reason>": a known gap (unsupported feature, missing dependency
    # modules). Documented, not counted as a failure.
    if [ "${marker%% *}" = "!skip" ]; then
      echo "SKIP  $bn (${marker#!skip })"; SKIP=$((SKIP + 1)); continue
    fi

    if [ ! -f "$bn.Mod" ]; then echo "SKIP  $bn (no .Mod)"; SKIP=$((SKIP + 1)); continue; fi
    out="$("$OC" "$bn.Mod" $OCFLAGS 2>&1)"

    # "!compile-error": a negative test — a compile error IS the expected
    # (passing) result. Remaining lines are substrings that must all appear in
    # the diagnostics, so the test pins down WHICH error is reported.
    if [ "$marker" = "!compile-error" ]; then
      if echo "$out" | grep -q "  pos [0-9]"; then
        ok=1
        while IFS= read -r sub; do
          [ -z "$sub" ] && continue
          echo "$out" | grep -qF "$sub" || ok=0
        done < <(tail -n +2 "$exp")
        if [ "$ok" = 1 ]; then
          echo "PASS  $bn (rejected as expected)"; PASS=$((PASS + 1))
        else
          echo "FAIL  $bn (wrong diagnostic)"; echo "$out" | grep "  pos [0-9]" | head -1 | sed 's/^/      /'
          FAIL=$((FAIL + 1))
        fi
      else
        echo "FAIL  $bn (expected a compile error, got none)"; FAIL=$((FAIL + 1))
      fi
      continue
    fi

    # Positive test.
    if echo "$out" | grep -q "  pos [0-9]"; then
      echo "FAIL  $bn (compile error)"; echo "$out" | grep "  pos [0-9]" | head -2 | sed 's/^/      /'
      FAIL=$((FAIL + 1)); continue
    fi
    [ -f "$bn.816" ] || { echo "SKIP  $bn (no .816)"; SKIP=$((SKIP + 1)); continue; }
    if ! python3 "$MKFLOPPY" -d . -x "$(echo $KERNEL | tr ' ' ,)" -m "$bn" -n "Library/Settings/Startup.txt=$bn" -L Kernel.img boot.img 2> floppy.err; then
      echo "FAIL  $bn (floppy: $(cat floppy.err))"; FAIL=$((FAIL + 1)); continue
    fi
    # em16's status, not tr's: 142 (128 + SIGALRM) if the alarm stopped it
    full="$(perl -e "alarm $TIMEOUT_SECS; exec @ARGV" "$EM16" -fpga -bootrom boot.rom -disk0 boot.img < /dev/null 2>/dev/null | tr -d '\r'; exit "${PIPESTATUS[0]}")"
    [ $? -eq 142 ] && { echo "FAIL  $bn (timeout, ${TIMEOUT_SECS} s)"; FAIL=$((FAIL + 1)); continue; }
    # Output from Out's "OK", as the kernel starts, up to em16's statistics
    # (the blank line before "Executed"): what the goldens capture.
    actual="$(echo "$full" | awk '/^OK$/{f=1} /^Executed /{exit} f{print}' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')"
    if [ "$actual" = "$(cat "$exp")" ]; then
      echo "PASS  $bn"; PASS=$((PASS + 1))
    else
      echo "FAIL  $bn (output mismatch)"; FAIL=$((FAIL + 1))
    fi
  done
done

echo ""
echo "=== oc816 self-test results ==="
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL  Skip: $SKIP"
[ $FAIL -gt 0 ] && exit 1 || exit 0
