# Linux x86-64 syscalls only: no libc, dynamic loader, SDL, or libX11.
.section .bss
.balign 8
frame_limit: .skip 8
dump_path: .skip 8
terminal_active: .skip 1
stop_requested: .skip 1
.balign 8
old_termios: .skip 36
raw_termios: .skip 36
win_size: .skip 8
next_frame: .skip 16
input_bytes: .skip 128
key_ttl: .skip 8
terminal_buffer: .skip 35000
pgm_pixels: .skip 23040
.section .data
signal_action:
    .quad signal_stop, 0x04000000, signal_restorer, 0
.section .rodata
usage:
    .ascii "GameboyASM - assembly-only DMG emulator for Linux x86-64\n"
    .ascii "Usage: build/gameboy ROM.gb [--frames N] [--dump image.pgm]\n"
    .ascii "Without --frames: interactive ANSI terminal (at least 80x37).\n"
    .ascii "WASD: directions, J/K: A/B, U/I: Select/Start, Q: quit.\n"
    .ascii "--frames N: run N emulated frame periods, serial output to stdout.\n"
usage_end:
rom_error: .ascii "Cannot read ROM (need a regular, complete 32 KiB-2 MiB image).\n"
rom_error_end:
cart_error: .ascii "Unsupported cartridge: use DMG ROM-only or MBC1 (types 00-03).\n"
cart_error_end:
terminal_error: .ascii "Need an ANSI terminal of at least 80 columns x 37 rows; or use --frames N.\n"
terminal_error_end:
dump_error: .ascii "Cannot create or write frame dump.\n"
dump_error_end:
terminal_enter: .ascii "\033[?1049h\033[?25l\033[2J\033[H"
terminal_enter_end:
terminal_leave: .ascii "\033[0m\033[?25h\033[?1049l"
terminal_leave_end:
# Exactly twelve bytes per cell, ANSI 256-color background + space.
cell_colors:
    .ascii "\033[48;5;194m "
    .ascii "\033[48;5;151m "
    .ascii "\033[48;5;065m "
    .ascii "\033[48;5;022m "
footer: .ascii "\033[0mWASD move | J/K A/B | U/I Select/Start | Q quit\033[K"
footer_end:
pgm_header: .ascii "P5\n160 144\n255\n"
pgm_header_end:
gray_palette: .byte 255,170,85,0
hex_digits: .ascii "0123456789ABCDEF"
key_chars: .ascii "dawsjkui"
.section .text
str_equal:
    mov al, byte ptr [rdi]
    cmp al, byte ptr [rsi]
    jne 1f
    inc rdi
    inc rsi
    test al, al
    jnz str_equal
    mov eax, 1
    ret
1:  xor eax, eax
    ret
parse_number:
    xor eax, eax
    cmp byte ptr [rdi], 0
    je usage_error
1:  movzx edx, byte ptr [rdi]
    test edx, edx
    jz 2f
    sub edx, '0'
    cmp edx, 9
    ja usage_error
    imul rax, rax, 10
    add rax, rdx
    cmp rax, 10000000
    ja usage_error
    inc rdi
    jmp 1b
2:  ret
hex_byte:
    mov edx, eax
    shr edx, 4
    and eax, 15
    mov dl, byte ptr [hex_digits+rdx]
    mov byte ptr [rdi], dl
    mov al, byte ptr [hex_digits+rax]
    mov byte ptr [rdi+1], al
    ret
write_all:                      # EDI fd, RSI bytes, RDX length -> EAX 0/-errno
    test rdx, rdx
    jz 3f
1:  mov eax, 1
    syscall
    cmp rax, -4                 # EINTR
    je 1b
    test rax, rax
    js 2f
    jz 4f
    add rsi, rax
    sub rdx, rax
    jnz 1b
3:  xor eax, eax
2:  ret
4:  mov eax, -5
    ret
show_help:
    mov edi, 1
    lea rsi, [usage]
    mov edx, usage_end-usage
    call write_all
    xor edi, edi
    jmp exit_process
usage_error:
    lea rsi, [usage]
    mov edx, usage_end-usage
fatal:
    mov edi, 2
    call write_all
    mov edi, 1
exit_process:
    mov eax, 60
    syscall

load_rom:
    push r12
    push r13
    mov eax, 2                  # open O_RDONLY | O_NONBLOCK (reject FIFOs)
    mov esi, 0x800
    xor edx, edx
    syscall
    test rax, rax
    js .rom_fail
    mov r12d, eax
    xor r13d, r13d
.rom_read:
    mov edi, r12d
    lea rsi, [rom+r13]
    mov edx, 2097153
    sub rdx, r13
    mov eax, 0
    syscall
    cmp rax, -4
    je .rom_read
    test rax, rax
    js .rom_close_fail
    jz .rom_loaded
    add r13, rax
    cmp r13, 2097152
    ja .rom_close_fail
    jmp .rom_read
.rom_loaded:
    mov eax, 3
    mov edi, r12d
    syscall
    cmp r13, 32768
    jb .rom_fail
    movzx ecx, byte ptr [rom+0x148]
    cmp ecx, 6
    ja .cart_fail
    mov eax, 32768
    shl eax, cl
    cmp r13, rax
    jne .rom_fail
    mov qword ptr [rom_size], r13
    dec eax
    mov dword ptr [rom_mask], eax
    cmp byte ptr [rom+0x143], 0xc0
    je .cart_fail
    movzx eax, byte ptr [rom+0x147]
    cmp eax, 3
    ja .cart_fail
    mov byte ptr [mapper], al
    test eax, eax
    jnz 1f
    cmp r13, 32768
    jne .cart_fail
1:  mov dword ptr [ram_mask], 0
    cmp eax, 2
    jb .rom_ok
    movzx eax, byte ptr [rom+0x149]
    test eax, eax
    jz .rom_ok
    cmp eax, 2
    je 2f
    cmp eax, 3
    jne .cart_fail
    mov dword ptr [ram_mask], 32767
    jmp .rom_ok
2:  mov dword ptr [ram_mask], 8191
.rom_ok:
    pop r13
    pop r12
    ret
.rom_close_fail:
    mov edi, r12d
    mov eax, 3
    syscall
.rom_fail:
    lea rsi, [rom_error]
    mov edx, rom_error_end-rom_error
    jmp fatal
.cart_fail:
    lea rsi, [cart_error]
    mov edx, cart_error_end-cart_error
    jmp fatal

terminal_init:
    mov eax, 16                 # ioctl stdout TIOCGWINSZ
    mov edi, 1
    mov esi, 0x5413
    lea rdx, [win_size]
    syscall
    test rax, rax
    js .terminal_fail
    cmp word ptr [win_size], 37
    jb .terminal_fail
    cmp word ptr [win_size+2], 80
    jb .terminal_fail
    mov eax, 16
    xor edi, edi
    mov esi, 0x5401             # TCGETS
    lea rdx, [old_termios]
    syscall
    test rax, rax
    js .terminal_fail
    lea rsi, [old_termios]
    lea rdi, [raw_termios]
    mov ecx, 36
    rep movsb
    and dword ptr [raw_termios], ~0x532
    and dword ptr [raw_termios+4], ~1
    and dword ptr [raw_termios+12], ~0x800b
    mov byte ptr [raw_termios+22], 0 # VTIME
    mov byte ptr [raw_termios+23], 0 # VMIN
    mov eax, 16
    xor edi, edi
    mov esi, 0x5402             # TCSETS
    lea rdx, [raw_termios]
    syscall
    test rax, rax
    js .terminal_fail
    mov byte ptr [terminal_active], 1
    mov edi, 2                  # SIGINT
    call install_handler
    mov edi, 15                 # SIGTERM
    call install_handler
    mov edi, 1                  # SIGHUP
    call install_handler
    mov edi, 20                 # SIGTSTP: exit cleanly, don't leave terminal raw
    call install_handler
    mov edi, 1
    lea rsi, [terminal_enter]
    mov edx, terminal_enter_end-terminal_enter
    call write_all
    mov eax, 228                # clock_gettime CLOCK_MONOTONIC
    mov edi, 1
    lea rsi, [next_frame]
    syscall
    ret
.terminal_fail:
    lea rsi, [terminal_error]
    mov edx, terminal_error_end-terminal_error
    jmp fatal
install_handler:
    mov eax, 13
    lea rsi, [signal_action]
    xor edx, edx
    mov r10d, 8
    syscall
    ret
signal_stop:
    mov byte ptr [stop_requested], 1
    ret
signal_restorer:
    mov eax, 15
    syscall
terminal_restore:
    cmp byte ptr [terminal_active], 0
    je 1f
    mov eax, 16
    xor edi, edi
    mov esi, 0x5402
    lea rdx, [old_termios]
    syscall
    mov byte ptr [terminal_active], 0
    mov edi, 1
    lea rsi, [terminal_leave]
    mov edx, terminal_leave_end-terminal_leave
    call write_all
1:  ret
terminal_input:
    push r12
    push r13
    xor ecx, ecx
1:  cmp byte ptr [key_ttl+rcx], 0
    je 2f
    dec byte ptr [key_ttl+rcx]
2:  inc ecx
    cmp ecx, 8
    jb 1b
    xor eax, eax
    xor edi, edi
    lea rsi, [input_bytes]
    mov edx, 128
    syscall
    test rax, rax
    jle .keys_build
    mov r12, rax
    xor r13d, r13d
.key_next:
    mov al, byte ptr [input_bytes+r13]
    cmp al, 3
    je .key_quit
    or al, 0x20
    cmp al, 'q'
    je .key_quit
    xor ecx, ecx
1:  cmp al, byte ptr [key_chars+rcx]
    jne 2f
    mov byte ptr [key_ttl+rcx], 12 # terminal has no release events (~200ms hold)
2:  inc ecx
    cmp ecx, 8
    jb 1b
    jmp .key_advance
.key_quit:
    mov byte ptr [stop_requested], 1
.key_advance:
    inc r13
    cmp r13, r12
    jb .key_next
.keys_build:
    call joy_read
    mov r12d, eax
    xor ecx, ecx
    xor edx, edx
1:  cmp byte ptr [key_ttl+rcx], 0
    je 2f
    bts edx, ecx
2:  inc ecx
    cmp ecx, 8
    jb 1b
    mov byte ptr [joy_keys], dl
    call joy_read
    not eax
    and eax, r12d
    test eax, 15
    jz 1f
    or byte ptr [mem+0xff0f], 0x10
    mov byte ptr [halted], 0
1:  pop r13
    pop r12
    ret
pace_frame:
    add qword ptr [next_frame+8], 16742706 # 70224 / 4194304 seconds
    cmp qword ptr [next_frame+8], 1000000000
    jb 1f
    sub qword ptr [next_frame+8], 1000000000
    inc qword ptr [next_frame]
1:  mov eax, 230                # clock_nanosleep, absolute deadline
    mov edi, 1
    mov esi, 1
    lea rdx, [next_frame]
    xor r10d, r10d
    syscall
    ret
terminal_draw:
    push r12
    push r13
    push r14
    lea rdi, [terminal_buffer]
    mov byte ptr [rdi], 27
    mov word ptr [rdi+1], 0x485b # [H
    add rdi, 3
    xor r12d, r12d              # y (groups of four)
.terminal_row:
    xor r13d, r13d              # x (groups of two)
.terminal_cell:
    imul eax, r12d, 160
    add eax, r13d
    lea rsi, [framebuffer+rax]
    xor eax, eax
    mov ecx, 4
1:  movzx edx, byte ptr [rsi]
    add eax, edx
    movzx edx, byte ptr [rsi+1]
    add eax, edx
    add rsi, 160
    loop 1b
    add eax, 4
    shr eax, 3
    imul eax, eax, 12
    lea rsi, [cell_colors+rax]
    mov ecx, 12
    rep movsb
    add r13d, 2
    cmp r13d, 160
    jb .terminal_cell
    mov word ptr [rdi], 0x0a0d
    add rdi, 2
    add r12d, 4
    cmp r12d, 144
    jb .terminal_row
    lea rsi, [footer]
    mov ecx, footer_end-footer
    rep movsb
    mov rdx, rdi
    lea rsi, [terminal_buffer]
    sub rdx, rsi
    mov edi, 1
    call write_all
    test eax, eax
    jns 1f
    mov byte ptr [stop_requested], 1
1:  pop r14
    pop r13
    pop r12
    ret
dump_frame:
    push r12
    mov eax, 2
    mov rdi, qword ptr [dump_path]
    mov esi, 0x241              # O_WRONLY | O_CREAT | O_TRUNC
    mov edx, 0644
    syscall
    test rax, rax
    js .dump_fail
    mov r12d, eax
    mov edi, eax
    lea rsi, [pgm_header]
    mov edx, pgm_header_end-pgm_header
    call write_all
    test eax, eax
    js .dump_close_fail
    xor ecx, ecx
1:  movzx eax, byte ptr [framebuffer+rcx]
    mov al, byte ptr [gray_palette+rax]
    mov byte ptr [pgm_pixels+rcx], al
    inc ecx
    cmp ecx, 23040
    jb 1b
    mov edi, r12d
    lea rsi, [pgm_pixels]
    mov edx, 23040
    call write_all
    test eax, eax
    js .dump_close_fail
    mov eax, 3
    mov edi, r12d
    syscall
    test eax, eax
    js .dump_fail
    pop r12
    ret
.dump_close_fail:
    mov eax, 3
    mov edi, r12d
    syscall
.dump_fail:
    lea rsi, [dump_error]
    mov edx, dump_error_end-dump_error
    jmp fatal
