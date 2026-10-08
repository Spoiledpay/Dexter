;=============================================================================
; Dexter/src/util/string.asm
; Utilidades de string/memória sem CRT.
;
; Requisitos atendidos: R-0.3 (strlen/memcmp/hex usados por CLI e emitter)
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

global dex_strlen
global dex_memcmp
global dex_memcpy
global dex_streq
global dex_parse_hex_u64
global dex_u64_to_dec
global dex_u64_to_hex

section .text

;-----------------------------------------------------------------------------
; dex_strlen
; Args:   rcx = str (NUL-terminada, pode ser 0)
; Ret:    rax = len (cap 1MiB)
;-----------------------------------------------------------------------------
dex_strlen:
    xor eax, eax
    test rcx, rcx
    jz .done
.L_len:
    cmp rax, 0x100000
    jae .done
    movzx edx, byte [rcx+rax]
    test dl, dl
    jz .done
    inc rax
    jmp .L_len
.done:
    ret

;-----------------------------------------------------------------------------
; dex_memcmp
; Args:   rcx=a, rdx=b, r8=len
; Ret:    rax = 0 igual, !=0 diferente
;-----------------------------------------------------------------------------
dex_memcmp:
    xor eax, eax
    test r8, r8
    jz .done_c
    push rbx
    push rsi
    push rdi
    mov rsi, rcx
    mov rdi, rdx
    mov rcx, r8
.L_cmp:
    mov bl, [rsi]
    mov bh, [rdi]
    cmp bl, bh
    jne .diff_c
    inc rsi
    inc rdi
    dec rcx
    jnz .L_cmp
    xor eax, eax
    pop rdi
    pop rsi
    pop rbx
.done_c:
    ret
.diff_c:
    movzx eax, bl
    movzx edx, bh
    sub eax, edx
    pop rdi
    pop rsi
    pop rbx
    ret

;-----------------------------------------------------------------------------
; dex_memcpy
; Args:   rcx=dst, rdx=src, r8=len (sem overlap)
; Ret:    rax = dst
;-----------------------------------------------------------------------------
dex_memcpy:
    mov rax, rcx
    test r8, r8
    jz .done_m
    push rsi
    push rdi
    push rbx
    mov rsi, rdx
    mov rdi, rax
    mov rbx, rax
    mov rcx, r8
    rep movsb
    mov rax, rbx
    pop rbx
    pop rdi
    pop rsi
.done_m:
    ret

;-----------------------------------------------------------------------------
; dex_streq
; Args:   rcx=a, rdx=b (NUL-terminadas)
; Ret:    rax = 1 iguais, 0 diferentes
;-----------------------------------------------------------------------------
dex_streq:
    push rbx
.L_eq:
    movzx eax, byte [rcx]
    movzx r8d, byte [rdx]
    cmp al, r8b
    jne .no_eq
    test al, al
    jz .yes_eq
    inc rcx
    inc rdx
    jmp .L_eq
.yes_eq:
    mov eax, 1
    pop rbx
    ret
.no_eq:
    xor eax, eax
    pop rbx
    ret

;-----------------------------------------------------------------------------
; dex_parse_hex_u64
; Aceita "0x1A", "1A", "1Ah".
; Args:   rcx = str
; Ret:    rax = valor, rdx = 1 ok / 0 invalido
;-----------------------------------------------------------------------------
dex_parse_hex_u64:
    push rbx
    push rsi
    xor eax, eax
    xor edx, edx
    test rcx, rcx
    jz .fail_p
    mov rsi, rcx
    cmp byte [rsi], 0
    je .fail_p
    cmp word [rsi], 0x7830
    je .skip2_p
    cmp word [rsi], 0x5830
    je .skip2_p
    jmp .digits_p
.skip2_p:
    add rsi, 2
.digits_p:
    xor ebx, ebx
    xor eax, eax
.L_p:
    movzx ecx, byte [rsi]
    test cl, cl
    jz .end_p
    cmp cl, 104
    je .endh_p
    cmp cl, 72
    je .endh_p
    cmp cl, 48
    jb .fail_p
    cmp cl, 57
    jbe .d09_p
    cmp cl, 97
    jb .up_p
    cmp cl, 102
    jbe .daf_p
    jmp .fail_p
.up_p:
    cmp cl, 65
    jb .fail_p
    cmp cl, 70
    ja .fail_p
    sub cl, 55
    jmp .acc_p
.d09_p:
    sub cl, 48
    jmp .acc_p
.daf_p:
    sub cl, 87
.acc_p:
    shl rax, 4
    movzx ecx, cl
    or rax, rcx
    inc rbx
    cmp rbx, 16
    ja .fail_p
    inc rsi
    jmp .L_p
.endh_p:
    inc rsi
    cmp byte [rsi], 0
    jne .fail_p
.end_p:
    test ebx, ebx
    jz .fail_p
    mov edx, 1
    pop rsi
    pop rbx
    ret
.fail_p:
    xor eax, eax
    xor edx, edx
    pop rsi
    pop rbx
    ret

;-----------------------------------------------------------------------------
; dex_u64_to_dec
; Args:   rcx=valor, rdx=buf (min 21 bytes)
; Ret:    rax = len (sem NUL)
;-----------------------------------------------------------------------------
dex_u64_to_dec:
    push rbx
    push rdi
    mov rax, rcx
    mov rdi, rdx
    test rax, rax
    jnz .conv_d
    mov byte [rdi], 48
    mov eax, 1
    pop rdi
    pop rbx
    ret
.conv_d:
    sub rsp, 40
    mov rbx, rsp
    xor ecx, ecx
.L_d:
    xor edx, edx
    mov r8d, 10
    div r8
    add dl, 48
    mov [rbx+rcx], dl
    inc rcx
    test rax, rax
    jnz .L_d
    mov r8, rcx
    mov rax, rcx
.dec_d:
    dec rcx
    mov dl, [rbx+rcx]
    mov [rdi], dl
    inc rdi
    test rcx, rcx
    jnz .dec_d
    add rsp, 40
    mov rax, r8
    pop rdi
    pop rbx
    ret

;-----------------------------------------------------------------------------
; dex_u64_to_hex
; Args:   rcx=valor, rdx=buf, r8d=digits (0=sem pad)
; Ret:    rax = len
;-----------------------------------------------------------------------------
dex_u64_to_hex:
    push rbx
    push rdi
    push r12
    push r13
    mov rax, rcx
    mov rdi, rdx
    mov r12d, r8d
    sub rsp, 40
    mov rbx, rsp
    xor ecx, ecx
    test rax, rax
    jnz .conv_h
    mov byte [rbx], 48
    mov ecx, 1
    jmp .pad_h
.conv_h:
.L_h:
    mov r13, rax
    and r13, 15
    shr rax, 4
    cmp r13, 9
    jbe .n_h
    add r13, 55
    jmp .s_h
.n_h:
    add r13, 48
.s_h:
    mov [rbx+rcx], r13b
    inc rcx
    test rax, rax
    jnz .L_h
.pad_h:
    cmp ecx, r12d
    jae .out_h
    mov r8d, r12d
    sub r8d, ecx
    cmp r8d, 32
    ja .out_h
.z_h:
    mov byte [rbx+rcx], 48
    inc rcx
    dec r8d
    jnz .z_h
.out_h:
    mov r8, rcx
    mov rax, rcx
.rev_h:
    dec rcx
    mov dl, [rbx+rcx]
    mov [rdi], dl
    inc rdi
    test rcx, rcx
    jnz .rev_h
    add rsp, 40
    mov rax, r8
    pop r13
    pop r12
    pop rdi
    pop rbx
    ret
