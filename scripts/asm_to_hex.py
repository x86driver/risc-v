#!/usr/bin/env python3
"""
Convert a RISC-V assembly file (main.S) into a hex file with per-line comments.

Pipeline:
- riscv64-elf-gcc -march=rv32i -mabi=ilp32 -g -c to compile into an object
- riscv64-elf-objdump -d -M numeric to disassemble with numeric registers
- Parse bytes (little-endian) into 32-bit words and append comments

Output format example:
00928313  // addi x6,x5,9

If the number of parsed source instructions matches the number of disassembled
instructions, comments will use the original source lines. Otherwise, comments
fall back to the disassembly text.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def run_cmd(cmd: list[str]) -> str:
    try:
        completed = subprocess.run(
            cmd,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        return completed.stdout
    except FileNotFoundError:
        print(f"error: command not found: {cmd[0]}", file=sys.stderr)
        sys.exit(127)
    except subprocess.CalledProcessError as e:
        sys.stderr.write(e.stderr)
        print(f"error: command failed: {' '.join(cmd)}", file=sys.stderr)
        sys.exit(e.returncode)


def parse_disassembly(text: str) -> tuple[list[str], list[str]]:
    """Return (words, asm_texts) from objdump output.

    words: list of 8-hex-digit strings (little-endian bytes reversed)
    asm_texts: corresponding disassembly strings
    """
    words: list[str] = []
    asms: list[str] = []

    # Supported line formats:
    # 1) bytes grouped:   0: 13 83 92 00  addi x6,x5,9
    # 2) word compact:    0:   00928313                addi    x6,x5,9
    bytes_re = re.compile(r"^\s*([0-9a-fA-F]+):\s+((?:[0-9a-fA-F]{2}\s+)+)\s+(.+?)\s*$")
    word_re = re.compile(r"^\s*([0-9a-fA-F]+):\s+([0-9a-fA-F]{8})\s+\s*(.+?)\s*$")
    for line in text.splitlines():
        m1 = bytes_re.match(line)
        m2 = word_re.match(line) if not m1 else None
        if m1:
            bytes_str = m1.group(2).strip()
            asm = m1.group(3).strip()
            byte_tokens = bytes_str.split()
            # Expect 4 bytes for rv32i
            if len(byte_tokens) != 4:
                continue
            word = ''.join(reversed(byte_tokens)).lower()
            words.append(word)
            asms.append(asm)
        elif m2:
            word = m2.group(2).lower()
            asm = m2.group(3).strip()
            words.append(word)
            asms.append(asm)
    return words, asms


def parse_source_instructions(src_path: Path) -> list[str]:
    """Extract instruction lines from the source file and include labels in front.

    Behavior:
    - Collects instructions; prefixes the immediate preceding label(s) to the first following instruction.
    - Skips directives (lines starting with '.') and full-line comments.
    - Skips blank lines.
    - Drops inline '#' comments.
    - Section handling: if explicit sections exist, only collect while in .text; if not, default to enabled.
    """
    instrs_with_labels: list[str] = []
    in_text = True  # default allow, will be refined if explicit sections appear
    saw_explicit_section = False
    pending_labels: list[str] = []
    in_block_comment = False

    with src_path.open('r', encoding='utf-8') as f:
        for raw in f:
            line = raw.rstrip('\n')
            s = line
            # Handle C-style block comments spanning lines
            while True:
                if in_block_comment:
                    end = s.find('*/')
                    if end == -1:
                        s = ''
                        break
                    else:
                        s = s[end + 2:]
                        in_block_comment = False
                        continue
                start = s.find('/*')
                if start != -1:
                    end = s.find('*/', start + 2)
                    if end != -1:
                        s = s[:start] + s[end + 2:]
                        continue
                    else:
                        s = s[:start]
                        in_block_comment = True
                        break
                break

            if not s:
                continue
            # Remove line comments //, then #, then ; and % (treated as comment markers)
            if '//' in s:
                s = s.split('//', 1)[0]
            s = s.split('#', 1)[0]
            for cm in (';', '%'):
                idx = s.find(cm)
                if idx != -1:
                    s = s[:idx]
            stripped = s.strip()
            if not stripped:
                continue
            if stripped.startswith('.section'):
                saw_explicit_section = True
                in_text = ('.text' in stripped)
                pending_labels.clear()
                continue
            if stripped == '.text':
                saw_explicit_section = True
                in_text = True
                pending_labels.clear()
                continue
            if saw_explicit_section and not in_text:
                # Ignore content outside .text when sections are explicitly used
                continue
            # Drop inline '#' comments
            code = stripped
            if not code:
                continue
            if code.endswith(':'):
                pending_labels.append(code)
                continue
            if code.startswith('.'):
                # directive
                continue
            if pending_labels:
                annotated = ' '.join(pending_labels + [code])
                pending_labels.clear()
            else:
                annotated = code
            instrs_with_labels.append(annotated)
    return instrs_with_labels


def main() -> None:
    parser = argparse.ArgumentParser(description="Assemble RISC-V .S into hex with comments")
    parser.add_argument("--input", required=True, help="Input assembly .S file")
    parser.add_argument("--output", required=True, help="Output hex file path")
    args = parser.parse_args()

    src = Path(args.input).resolve()
    out = Path(args.output).resolve()

    if not src.exists():
        print(f"error: input not found: {src}", file=sys.stderr)
        sys.exit(2)

    # Ensure required tools are present
    for tool in ("riscv64-elf-gcc", "riscv64-elf-objdump"):
        if shutil.which(tool) is None:
            print(f"error: required tool not found in PATH: {tool}", file=sys.stderr)
            sys.exit(127)

    with tempfile.TemporaryDirectory() as td:
        obj = Path(td) / "a.o"
        # Compile
        gcc_cmd = [
            "riscv64-elf-gcc",
            "-nostdlib",
            "-Wl,-Ttext=0",
            "-Wl,--no-relax",
            "-march=rv32i_zicsr",
            "-mabi=ilp32",
            "-g",
            "-o",
            str(obj),
            str(src),
        ]
        run_cmd(gcc_cmd)

        # Disassemble
        objdump_cmd = [
            "riscv64-elf-objdump",
            "-d",
            "-M",
            "numeric",
            str(obj),
        ]
        dis = run_cmd(objdump_cmd)

        words, disasms = parse_disassembly(dis)
        if not words:
            print("error: no instructions found in disassembly", file=sys.stderr)
            sys.exit(1)

        src_instrs = parse_source_instructions(src)

        if len(src_instrs) == len(words):
            comments = src_instrs
        else:
            comments = disasms

        out.parent.mkdir(parents=True, exist_ok=True)
        with out.open('w', encoding='utf-8') as f:
            for w, c in zip(words, comments):
                f.write(f"{w}  // {c}\n")

        print(f"wrote {len(words)} instructions to: {out}")


if __name__ == "__main__":
    main()


