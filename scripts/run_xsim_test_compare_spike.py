#!/usr/bin/env python3
"""
Run a RISC-V test ELF on:
  1) Spike (golden)  -> produce a Spike-like trimmed log
  2) XSim (DUT)      -> produce a Spike-like trimmed log + signature dump

Then compare:
  - DUT log vs Spike log (exact text match)
  - DUT signature vs reconstructed Spike signature (if signature region non-empty)

This is similar to run_riscv_test_compare_spike.py but uses Vivado XSim instead of Verilator.
"""

from __future__ import annotations

import argparse
import os
import re
import struct
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Tuple


RISCV_BIN = Path("/opt/riscv/bin")
SPIKE = RISCV_BIN / "spike"
OBJCOPY = RISCV_BIN / "riscv64-unknown-elf-objcopy"


@dataclass(frozen=True)
class ElfInfo:
    entry: int
    tohost: int
    begin_sig: int
    end_sig: int
    load_addr: int


def run_checked(cmd: List[str], *, cwd: Optional[Path] = None, env: Optional[dict] = None) -> subprocess.CompletedProcess:
    return subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        env=env,
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
    for line in readelf_l.splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[0] == "LOAD":
            try:
                return int(parts[2], 16)
            except ValueError:
                continue
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


def elf_to_coe(elf: Path, out_coe: Path) -> Path:
    """Convert ELF to COE format for Vivado Block Memory Generator. Returns path to HEX file."""
    out_coe.parent.mkdir(parents=True, exist_ok=True)
    out_bin = out_coe.with_suffix(".bin")
    out_hex = out_coe.with_suffix(".hex")
    
    # Convert ELF to binary
    run_checked([str(OBJCOPY), "-O", "binary", str(elf), str(out_bin)])
    
    # Read binary and create COE and HEX files
    data = out_bin.read_bytes()
    if len(data) % 4:
        data += b"\x00" * (4 - (len(data) % 4))
    
    # Write COE file
    with out_coe.open("w", encoding="utf-8") as f:
        f.write("memory_initialization_radix=16;\n")
        f.write("memory_initialization_vector=\n")
        words = []
        for i in range(0, len(data), 4):
            w = struct.unpack_from("<I", data, i)[0]
            words.append(f"{w:08x}")
        # Join with commas, last one with semicolon
        for i, w in enumerate(words):
            if i == len(words) - 1:
                f.write(f"{w};\n")
            else:
                f.write(f"{w},\n")
    
    # Write HEX file (for $readmemh in data memory)
    with out_hex.open("w", encoding="utf-8") as f:
        for i in range(0, len(data), 4):
            w = struct.unpack_from("<I", data, i)[0]
            f.write(f"{w:08x}\n")
    
    return out_hex


# Spike commit line regex
_SPIKE_COMMIT_RE = re.compile(
    r"^core\s+\d+:\s+([0-3])\s+(0x[0-9a-fA-F]+)\s+(\(0x[0-9a-fA-F]+\))\s*(.*)$"
)


def _format_log_spike_style(tokens: List[str]) -> str:
    if len(tokens) == 2:
        return f"{tokens[0]} {tokens[1]}   \n"

    if "c784_mstatush" in tokens:
        idx = tokens.index("c784_mstatush")
        if idx + 1 < len(tokens) and tokens[idx + 1].startswith("0x"):
            tokens = tokens[: idx + 1]
        return " ".join(tokens) + "\n"

    if "mem" in tokens:
        if tokens[-1] == "mem":
            return " ".join(tokens) + "\n"
        mem_i = tokens.index("mem")
        if mem_i == len(tokens) - 2:
            tokens = tokens[: mem_i + 1]
            return " ".join(tokens) + "\n"
        if mem_i == len(tokens) - 3:
            return " ".join(tokens) + "\n"

    return " ".join(tokens) + " \n"


def spike_trimmed_log(
    elf: Path, out_log: Path, *, isa: str, max_instructions: int, tohost: int, entry: int
) -> None:
    out_log.parent.mkdir(parents=True, exist_ok=True)
    raw_log = out_log.with_suffix(".raw.log")

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
            pc = m.group(2)
            inst = m.group(3)
            tail = m.group(4).strip()

            try:
                pc_val = int(pc, 16)
            except ValueError:
                continue
            if pc_val < entry:
                continue

            tokens = [pc, inst] + (tail.split() if tail else [])

            if "mem" in tokens:
                mem_i = tokens.index("mem")
                if mem_i == len(tokens) - 2:
                    tokens = tokens[: mem_i + 1]

            if "c784_mstatush" in tokens:
                idx = tokens.index("c784_mstatush")
                if idx + 1 < len(tokens) and tokens[idx + 1].startswith("0x"):
                    tokens = tokens[: idx + 1]

            out_line = _format_log_spike_style(tokens)
            trimmed_lines.append(out_line)

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
    out_sig.parent.mkdir(parents=True, exist_ok=True)
    size = max(0, end_sig - begin_sig)
    mem = bytearray(size)

    if elf_bin is not None and elf_bin.exists():
        bin_data = elf_bin.read_bytes()
        sig_offset = begin_sig - load_addr
        if 0 <= sig_offset < len(bin_data):
            copy_len = min(size, len(bin_data) - sig_offset)
            if copy_len > 0:
                mem[:copy_len] = bin_data[sig_offset : sig_offset + copy_len]

    with log_path.open("r", encoding="utf-8", errors="replace") as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) < 5:
                continue
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
            if opcode != 0x23:
                continue
            funct3 = (inst >> 12) & 0x7
            if funct3 == 0x0:
                nbytes = 1
            elif funct3 == 0x1:
                nbytes = 2
            elif funct3 == 0x2:
                nbytes = 4
            else:
                continue

            base = addr - begin_sig
            if base < 0 or base >= size:
                continue
            for i in range(nbytes):
                off = base + i
                if 0 <= off < size:
                    mem[off] = (data >> (8 * i)) & 0xFF

    with out_sig.open("w", encoding="utf-8") as f:
        for off in range(0, size, 4):
            chunk = mem[off : off + 4]
            if len(chunk) < 4:
                chunk = chunk + b"\x00" * (4 - len(chunk))
            w = int.from_bytes(chunk, byteorder="little", signed=False)
            f.write(f"{w:08x}\n")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--elf", required=True, type=Path, help="Path to riscv-tests ELF")
    ap.add_argument("--outdir", default=Path("build/xsim-tests"), type=Path)
    ap.add_argument("--isa", default="rv32i", help="Spike ISA string (default: rv32i)")
    ap.add_argument("--spike-max-instructions", type=int, default=200000)
    ap.add_argument("--max-cycles", type=int, default=200000)
    ap.add_argument("--vivado-path", default="/home/shane/tools/Xilinx/2025.2/Vivado",
                    help="Path to Vivado installation")
    ap.add_argument("--skip-setup", action="store_true",
                    help="Skip Vivado setup (use existing simulation scripts)")
    args = ap.parse_args()

    elf = args.elf.resolve()
    if not elf.exists():
        print(f"ELF not found: {elf}", file=sys.stderr)
        return 2

    info = elf_info(elf)
    outdir = args.outdir.resolve()
    outdir.mkdir(parents=True, exist_ok=True)

    project_root = Path(__file__).parent.parent.resolve()
    vivado_bin = Path(args.vivado_path) / "bin"
    xsim_script_dir = project_root / "risc-v.sim/sim_1/behav/xsim/xsim"

    # Convert ELF to COE and HEX
    coe_path = outdir / (elf.name + ".coe")
    hex_path = elf_to_coe(elf, coe_path)
    print(f"[INFO] Generated COE: {coe_path}")
    print(f"[INFO] Generated HEX: {hex_path}")

    # Setup Vivado simulation (update COE, regenerate IP, export scripts)
    if not args.skip_setup:
        print("[INFO] Setting up Vivado XSim simulation...")
        setup_cmd = [
            str(vivado_bin / "vivado"),
            "-mode", "batch",
            "-nojournal", "-nolog",
            "-source", str(project_root / "scripts/setup_xsim_test.tcl"),
            "-tclargs", str(coe_path),
        ]
        try:
            result = subprocess.run(
                setup_cmd,
                cwd=str(project_root),
                check=True,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
            )
            print(result.stdout)
        except subprocess.CalledProcessError as e:
            print(f"[ERROR] Vivado setup failed:\n{e.stdout}", file=sys.stderr)
            return 2
    else:
        print("[INFO] Skipping Vivado setup (--skip-setup)")

    # Golden (Spike) log
    spike_log = outdir / (elf.name + ".spike.log")
    print("[INFO] Running Spike...")
    spike_trimmed_log(
        elf,
        spike_log,
        isa=args.isa,
        max_instructions=args.spike_max_instructions,
        tohost=info.tohost,
        entry=info.entry,
    )

    # Run XSim
    dut_log = outdir / (elf.name + ".xsim.log")
    dut_sig = outdir / (elf.name + ".xsim.sig")
    
    xsim_script = xsim_script_dir / "tb_xsim.sh"
    if not xsim_script.exists():
        print(f"[ERROR] XSim script not found: {xsim_script}", file=sys.stderr)
        print("[HINT] Run 'make xsim-export' first or remove --skip-setup", file=sys.stderr)
        return 2

    print("[INFO] Running XSim simulation...")
    
    # Create a custom TCL script for this run
    run_tcl = outdir / (elf.name + ".run.tcl")
    run_tcl.write_text(f"""\
# Auto-generated run script for {elf.name}
set_property verilog_define {{}} [current_fileset -simset]
run -all
quit
""", encoding="utf-8")

    # Set up environment
    env = os.environ.copy()
    env["PATH"] = f"{vivado_bin}:{env.get('PATH', '')}"

    # Run the simulation with plusargs
    xsim_cmd = [
        str(xsim_script),
        "-step", "all",
    ]
    
    # We need to pass plusargs through xsim, not the shell script
    # The shell script will elaborate and then run xsim
    # Let's create a custom cmd.tcl with our plusargs
    xsim_cmd_tcl = xsim_script_dir / "cmd.tcl"
    xsim_cmd_tcl_backup = xsim_script_dir / "cmd.tcl.bak"
    
    # Backup original cmd.tcl
    if xsim_cmd_tcl.exists():
        xsim_cmd_tcl_backup.write_text(xsim_cmd_tcl.read_text())
    
    # Write new cmd.tcl with run -all
    xsim_cmd_tcl.write_text("""\
set curr_wave [current_wave_config]
if { [string length $curr_wave] == 0 } {
  if { [llength [get_objects]] > 0} {
    add_wave /
    set_property needs_save false [current_wave_config]
  }
}
run -all
quit
""", encoding="utf-8")

    try:
        # Modify the simulation script to pass plusargs
        # We need to edit the vlog.prj or pass args to xsim directly
        # For now, let's run the shell script and then run xsim manually
        
        # First, compile and elaborate
        compile_result = subprocess.run(
            ["bash", str(xsim_script), "-step", "compile"],
            cwd=str(xsim_script_dir),
            env=env,
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        
        elaborate_result = subprocess.run(
            ["bash", str(xsim_script), "-step", "elaborate"],
            cwd=str(xsim_script_dir),
            env=env,
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        
        # Run xsim with plusargs
        xsim_run_cmd = [
            "xsim", "tb_xsim",
            "-tclbatch", "cmd.tcl",
            "-testplusarg", f"HEX={hex_path}",
            "-testplusarg", f"LOG={dut_log}",
            "-testplusarg", f"SIG={dut_sig}",
            "-testplusarg", f"TOHOST={info.tohost:08x}",
            "-testplusarg", f"BEGIN_SIG={info.begin_sig:08x}",
            "-testplusarg", f"END_SIG={info.end_sig:08x}",
            "-testplusarg", f"MAX_CYCLES={args.max_cycles}",
        ]
        
        sim_result = subprocess.run(
            xsim_run_cmd,
            cwd=str(xsim_script_dir),
            env=env,
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        print(sim_result.stdout[-2000:] if len(sim_result.stdout) > 2000 else sim_result.stdout)
        
    except subprocess.CalledProcessError as e:
        print(f"[ERROR] XSim simulation failed:\n{e.stdout}", file=sys.stderr)
        return 2
    finally:
        # Restore original cmd.tcl
        if xsim_cmd_tcl_backup.exists():
            xsim_cmd_tcl.write_text(xsim_cmd_tcl_backup.read_text())
            xsim_cmd_tcl_backup.unlink()

    # Compare logs
    if not dut_log.exists():
        print(f"[ERROR] DUT log not found: {dut_log}", file=sys.stderr)
        return 2

    ok, msg = compare_files_exact(spike_log, dut_log)
    print(f"[LOG] compare: {'PASS' if ok else 'FAIL'}")
    if not ok:
        print(msg)

    # Signature compare
    spike_sig = outdir / (elf.name + ".spike.sig")
    bin_path = coe_path.with_suffix(".bin")
    
    if info.begin_sig == info.end_sig:
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
