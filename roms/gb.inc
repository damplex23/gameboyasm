# Small SM83 mnemonic macros for GNU as. The host assembler emits cartridge
# bytes directly, so the demo needs no C tool, RGBDS, or binary asset pipeline.
.macro gb_nop
    .byte 0x00
.endm
.macro gb_ld_a value
    .byte 0x3e, \value
.endm
.macro gb_ld_b value
    .byte 0x06, \value
.endm
.macro gb_ld_c value
    .byte 0x0e, \value
.endm
.macro gb_ld_bc value
    .byte 0x01
    .word \value
.endm
.macro gb_ld_de value
    .byte 0x11
    .word \value
.endm
.macro gb_ld_hl value
    .byte 0x21
    .word \value
.endm
.macro gb_ld_sp value
    .byte 0x31
    .word \value
.endm
.macro gb_ldh_store address
    .byte 0xe0, (\address)&255
.endm
.macro gb_ldh_load address
    .byte 0xf0, (\address)&255
.endm
.macro gb_store address
    .byte 0xea
    .word \address
.endm
.macro gb_load address
    .byte 0xfa
    .word \address
.endm
.macro gb_jp target
    .byte 0xc3
    .word \target
.endm
.macro gb_jr target
    .byte 0x18, (\target)-.-1
.endm
.macro gb_jr_nz target
    .byte 0x20, (\target)-.-1
.endm
.macro gb_jr_z target
    .byte 0x28, (\target)-.-1
.endm
.macro gb_call target
    .byte 0xcd
    .word \target
.endm
.macro gb_ret
    .byte 0xc9
.endm
.macro tile_row bits
    .byte \bits, \bits
.endm
