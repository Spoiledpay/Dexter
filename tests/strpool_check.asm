;=============================================================================
; Dexter/tests/strpool_check.asm
; Driver de teste do string pool (D-3): exercita strpool_new/add/get/free e
; o buffer subjacente (asmbuf). Golden ([44]): `STRPOOL o=0 6 B len=11`
; + exit 0. Retorno: 0 se confere internamente, 2 em divergencia.
;
; O quê: valida offsets estaveis (cada add anexa cstr+NUL), leitura por
;   offset (streq contra o esperado) e a borda de limite (off >= len -> 0).
; Por quê: strpool alimenta os nomes __imp_ sanitizados; sem teste dedicado
;   ele so era coberto de forma indireta pelo generate.
; Contrato: add(a)->0; add(b)->6; add(c)->11; len==17; get(0/6/11) confere;
;   get(17)==0.
;
; Requisitos atendidos: R-4.x (strpool) + D-3 (teste dedicado)
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

global main

extern GetStdHandle
extern WriteFile
extern ExitProcess
extern strpool_new
extern strpool_add
extern strpool_get
extern strpool_free
extern asmbuf_len
extern dex_streq

section .rodata
s_a      db "alpha", 0
s_b      db "beta", 0
s_c      db "gamma", 0
s_p0     db "STRPOOL o=", 0
s_sp     db " ", 0
s_plen   db " len=", 0
s_crlf   db 13, 10, 0

section .text

;-----------------------------------------------------------------------------
; main — 3 pushes + sub 64 => corpo rsp%16==0. hOut [rbp-32], pool [rbp-40],
; hex tmp 24B em [rbp-80,-57).
;-----------------------------------------------------------------------------
main:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 64
    mov ecx, -11
    sub rsp, 32
    call GetStdHandle
    add rsp, 32
    mov [rbp-32], rax              ; hOut

    mov ecx, 64
    sub rsp, 32
    call strpool_new
    add rsp, 32
    test rax, rax
    jz .fail
    mov [rbp-40], rax              ; pool

    ; add("alpha") -> 0
    mov rcx, [rbp-40]
    lea rdx, [rel s_a]
    sub rsp, 32
    call strpool_add
    add rsp, 32
    cmp rax, 0
    jne .fail
    ; add("beta") -> 6 (5 bytes + NUL)
    mov rcx, [rbp-40]
    lea rdx, [rel s_b]
    sub rsp, 32
    call strpool_add
    add rsp, 32
    cmp rax, 6
    jne .fail
    ; add("gamma") -> 11 (6 + 5)
    mov rcx, [rbp-40]
    lea rdx, [rel s_c]
    sub rsp, 32
    call strpool_add
    add rsp, 32
    cmp rax, 11
    jne .fail
    ; len == 17 (6 + 5 + 6)
    mov rcx, [rbp-40]
    sub rsp, 32
    call asmbuf_len
    add rsp, 32
    cmp rax, 17
    jne .fail

    ; get(0) == "alpha"
    mov rcx, [rbp-40]
    xor edx, edx
    sub rsp, 32
    call strpool_get
    add rsp, 32
    test rax, rax
    jz .fail
    mov rcx, rax
    lea rdx, [rel s_a]
    sub rsp, 32
    call dex_streq
    add rsp, 32
    test eax, eax
    jz .fail
    ; get(6) == "beta"
    mov rcx, [rbp-40]
    mov rdx, 6
    sub rsp, 32
    call strpool_get
    add rsp, 32
    test rax, rax
    jz .fail
    mov rcx, rax
    lea rdx, [rel s_b]
    sub rsp, 32
    call dex_streq
    add rsp, 32
    test eax, eax
    jz .fail
    ; get(11) == "gamma"
    mov rcx, [rbp-40]
    mov rdx, 11
    sub rsp, 32
    call strpool_get
    add rsp, 32
    test rax, rax
    jz .fail
    mov rcx, rax
    lea rdx, [rel s_c]
    sub rsp, 32
    call dex_streq
    add rsp, 32
    test eax, eax
    jz .fail
    ; get(17) == 0 (off >= len)
    mov rcx, [rbp-40]
    mov rdx, 17
    sub rsp, 32
    call strpool_get
    add rsp, 32
    test rax, rax
    jnz .fail

    ; imprime "STRPOOL o=0 6 B len=11"
    lea rcx, [rel s_p0]
    call .print_cstr
    xor r12d, r12d                 ; nao usado p/ loop; r12d livre
    xor ecx, ecx
    call .print_hex
    lea rcx, [rel s_sp]
    call .print_cstr
    mov rcx, 6
    call .print_hex
    lea rcx, [rel s_sp]
    call .print_cstr
    mov rcx, 11
    call .print_hex
    lea rcx, [rel s_plen]
    call .print_cstr
    mov rcx, 17
    call .print_hex
    lea rcx, [rel s_crlf]
    call .print_cstr

    mov rcx, [rbp-40]
    sub rsp, 32
    call strpool_free
    add rsp, 32
    xor ecx, ecx
    call ExitProcess
.fail:
    mov ecx, 2
    call ExitProcess

;-----------------------------------------------------------------------------
; Helpers (hOut [rbp-32]; hex tmp 24B em [rbp-80,-57)).
;-----------------------------------------------------------------------------
.print_cstr:
    push rbx
    mov rbx, rcx
    call .strlen_loc
    mov r8, rax
    mov rdx, rbx
    mov rcx, [rbp-32]
    sub rsp, 48
    mov qword [rsp+32], 0
    lea r9, [rsp+40]
    call WriteFile
    add rsp, 48
    pop rbx
    ret
.print_hex:
    push rbx
    mov rax, rcx
    lea rbx, [rbp-80]
    test rax, rax
    jnz .ph_conv
    mov byte [rbx], '0'
    mov r8, 1
    jmp .ph_wr
.ph_conv:
    sub rsp, 40
    xor r8d, r8d
.ph_l:
    mov r9, rax
    and r9d, 15
    shr rax, 4
    cmp r9d, 9
    jbe .ph_d
    add r9d, 55
    jmp .ph_s
.ph_d:
    add r9d, 48
.ph_s:
    mov [rsp+r8], r9b
    inc r8d
    test rax, rax
    jnz .ph_l
    mov rcx, r8
    xor r9d, r9d
.ph_r:
    dec r8
    mov dl, [rsp+r8]
    mov [rbx+r9], dl
    inc r9d
    test r8, r8
    jnz .ph_r
    mov r8, rcx
    add rsp, 40
.ph_wr:
    mov rdx, rbx
    mov rcx, [rbp-32]
    sub rsp, 48
    mov qword [rsp+32], 0
    lea r9, [rsp+40]
    call WriteFile
    add rsp, 48
    pop rbx
    ret
.strlen_loc:
    xor eax, eax
.sl_l:
    cmp byte [rcx+rax], 0
    je .sl_d
    inc rax
    jmp .sl_l
.sl_d:
    ret
