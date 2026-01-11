#!/usr/bin/env python3
"""
Run a suite of riscv-tests ELFs from a directory using the XSim comparator
(`scripts/run_xsim_test_compare_spike.py`).

Default:
  - directory: /opt/riscv/target/share/riscv-tests/isa
  - pattern:   rv32ui-p-*
  - excludes:  *.dump

Outputs:
  - per-test artifacts in --outdir (coe/hex, spike log/sig, xsim log/sig)
  - summary.txt with PASS/FAIL list
  - exits 0 if all selected tests PASS, else 1

Performance strategy:
  - default: setup-mode=full for every test (updates COE + regenerates IP + exports scripts)
    This is slower but avoids stateful side-effects between tests.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import List


DEFAULT_DIR = Path("/opt/riscv/target/share/riscv-tests/isa")


@dataclass(frozen=True)
class TestResult:
    name: str
    elf: Path
    ok: bool
    seconds: float


def run_one(
    elf: Path,
    outdir: Path,
    *,
    isa: str,
    spike_max_instructions: int,
    max_cycles: int,
    vivado_path: str,
    setup_mode: str,
    verbose: bool,
) -> TestResult:
    t0 = time.time()
    cmd = [
        "python3",
        "scripts/run_xsim_test_compare_spike.py",
        "--elf",
        str(elf),
        "--outdir",
        str(outdir),
        "--isa",
        isa,
        "--spike-max-instructions",
        str(spike_max_instructions),
        "--max-cycles",
        str(max_cycles),
        "--vivado-path",
        vivado_path,
        "--setup-mode",
        setup_mode,
    ]

    runner_out = outdir / f"{elf.name}.runner.txt"
    proc = subprocess.run(
        cmd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    runner_out.write_text(proc.stdout, encoding="utf-8", errors="replace")

    if verbose:
        sys.stdout.write(proc.stdout)
        sys.stdout.flush()

    t1 = time.time()
    return TestResult(name=elf.name, elf=elf, ok=(proc.returncode == 0), seconds=(t1 - t0))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", dest="dir_", type=Path, default=DEFAULT_DIR)
    ap.add_argument("--pattern", default="rv32ui-p-*", help="Glob pattern (default: rv32ui-p-*)")
    ap.add_argument("--outdir", type=Path, default=Path("build/xsim-tests"))
    ap.add_argument("--isa", default="rv32i")
    ap.add_argument("--spike-max-instructions", type=int, default=200000)
    ap.add_argument("--max-cycles", type=int, default=200000)
    ap.add_argument("--vivado-path", default=str(Path.home() / "tools/Xilinx/2025.2/Vivado"))
    ap.add_argument("--fail-fast", action="store_true")
    ap.add_argument("--limit", type=int, default=0, help="Only run first N tests (0 = no limit)")
    ap.add_argument("--verbose", action="store_true", help="Print full per-test runner output to stdout")
    ap.add_argument(
        "--setup-mode",
        choices=["full", "coe-only"],
        default="full",
        help="How to setup XSim for every test (default: full).",
    )
    args = ap.parse_args()

    tests_dir = args.dir_.resolve()
    if not tests_dir.is_dir():
        print(f"Not a directory: {tests_dir}", file=sys.stderr)
        return 2

    outdir = args.outdir.resolve()
    outdir.mkdir(parents=True, exist_ok=True)

    # Select tests
    elfs = sorted(tests_dir.glob(args.pattern))
    elfs = [p for p in elfs if p.is_file() and p.suffix != ".dump"]
    if args.limit and args.limit > 0:
        elfs = elfs[: args.limit]

    if not elfs:
        print(f"No tests matched: dir={tests_dir} pattern={args.pattern}", file=sys.stderr)
        return 2

    print(f"[xsim-suite] dir={tests_dir} pattern={args.pattern} count={len(elfs)} outdir={outdir}")

    results: List[TestResult] = []
    passed = 0
    failed = 0

    for i, elf in enumerate(elfs, start=1):
        mode = args.setup_mode
        print(f"[{i}/{len(elfs)}] {elf.name} (setup={mode}) ...", end="", flush=True)
        r = run_one(
            elf,
            outdir,
            isa=args.isa,
            spike_max_instructions=args.spike_max_instructions,
            max_cycles=args.max_cycles,
            vivado_path=args.vivado_path,
            setup_mode=mode,
            verbose=args.verbose,
        )
        results.append(r)
        if r.ok:
            passed += 1
            print(f" PASS ({r.seconds:.2f}s)")
        else:
            failed += 1
            print(f" FAIL ({r.seconds:.2f}s)  (see {outdir}/{elf.name}.runner.txt)")
            if args.fail_fast:
                break

    summary_path = outdir / "summary.txt"
    with summary_path.open("w", encoding="utf-8") as f:
        f.write(f"dir={tests_dir}\npattern={args.pattern}\ncount={len(results)}\n")
        f.write(f"PASS={passed}\nFAIL={failed}\n\n")
        for r in results:
            f.write(f"{'PASS' if r.ok else 'FAIL'} {r.name} {r.seconds:.2f}s\n")

    print(f"[xsim-suite] PASS={passed} FAIL={failed} summary={summary_path}")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())

