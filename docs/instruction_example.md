    
    logic [31:0] mem [INST_COUNT] = {
        32'h0000_2083, // lw	x1,0(x0) # 0 <_start>
        32'h0040_2103, // lw	x2,4(x0) # 4 <_start+0x4>
        32'h0080_2183, // lw	x3,8(x0) # 8 <_start+0x8>
        32'h00c0_2203, // lw	x4,12(x0) # c <_start+0xc>
        32'h0100_2283, // lw	x5,16(x0) # 10 <_start+0x10>
        32'h0092_8313  // addi  x6,x5,9
    };

    /*
    logic [31:0] mem [INST_COUNT] = {
        32'h0000016f  // jal     x2,0 <_start>
    };
    */
    /*
    logic [31:0] mem [INST_COUNT] = {
        32'h0090_0093, // addi	x1,x0,9
        32'h0010_8093, // addi	x1,x1,1
        32'hffdf_f16f, // jal	x2,4 <incr>
        32'h00f0_0193  // addi	x3,x0,15
    };
    */
    /* hazard 測試 */
    /*
    logic [31:0] mem [INST_COUNT] = {
        32'h00a00093, // addi   x1, x0, 10  # x1 = 0xa
        32'h00500113, // addi   x2, x0, 5   # x2 = 0x5
        32'h002081b3, // add    x3, x1, x2  # x3 = 0xf
        32'h40218233, // sub    x4, x3, x2  # x4 = 0xa
        32'h00408263, // beq    x1, x4, _NEXT
        32'h003202b3, // _NEXT: add    x5, x4, x3  # x5 = 0x19
        32'h00800313, // addi   x6, x0, 8   # x6 = 8
        32'h00432383, // lw     x7, 4(x6)   # x7 = 0x40218233
        32'h00730433  // add    x8, x6, x7  # x8 = 0x4021823b
    };
    */
    /* uart rx with interrupt */
    /*
    logic [31:0] mem [INST_COUNT] = '{
        32'h70000093, // addi x1, x0, 0x700
        32'h01000113, // addi x2, x0, 16
        32'h0020a623, // sw x2, 0xc(x1)
        32'h0000a183, // _RECV: lw x3, 0x0(x1)
        32'hfe000ee3, // beq x0, x0, _RECV
        32'h00400213  // addi x4, x0, 4
    };
    */
    /*
    logic [31:0] mem [INST_COUNT] = {
        32'h0000_2083, // lw	x1,0(x0) # 0 <_start>
        32'h0000_9463, // bnez	x1,c <skip>
        32'h0020_0113, // li	x2,2
        32'h0090_8093, // addi	x1,x1,9
        32'h0030_0193  // li	x3,3
    };
    */
    /*
    logic [31:0] mem [INST_COUNT] = {
        32'h0000_2023, // sw	x0,0(x0) # 0 <_start>
        32'h0000_2083, // lw	x1,0(x0) # 0 <_start>

        32'h0000_2223, // sw	x0,4(x0) # 4 <_start+0x4>
        32'h0040_2103, // lw	x2,4(x0) # 4 <_start+0x4>

        32'h0000_2423, // sw	x0,8(x0) # 8 <_start+0x8>
        32'h0080_2183, // lw	x3,8(x0) # 8 <_start+0x8>

        32'h0000_2623, // sw	x0,12(x0) # c <_start+0xc>
        32'h00c0_2203, // lw	x4,12(x0) # c <_start+0xc>

        32'h0000_2823, // sw	x0,16(x0) # 10 <_start+0x10>
        32'h0100_2283  // lw	x5,16(x0) # 10 <_start+0x10>
    };
    */
    /*
    logic [31:0] mem [INST_COUNT] = {
        32'h00002023, // sw      x0,0(x0)
        32'h00002083  // lw      x1,0(x0)
    };
    */
    /*1+到10*/
    /*
    logic [31:0] mem [INST_COUNT] = {
        32'h0000_0133, // add	x2,x0,x0
        32'h00a0_0093, // li	x1,10
        32'h0011_0133, // add	x2,x2,x1
        32'hfff0_8093, // addi	x1,x1,-1
        32'hfe00_9ce3, // bnez	x1,8 <.L1>
        32'h0020_2223, // sw	x2,4(x0) # 4 <_start+0x4>
        32'h0040_2183  // lw	x3,4(x0) # 4 <_start+0x4>
    };
    */

/*
    logic [31:0] mem [INST_COUNT] = {
        32'h000000b3, // add x1, x0, x0 // value
        32'h00000133, // add x2, x0, x0 // address
        32'h40000193, // addi x3, x0, 0x400 // counter
        32'h71000293, // addi x5, x0, 0x710 // leds base
        32'h00100313, // addi x6, x0, 1 // led indicator
        32'h00112023, // .loop: sw x1, (x2)
        32'h00012203, // lw x4, (x2) // load the value
        32'h00221e63, // bne x4, x2, .error
        32'h0062a023, // sw x6, (x5)
        32'hfff18193, // addi x3, x3, -1 // counter - 1
        32'h00408093, // addi x1, x1, 4 // value + 4
        32'h00410113, // addi x2, x2, 4 // address + 4
        32'hfe0192e3, // bne x3, x0, .loop
        32'h00000063, // .exit: beq x0, x0, .exit
        32'h71000293, // .error: addi x5, x0, 0x710
        32'h00230313, // addi x6, x6, 0x2
        32'h0062a023, // sw x6, (x5)
        32'h00000063  // _error_end: beq x0, x0, ._error_end
    };
*/
/*
    logic [31:0] mem [INST_COUNT] = {
        32'h0000_0133, // add	x2,x0,x0
        32'h00a0_0093, // li	x1,10
        32'h0011_0133, // add	x2,x2,x1
        32'hfff0_8093, // addi	x1,x1,-1
        32'hfe00_9ce3, // bnez	x1,8 <.L1>
        32'h0020_2223, // sw	x2,4(x0) # 4 <_start+0x4>
        32'h0040_2183  // lw	x3,4(x0) # 4 <_start+0x4>
    };
*/

    logic [31:0] mem [INST_COUNT] = {
        32'h0000_2083, // lw	x1,0(x0) # 0 <_start>
        32'h0040_2103, // lw	x2,4(x0) # 4 <_start+0x4>
        32'h0080_2183, // lw	x3,8(x0) # 8 <_start+0x8>
        32'h00c0_2203, // lw	x4,12(x0) # c <_start+0xc>
        32'h0100_2283, // lw	x5,16(x0) # 10 <_start+0x10>
        32'h00928313   // addi    x6,x5,9
    };

/*
    logic [31:0] mem [INST_COUNT] = {
        32'h00a00093, // addi   x1, x0, 10  # x1 = 0xa
        32'h00500113, // addi   x2, x0, 5   # x2 = 0x5
        32'h002081b3, // add    x3, x1, x2  # x3 = 0xf
        32'h40218233, // sub    x4, x3, x2  # x4 = 0xa
        32'h00408263, // beq    x1, x4, _NEXT
        32'h003202b3, // _NEXT: add    x5, x4, x3  # x5 = 0x19
        32'h00800313, // addi   x6, x0, 8   # x6 = 8
        32'h00432383, // lw     x7, 4(x6)   # x7 = 0xcccccccc
        32'h00730433  // add    x8, x6, x7  # x8 = 0xccccccd4
    };
*/

    logic [31:0] mem [INST_COUNT] = '{
        32'h0000_0133, // add	x2,x0,x0
        32'h00a0_0093, // li	x1,10
        32'h0011_0133, // .L1: add	x2,x2,x1
        32'hfff0_8093, // addi	x1,x1,-1
        32'hfe00_9ce3, // bnez	x1,8 <.L1>
        32'h0020_2223, // sw	x2,4(x0) # 4 <_start+0x4>
        32'h0040_2183  // lw	x3,4(x0) # 4 <_start+0x4>
    };

/* 測試 lui 和 auipc */
/*
    logic [31:0] mem [INST_COUNT] = '{
        32'h0000f0b7, // lui x1, 0xf
        32'h00002117, // auipc x2, 0x2
        32'h00000013  // nop
    };
*/
/* 每次加 1, 總計 0x90000 次 */
/*
    logic [31:0] mem [INST_COUNT] = '{
        32'h00000133, // add x2, x0, x0
        32'h000090b7, // lui x1, 0x9
        32'h00110113, // .L1: addi x2, x2, 1
        32'hfff08093, // addi x1, x1, -1
        32'hfe009ce3  // bne x1, x0, .L1
    };
*/
/* leds 輸出 0x41, 存到 0x0, 再讀出來 */
/*
    logic [31:0] mem [INST_COUNT] = '{
        32'h71000093, // addi x1, x0, 0x710
        32'h04100113, // addi x2, x0, 0x41
        32'h0020a023, // sw x2, (x1)
        32'h0000a183, // lw x3, (x1)
        32'h00302023, // sw x3, (x0)
        32'h00002203  // lw x4, (x0)
    };
*/
/* ddr3 讀寫 + 迴圈, 測試正確會讓 leds 輸出 0x1 */
/* 超過 UART_ADDR_OFFSET 會讓 leds 輸出 0x1 + 0x2 = 0x3 */
/*
    logic [31:0] mem [INST_COUNT] = '{
        32'h000000b3, // add x1, x0, x0 // value
        32'h00000133, // add x2, x0, x0 // address
        32'h40000193, // addi x3, x0, 0x400 // counter
        32'h71000293, // addi x5, x0, 0x710 // leds base
        32'h00100313, // addi x6, x0, 1 // led indicator
        32'h00112023, // .loop: sw x1, (x2)
        32'h00012203, // lw x4, (x2) // load the value
        32'h00221e63, // bne x4, x2, .error
        32'h0062a023, // sw x6, (x5)
        32'hfff18193, // addi x3, x3, -1 // counter - 1
        32'h00408093, // addi x1, x1, 4 // value + 4
        32'h00410113, // addi x2, x2, 4 // address + 4
        32'hfe0192e3, // bne x3, x0, .loop
        32'h00000063, // .exit: beq x0, x0, .exit
        32'h71000293, // .error: addi x5, x0, 0x710
        32'h00230313, // addi x6, x6, 0x2
        32'h0062a023, // sw x6, (x5)
        32'h00000063  // _error_end: beq x0, x0, ._error_end
    };
*/
/* ddr3 讀寫測試 */
/*
    logic [31:0] mem [INST_COUNT] = '{
        32'h12300093,
        32'h00102023,
        32'h45600093,
        32'h00102223,
        32'h78900093,
        32'h00102423,
        32'h11100093,
        32'h00102623,
        32'h22200093,
        32'h00102823,
        32'h33300093,
        32'h00102a23,
        32'h00002103,
        32'h00402183,
        32'h00802203,
        32'h00c02283,
        32'h01002303,
        32'h01402383
    };
*/
/* uart rx with interrupt */
/*
    logic [31:0] mem [INST_COUNT] = '{
        32'h40000093, // addi x1, x0, 0x400
        32'h01000113, // addi x2, x0, 16
        32'h0020a623, // sw x2, 0xc(x1)
        32'h0000a183, // _RECV: lw x3, 0x0(x1)
        32'hfe000ee3, // beq x0, x0, _RECV
        32'h00400213  // addi x4, x0, 4
    };
*/
/* 送 A-P 共 16 個字母 */
/*
    logic [31:0] mem [0:INST_COUNT-1] = '{
        32'h40000093, // addi x1, x0, 0x400
        32'h04100113, // addi x2, x0, 'A'
        32'h01000193, // li x3, 16
        32'h0020a223, // _SEND: sw x2, 4(x1)
        32'hfff18193, // addi x3, x3, -1
        32'h00110113, // addi x2, x2, 1
        32'hfe019ae3, // bne x3, x0, _SEND
        32'h0080a203  // lw x4, 8(x1)
    };
*/
/* 送 16 次 tx */
/*
    logic [31:0] mem [0:INST_COUNT-1] = '{
        32'h70000093, // addi x1, x0, 0x700
        32'h05500113, // addi x2, x0, 0x55
        32'h01000193, // li x3, 16
        32'h0020a223, // _SEND: sw x2, 4(x1)
        32'hfff18193, // addi x3, x3, -1
        32'hfe019ce3, // bne x3, x0, _SEND
        32'h0080a203  // lw x4, 8(x1)
    };
*/
/* test uart rx */
/*
    logic [31:0] mem [0:INST_COUNT-1] = '{
        32'h40000093, // addi x1, x0, 0x400
        32'h0000a183, // _RECV: lw x3, 0x0(x1)
        32'hfe000ee3, // beq x0, x0, _RECV
        32'h00400213, // addi x4, x0, 4
        32'h00500293, // addi x5, x0, 5
        32'h00600313, // addi x6, x0, 6
        32'h00700393  // addi x7, x0, 7
    };
*/

/* read uartlite status register, x3 = 0x404 */
/*
    logic [31:0] mem [0:INST_COUNT-1] = '{
        32'h40000093,
        32'h0080a103,
        32'h002081b3
    };
*/
/*
    logic [31:0] mem [0:INST_COUNT-1] = '{
        32'h00002083, // lw x1, 0(x0)
        32'h00108a63, // beq x1, x1, .L1
        32'h00200113, // addi x2, x0, 2
        32'h00300193, // addi x3, x0, 3
        32'h00400213, // addi x4, x0, 4
        32'h00500293, // addi x5, x0, 5
        32'h00600313  // .L1: addi x6, x0, 6
    };
*/
/* 分開測試EX/MEM hazard、MEM/WB hazard 與 load-use hazard */
/*
    logic [31:0] mem [0:INST_COUNT-1] = '{
        32'h00a00093, // addi   x1, x0, 10  # x1 = 0xa
        32'h00500113, // addi   x2, x0, 5   # x2 = 0x5
        32'h002081b3, // add    x3, x1, x2  # x3 = 0xf
        32'h40218233, // sub    x4, x3, x2  # x4 = 0xa
        32'h00408263, // beq    x1, x4, _NEXT
        32'h003202b3, // _NEXT: add    x5, x4, x3  # x5 = 0x19
        32'h00800313, // addi   x6, x0, 8   # x6 = 8
        32'h00432383, // lw     x7, 4(x6)   # x7 = 0xabc
        32'h00730433  // add    x8, x6, x7  # x8 = 0xac4
    };
*/
/* 從 ram lw, 再直接寫入 sw 到 uart, 並且測試 not taken 的 beq */
/*
    logic [31:0] mem [0:INST_COUNT-1] = '{
        32'h40000093, // _start: addi x1, x0, 0x400
        32'h00002103, // lw x2, 0(x0)
        32'h0020a223, // sw x2, 4(x1)
        32'hfe208ae3, // beq x1, x2, _start
        32'h00110113  // addi x2, x2, 1
    };
*/
    /*從1加到10*/
/*
    logic [31:0] mem [0:INST_COUNT-1] = '{
        32'h00000133,
        32'h00a00093,
        32'h00110133,
        32'hfff08093,
        32'hfe009ce3,
        32'h00202223
    };
*/
/* 測試 x2 會不會被寫入 也就是測試 flush 訊號來的時間對不對 */
/*
    logic [31:0] mem [0:INST_COUNT-1] = '{
        32'h00100093, // _start: addi x1, x0, 1
        32'hfe009ee3, // bne x1,	x0, _start
        32'h00200113  // addi x2, x0, 2
    };
*/