.intel_syntax noprefix
.include "src/state.s"
.include "src/cpu.s"
.include "src/memory.s"
.include "src/ppu.s"
.include "src/linux.s"

.macro check8 address, value
    cmp byte ptr [\address], \value
    jne test_fail
.endm
.macro check16 address, value
    cmp word ptr [\address], \value
    jne test_fail
.endm
.macro check32 address, value
    cmp dword ptr [\address], \value
    jne test_fail
.endm
.macro case label
    lea rax, [\label]
    mov qword ptr [test_name], rax
    call fixture
.endm
.section .bss
test_name: .skip 8
expected_value: .skip 4
expected_flags: .skip 4
.section .rodata
name_alu: .asciz "exhaustive ALU (1,048,576 input combinations)"
name_cb: .asciz "all CB opcodes, operands and carry inputs (131,072 cases)"
name_cpu: .asciz "CPU loads, flags, stack, branches, signed SP, DAA"
name_decode: .asciz "all base opcodes: legality and taken/untaken cycle counts"
name_irq: .asciz "interrupt priority, delayed EI, RETI, HALT bug"
name_bus: .asciz "ROM protection, echo RAM, MBC1 ROM and RAM banking, DMA"
name_timer: .asciz "DIV/TIMA edges, overflow delay, TAC writes"
name_ppu: .asciz "PPU timing, STAT edge, tiles, window, sprite priority"
pass_text: .ascii "All assembly tests passed.\n"
pass_end:
fail_text: .ascii "FAIL: "
newline: .byte 10
.section .text
.global _start
_start:
    case name_alu
    xor r12d, r12d             # ALU operation
.alu_test_op:
    xor r13d, r13d             # A
.alu_test_a:
    xor r14d, r14d             # operand
.alu_test_b:
    xor r15d, r15d             # carry
.alu_test_c:
    mov byte ptr [regs+7], r13b
    mov eax, r15d
    shl eax, 4
    mov byte ptr [reg_f], al
    call reference_alu
    mov dword ptr [expected_value], eax
    mov dword ptr [expected_flags], edx
    mov edi, r12d
    mov esi, r14d
    call alu8
    movzx eax, byte ptr [regs+7]
    cmp eax, dword ptr [expected_value]
    jne test_fail
    movzx eax, byte ptr [reg_f]
    cmp eax, dword ptr [expected_flags]
    jne test_fail
    inc r15d
    cmp r15d, 2
    jb .alu_test_c
    inc r14d
    cmp r14d, 256
    jb .alu_test_b
    inc r13d
    cmp r13d, 256
    jb .alu_test_a
    inc r12d
    cmp r12d, 8
    jb .alu_test_op

    case name_cb
    xor r12d, r12d
.cb_test_op:
    xor r13d, r13d
.cb_test_value:
    xor r14d, r14d
.cb_test_carry:
    mov word ptr [reg_pc], 0xc100
    mov byte ptr [mem+0xc100], 0xcb
    mov byte ptr [mem+0xc101], r12b
    mov byte ptr [regs+4], 0xc0
    mov byte ptr [regs+5], 0
    mov edi, r12d
    and edi, 7
    mov esi, r13d
    call put8
    mov eax, r14d
    shl eax, 4
    mov byte ptr [reg_f], al
    call reference_cb
    mov dword ptr [expected_value], eax
    mov dword ptr [expected_flags], edx
    call cpu_step
    mov edx, 8
    mov ecx, r12d
    and ecx, 7
    cmp ecx, 6
    jne 1f
    mov edx, 16
    cmp r12d, 0x40
    jb 1f
    cmp r12d, 0x80
    jae 1f
    mov edx, 12
1:  cmp eax, edx
    jne test_fail
    check16 reg_pc, 0xc102
    mov edi, r12d
    and edi, 7
    call get8
    cmp eax, dword ptr [expected_value]
    jne test_fail
    movzx eax, byte ptr [reg_f]
    cmp eax, dword ptr [expected_flags]
    jne test_fail
    inc r14d
    cmp r14d, 2
    jb .cb_test_carry
    inc r13d
    cmp r13d, 256
    jb .cb_test_value
    inc r12d
    cmp r12d, 256
    jb .cb_test_op

    case name_decode
    xor r12d, r12d
.decode_test_opcode:
    xor r13d, r13d
.decode_test_flags:
    call fixture
    mov word ptr [reg_pc], 0xc100
    mov byte ptr [mem+0xc100], r12b
    mov word ptr [mem+0xc101], 0x5555
    mov eax, r13d
    imul eax, eax, 0xf0
    mov byte ptr [reg_f], al
    call cpu_step
    movzx edx, byte ptr [base_cycles+r12]
    test edx, edx
    jnz .decode_legal
    check8 cpu_fault, 1
    jmp .decode_test_next
.decode_legal:
    check8 cpu_fault, 0
    # Conditional branch tables give untaken timings. NZ/NC are true with
    # F=0; Z/C are true with F=f0. Test both independently.
    mov ecx, r12d
    and ecx, 0xe7
    cmp ecx, 0x20
    je .decode_jr
    mov ecx, r12d
    and ecx, 0xe7
    cmp ecx, 0xc0
    je .decode_ret
    cmp ecx, 0xc2
    je .decode_jp
    cmp ecx, 0xc4
    je .decode_call
    jmp .decode_compare
.decode_jr:
    mov esi, 4
    jmp .decode_condition
.decode_ret:
    mov esi, 12
    jmp .decode_condition
.decode_jp:
    mov esi, 4
    jmp .decode_condition
.decode_call:
    mov esi, 12
.decode_condition:
    mov ecx, r12d
    shr ecx, 3
    and ecx, 1
    cmp ecx, r13d
    jne .decode_compare
    add edx, esi
.decode_compare:
    cmp eax, edx
    jne test_fail
.decode_test_next:
    inc r13d
    cmp r13d, 2
    jb .decode_test_flags
    inc r12d
    cmp r12d, 256
    jb .decode_test_opcode

    case name_cpu
    lea rsi, [cpu_program]
    lea rdi, [mem+0xc000]
    mov ecx, cpu_program_end-cpu_program
    rep movsb
    mov word ptr [reg_pc], 0xc000
    mov r12d, 27
1:  call cpu_step
    check8 cpu_fault, 0
    dec r12d
    jnz 1b
    check8 regs+7, 0x42
    check8 reg_f, 0
    check8 regs, 0x12
    check8 regs+1, 0x34
    check8 regs+2, 0x12
    check8 regs+3, 0x34
    check16 reg_sp, 0xcfff
    check8 mem+0xc200, 0x12
    check8 mem+0xc201, 0x34
    check8 mem+0xc202, 0x00
    check8 mem+0xc203, 0x0f
    check8 mem+0xc204, 0x0f
    # POP AF masks the unused low flag bits.
    mov word ptr [mem+0xcfff], 0x56ff
    mov byte ptr [mem+0xc100], 0xf1
    mov word ptr [reg_pc], 0xc100
    call cpu_step
    check8 regs+7, 0x56
    check8 reg_f, 0xf0
    # CALL/RET and RST use little-endian return addresses and wrap SP correctly.
    mov word ptr [reg_sp], 0xfffe
    mov word ptr [reg_pc], 0xc100
    mov dword ptr [mem+0xc100], 0xdfc110cd
    mov byte ptr [mem+0xc110], 0xc9
    call cpu_step
    check16 reg_pc, 0xc110
    check16 reg_sp, 0xfffc
    check16 mem+0xfffc, 0xc103
    call cpu_step
    check16 reg_pc, 0xc103
    check16 reg_sp, 0xfffe
    call cpu_step
    check16 reg_pc, 0x18
    check16 mem+0xfffc, 0xc104
    # Signed SP offsets carry from the unsigned low byte, not bit 15.
    mov word ptr [reg_pc], 0xc100
    mov word ptr [reg_sp], 0xfff8
    mov word ptr [mem+0xc100], 0x08e8
    call cpu_step
    check16 reg_sp, 0
    check8 reg_f, 0x30
    mov word ptr [reg_pc], 0xc100
    mov word ptr [mem+0xc100], 0xfff8
    call cpu_step
    check8 regs+4, 0xff
    check8 regs+5, 0xff
    check8 reg_f, 0
    # DAA vectors cover addition, subtraction, carry, and zero.
    xor r12d, r12d
.daa_vectors:
    mov al, byte ptr [daa_vectors+r12]
    mov byte ptr [regs+7], al
    mov al, byte ptr [daa_vectors+r12+1]
    mov byte ptr [reg_f], al
    mov word ptr [reg_pc], 0xc100
    mov byte ptr [mem+0xc100], 0x27
    call cpu_step
    mov al, byte ptr [daa_vectors+r12+2]
    cmp byte ptr [regs+7], al
    jne test_fail
    mov al, byte ptr [daa_vectors+r12+3]
    cmp byte ptr [reg_f], al
    jne test_fail
    add r12d, 4
    cmp r12d, daa_vectors_end-daa_vectors
    jb .daa_vectors
    # Illegal hardware opcodes must stop, never silently act as NOP.
    mov byte ptr [mem+0xc100], 0xd3
    mov word ptr [reg_pc], 0xc100
    call cpu_step
    check8 cpu_fault, 1
    check8 fault_opcode, 0xd3
    check16 fault_pc, 0xc100

    case name_irq
    mov byte ptr [mem+0xffff], 0x1f
    mov byte ptr [mem+0xff0f], 5
    mov byte ptr [ime], 1
    mov word ptr [reg_pc], 0xc123
    call cpu_step
    cmp eax, 20
    jne test_fail
    check16 reg_pc, 0x40
    check16 reg_sp, 0xfffc
    check16 mem+0xfffc, 0xc123
    check8 mem+0xff0f, 4
    check8 ime, 0
    mov byte ptr [rom+0x40], 0xd9
    call cpu_step
    check16 reg_pc, 0xc123
    check8 ime, 1
    mov byte ptr [ime], 0
    mov dword ptr [mem+0xc123], 0x0000fbfb # EI; EI; NOP; NOP
    call cpu_step
    check8 ime, 0
    call cpu_step
    check8 ime, 1
    call cpu_step
    check16 reg_pc, 0x50
    # EI; DI cancels pending enable.
    mov byte ptr [ime], 0
    mov word ptr [reg_pc], 0xc100
    mov word ptr [mem+0xc100], 0xf3fb
    call cpu_step
    call cpu_step
    check8 ime, 0
    check8 ei_delay, 0
    # Pending interrupt with IME=0: HALT bug repeats opcode byte as immediate.
    mov word ptr [reg_pc], 0xc100
    mov dword ptr [mem+0xc100], 0x00423e76
    mov byte ptr [mem+0xff0f], 1
    call cpu_step
    check8 halt_bug, 1
    call cpu_step
    check8 regs+7, 0x3e
    check16 reg_pc, 0xc102

    case name_bus
    mov byte ptr [rom+0x100], 0xab
    mov edi, 0x100
    mov esi, 0x55
    call bus_write
    mov edi, 0x100
    call bus_read
    cmp eax, 0xab
    jne test_fail
    mov edi, 0xe123
    mov esi, 0x65
    call bus_write
    check8 mem+0xc123, 0x65
    mov edi, 0x1e123
    call bus_read
    cmp eax, 0x65
    jne test_fail
    mov edi, 0xfea0
    call bus_read
    cmp eax, 255
    jne test_fail
    mov byte ptr [mapper], 1
    mov dword ptr [rom_mask], 2097151
    mov byte ptr [rom+0x4000], 0x11
    mov byte ptr [rom+0x8000], 0x22
    mov byte ptr [rom+0x80000], 0x20
    mov byte ptr [rom+0x88000], 0x32
    mov edi, 0x2000
    mov esi, 2
    call bus_write
    mov edi, 0x4000
    call bus_read
    cmp eax, 0x22
    jne test_fail
    mov edi, 0x4000
    mov esi, 1
    call bus_write
    mov edi, 0x4000
    call bus_read
    cmp eax, 0x32
    jne test_fail
    mov edi, 0x6000
    mov esi, 1
    call bus_write
    xor edi, edi
    call bus_read
    cmp eax, 0x20
    jne test_fail
    mov dword ptr [ram_mask], 32767
    xor edi, edi
    mov esi, 0x0a
    call bus_write
    mov edi, 0xa000
    mov esi, 0x77
    call bus_write
    check8 cart_ram+8192, 0x77
    mov edi, 0xa000
    call bus_read
    cmp eax, 0x77
    jne test_fail
    xor edi, edi
    xor esi, esi
    call bus_write
    mov edi, 0xa000
    call bus_read
    cmp eax, 255
    jne test_fail
    mov byte ptr [mem+0xc000], 0xaa
    mov byte ptr [mem+0xc09f], 0xbb
    mov edi, 0xff46
    mov esi, 0xc0
    call bus_write
    check8 mem+0xfe00, 0xaa
    check8 mem+0xfe9f, 0xbb

    case name_timer
    mov byte ptr [mem+0xff40], 0
    mov byte ptr [mem+0xff07], 5
    mov edi, 16
    call hardware_tick
    check8 mem+0xff05, 1
    mov byte ptr [mem+0xff05], 255
    mov byte ptr [mem+0xff06], 0x42
    mov byte ptr [mem+0xff0f], 0
    mov edi, 16
    call hardware_tick
    check8 mem+0xff05, 0
    check8 mem+0xff0f, 0
    mov edi, 4
    call hardware_tick
    check8 mem+0xff05, 0x42
    check8 mem+0xff0f, 4
    mov dword ptr [div_counter], 8
    mov edi, 0xff04
    xor esi, esi
    call bus_write
    check8 mem+0xff05, 0x43
    check32 div_counter, 0
    mov dword ptr [div_counter], 8
    mov edi, 0xff07
    xor esi, esi
    call bus_write
    check8 mem+0xff05, 0x44
    # Writing TIMA during the pending reload cancels it.
    mov dword ptr [timer_reload], 4
    mov edi, 0xff05
    mov esi, 0x99
    call bus_write
    mov edi, 4
    call hardware_tick
    check8 mem+0xff05, 0x99
    check32 timer_reload, 0

    case name_ppu
    mov byte ptr [mem+0xff0f], 0
    mov edi, 70224
    call hardware_tick
    check8 mem+0xff44, 0
    check32 ppu_dot, 0
    check32 frame_count, 1
    test byte ptr [mem+0xff0f], 1
    jz test_fail
    mov byte ptr [mem+0xff41], 0x40
    call stat_update
    test byte ptr [mem+0xff0f], 2
    jz test_fail
    mov byte ptr [mem+0xff0f], 0
    call stat_update
    check8 mem+0xff0f, 0       # high STAT line doesn't re-request
    mov byte ptr [mem+0xff47], 0xe4
    mov byte ptr [mem+0x8000], 0x80
    mov byte ptr [mem+0x8001], 0x40
    call render_line
    check8 framebuffer, 1
    check8 framebuffer+1, 2
    check8 framebuffer+2, 0
    # Signed tile index -1 uses 0x8ff0, not 0x9ff0.
    mov byte ptr [mem+0xff40], 0x81
    mov byte ptr [mem+0x9800], 0xff
    mov byte ptr [mem+0x8ff0], 0x80
    mov byte ptr [mem+0x8ff1], 0x80
    call render_line
    check8 framebuffer, 3
    # Window at WX=7 starts at x=0 and uses its own line counter.
    mov byte ptr [mem+0xff40], 0xf1
    mov byte ptr [mem+0xff4b], 7
    mov byte ptr [mem+0x9c00], 1
    mov byte ptr [mem+0x8010], 0xff
    call render_line
    check8 framebuffer, 1
    check32 window_line, 1
    # Two equal-X sprites: earlier OAM wins; transparent pixels pass through.
    mov byte ptr [mem+0xff40], 0x93
    mov byte ptr [mem+0x9800], 0
    mov byte ptr [mem+0xff48], 0xe4
    mov dword ptr [mem+0xfe00], 0x00020810
    mov dword ptr [mem+0xfe04], 0x00030810
    mov byte ptr [mem+0x8020], 0x80
    mov byte ptr [mem+0x8031], 0xc0
    call render_line
    check8 framebuffer, 1
    check8 framebuffer+1, 2
    # First object's BG priority masks lower objects as well.
    mov byte ptr [mem+0xfe03], 0x80
    mov byte ptr [mem+0x8001], 0xc0
    call render_line
    check8 framebuffer, 3
    # Horizontal flip takes bit 0 as the leftmost pixel.
    mov dword ptr [mem+0xfe00], 0x20020810
    mov byte ptr [mem+0xfe04], 0
    mov byte ptr [mem+0x8020], 1
    call render_line
    check8 framebuffer, 1

    mov edi, 1
    lea rsi, [pass_text]
    mov edx, pass_end-pass_text
    call write_all
    xor edi, edi
    jmp exit_process

fixture:
    call machine_reset
    mov byte ptr [mapper], 0
    mov dword ptr [rom_mask], 32767
    mov dword ptr [ram_mask], 0
    ret
test_fail:
    mov edi, 2
    lea rsi, [fail_text]
    mov edx, 6
    call write_all
    mov rsi, qword ptr [test_name]
    xor edx, edx
1:  cmp byte ptr [rsi+rdx], 0
    je 2f
    inc edx
    jmp 1b
2:  mov edi, 2
    call write_all
    mov edi, 2
    lea rsi, [newline]
    mov edx, 1
    call write_all
    mov edi, 1
    jmp exit_process

# Mathematical reference: wide arithmetic and nibble comparisons, independent
# of the interpreter's x86 LAHF-based implementation.
reference_alu:
    mov eax, r13d
    xor edx, edx
    cmp r12d, 4
    jb .ref_arithmetic
    cmp r12d, 7
    je .ref_arithmetic
    cmp r12d, 4
    jne 1f
    and eax, r14d
    mov edx, 0x20
    jmp .ref_zero
1:  cmp r12d, 5
    jne 2f
    xor eax, r14d
    jmp .ref_zero
2:  or eax, r14d
    jmp .ref_zero
.ref_arithmetic:
    xor ecx, ecx
    cmp r12d, 1
    je 1f
    cmp r12d, 3
    jne 2f
1:  mov ecx, r15d
2:  mov esi, r14d
    and esi, 15
    add esi, ecx
    mov edi, r13d
    and edi, 15
    cmp r12d, 2
    jae .ref_subtract
    add edi, esi
    cmp edi, 15
    jbe 3f
    or edx, 0x20
3:  add eax, r14d
    add eax, ecx
    cmp eax, 255
    jbe .ref_zero
    or edx, 0x10
    jmp .ref_zero
.ref_subtract:
    mov edx, 0x40
    cmp edi, esi
    jae 1f
    or edx, 0x20
1:  sub eax, r14d
    sub eax, ecx
    test eax, eax
    jns .ref_zero
    or edx, 0x10
.ref_zero:
    and eax, 255
    jnz 1f
    or edx, 0x80
1:  cmp r12d, 7
    jne 2f
    mov eax, r13d
2:  ret

reference_cb:
    mov eax, r13d
    mov ecx, r12d
    shr ecx, 3
    and ecx, 7
    mov edx, r14d
    shl edx, 4
    cmp r12d, 0x40
    jb .ref_rotate
    mov esi, 1
    shl esi, cl
    cmp r12d, 0x80
    jae 1f
    or edx, 0x20
    test eax, esi
    jnz 3f
    or edx, 0x80
    ret
1:  cmp r12d, 0xc0
    jae 2f
    not esi
    and eax, esi
    ret
2:  or eax, esi
3:  ret
.ref_rotate:
    xor edx, edx
    cmp ecx, 6
    je .ref_swap
    cmp ecx, 7
    je .ref_right
    test ecx, 1
    jnz .ref_right
    mov edx, eax
    shr edx, 7
    shl eax, 1
    cmp ecx, 0
    jne 1f
    or eax, edx
1:  cmp ecx, 2
    jne .ref_rotate_flags
    or eax, r14d
    jmp .ref_rotate_flags
.ref_right:
    mov edx, eax
    and edx, 1
    shr eax, 1
    cmp ecx, 1
    jne 1f
    mov esi, edx
    shl esi, 7
    or eax, esi
1:  cmp ecx, 3
    jne 2f
    mov esi, r14d
    shl esi, 7
    or eax, esi
2:  cmp ecx, 5
    jne .ref_rotate_flags
    mov esi, r13d
    and esi, 0x80
    or eax, esi
    jmp .ref_rotate_flags
.ref_swap:
    mov esi, eax
    shr esi, 4
    shl eax, 4
    or eax, esi
.ref_rotate_flags:
    shl edx, 4
    and eax, 255
    jnz 1f
    or edx, 0x80
1:  ret

.section .rodata
daa_vectors:
    .byte 0x9a,0x00,0x00,0x90
    .byte 0x0f,0x60,0x09,0x40
    .byte 0x00,0x70,0x9a,0x50
    .byte 0x32,0x10,0x92,0x10
    .byte 0x99,0x00,0x99,0x00
    .byte 0x00,0x00,0x00,0x80
    .byte 0x00,0x40,0x00,0xc0
daa_vectors_end:
# T-cycles, untaken conditionals. Zero means an illegal opcode. CB 55 is BIT
# 2,L, so the prefix's complete instruction takes 8 cycles for this fixture.
base_cycles:
    .byte 4,12,8,8,4,4,8,4,20,8,8,8,4,4,8,4
    .byte 4,12,8,8,4,4,8,4,12,8,8,8,4,4,8,4
    .byte 8,12,8,8,4,4,8,4,8,8,8,8,4,4,8,4
    .byte 8,12,8,8,12,12,12,4,8,8,8,8,4,4,8,4
    .byte 4,4,4,4,4,4,8,4,4,4,4,4,4,4,8,4
    .byte 4,4,4,4,4,4,8,4,4,4,4,4,4,4,8,4
    .byte 4,4,4,4,4,4,8,4,4,4,4,4,4,4,8,4
    .byte 8,8,8,8,8,8,4,8,4,4,4,4,4,4,8,4
    .byte 4,4,4,4,4,4,8,4,4,4,4,4,4,4,8,4
    .byte 4,4,4,4,4,4,8,4,4,4,4,4,4,4,8,4
    .byte 4,4,4,4,4,4,8,4,4,4,4,4,4,4,8,4
    .byte 4,4,4,4,4,4,8,4,4,4,4,4,4,4,8,4
    .byte 8,12,12,16,12,16,8,16,8,16,12,8,12,24,8,16
    .byte 8,12,12,0,12,16,8,16,8,16,12,0,12,0,8,16
    .byte 12,12,8,0,0,16,8,16,16,4,16,0,0,0,8,16
    .byte 12,12,8,4,0,16,8,16,12,8,16,4,0,0,8,16
cpu_program:
    .byte 0x31,0x00,0xd0        # LD SP,d000
    .byte 0x01,0x34,0x12        # LD BC,1234
    .byte 0xc5,0xd1             # PUSH BC; POP DE
    .byte 0x21,0x00,0xc2        # LD HL,c200
    .byte 0x70,0x23,0x71        # LD (HL),B; INC HL; LD (HL),C
    .byte 0x3e,0x99,0xc6,0x01,0x27 # LD A,99; ADD 1; DAA -> 00,C
    .byte 0xea,0x02,0xc2        # LD (c202),A
    .byte 0x3e,0x10,0xd6,0x01   # LD A,10; SUB 1 -> 0f
    .byte 0xea,0x03,0xc2
    .byte 0x3e,0x0f,0x3c,0x3d   # INC A; DEC A -> 0f, N,H
    .byte 0xea,0x04,0xc2
    .byte 0xf8,0xff             # LD HL,SP-1 -> cfff, no H/C
    .byte 0xf9                  # LD SP,HL
    .byte 0xaf,0x20,0x02        # XOR A; JR NZ (not taken)
    .byte 0x28,0x02             # JR Z (taken)
    .byte 0x3e,0xff             # skipped
    .byte 0x3e,0x42,0xb7        # LD A,42; OR A -> F=0
    .byte 0x00,0x00
cpu_program_end:
