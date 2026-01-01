/* Minimal linker script for Spike/riscv-tests style bare-metal ELFs.
 *
 * Goals:
 * - Text at 0x8000_0000
 * - .tohost at 0x8000_1000
 * - Optional signature region at 0x8000_2000
 * - Do NOT map ELF file headers into target memory (avoid PT_LOAD starting at 0x7fff_f000)
 */

OUTPUT_ARCH("riscv")
ENTRY(_start)

PHDRS
{
  text PT_LOAD FLAGS(5); /* R + X */
  data PT_LOAD FLAGS(6); /* R + W */
}

SECTIONS
{
  /* Code */
  . = 0x80000000;
  .text : ALIGN(4)
  {
    *(.text.init)
    *(.text .text.*)
  } :text

  /* tohost/fromhost (8-byte aligned, riscv-tests convention) */
  . = 0x80001000;
  .tohost : ALIGN(64)
  {
    *(.tohost)
  } :data

  /* Signature region (may be empty) */
  . = 0x80002000;
  .signature : ALIGN(4)
  {
    *(.signature)
  } :data

  /* Drop everything else */
  /DISCARD/ : { *(*); }
}

