;=============================================================================
; Dexter/src/gen/strings.asm
; Pool de strings com offset estável (usado p/ nomes __imp_ sanitizados).
; Implementado sobre AsmBuf (mesmo layout: data/len/cap).
;
; Requisitos atendidos: R-4.x (pool de strings)
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "dexter.inc"

global strpool_new
global strpool_add
global strpool_get
global strpool_free

extern asmbuf_new
extern asmbuf_append
extern asmbuf_free
extern dex_strlen

section .text

;-----------------------------------------------------------------------------
; strpool_new — rcx=cap -> rax=pool* ou 0
;-----------------------------------------------------------------------------
strpool_new:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    call asmbuf_new
    add rsp, 32
    pop rbp
    ret

;-----------------------------------------------------------------------------
; strpool_add — rcx=pool, rdx=cstr -> rax=offset ou -1
; Anexa bytes + NUL.
;-----------------------------------------------------------------------------
strpool_add:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 40
    mov rbx, rcx
    mov r12, rdx
    test rbx, rbx
    jz .fail_p
    test r12, r12
    jz .fail_p
    mov rax, [rbx+AsmBuf.len]
    mov r13, rax               ; offset de retorno
    mov rcx, r12
    call dex_strlen
    lea r8, [rax+1]            ; +NUL
    mov rcx, rbx
    mov rdx, r12
    call asmbuf_append
    test eax, eax
    jnz .fail_p
    mov rax, r13
    add rsp, 40
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.fail_p:
    mov rax, -1
    add rsp, 40
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; strpool_get — rcx=pool, rdx=off -> rax=ptr ou 0 (valida limite)
;-----------------------------------------------------------------------------
strpool_get:
    test rcx, rcx
    jz .z_g
    cmp rdx, [rcx+AsmBuf.len]
    jae .z_g
    mov rax, [rcx+AsmBuf.data]
    add rax, rdx
    ret
.z_g:
    xor eax, eax
    ret

;-----------------------------------------------------------------------------
; strpool_free — rcx=pool
;-----------------------------------------------------------------------------
strpool_free:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    call asmbuf_free
    add rsp, 32
    pop rbp
    ret
