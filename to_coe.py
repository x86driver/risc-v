#!/usr/bin/env python3
import sys

def convert(infile, outfile):
    # 開頭兩行
    print("memory_initialization_radix=16;", file=outfile)
    print("memory_initialization_vector=", file=outfile)

    for line in infile:
        line = line.strip()
        # 略過空行和 @ 開頭的行
        if not line or line.startswith('@'):
            continue
        print(line, file=outfile)

    # 結尾
    print(";", file=outfile)


if __name__ == "__main__":
    if len(sys.argv) > 1:
        # 從指定檔案讀取
        with open(sys.argv[1], "r") as f:
            convert(f, sys.stdout)
    else:
        # 從 stdin 讀取
        convert(sys.stdin, sys.stdout)
