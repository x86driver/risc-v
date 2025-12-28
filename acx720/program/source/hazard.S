  _start:
          addi   x1, x0, 10    # x1 = 0xa
          addi   x2, x0, 5     # x2 = 0x5
          add    x3, x1, x2    # x3 = 0xf
          sub    x4, x3, x2    # x4 = 0xa
          beq    x1, x4, _NEXT
  _NEXT:
          add    x5, x4, x3    # x5 = 0x19
          addi   x6, x0, 8     # x6 = 8
          lw     x7, 4(x6)     # x7 = 0x40218233
          add    x8, x6, x7    # x8 = 0x4021823b
