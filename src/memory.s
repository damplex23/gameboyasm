.section .text
# bus_read: EDI address -> EAX byte. bus_write: EDI address, ESI byte.
bus_read:
    and edi, 0xffff
    cmp edi, 0x8000
    jb .read_rom
    cmp edi, 0xa000
    jb .read_plain
    cmp edi, 0xc000
    jb .read_ram
    cmp edi, 0xe000
    jb .read_plain
    cmp edi, 0xfe00
    jae 1f
    sub edi, 0x2000
    jmp .read_plain
1:  cmp edi, 0xfea0
    jb .read_plain
    cmp edi, 0xff00
    jb .read_ff
    je joy_read
    cmp edi, 0xff04
    je .read_div
    cmp edi, 0xff07
    je .read_tac
    cmp edi, 0xff0f
    je .read_if
    cmp edi, 0xff03
    je .read_ff
    cmp edi, 0xff08
    jb .read_plain
    cmp edi, 0xff0f
    jb .read_ff
    cmp edi, 0xff4c
    jb .read_plain
    cmp edi, 0xff80
    jb .read_ff
.read_plain:
    movzx eax, byte ptr [mem+rdi]
    ret
.read_div:
    movzx eax, byte ptr [div_counter+1]
    ret
.read_tac:
    movzx eax, byte ptr [mem+0xff07]
    or eax, 0xf8
    ret
.read_if:
    movzx eax, byte ptr [mem+0xff0f]
    or eax, 0xe0
    ret
.read_ff:
    mov eax, 255
    ret
.read_rom:
    mov eax, edi
    cmp byte ptr [mapper], 0
    je .rom_index
    and eax, 0x3fff
    xor ecx, ecx
    cmp edi, 0x4000
    jae 1f
    cmp byte ptr [bank_mode], 0
    je .rom_bank
    movzx ecx, byte ptr [bank_high]
    shl ecx, 5
    jmp .rom_bank
1:  movzx ecx, byte ptr [bank_high]
    shl ecx, 5
    movzx edx, byte ptr [bank_low]
    or ecx, edx
.rom_bank:
    shl ecx, 14
    or eax, ecx
.rom_index:
    and eax, dword ptr [rom_mask]
    movzx eax, byte ptr [rom+rax]
    ret
.read_ram:
    cmp dword ptr [ram_mask], 0
    je .read_ff
    cmp byte ptr [ram_enabled], 0
    je .read_ff
    call ram_index
    movzx eax, byte ptr [cart_ram+rax]
    ret
ram_index:
    mov eax, edi
    sub eax, 0xa000
    cmp byte ptr [bank_mode], 0
    je 1f
    movzx ecx, byte ptr [bank_high]
    shl ecx, 13
    or eax, ecx
1:  and eax, dword ptr [ram_mask]
    ret
joy_read:
    movzx eax, byte ptr [mem+0xff00]
    and eax, 0x30
    or eax, 0xcf
    movzx edx, byte ptr [joy_keys]
    not edx
    test eax, 0x10
    jnz 1f
    mov ecx, edx
    or ecx, 0xf0
    and eax, ecx
1:  test eax, 0x20
    jnz 2f
    shr edx, 4
    or edx, 0xf0
    and eax, edx
2:  ret

bus_write:
    and edi, 0xffff
    and esi, 255
    cmp edi, 0x8000
    jb .write_mapper
    cmp edi, 0xa000
    jb .write_plain
    cmp edi, 0xc000
    jb .write_ram
    cmp edi, 0xe000
    jb .write_plain
    cmp edi, 0xfe00
    jae 1f
    sub edi, 0x2000
    jmp .write_plain
1:  cmp edi, 0xfea0
    jb .write_plain
    cmp edi, 0xff00
    jb .write_done
    je .write_joy
    cmp edi, 0xff04
    je .write_div
    cmp edi, 0xff05
    je .write_tima
    cmp edi, 0xff07
    je .write_tac
    cmp edi, 0xff02
    je .write_serial
    cmp edi, 0xff40
    je .write_lcdc
    cmp edi, 0xff41
    je .write_stat
    cmp edi, 0xff44
    je .write_done
    cmp edi, 0xff45
    je .write_lyc
    cmp edi, 0xff46
    je .write_dma
.write_plain:
    mov byte ptr [mem+rdi], sil
.write_done:
    ret
.write_mapper:
    cmp byte ptr [mapper], 0
    je .write_done
    cmp edi, 0x2000
    jae 1f
    and esi, 15
    cmp esi, 10
    sete byte ptr [ram_enabled]
    ret
1:  cmp edi, 0x4000
    jae 2f
    and esi, 31
    jnz 3f
    inc esi
3:  mov byte ptr [bank_low], sil
    ret
2:  cmp edi, 0x6000
    jae 4f
    and esi, 3
    mov byte ptr [bank_high], sil
    ret
4:  and esi, 1
    mov byte ptr [bank_mode], sil
    ret
.write_ram:
    cmp dword ptr [ram_mask], 0
    je .write_done
    cmp byte ptr [ram_enabled], 0
    je .write_done
    call ram_index
    mov byte ptr [cart_ram+rax], sil
    ret
.write_joy:
    push rsi
    call joy_read
    push rax
    mov esi, dword ptr [rsp+8]
    mov byte ptr [mem+0xff00], sil
    call joy_read
    pop rdx
    pop rsi
    not eax
    and eax, edx
    test eax, 15
    jz .write_done
    or byte ptr [mem+0xff0f], 0x10
    ret
.write_div:
    call timer_signal
    push rax
    mov dword ptr [div_counter], 0
    jmp .timer_write_edge
.write_tac:
    push rsi
    call timer_signal
    pop rsi
    push rax
    and esi, 7
    mov byte ptr [mem+0xff07], sil
.timer_write_edge:
    call timer_signal
    pop rdx
    test edx, edx
    jz .write_done
    test eax, eax
    jnz .write_done
    jmp timer_increment
.write_tima:
    mov dword ptr [timer_reload], 0
    jmp .write_plain
.write_serial:
    mov byte ptr [mem+0xff02], sil
    and esi, 0x81
    cmp esi, 0x81
    jne .write_done
    mov dword ptr [serial_clock], 4096
    ret
.write_lcdc:
    mov al, byte ptr [mem+0xff40]
    mov byte ptr [mem+0xff40], sil
    xor eax, esi
    test eax, 0x80
    jz .write_done
    mov dword ptr [ppu_dot], 0
    mov byte ptr [mem+0xff44], 0
    mov dword ptr [window_line], 0
    mov byte ptr [stat_line], 0
    test esi, 0x80
    jnz stat_update
    push rdi
    lea rdi, [framebuffer]
    xor eax, eax
    mov ecx, 23040
    rep stosb
    pop rdi
    jmp stat_update
.write_stat:
    and esi, 0x78
    mov al, byte ptr [mem+0xff41]
    and eax, 7
    or eax, esi
    or eax, 0x80
    mov byte ptr [mem+0xff41], al
    jmp stat_update
.write_lyc:
    mov byte ptr [mem+0xff45], sil
    jmp stat_update
.write_dma:
    mov byte ptr [mem+0xff46], sil
    push r12
    push r13
    mov r12d, esi
    shl r12d, 8
    xor r13d, r13d
1:  lea edi, [r12+r13]
    call bus_read
    mov byte ptr [mem+0xfe00+r13], al
    inc r13d
    cmp r13d, 160
    jb 1b
    pop r13
    pop r12
    ret

# The timer is driven by a falling edge of a divider bit, including DIV/TAC
# writes. CPU bus accesses remain instruction-granular in this version.
timer_signal:
    xor eax, eax
    movzx ecx, byte ptr [mem+0xff07]
    test ecx, 4
    jz 1f
    and ecx, 3
    movzx ecx, byte ptr [timer_bits+rcx]
    mov eax, dword ptr [div_counter]
    shr eax, cl
    and eax, 1
1:  ret
timer_increment:
    cmp dword ptr [timer_reload], 0
    jne 1f
    inc byte ptr [mem+0xff05]
    jnz 1f
    mov dword ptr [timer_reload], 4
1:  ret
hardware_tick:                   # EDI elapsed T-cycles, always a multiple of 4
    push r12
    push r13
    mov r12d, edi
    add qword ptr [total_cycles], rdi
.tick_loop:
    cmp dword ptr [timer_reload], 0
    je 1f
    sub dword ptr [timer_reload], 4
    jne 1f
    mov al, byte ptr [mem+0xff06]
    mov byte ptr [mem+0xff05], al
    or byte ptr [mem+0xff0f], 4
1:  call timer_signal
    mov r13d, eax
    add dword ptr [div_counter], 4
    call timer_signal
    test r13d, r13d
    jz 2f
    test eax, eax
    jnz 2f
    call timer_increment
2:  cmp dword ptr [serial_clock], 0
    je 3f
    sub dword ptr [serial_clock], 4
    jnz 3f
    cmp byte ptr [serial_enabled], 0
    je 4f
    mov edi, 1
    lea rsi, [mem+0xff01]
    mov edx, 1
    call write_all
4:  mov byte ptr [mem+0xff01], 0xff
    and byte ptr [mem+0xff02], 0x7f
    or byte ptr [mem+0xff0f], 8
3:  call ppu_tick
    sub r12d, 4
    jnz .tick_loop
    pop r13
    pop r12
    ret
.section .rodata
timer_bits: .byte 9,3,5,7
