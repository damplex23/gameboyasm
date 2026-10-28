.intel_syntax noprefix
.include "src/state.s"
.include "src/cpu.s"
.include "src/memory.s"
.include "src/ppu.s"
.include "src/linux.s"

.section .text
.global _start
_start:
    mov r12, rsp
    cmp qword ptr [r12], 2
    jb usage_error
    mov rdi, qword ptr [r12+16]
    lea rsi, [help_option]
    call str_equal
    test eax, eax
    jnz show_help
    mov rdi, qword ptr [r12+16]
    call load_rom
    mov r13d, 2
.args:
    cmp r13, qword ptr [r12]
    jae .args_done
    mov rdi, qword ptr [r12+r13*8+8]
    lea rsi, [frames_option]
    call str_equal
    test eax, eax
    jnz .frames_arg
    mov rdi, qword ptr [r12+r13*8+8]
    lea rsi, [dump_option]
    call str_equal
    test eax, eax
    jz usage_error
    inc r13
    cmp r13, qword ptr [r12]
    jae usage_error
    mov rax, qword ptr [r12+r13*8+8]
    mov qword ptr [dump_path], rax
    inc r13
    jmp .args
.frames_arg:
    inc r13
    cmp r13, qword ptr [r12]
    jae usage_error
    mov rdi, qword ptr [r12+r13*8+8]
    call parse_number
    test eax, eax
    jz usage_error
    mov qword ptr [frame_limit], rax
    inc r13
    jmp .args
.args_done:
    call machine_reset
    cmp qword ptr [frame_limit], 0
    jne .headless
    call terminal_init
    jmp .run
.headless:
    mov byte ptr [serial_enabled], 1
.run:
    mov r14, 70224
    xor r15d, r15d
.emulate:
    cmp byte ptr [stop_requested], 0
    jne .finished
    call cpu_step
    cmp byte ptr [cpu_fault], 0
    jne .fault
    mov edi, eax
    call hardware_tick
    cmp qword ptr [total_cycles], r14
    jb .emulate
    add r14, 70224
    inc r15
    cmp qword ptr [frame_limit], 0
    jne .headless_frame
    call terminal_input
    test r15b, 1               # ~30 terminal refreshes/sec; emulation ~59.7 Hz
    jnz 1f
    call terminal_draw
1:  call pace_frame
    jmp .emulate
.headless_frame:
    cmp r15, qword ptr [frame_limit]
    jb .emulate
.finished:
    call terminal_restore
    cmp qword ptr [dump_path], 0
    je 1f
    call dump_frame
1:  xor edi, edi
    jmp exit_process
.fault:
    call terminal_restore
    lea rdi, [fault_op_hex]
    movzx eax, byte ptr [fault_opcode]
    call hex_byte
    lea rdi, [fault_pc_hex]
    movzx eax, byte ptr [fault_pc+1]
    call hex_byte
    lea rdi, [fault_pc_hex+2]
    movzx eax, byte ptr [fault_pc]
    call hex_byte
    lea rsi, [fault_message]
    mov edx, fault_message_end-fault_message
    jmp fatal

.section .rodata
frames_option: .asciz "--frames"
dump_option: .asciz "--dump"
help_option: .asciz "--help"
.section .data
fault_message: .ascii "Illegal SM83 opcode 0x"
fault_op_hex: .ascii "00 at PC 0x"
fault_pc_hex: .ascii "0000.\n"
fault_message_end:
