;=============================================================================
; Dexter/src/gen/labels.asm
; Geração de nomes de label determinísticos: "label_<VA hex>" p/ código e
; "__imp_<dll>_<func>" p/ imports (sanitizado).
;
; Requisitos atendidos: R-4.x (labels)
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "dexter.inc"

global dex_label_emit_va
global dex_label_emit_imp
global dex_sanitize_append

extern asmbuf_append
extern asmbuf_append_str
extern asmbuf_append_char
extern asmbuf_append_u64_hex

section .rodata
s_label_pre2 db "label_", 0
s_imp_pre    db "__imp_", 0
s_us         db "_", 0

section .text

;-----------------------------------------------------------------------------
; dex_label_emit_va — rcx=buf, rdx=va -> "label_<hex>". rax=0/1.
;-----------------------------------------------------------------------------
dex_label_emit_va:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 32
    mov rbx, rcx
    mov r12, rdx
    lea rdx, [rel s_label_pre2]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fail_v
    mov rcx, rbx
    mov rdx, r12
    xor r8d, r8d
    sub rsp, 32
    call asmbuf_append_u64_hex
    add rsp, 32
.fail_v:
    add rsp, 32
    pop r12
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; dex_sanitize_append — rcx=buf, rdx=cstr. Anexa alnum+_; outros viram _.
; Ret: rax=0/1. (Nomes de DLL/func viram símbolos NASM válidos.)
;-----------------------------------------------------------------------------
dex_sanitize_append:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 40
    mov rbx, rcx
    mov r12, rdx
    test r12, r12
    jz .fail_s
.loop_s:
    movzx eax, byte [r12]
    test al, al
    jz .ok_s
    mov r13d, eax
    ; alnum ou _ ?
    cmp al, 'A'
    jb .ck_d
    cmp al, 'Z'
    jbe .emit
    cmp al, 'a'
    jb .ck_us
    cmp al, 'z'
    jbe .emit
    jmp .under
.ck_d:
    cmp al, '0'
    jb .under
    cmp al, '9'
    jbe .emit
    jmp .under
.ck_us:
    cmp al, '_'
    je .emit
.under:
    mov r13d, '_'
.emit:
    mov rcx, rbx
    mov edx, r13d
    sub rsp, 32
    call asmbuf_append_char
    add rsp, 32
    test eax, eax
    jnz .fail_s
    inc r12
    jmp .loop_s
.ok_s:
    xor eax, eax
    add rsp, 40
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.fail_s:
    mov eax, 1
    add rsp, 40
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; dex_label_emit_imp — rcx=buf, rdx=dll, r8=func(ou 0 se ordinal),
;                      r9d=ordinal. Emite "__imp_<dll>_<func|ordN>".
;-----------------------------------------------------------------------------
dex_label_emit_imp:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 32
    mov rbx, rcx
    mov r12, rdx
    mov r13, r8
    mov r14d, r9d
    lea rdx, [rel s_imp_pre]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fail_e
    mov rcx, rbx
    mov rdx, r12
    sub rsp, 32
    call dex_sanitize_append
    add rsp, 32
    test eax, eax
    jnz .fail_e
    lea rdx, [rel s_us]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fail_e
    test r13, r13
    jnz .byname
    ; ordinal: "ord<dec>"
    mov rcx, rbx
    mov edx, 'o'
    sub rsp, 32
    call asmbuf_append_char
    add rsp, 32
    test eax, eax
    jnz .fail_e
    mov rcx, rbx
    mov edx, 'r'
    sub rsp, 32
    call asmbuf_append_char
    add rsp, 32
    test eax, eax
    jnz .fail_e
    mov rcx, rbx
    mov edx, 'd'
    sub rsp, 32
    call asmbuf_append_char
    add rsp, 32
    test eax, eax
    jnz .fail_e
    ; decimal do ordinal (r14d, 16 bits)
    sub rsp, 64
    lea rdx, [rsp+32]
    mov ecx, r14d
    call dex_u64_to_dec_fit
    add rsp, 64
    test eax, eax
    jnz .fail_e
    jmp .ok_e
.byname:
    mov rcx, rbx
    mov rdx, r13
    sub rsp, 32
    call dex_sanitize_append
    add rsp, 32
    test eax, eax
    jnz .fail_e
.ok_e:
    xor eax, eax
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.fail_e:
    mov eax, 1
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; dex_u64_to_dec_fit (interna): rcx=buf, rdx=tmp(21B), ecx=u16 -> usa u64_to_dec
dex_u64_to_dec_fit:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 32
    mov rbx, rcx
    mov r12, rdx
    movzx ecx, cx
    mov rdx, r12
    sub rsp, 32
    call dex_u64_to_dec
    add rsp, 32
    mov r8, rax
    mov rdx, r12
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append
    add rsp, 32
    add rsp, 32
    pop r12
    pop rbx
    pop rbp
    ret

extern dex_u64_to_dec
