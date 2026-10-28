# Internal ABI: SysV callee-saved registers are preserved. All other registers
# are scratch. Addresses passed to the bus are masked to 16 bits.
.intel_syntax noprefix
.section .bss
.balign 16
state_begin:
regs: .skip 8                    # B C D E H L unused A (opcode order)
reg_f: .skip 1
ime: .skip 1
ei_delay: .skip 1
halted: .skip 1
halt_bug: .skip 1
cpu_fault: .skip 1
fault_opcode: .skip 1
.balign 2
reg_sp: .skip 2
reg_pc: .skip 2
fault_pc: .skip 2
.balign 4
div_counter: .skip 4
timer_reload: .skip 4
serial_clock: .skip 4
ppu_dot: .skip 4
window_line: .skip 4
stat_line: .skip 1
joy_keys: .skip 1                # active high: R L U D A B Select Start
.balign 8
frame_count: .skip 8
total_cycles: .skip 8
mem: .skip 65536
cart_ram: .skip 32768
framebuffer: .skip 23040         # palette-mapped shades 0..3
bg_line: .skip 160               # raw BG color indices for OBJ priority
obj_owner: .skip 160             # winning OBJ X (255 means none)
state_end:
rom: .skip 2097153               # one extra byte detects oversized images
rom_size: .skip 8
rom_mask: .skip 4
ram_mask: .skip 4
mapper: .skip 1
ram_enabled: .skip 1
bank_low: .skip 1
bank_high: .skip 1
bank_mode: .skip 1
serial_enabled: .skip 1
.section .text
machine_reset:
    lea rdi, [rip+state_begin]
    mov ecx, state_end-state_begin
    xor eax, eax
    rep stosb
    mov byte ptr [regs+7], 1
    mov byte ptr [regs+1], 0x13
    mov byte ptr [regs+3], 0xd8
    mov byte ptr [regs+4], 1
    mov byte ptr [regs+5], 0x4d
    mov byte ptr [reg_f], 0xb0
    mov word ptr [reg_sp], 0xfffe
    mov word ptr [reg_pc], 0x100
    mov byte ptr [bank_low], 1
    mov byte ptr [bank_high], 0
    mov byte ptr [bank_mode], 0
    mov byte ptr [ram_enabled], 0
    mov byte ptr [mem+0xff00], 0xcf
    mov byte ptr [mem+0xff0f], 0xe1
    mov byte ptr [mem+0xff40], 0x91
    mov byte ptr [mem+0xff41], 0x86
    mov byte ptr [mem+0xff47], 0xfc
    mov byte ptr [mem+0xff48], 0xff
    mov byte ptr [mem+0xff49], 0xff
    mov byte ptr [mem+0xff50], 1
    ret
