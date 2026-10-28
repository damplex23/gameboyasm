.include "roms/gb.inc"
.section .text
.org 0x40
    .byte 0xd9                  # RETI: VBlank
.org 0x100
    gb_nop
    gb_jp start
.org 0x134
    .ascii "ASM DEMO"
.org 0x147
    .byte 0,0,0                # ROM-only, 32 KiB, no SRAM
.org 0x14d
    .byte 0xc1                 # header checksum (no boot-logo dependency)
.org 0x150
start:
    .byte 0xf3                  # DI
    gb_ld_sp 0xfffe
    .byte 0xaf                  # XOR A
    gb_ldh_store 0xff40
    gb_ldh_store 0xff42
    gb_ldh_store 0xff43
    gb_ldh_store 0xff0f
    gb_ld_hl tiles
    gb_ld_de 0x8000
    gb_ld_bc tiles_end-tiles
copy_tiles:
    .byte 0x2a,0x12,0x13,0x0b  # LD A,(HL+); LD (DE),A; INC DE; DEC BC
    .byte 0x78,0xb1             # LD A,B; OR C
    gb_jr_nz copy_tiles
    gb_ld_hl 0x9800
    gb_ld_bc 1024
fill_map:
    gb_ld_a 1
    .byte 0x22,0x0b,0x78,0xb1
    gb_jr_nz fill_map
    gb_ld_hl 0x9846
    gb_ld_a 3
    .byte 0x22                  # A
    gb_ld_a 4
    .byte 0x22                  # S
    gb_ld_a 5
    .byte 0x22                  # M
    gb_ld_a 0
    .byte 0x22
    gb_ld_a 6
    .byte 0x22                  # O
    gb_ld_a 7
    .byte 0x22                  # N
    gb_ld_a 8
    .byte 0x22                  # L
    gb_ld_a 9
    .byte 0x22                  # Y
    gb_ld_a 88
    gb_store 0xfe00
    gb_ld_a 88
    gb_store 0xfe01
    gb_ld_a 10
    gb_store 0xfe02
    .byte 0xaf
    gb_store 0xfe03
    gb_ld_a 0xe4
    gb_ldh_store 0xff47
    gb_ldh_store 0xff48
    gb_ld_a 0x93
    gb_ldh_store 0xff40
    gb_ld_hl message
send_message:
    .byte 0x2a,0xb7             # LD A,(HL+); OR A
    gb_jr_z message_done
    gb_ldh_store 0xff01
    gb_ld_a 0x81
    gb_ldh_store 0xff02
serial_wait:
    gb_ldh_load 0xff02
    .byte 0xcb,0x7f             # BIT 7,A
    gb_jr_nz serial_wait
    gb_jr send_message
message_done:
    gb_ld_a 1
    gb_store 0xffff
    .byte 0xaf
    gb_ldh_store 0xff0f
    .byte 0xfb                  # EI
main_loop:
    .byte 0x76,0x00             # HALT; NOP
    gb_ld_a 0x20               # select directions
    gb_ldh_store 0xff00
    gb_ldh_load 0xff00
    .byte 0x47                  # LD B,A
    .byte 0xcb,0x40             # BIT 0,B (right)
    gb_jr_nz no_right
    gb_ld_hl 0xfe01
    .byte 0x34                  # INC (HL)
no_right:
    .byte 0xcb,0x48             # BIT 1,B (left)
    gb_jr_nz no_left
    gb_ld_hl 0xfe01
    .byte 0x35
no_left:
    .byte 0xcb,0x50             # BIT 2,B (up)
    gb_jr_nz no_up
    gb_ld_hl 0xfe00
    .byte 0x35
no_up:
    .byte 0xcb,0x58             # BIT 3,B (down)
    gb_jr_nz no_down
    gb_ld_hl 0xfe00
    .byte 0x34
no_down:
    gb_jr main_loop
message: .asciz "ASM OK\n"
.balign 16
tiles:
    .fill 16,1,0               # 0: white
    .rept 4                    # 1: light floor texture
    .byte 0x80,0,0,0
    .endr
    .fill 16,1,255             # 2: black
    # 3..9: A S M O N L Y
    tile_row 0x38
    tile_row 0x44
    tile_row 0x44
    tile_row 0x7c
    tile_row 0x44
    tile_row 0x44
    tile_row 0x44
    tile_row 0
    tile_row 0x3c
    tile_row 0x40
    tile_row 0x40
    tile_row 0x38
    tile_row 0x04
    tile_row 0x04
    tile_row 0x78
    tile_row 0
    tile_row 0x44
    tile_row 0x6c
    tile_row 0x54
    tile_row 0x44
    tile_row 0x44
    tile_row 0x44
    tile_row 0x44
    tile_row 0
    tile_row 0x38
    tile_row 0x44
    tile_row 0x44
    tile_row 0x44
    tile_row 0x44
    tile_row 0x44
    tile_row 0x38
    tile_row 0
    tile_row 0x44
    tile_row 0x64
    tile_row 0x54
    tile_row 0x4c
    tile_row 0x44
    tile_row 0x44
    tile_row 0x44
    tile_row 0
    tile_row 0x40
    tile_row 0x40
    tile_row 0x40
    tile_row 0x40
    tile_row 0x40
    tile_row 0x40
    tile_row 0x7c
    tile_row 0
    tile_row 0x44
    tile_row 0x44
    tile_row 0x28
    tile_row 0x10
    tile_row 0x10
    tile_row 0x10
    tile_row 0x10
    tile_row 0
    # 10: transparent smiling sprite
    tile_row 0x3c
    tile_row 0x42
    tile_row 0xa5
    tile_row 0x81
    tile_row 0xa5
    tile_row 0x99
    tile_row 0x42
    tile_row 0x3c
tiles_end:
.org 32768
