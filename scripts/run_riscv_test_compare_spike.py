#!/usr/bin/env python3
"""
Run a RISC-V test ELF on:
  1) Spike (golden)  -> produce a Spike-like trimmed log (log-spike style)
  2) Verilator (DUT) -> produce a Spike-like trimmed log + signature dump

Then compare:
  - DUT log vs Spike log (exact text match)
  - DUT signature vs reconstructed Spike signature (if signature region non-empty)

Notes:
  - This repo's Verilator TB (`sim/tb_verilator.sv`) stops on first non-zero write to tohost.
  - Spike may keep executing the write_tohost loop; we trim its log at the same condition.
"""

from __future__ import annotations

import argparse
import re
import struct
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple


RISCV_BIN = Path("/opt/riscv/bin")
SPIKE = RISCV_BIN / "spike"
OBJDUMP = RISCV_BIN / "riscv64-unknown-elf-objdump"
OBJCOPY = RISCV_BIN / "riscv64-unknown-elf-objcopy"


@dataclass(frozen=True)
class ElfInfo:
    entry: int
    tohost: int
    begin_sig: int
    end_sig: int
    load_addr: int  # First LOAD segment virtual address (usually 0x80000000 for riscv-tests)


def run_checked(cmd: List[str], *, cwd: Optional[Path] = None) -> subprocess.CompletedProcess:
    return subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )


def parse_readelf_entry(readelf_h: str) -> int:
    m = re.search(r"Entry point address:\s+0x([0-9a-fA-F]+)", readelf_h)
    if not m:
        raise RuntimeError("Failed to parse ELF entry from `readelf -h` output")
    return int(m.group(1), 16)


def parse_readelf_symbols(readelf_s: str) -> Dict[str, int]:
    out: Dict[str, int] = {}
    for line in readelf_s.splitlines():
        # Example:
        #  55: 80001000     8 NOTYPE  GLOBAL DEFAULT    2 tohost
        parts = line.split()
        if len(parts) < 8:
            continue
        name = parts[-1]
        if name in ("tohost", "begin_signature", "end_signature"):
            try:
                addr = int(parts[1], 16)
            except ValueError:
                continue
            out[name] = addr
    return out


def parse_readelf_load_addr(readelf_l: str) -> int:
    """Parse the first LOAD segment's virtual address from `readelf -l` output."""
    # Example line:
    #   LOAD           0x000000 0x80000000 0x80000000 0x02010 0x02010 RWE 0x1000
    for line in readelf_l.splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[0] == "LOAD":
            try:
                return int(parts[2], 16)
            except ValueError:
                continue
    # Default for riscv-tests
    return 0x80000000


def elf_info(elf: Path) -> ElfInfo:
    h = run_checked(["readelf", "-h", str(elf)]).stdout
    s = run_checked(["readelf", "-s", str(elf)]).stdout
    l = run_checked(["readelf", "-l", str(elf)]).stdout
    entry = parse_readelf_entry(h)
    syms = parse_readelf_symbols(s)
    load_addr = parse_readelf_load_addr(l)
    if "tohost" not in syms:
        raise RuntimeError("ELF missing `tohost` symbol (required for riscv-tests)")
    begin_sig = syms.get("begin_signature", 0)
    end_sig = syms.get("end_signature", 0)
    return ElfInfo(entry=entry, tohost=syms["tohost"], begin_sig=begin_sig, end_sig=end_sig, load_addr=load_addr)


def objcopy_to_hex(elf: Path, out_hex: Path) -> Path:
    """Convert ELF to hex format for Verilog $readmemh. Returns path to the binary file."""
    out_hex.parent.mkdir(parents=True, exist_ok=True)
    out_bin = out_hex.with_suffix(".bin")
    run_checked([str(OBJCOPY), "-O", "binary", str(elf), str(out_bin)])
    data = out_bin.read_bytes()
    if len(data) % 4:
        data += b"\x00" * (4 - (len(data) % 4))
    with out_hex.open("w", encoding="utf-8") as f:
        for i in range(0, len(data), 4):
            w = struct.unpack_from("<I", data, i)[0]
            f.write(f"{w:08x}\n")
    # Keep the binary file for signature reconstruction
    return out_bin


def objdump_to_dump(elf: Path, out_dump: Path) -> None:
    """
    Produce a disassembly dump for debugging (always deterministic for a given ELF).
    """
    out_dump.parent.mkdir(parents=True, exist_ok=True)
    # Get list of sections in the ELF file
    sections_output = run_checked([str(OBJDUMP), "-h", str(elf)]).stdout
    sections = []
    for line in sections_output.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0].isdigit():
            section_name = parts[1]
            # Include .text.init, .text, and .data sections if they exist
            if section_name in (".text.init", ".text", ".data"):
                sections.append(section_name)

    # Build objdump command with available sections
    cmd = [str(OBJDUMP), "-d", "-M", "numeric", str(elf)]
    if sections:
        # Add -j for each section
        for sec in sections:
            cmd.extend(["-j", sec])
    else:
        # If no matching sections found, just disassemble all (fallback)
        cmd.append("-d")

    dump_txt = run_checked(cmd).stdout
    out_dump.write_text(dump_txt, encoding="utf-8", errors="replace")


# Spike commit lines include current privilege as a single digit (0=U,1=S,3=M):
#   core   0: 3 0x80000000 (0x0500006f) ...
_SPIKE_COMMIT_RE = re.compile(
    r"^core\s+\d+:\s+([0-3])\s+(0x[0-9a-fA-F]+)\s+(\(0x[0-9a-fA-F]+\))\s*(.*)$"
)


def _format_log_spike_style(tokens: List[str]) -> str:
    """
    Convert parsed tokens into the repo's `log-spike.txt` style:
      - no-side-effect: "PC (INST)   \\n" (3 spaces)
      - reg/csr write: trailing space before \\n
      - load: ends with 'mem' and NO trailing space
      - store: ends with data and NO trailing space
      - mret: ends with 'c784_mstatush' (no value) and NO trailing space
    """
    if len(tokens) == 2:
        return f"{tokens[0]} {tokens[1]}   \n"

    # mret special (log-spike.txt drops mstatush value)
    if "c784_mstatush" in tokens:
        # If there's a value after mstatush, drop it.
        idx = tokens.index("c784_mstatush")
        if idx + 1 < len(tokens) and tokens[idx + 1].startswith("0x"):
            tokens = tokens[: idx + 1]
        return " ".join(tokens) + "\n"

    # load: "... xN 0xVAL mem 0xADDR" -> drop addr
    if "mem" in tokens:
        # If already trimmed, load ends with 'mem' (no trailing space)
        if tokens[-1] == "mem":
            return " ".join(tokens) + "\n"
        mem_i = tokens.index("mem")
        # load pattern has one token after mem (the address)
        if mem_i == len(tokens) - 2:
            tokens = tokens[: mem_i + 1]
            return " ".join(tokens) + "\n"
        # store pattern has two tokens after mem (addr + data)
        if mem_i == len(tokens) - 3:
            return " ".join(tokens) + "\n"

    # reg/csr write lines: keep trailing space
    return " ".join(tokens) + " \n"


def spike_trimmed_log(
    elf: Path, out_log: Path, *, isa: str, max_instructions: int, tohost: int, entry: int
) -> None:
    out_log.parent.mkdir(parents=True, exist_ok=True)
    raw_log = out_log.with_suffix(".raw.log")

    # Produce a raw Spike log (can be large); we will trim while converting.
    # Use --priv=m to match DUT behavior (M-mode only, no S-mode).
    # This ensures mstatus.FS is hardwired to 0 when F extension is not present.
    run_checked(
        [
            str(SPIKE),
            f"--isa={isa}",
            "--priv=m",
            "--log-commits",
            "-l",
            f"--log={raw_log}",
            f"--instructions={max_instructions}",
            str(elf),
        ]
    )

    trimmed_lines: List[str] = []
    tohost_hit = False

    with raw_log.open("r", encoding="utf-8", errors="replace") as f:
        for line in f:
            m = _SPIKE_COMMIT_RE.match(line.rstrip("\n"))
            if not m:
                continue
            # priv = m.group(1)  # unused (we want log-spike style without this field)
            pc = m.group(2)
            inst = m.group(3)
            tail = m.group(4).strip()

            # Skip Spike boot ROM instructions (PC < entry point).
            # Spike starts at 0x1000 boot ROM, then jumps to program entry (e.g. 0x80000000).
            # Our RTL starts directly at entry, so we skip the boot ROM portion of the log.
            try:
                pc_val = int(pc, 16)
            except ValueError:
                continue
            if pc_val < entry:
                continue

            tokens = [pc, inst] + (tail.split() if tail else [])

            # Drop load address if present (keep store addr+data).
            if "mem" in tokens:
                mem_i = tokens.index("mem")
                if mem_i == len(tokens) - 2:
                    tokens = tokens[: mem_i + 1]

            # Match log-spike quirk: mret drops mstatush value.
            if "c784_mstatush" in tokens:
                idx = tokens.index("c784_mstatush")
                if idx + 1 < len(tokens) and tokens[idx + 1].startswith("0x"):
                    tokens = tokens[: idx + 1]

            # Strip tcontrol CSR (Sdtrig extension) — DUT doesn't implement it,
            # but Spike logs it on mret by default.
            if "c1957_tcontrol" in tokens:
                idx = tokens.index("c1957_tcontrol")
                end = idx + 2 if (idx + 1 < len(tokens) and tokens[idx + 1].startswith("0x")) else idx + 1
                tokens = tokens[:idx] + tokens[end:]

            out_line = _format_log_spike_style(tokens)
            trimmed_lines.append(out_line)

            # Stop trimming when we see a non-zero store to tohost.
            if len(tokens) >= 5 and tokens[2] == "mem":
                try:
                    addr = int(tokens[3], 16)
                    data = int(tokens[4], 16)
                except ValueError:
                    continue
                if addr == tohost and data != 0:
                    tohost_hit = True
                    break

    out_log.write_text("".join(trimmed_lines), encoding="utf-8")
    raw_log.unlink(missing_ok=True)

    if not tohost_hit:
        print(f"[WARN] Spike log did not reach tohost within {max_instructions} instructions", file=sys.stderr)


def compare_files_exact(a: Path, b: Path) -> Tuple[bool, str]:
    a_lines = a.read_text(encoding="utf-8", errors="replace").splitlines(keepends=True)
    b_lines = b.read_text(encoding="utf-8", errors="replace").splitlines(keepends=True)
    n = min(len(a_lines), len(b_lines))
    for i in range(n):
        if a_lines[i] != b_lines[i]:
            return False, f"Line {i+1} differs:\n- spike: {a_lines[i]!r}\n-  dut:  {b_lines[i]!r}"
    if len(a_lines) != len(b_lines):
        return False, f"Line count differs: spike={len(a_lines)} dut={len(b_lines)}"
    return True, "OK"


def reconstruct_signature_from_log(
    log_path: Path,
    begin_sig: int,
    end_sig: int,
    out_sig: Path,
    elf_bin: Optional[Path] = None,
    load_addr: int = 0x80000000,
) -> None:
    """
    Build a signature dump (word-per-line, little-endian) by:
    1. Initializing from ELF binary content (if provided), not all zeros
    2. Replaying stores from log that target [begin_sig, end_sig)

    This ensures the reconstructed signature matches what the DUT reads from memory,
    including initial .data section values.
    """
    out_sig.parent.mkdir(parents=True, exist_ok=True)
    size = max(0, end_sig - begin_sig)
    mem = bytearray(size)

    # Initialize from ELF binary content (not all zeros)
    if elf_bin is not None and elf_bin.exists():
        bin_data = elf_bin.read_bytes()
        sig_offset = begin_sig - load_addr  # signature region offset in binary
        if 0 <= sig_offset < len(bin_data):
            copy_len = min(size, len(bin_data) - sig_offset)
            if copy_len > 0:
                mem[:copy_len] = bin_data[sig_offset : sig_offset + copy_len]

    with log_path.open("r", encoding="utf-8", errors="replace") as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) < 5:
                continue
            # Store line format:
            #   0xPC (0xINST) mem 0xADDR 0xDATA
            if parts[2] != "mem":
                continue
            inst_s = parts[1]
            if not (inst_s.startswith("(") and inst_s.endswith(")")):
                continue
            try:
                inst = int(inst_s[1:-1], 16)
                addr = int(parts[3], 16)
                data = int(parts[4], 16)
            except ValueError:
                continue

            opcode = inst & 0x7F
            if opcode != 0x23:  # STORE
                continue
            funct3 = (inst >> 12) & 0x7
            if funct3 == 0x0:
                nbytes = 1  # sb
            elif funct3 == 0x1:
                nbytes = 2  # sh
            elif funct3 == 0x2:
                nbytes = 4  # sw
            else:
                continue

            base = addr - begin_sig
            if base < 0 or base >= size:
                continue
            for i in range(nbytes):
                off = base + i
                if 0 <= off < size:
                    mem[off] = (data >> (8 * i)) & 0xFF

    # Dump as 32-bit words (little-endian), one per line, like `$readmemh` style.
    with out_sig.open("w", encoding="utf-8") as f:
        for off in range(0, size, 4):
            chunk = mem[off : off + 4]
            if len(chunk) < 4:
                chunk = chunk + b"\x00" * (4 - len(chunk))
            w = int.from_bytes(chunk, byteorder="little", signed=False)
            f.write(f"{w:08x}\n")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--elf", required=True, type=Path, help="Path to riscv-tests ELF (e.g. rv32ui-p-add)")
    ap.add_argument("--outdir", default=Path("build/riscv-tests"), type=Path)
    ap.add_argument("--isa", default="rv64i", help="Spike ISA string (default: rv64i)")
    ap.add_argument("--spike-max-instructions", type=int, default=200000)
    ap.add_argument("--max-cycles", type=int, default=200000)
    ap.add_argument("--build-verilator", action="store_true", help="Rebuild Verilator sim binary before running")
    args = ap.parse_args()

    elf = args.elf.resolve()
    if not elf.exists():
        print(f"ELF not found: {elf}", file=sys.stderr)
        return 2

    info = elf_info(elf)
    outdir = args.outdir.resolve()
    outdir.mkdir(parents=True, exist_ok=True)

    # Always keep a disassembly around for debugging (overwrite to avoid stale dumps).
    dump_path = outdir / (elf.name + ".dump")
    objdump_to_dump(elf, dump_path)

    hex_path = outdir / (elf.name + ".hex")
    bin_path = objcopy_to_hex(elf, hex_path)

    spike_log = outdir / (elf.name + ".spike.log")
    dut_log = outdir / (elf.name + ".dut.log")
    dut_sig = outdir / (elf.name + ".dut.sig")

    if args.build_verilator:
        # Build the SV TB + RTL into obj_dir/simv_verilator
        run_checked(
            [
                "verilator",
                "--binary",
                "--timing",
                "-Wall",
                "-Wno-fatal",
                "-DIVERILOG",
                f"-I{Path.cwd() / 'rtl'}",
                "--top-module",
                "tb_verilator",
                str(Path.cwd() / "sim" / "tb_verilator.sv"),
                "-o",
                "simv_verilator",
            ],
            cwd=Path.cwd(),
        )

    sim_bin = Path.cwd() / "obj_dir" / "simv_verilator"
    if not sim_bin.exists():
        print("Missing Verilator binary: obj_dir/simv_verilator (run with --build-verilator)", file=sys.stderr)
        return 2

    # Golden (Spike) log (trimmed to first tohost write, skipping boot ROM)
    spike_trimmed_log(
        elf,
        spike_log,
        isa=args.isa,
        max_instructions=args.spike_max_instructions,
        tohost=info.tohost,
        entry=info.entry,
    )

    # DUT run (stops on first tohost write by design)
    subprocess.run(
        [
            str(sim_bin),
            f"+HEX={hex_path}",
            f"+ENTRY={info.entry:08x}",
            f"+TOHOST={info.tohost:08x}",
            f"+BEGIN_SIG={info.begin_sig:08x}",
            f"+END_SIG={info.end_sig:08x}",
            f"+LOG={dut_log}",
            f"+SIG={dut_sig}",
            f"+MAX_CYCLES={args.max_cycles}",
        ],
        check=True,
    )

    ok, msg = compare_files_exact(spike_log, dut_log)
    print(f"[LOG] compare: {'PASS' if ok else 'FAIL'}")
    if not ok:
        print(msg)

    # Signature compare: reconstruct Spike signature from the trimmed log, compare with DUT dump.
    spike_sig = outdir / (elf.name + ".spike.sig")
    if info.begin_sig == info.end_sig:
        # Both should be empty files
        spike_sig.write_text("", encoding="utf-8")
        if dut_sig.exists() and dut_sig.stat().st_size == 0:
            print("[SIG] empty region: PASS")
        else:
            print("[SIG] empty region: FAIL (DUT signature file missing or non-empty)")
            ok = False
    else:
        reconstruct_signature_from_log(
            spike_log,
            info.begin_sig,
            info.end_sig,
            spike_sig,
            elf_bin=bin_path,
            load_addr=info.load_addr,
        )
        if not dut_sig.exists():
            print(f"[SIG] compare: FAIL (DUT signature file missing: {dut_sig})")
            ok = False
        else:
            ok_sig, msg_sig = compare_files_exact(spike_sig, dut_sig)
            print(f"[SIG] compare: {'PASS' if ok_sig else 'FAIL'}")
            if not ok_sig:
                print(msg_sig)
                ok = False

    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())

