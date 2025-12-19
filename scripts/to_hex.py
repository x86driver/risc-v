#!/usr/bin/env python3
import sys
import struct

def convert(data, outfile):
    # 每 4 byte 一個 little-endian word
    words = [
        struct.unpack("<I", data[i:i+4])[0]
        for i in range(0, len(data), 4)
    ]

    for i, w in enumerate(words):
        print(f"{w:08x}", file=outfile)


if __name__ == "__main__":
    if len(sys.argv) > 1:
        # 從指定檔案讀取
        with open(sys.argv[1], "rb") as f:
            convert(f.read(), sys.stdout)
    else:
        print("Usage:", sys.argv[0], "uart.bin")
