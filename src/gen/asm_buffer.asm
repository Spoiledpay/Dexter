;=============================================================================
; Dexter/src/gen/asm_buffer.asm
; AsmBuf — buffer dinâmico de saída (dex_realloc_grow).
;
; Requisitos atendidos: R-4.x
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "dexter.inc"

global asmbuf_new
global asmbuf_append
global asmbuf_append_str
global asmbuf_append_char
global asmbuf_append_u64_hex
global asmbuf_free
global asmbuf_len
global asmbuf_data

extern dex_malloc
extern dex_free
extern dex_realloc_grow
extern dex_strlen
extern dex_memcpy
extern dex_u64_to_hex

section .text

;-----------------------------------------------------------------------------
; asmbuf_new — rcx=cap_inicial (0 => 64KB) -> rax=AsmBuf* ou 0
;-----------------------------------------------------------------------------
asmbuf_new:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 32
    mov rbx, rcx
    test rbx, rbx
    jnz .cap_ok
    mov rbx, 0x10000
.cap_ok:
    mov rcx, 16                ; sizeof(AsmBuf)=24? 3 qwords = 24
    mov rcx, 24
    call dex_malloc
    test rax, rax
    jz .fail_n
    mov r12, rax
    mov rcx, rbx
    call dex_malloc
    test rax, rax
    jz .fail_data
    mov [r12+AsmBuf.data], rax
    mov qword [r12+AsmBuf.len], 0
    mov [r12+AsmBuf.cap], rbx
    mov rax, r12
    add rsp, 32
    pop r12
    pop rbx
    pop rbp
    ret
.fail_data:
    mov rcx, r12
    call dex_free
.fail_n:
    xor eax, eax
    add rsp, 32
    pop r12
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; asmbuf_append — rcx=buf, rdx=src, r8=n -> rax=0 ok, 1 OOM
;-----------------------------------------------------------------------------
asmbuf_append:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    sub rsp, 40
    test rcx, rcx
    jz .fail_a
    test r8, r8
    jz .ok_a
    test rdx, rdx
    jz .fail_a
    mov rbx, rcx               ; buf
    mov rsi, rdx               ; src
    mov r12, r8                ; n
    mov r13, [rbx+AsmBuf.len]
    mov rdi, [rbx+AsmBuf.cap]
    mov rax, r13
    add rax, r12
    cmp rax, rdi
    jbe .fit
    ; grow: new_cap via dex_realloc_grow(data, cap, len+n)
    mov rcx, [rbx+AsmBuf.data]
    mov rdx, rdi
    mov r8, rax
    call dex_realloc_grow      ; rax=ptr, rdx=cap
    test rax, rax
    jz .fail_a
    mov [rbx+AsmBuf.data], rax
    mov [rbx+AsmBuf.cap], rdx
.fit:
    mov rcx, [rbx+AsmBuf.data]
    add rcx, r13
    mov rdx, rsi
    mov r8, r12
    call dex_memcpy
    add r13, r12
    mov [rbx+AsmBuf.len], r13
.ok_a:
    xor eax, eax
    add rsp, 40
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret
.fail_a:
    mov eax, 1
    add rsp, 40
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; asmbuf_append_str — rcx=buf, rdx=cstr -> rax=0/1
;-----------------------------------------------------------------------------
asmbuf_append_str:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 32
    mov rbx, rcx
    mov r12, rdx
    mov rcx, rdx
    call dex_strlen
    mov r8, rax
    mov rdx, r12
    mov rcx, rbx
    call asmbuf_append
    add rsp, 32
    pop r12
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; asmbuf_append_char — rcx=buf, dl=char -> rax=0/1
;-----------------------------------------------------------------------------
asmbuf_append_char:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    mov [rbp-8], dl
    mov rdx, rbp
    sub rdx, 8
    mov r8, 1
    call asmbuf_append         ; frame: 1 push + 48 => rsp%16==0 ✓
    add rsp, 48
    pop rbp
    ret

;-----------------------------------------------------------------------------
; asmbuf_append_u64_hex — rcx=buf, rdx=valor, r8d=digits -> rax=0/1
;-----------------------------------------------------------------------------
asmbuf_append_u64_hex:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 88                ; 3 pushes -> rsp%16==8; 88%16==8 => calls ≡0.
                               ; (D-16 auditado: o "prólogo duplicado" descrito
                               ; em 2026-10-11 NÃO existe; o buffer antigo em
                               ; [rbp-40] cabia 16 dígitos e não tocava os regs
                               ; salvos. Buffer movido p/ [rbp-72] (32 B, acima
                               ; da shadow [rbp-112,-81]) => cobre digits<=32.)
    mov rbx, rcx
    mov r12, rdx
    mov r13d, r8d
    lea rdx, [rbp-72]
    mov rcx, r12
    mov r8d, r13d
    call dex_u64_to_hex        ; rax = len
    mov r8, rax
    lea rdx, [rbp-72]
    mov rcx, rbx
    call asmbuf_append
    add rsp, 88
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; asmbuf_free — rcx=buf
;-----------------------------------------------------------------------------
asmbuf_free:
    test rcx, rcx
    jz .done_f
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 40
    mov rbx, rcx
    mov rcx, [rbx+AsmBuf.data]
    call dex_free
    mov rcx, rbx
    call dex_free
    add rsp, 40
    pop rbx
    pop rbp
.done_f:
    ret

;-----------------------------------------------------------------------------
; asmbuf_len — rcx=buf -> rax=len
; asmbuf_data — rcx=buf -> rax=data
;-----------------------------------------------------------------------------
asmbuf_len:
    test rcx, rcx
    jz .z_l
    mov rax, [rcx+AsmBuf.len]
    ret
.z_l:
    xor eax, eax
    ret
asmbuf_data:
    test rcx, rcx
    jz .z_d
    mov rax, [rcx+AsmBuf.data]
    ret
.z_d:
    xor eax, eax
    ret
