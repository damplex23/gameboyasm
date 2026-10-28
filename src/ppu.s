.section .text
ppu_tick:
    test byte ptr [mem+0xff40], 0x80
    jz .ppu_done
    add dword ptr [ppu_dot], 4
    cmp dword ptr [ppu_dot], 252
    jne 1f
    cmp byte ptr [mem+0xff44], 144
    jae 1f
    call render_line
1:  cmp dword ptr [ppu_dot], 456
    jb stat_update
    mov dword ptr [ppu_dot], 0
    inc byte ptr [mem+0xff44]
    cmp byte ptr [mem+0xff44], 144
    jne 2f
    or byte ptr [mem+0xff0f], 1
    inc qword ptr [frame_count]
2:  cmp byte ptr [mem+0xff44], 154
    jb stat_update
    mov byte ptr [mem+0xff44], 0
    mov dword ptr [window_line], 0
    jmp stat_update
.ppu_done:
    ret

# Combined STAT interrupt line: request only on a low-to-high edge.
stat_update:
    movzx edx, byte ptr [mem+0xff41]
    and edx, 0xf8
    or edx, 0x80
    movzx eax, byte ptr [mem+0xff44]
    cmp al, byte ptr [mem+0xff45]
    jne 1f
    or edx, 4
1:  xor esi, esi
    test byte ptr [mem+0xff40], 0x80
    jz .stat_save
    cmp eax, 144
    jae .stat_vblank
    cmp dword ptr [ppu_dot], 80
    jb .stat_oam
    cmp dword ptr [ppu_dot], 252
    jb .stat_draw
    test edx, 8
    setnz sil
    jmp .stat_lyc
.stat_vblank:
    or edx, 1
    test edx, 0x10
    setnz sil
    jmp .stat_lyc
.stat_oam:
    or edx, 2
    test edx, 0x20
    setnz sil
    jmp .stat_lyc
.stat_draw:
    or edx, 3
.stat_lyc:
    mov eax, edx
    and eax, 0x44
    cmp eax, 0x44
    jne .stat_save
    mov esi, 1
.stat_save:
    mov byte ptr [mem+0xff41], dl
    cmp sil, byte ptr [stat_line]
    je 1f
    mov byte ptr [stat_line], sil
    test esi, esi
    jz 1f
    or byte ptr [mem+0xff0f], 2
1:  ret

# Scanline renderer: BG/window, then up to ten selected OBJs. Smaller OBJ X
# wins; equal X preserves OAM order. Raw BG colors determine OBJ masking.
render_line:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    movzx r12d, byte ptr [mem+0xff44]
    imul r13d, r12d, 160
    lea r13, [framebuffer+r13]
    movzx r14d, byte ptr [mem+0xff40]
    xor ebx, ebx                # screen X
    xor ebp, ebp                # window used this line
.bg_pixel:
    xor eax, eax
    test r14d, 1
    jz .bg_blank
    movzx esi, byte ptr [mem+0xff43]
    add esi, ebx
    and esi, 255
    movzx edi, byte ptr [mem+0xff42]
    add edi, r12d
    and edi, 255
    mov r8d, 0x9800
    test r14d, 8
    jz 1f
    mov r8d, 0x9c00
1:  test r14d, 0x20
    jz .tile_pixel
    movzx eax, byte ptr [mem+0xff4a]
    cmp r12d, eax
    jb .tile_pixel
    movzx eax, byte ptr [mem+0xff4b]
    sub eax, 7
    cmp ebx, eax
    jl .tile_pixel
    mov esi, ebx
    sub esi, eax
    mov edi, dword ptr [window_line]
    mov ebp, 1
    mov r8d, 0x9800
    test r14d, 0x40
    jz .tile_pixel
    mov r8d, 0x9c00
.tile_pixel:
    mov eax, edi
    shr eax, 3
    shl eax, 5
    mov ecx, esi
    shr ecx, 3
    add eax, ecx
    add eax, r8d
    movzx eax, byte ptr [mem+rax]
    test r14d, 0x10
    jz 1f
    shl eax, 4
    add eax, 0x8000
    jmp 2f
1:  movsx eax, al
    shl eax, 4
    add eax, 0x9000
2:  and edi, 7
    lea eax, [rax+rdi*2]
    and esi, 7
    mov ecx, 7
    sub ecx, esi
    movzx edx, byte ptr [mem+rax]
    movzx eax, byte ptr [mem+rax+1]
    shr edx, cl
    shr eax, cl
    and eax, 1
    and edx, 1
    lea eax, [rdx+rax*2]
    mov byte ptr [bg_line+rbx], al
    lea ecx, [rax+rax]
    movzx eax, byte ptr [mem+0xff47]
    shr eax, cl
    and eax, 3
    jmp .bg_store
.bg_blank:
    mov byte ptr [bg_line+rbx], 0
.bg_store:
    mov byte ptr [r13+rbx], al
    mov byte ptr [obj_owner+rbx], 255
    inc ebx
    cmp ebx, 160
    jb .bg_pixel
    add dword ptr [window_line], ebp
    test r14d, 2
    jz .render_done
    xor ebx, ebx                # OAM byte offset
    xor ebp, ebp                # selected objects count
.obj_next:
    movzx eax, byte ptr [mem+0xfe00+rbx]
    sub eax, 16
    mov esi, r12d
    sub esi, eax                # row in object
    mov r15d, 8
    test r14d, 4
    jz 1f
    mov r15d, 16
1:  cmp esi, r15d
    jae .obj_skip
    inc ebp
    cmp ebp, 10
    ja .render_done
    movzx r8d, byte ptr [mem+0xfe01+rbx] # hardware X
    movzx r9d, byte ptr [mem+0xfe03+rbx] # attributes
    test r9d, 0x40
    jz 2f
    dec r15d
    sub r15d, esi
    mov esi, r15d
2:  movzx eax, byte ptr [mem+0xfe02+rbx]
    test r14d, 4
    jz 3f
    and eax, 0xfe
3:  shl eax, 4
    lea eax, [rax+rsi*2+0x8000]
    movzx r10d, byte ptr [mem+rax]
    movzx r11d, byte ptr [mem+rax+1]
    xor edi, edi                # local X
.obj_pixel:
    lea esi, [r8+rdi-8]
    cmp esi, 160
    jae .obj_pixel_next
    mov ecx, 7
    sub ecx, edi
    test r9d, 0x20
    jz 1f
    mov ecx, edi
1:  mov eax, r11d
    mov edx, r10d
    shr eax, cl
    shr edx, cl
    and eax, 1
    and edx, 1
    lea eax, [rdx+rax*2]
    test eax, eax
    jz .obj_pixel_next
    cmp byte ptr [obj_owner+rsi], r8b
    jbe .obj_pixel_next
    mov byte ptr [obj_owner+rsi], r8b
    test r9d, 0x80
    jz 2f
    cmp byte ptr [bg_line+rsi], 0
    jne .obj_restore_bg
2:  lea ecx, [rax+rax]
    movzx eax, byte ptr [mem+0xff48]
    test r9d, 0x10
    jz 3f
    movzx eax, byte ptr [mem+0xff49]
3:  shr eax, cl
    and eax, 3
    mov byte ptr [r13+rsi], al
    jmp .obj_pixel_next
.obj_restore_bg:                # a higher-priority masked OBJ hides lower OBJs
    movzx ecx, byte ptr [bg_line+rsi]
    add ecx, ecx
    movzx eax, byte ptr [mem+0xff47]
    shr eax, cl
    and eax, 3
    mov byte ptr [r13+rsi], al
.obj_pixel_next:
    inc edi
    cmp edi, 8
    jb .obj_pixel
.obj_skip:
    add ebx, 4
    cmp ebx, 160
    jb .obj_next
.render_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
