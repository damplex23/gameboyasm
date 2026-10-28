# SM83 interpreter. cpu_step returns elapsed T-cycles in EAX.
# Grouped decoding follows the instruction encoding, not a Z80 interpreter.
.section .text
fetch8:
    movzx edi, word ptr [reg_pc]
    inc word ptr [reg_pc]
    jmp bus_read
fetch16:
    call fetch8
    push rax
    call fetch8
    shl eax, 8
    pop rdx
    or eax, edx
    ret
get8:
    cmp edi, 6
    je .get_hl
    movzx eax, byte ptr [regs+rdi]
    ret
.get_hl:
    movzx edi, byte ptr [regs+4]
    shl edi, 8
    mov dil, byte ptr [regs+5]
    jmp bus_read
put8:
    cmp edi, 6
    je .put_hl
    mov byte ptr [regs+rdi], sil
    ret
.put_hl:
    movzx edi, byte ptr [regs+4]
    shl edi, 8
    mov dil, byte ptr [regs+5]
    jmp bus_write
get16:
    cmp edi, 3
    je .get_sp
    movzx eax, byte ptr [regs+rdi*2]
    shl eax, 8
    mov al, byte ptr [regs+rdi*2+1]
    ret
.get_sp:
    movzx eax, word ptr [reg_sp]
    ret
put16:
    cmp edi, 3
    je .put_sp
    mov byte ptr [regs+rdi*2+1], sil
    shr esi, 8
    mov byte ptr [regs+rdi*2], sil
    ret
.put_sp:
    mov word ptr [reg_sp], si
    ret
push16:                         # EAX value, bus writes high then low
    push rax
    dec word ptr [reg_sp]
    movzx edi, word ptr [reg_sp]
    mov esi, eax
    shr esi, 8
    call bus_write
    pop rsi
    dec word ptr [reg_sp]
    movzx edi, word ptr [reg_sp]
    jmp bus_write
pop16:
    movzx edi, word ptr [reg_sp]
    inc word ptr [reg_sp]
    call bus_read
    push rax
    movzx edi, word ptr [reg_sp]
    inc word ptr [reg_sp]
    call bus_read
    shl eax, 8
    pop rdx
    or eax, edx
    ret
condition:                      # EDI = NZ/Z/NC/C, returns ZF=0 if true
    movzx eax, byte ptr [reg_f]
    test edi, 2
    jnz .cond_c
    shr eax, 7
    jmp .cond_invert
.cond_c:
    shr eax, 4
.cond_invert:
    and eax, 1
    and edi, 1
    xor eax, edi
    xor eax, 1
    test eax, eax
    ret

cpu_step:
    push r12
    push r13
    push r14
    push r15
    mov r15d, 4
    movzx eax, byte ptr [mem+0xffff]
    and al, byte ptr [mem+0xff0f]
    and eax, 0x1f
    jz .no_irq
    mov byte ptr [halted], 0
    cmp byte ptr [ime], 0
    je .no_irq
    bsf r12d, eax
    mov ecx, r12d
    mov eax, 1
    shl eax, cl
    not eax
    and byte ptr [mem+0xff0f], al
    mov byte ptr [ime], 0
    mov byte ptr [ei_delay], 0
    mov byte ptr [halt_bug], 0
    movzx eax, word ptr [reg_pc]
    call push16
    lea eax, [r12*8+0x40]
    mov word ptr [reg_pc], ax
    mov r15d, 20
    jmp .cpu_return
.no_irq:
    cmp byte ptr [halted], 0
    jne .cpu_return
    mov ax, word ptr [reg_pc]
    mov word ptr [fault_pc], ax
    call fetch8
    cmp byte ptr [halt_bug], 0
    je .decode
    dec word ptr [reg_pc]
    mov byte ptr [halt_bug], 0
.decode:
    mov r12d, eax
    mov byte ptr [fault_opcode], al
    cmp eax, 0x40
    jb .low
    cmp eax, 0x80
    jb .ld_group
    cmp eax, 0xc0
    jb .alu_group
    sub eax, 0xc0
    jmp qword ptr [high_ops+rax*8]
.low:
    jmp qword ptr [low_ops+rax*8]
.ld_group:
    cmp r12d, 0x76
    je op_halt
    mov edi, r12d
    and edi, 7
    cmp edi, 6
    jne 1f
    mov r15d, 8
1:  call get8
    mov esi, eax
    mov edi, r12d
    shr edi, 3
    and edi, 7
    cmp edi, 6
    jne 2f
    mov r15d, 8
2:  call put8
    jmp done
.alu_group:
    mov edi, r12d
    and edi, 7
    cmp edi, 6
    jne 1f
    mov r15d, 8
1:  call get8
    mov esi, eax
    mov edi, r12d
    shr edi, 3
    and edi, 7
    call alu8
    jmp done
done:
    cmp byte ptr [ei_delay], 0
    je .cpu_return
    dec byte ptr [ei_delay]
    jne .cpu_return
    mov byte ptr [ime], 1
.cpu_return:
    mov eax, r15d
    pop r15
    pop r14
    pop r13
    pop r12
    ret
op_nop:
    jmp done
op_bad:
    mov byte ptr [cpu_fault], 1
    jmp done
op_halt:
    cmp byte ptr [ime], 0
    jne 1f
    mov al, byte ptr [mem+0xffff]
    and al, byte ptr [mem+0xff0f]
    test al, 0x1f
    jz 1f
    mov byte ptr [halt_bug], 1
    jmp done
1:  mov byte ptr [halted], 1
    jmp done
op_stop:
    call fetch8
    mov byte ptr [halted], 1     # simplified STOP; see accuracy notes
    jmp done
op_ld16:
    call fetch16
    mov esi, eax
    mov edi, r12d
    shr edi, 4
    call put16
    mov r15d, 12
    jmp done
op_indirect:
    mov edi, r12d
    shr edi, 4
    cmp edi, 3
    jne 1f
    mov edi, 2
1:  call get16
    mov edi, eax
    test r12d, 8
    jnz 2f
    movzx esi, byte ptr [regs+7]
    call bus_write
    jmp 3f
2:  call bus_read
    mov byte ptr [regs+7], al
3:  cmp r12d, 0x20
    jb 5f
    mov edi, 2
    call get16
    inc eax
    cmp r12d, 0x30
    jb 4f
    sub eax, 2
4:  mov esi, eax
    mov edi, 2
    call put16
5:  mov r15d, 8
    jmp done
op_incdec16:
    mov edi, r12d
    shr edi, 4
    call get16
    inc eax
    test r12d, 8
    jz 1f
    sub eax, 2
1:  mov esi, eax
    mov edi, r12d
    shr edi, 4
    call put16
    mov r15d, 8
    jmp done
op_addhl:
    mov edi, r12d
    shr edi, 4
    call get16
    mov r14d, eax
    mov edi, 2
    call get16
    mov edx, eax
    add eax, r14d
    xor edx, r14d
    xor edx, eax
    shr edx, 7                  # half carry from bit 12 -> flag bit 5
    and edx, 0x20
    mov ecx, eax
    shr ecx, 12
    and ecx, 0x10
    or edx, ecx
    and byte ptr [reg_f], 0x80
    or byte ptr [reg_f], dl
    mov esi, eax
    mov edi, 2
    call put16
    mov r15d, 8
    jmp done
op_incdec8:
    mov r13d, r12d
    shr r13d, 3
    and r13d, 7
    mov edi, r13d
    call get8
    test r12d, 1
    jnz 1f
    add al, 1
    lahf
    movzx edx, ah
    xor ecx, ecx
    jmp 2f
1:  sub al, 1
    lahf
    movzx edx, ah
    mov ecx, 0x40
2:  and edx, 0x50
    shl edx, 1
    or edx, ecx
    mov cl, byte ptr [reg_f]
    and ecx, 0x10
    or edx, ecx
    mov byte ptr [reg_f], dl
    movzx esi, al
    mov edi, r13d
    call put8
    cmp r13d, 6
    jne done
    mov r15d, 12
    jmp done
op_ld8imm:
    call fetch8
    mov esi, eax
    mov edi, r12d
    shr edi, 3
    and edi, 7
    mov r15d, 8
    cmp edi, 6
    jne 1f
    mov r15d, 12
1:  call put8
    jmp done
op_ld_sp_abs:
    call fetch16
    mov r13d, eax
    mov edi, eax
    movzx esi, word ptr [reg_sp]
    call bus_write
    lea edi, [r13+1]
    movzx esi, byte ptr [reg_sp+1]
    call bus_write
    mov r15d, 20
    jmp done
op_rotate_a:
    mov edi, r12d
    shr edi, 3                 # same operation order as CB group 0..3
    movzx eax, byte ptr [regs+7]
    call rotate8
    mov byte ptr [regs+7], al
    and byte ptr [reg_f], 0x10 # A rotates always clear Z
    jmp done
op_jr:
    call fetch8
    movsx r14d, al
    mov r15d, 8
    cmp r12d, 0x18
    je 1f
    mov edi, r12d
    shr edi, 3
    and edi, 3
    call condition
    jz done
1:  add word ptr [reg_pc], r14w
    mov r15d, 12
    jmp done
op_daa:
    mov al, byte ptr [regs+7]
    mov dl, byte ptr [reg_f]
    xor ecx, ecx
    test dl, 0x40
    jnz .daa_sub
    test dl, 0x10
    jnz 1f
    cmp al, 0x99
    jbe 2f
1:  or ecx, 0x60
    or dl, 0x10
2:  test dl, 0x20
    jnz 3f
    mov ah, al
    and ah, 15
    cmp ah, 9
    jbe 4f
3:  or ecx, 6
4:  add al, cl
    jmp .daa_end
.daa_sub:
    test dl, 0x10
    jz 1f
    or ecx, 0x60
1:  test dl, 0x20
    jz 2f
    or ecx, 6
2:  sub al, cl
.daa_end:
    and dl, 0x50
    test al, al
    jnz 1f
    or dl, 0x80
1:  mov byte ptr [regs+7], al
    mov byte ptr [reg_f], dl
    jmp done
op_cpl:
    not byte ptr [regs+7]
    or byte ptr [reg_f], 0x60
    jmp done
op_scf:
    and byte ptr [reg_f], 0x80
    or byte ptr [reg_f], 0x10
    jmp done
op_ccf:
    and byte ptr [reg_f], 0x90
    xor byte ptr [reg_f], 0x10
    jmp done
op_ret_cond:
    mov r15d, 8
    mov edi, r12d
    shr edi, 3
    and edi, 3
    call condition
    jz done
    call pop16
    mov word ptr [reg_pc], ax
    mov r15d, 20
    jmp done
op_ret:
    call pop16
    mov word ptr [reg_pc], ax
    mov r15d, 16
    cmp r12d, 0xd9
    jne done
    mov byte ptr [ime], 1
    mov byte ptr [ei_delay], 0
    jmp done
op_pop:
    call pop16
    mov esi, eax
    mov edi, r12d
    shr edi, 4
    and edi, 3
    cmp edi, 3
    jne 1f
    and al, 0xf0
    mov byte ptr [reg_f], al
    shr eax, 8
    mov byte ptr [regs+7], al
    jmp 2f
1:  call put16
2:  mov r15d, 12
    jmp done
op_push:
    mov edi, r12d
    shr edi, 4
    and edi, 3
    cmp edi, 3
    jne 1f
    movzx eax, byte ptr [regs+7]
    shl eax, 8
    mov al, byte ptr [reg_f]
    jmp 2f
1:  call get16
2:  call push16
    mov r15d, 16
    jmp done
op_jp_cond:
    call fetch16
    mov r14d, eax
    mov r15d, 12
    mov edi, r12d
    shr edi, 3
    and edi, 3
    call condition
    jz done
    mov word ptr [reg_pc], r14w
    mov r15d, 16
    jmp done
op_jp:
    call fetch16
    mov word ptr [reg_pc], ax
    mov r15d, 16
    jmp done
op_jp_hl:
    mov edi, 2
    call get16
    mov word ptr [reg_pc], ax
    jmp done
op_call_cond:
    call fetch16
    mov r14d, eax
    mov r15d, 12
    mov edi, r12d
    shr edi, 3
    and edi, 3
    call condition
    jz done
    jmp .call_taken
op_call:
    call fetch16
    mov r14d, eax
.call_taken:
    movzx eax, word ptr [reg_pc]
    call push16
    mov word ptr [reg_pc], r14w
    mov r15d, 24
    jmp done
op_rst:
    movzx eax, word ptr [reg_pc]
    call push16
    mov eax, r12d
    and eax, 0x38
    mov word ptr [reg_pc], ax
    mov r15d, 16
    jmp done
op_alu_imm:
    call fetch8
    mov esi, eax
    mov edi, r12d
    shr edi, 3
    and edi, 7
    call alu8
    mov r15d, 8
    jmp done
op_ldh_imm:
    call fetch8
    lea edi, [rax+0xff00]
    mov r15d, 12
    jmp .ld_io
op_ldh_c:
    movzx edi, byte ptr [regs+1]
    add edi, 0xff00
    mov r15d, 8
    jmp .ld_io
op_ld_abs:
    call fetch16
    mov edi, eax
    mov r15d, 16
.ld_io:
    test r12d, 0x10
    jnz 1f
    movzx esi, byte ptr [regs+7]
    call bus_write
    jmp done
1:  call bus_read
    mov byte ptr [regs+7], al
    jmp done
op_sp_offset:
    call fetch8
    movsx esi, al
    movzx edx, word ptr [reg_sp]
    mov ecx, edx
    xor ecx, esi
    add esi, edx
    xor ecx, esi
    mov eax, ecx
    and ecx, 0x10
    shl ecx, 1
    and eax, 0x100
    shr eax, 4
    or eax, ecx
    mov byte ptr [reg_f], al
    mov r15d, 16
    cmp r12d, 0xe8
    jne 1f
    mov word ptr [reg_sp], si
    jmp done
1:  mov edi, 2
    call put16
    mov r15d, 12
    jmp done
op_sp_hl:
    mov edi, 2
    call get16
    mov word ptr [reg_sp], ax
    mov r15d, 8
    jmp done
op_di:
    mov byte ptr [ime], 0
    mov byte ptr [ei_delay], 0
    jmp done
op_ei:
    cmp byte ptr [ei_delay], 0
    jne done
    cmp byte ptr [ime], 0
    jne done
    mov byte ptr [ei_delay], 2
    jmp done

# EDI operation 0..7, ESI operand; ALU flag translation uses host AF/ZF/CF.
alu8:
    mov al, byte ptr [regs+7]
    movzx edx, byte ptr [reg_f]
    jmp qword ptr [alu_ops+rdi*8]
.alu_add:
    add al, sil
    jmp .arith_flags
.alu_adc:
    bt edx, 4
    adc al, sil
    jmp .arith_flags
.alu_sub:
    sub al, sil
    jmp .arith_flags
.alu_sbc:
    bt edx, 4
    sbb al, sil
    jmp .arith_flags
.arith_flags:
    lahf
    movzx edx, ah
    mov ecx, edx
    and edx, 0x50
    shl edx, 1
    and ecx, 1
    shl ecx, 4
    or edx, ecx
    cmp edi, 2
    jb .alu_store
    or edx, 0x40
    cmp edi, 7
    je .alu_flags_only
.alu_store:
    mov byte ptr [regs+7], al
.alu_flags_only:
    mov byte ptr [reg_f], dl
    ret
.alu_and:
    and al, sil
    mov edx, 0x20
    jmp .logic_flags
.alu_xor:
    xor al, sil
    mov edx, 0
    jmp .logic_flags
.alu_or:
    or al, sil
    mov edx, 0
.logic_flags:
    test al, al
    jnz .alu_store
    or edx, 0x80
    jmp .alu_store

op_cb:
    call fetch8
    mov r12d, eax
    mov r13d, eax
    and r13d, 7
    mov edi, r13d
    call get8
    mov r14d, eax
    mov r15d, 8
    cmp r13d, 6
    jne 1f
    mov r15d, 16
1:  mov edi, r12d
    shr edi, 3
    and edi, 7
    cmp r12d, 0x40
    jb .cb_rotate
    mov ecx, edi
    mov edx, 1
    shl edx, cl
    cmp r12d, 0x80
    jb .cb_bit
    cmp r12d, 0xc0
    jae .cb_set
    not edx
    and r14d, edx
    jmp .cb_store
.cb_set:
    or r14d, edx
    jmp .cb_store
.cb_bit:
    and byte ptr [reg_f], 0x10
    or byte ptr [reg_f], 0x20
    test r14d, edx
    jnz 1f
    or byte ptr [reg_f], 0x80
1:  cmp r13d, 6
    jne done
    mov r15d, 12
    jmp done
.cb_rotate:
    call rotate8
    mov r14d, eax
.cb_store:
    mov esi, r14d
    mov edi, r13d
    call put8
    jmp done
rotate8:
    movzx edx, byte ptr [reg_f]
    jmp qword ptr [rotate_ops+rdi*8]
.rlc:
    rol al, 1
    jmp .rot_flags
.rrc:
    ror al, 1
    jmp .rot_flags
.rl:
    bt edx, 4
    rcl al, 1
    jmp .rot_flags
.rr:
    bt edx, 4
    rcr al, 1
    jmp .rot_flags
.sla:
    shl al, 1
    jmp .rot_flags
.sra:
    sar al, 1
    jmp .rot_flags
.swap:
    rol al, 4
    clc
    jmp .rot_flags
.srl:
    shr al, 1
.rot_flags:
    setc dl
    shl dl, 4
    test al, al
    jnz 1f
    or dl, 0x80
1:  mov byte ptr [reg_f], dl
    movzx eax, al
    ret

.section .rodata
.balign 8
low_ops:
    .quad op_nop,op_ld16,op_indirect,op_incdec16,op_incdec8,op_incdec8,op_ld8imm,op_rotate_a
    .quad op_ld_sp_abs,op_addhl,op_indirect,op_incdec16,op_incdec8,op_incdec8,op_ld8imm,op_rotate_a
    .quad op_stop,op_ld16,op_indirect,op_incdec16,op_incdec8,op_incdec8,op_ld8imm,op_rotate_a
    .quad op_jr,op_addhl,op_indirect,op_incdec16,op_incdec8,op_incdec8,op_ld8imm,op_rotate_a
    .quad op_jr,op_ld16,op_indirect,op_incdec16,op_incdec8,op_incdec8,op_ld8imm,op_daa
    .quad op_jr,op_addhl,op_indirect,op_incdec16,op_incdec8,op_incdec8,op_ld8imm,op_cpl
    .quad op_jr,op_ld16,op_indirect,op_incdec16,op_incdec8,op_incdec8,op_ld8imm,op_scf
    .quad op_jr,op_addhl,op_indirect,op_incdec16,op_incdec8,op_incdec8,op_ld8imm,op_ccf
high_ops:
    .quad op_ret_cond,op_pop,op_jp_cond,op_jp,op_call_cond,op_push,op_alu_imm,op_rst
    .quad op_ret_cond,op_ret,op_jp_cond,op_cb,op_call_cond,op_call,op_alu_imm,op_rst
    .quad op_ret_cond,op_pop,op_jp_cond,op_bad,op_call_cond,op_push,op_alu_imm,op_rst
    .quad op_ret_cond,op_ret,op_jp_cond,op_bad,op_call_cond,op_bad,op_alu_imm,op_rst
    .quad op_ldh_imm,op_pop,op_ldh_c,op_bad,op_bad,op_push,op_alu_imm,op_rst
    .quad op_sp_offset,op_jp_hl,op_ld_abs,op_bad,op_bad,op_bad,op_alu_imm,op_rst
    .quad op_ldh_imm,op_pop,op_ldh_c,op_di,op_bad,op_push,op_alu_imm,op_rst
    .quad op_sp_offset,op_sp_hl,op_ld_abs,op_ei,op_bad,op_bad,op_alu_imm,op_rst
alu_ops:
    .quad .alu_add,.alu_adc,.alu_sub,.alu_sbc,.alu_and,.alu_xor,.alu_or,.alu_sub
rotate_ops:
    .quad .rlc,.rrc,.rl,.rr,.sla,.sra,.swap,.srl
