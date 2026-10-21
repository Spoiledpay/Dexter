;=============================================================================
; Dexter/tests/imp_check.asm
; Driver de teste do dex_emit_imp_label (R-6.4 fatia 3): AsmBuf manual +
; PeImage/imports craftados, sem file I/O:
;   caso HIT (va=slot): ret 0 + `__imp_KERNEL32_dll_ExitProcess:`.
;   caso HIT duplicado (mesmo dll+func em outro slot): `..._ExitProcess_2008:`.
;   caso HIT unico (outro func): `__imp_KERNEL32_dll_WriteFile:`.
;   caso MISS (va fora): ret 0 + buf intacto.
; Retorno: 0 se tudo confere, 2 em divergência.
;
; Requisitos atendidos: R-6.4 (IAT label-at-slot, fatia 3)
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "dexter.inc"

global main

extern GetStdHandle
extern WriteFile
extern ExitProcess
extern dex_emit_imp_label
extern dex_malloc

section .rodata
s_dll    db "KERNEL32.dll", 0
s_fn     db "ExitProcess", 0
s_fn2    db "WriteFile", 0

section .data
align 8
; 3 entries: #0 nome unico, #1 duplicata (mesma dll+func em outro slot),
; #2 outro nome. O dup check existe p/ PEs reais (gcc importa _fileno etc.
; duas vezes); a 1a ocorrencia mantem o nome puro, a 2a leva _<iat_rva>.
fake_imp:
    dq s_dll, s_fn               ; dll_name, func_name
    dw 0                         ; ordinal
    db 0                         ; is_ordinal
    db 0, 0, 0, 0, 0             ; pad
    dd 0x2000                    ; iat_rva
    dd 0                         ; pad2
    dq s_dll, s_fn               ; duplicata (mesmo nome)
    dw 0
    db 0
    db 0, 0, 0, 0, 0
    dd 0x2008
    dd 0
    dq s_dll, s_fn2              ; nome unico
    dw 0
    db 0
    db 0, 0, 0, 0, 0
    dd 0x2010
    dd 0
fake_img:
    dq 0, 0                      ; file_buffer, file_size
    dq 0x140000000               ; image_base
    dq 0x1000                    ; entry_point
    dd 0, 0                      ; num_sections
    dq 0                         ; sections_ptr
    dq fake_imp                  ; imports_ptr
    dd 3, 0                      ; imports_count

section .bss
align 8
g_abuf:  resb 4096
g_asm:   resb 24

section .text

;-----------------------------------------------------------------------------
; main — 3 pushes + sub 32 (24+32=56 ≡ 8). hOut [rbp-32].
;-----------------------------------------------------------------------------
main:
    push rbp
    mov rbp, rsp
    push rbx
    push r14
    sub rsp, 32
    mov ecx, -11
    sub rsp, 32
    call GetStdHandle
    add rsp, 32
    mov [rbp-32], rax              ; hOut
    ; buf em heap (8 KB, len 8000: estado real do produto a meio generate)
    mov ecx, 8192
    sub rsp, 32
    call dex_malloc
    add rsp, 32
    test rax, rax
    jz .fail
    mov [g_asm+AsmBuf.data], rax
    mov qword [g_asm+AsmBuf.len], 8000
    mov qword [g_asm+AsmBuf.cap], 8192
    ; ---- HIT: va = base+0x2000 (slot) ----
    lea rcx, [rel g_asm]
    mov rdx, 0x140002000
    lea r8, [rel fake_img]
    sub rsp, 32
    call dex_emit_imp_label
    add rsp, 32
    test eax, eax
    jnz .fail
    cmp qword [g_asm+AsmBuf.len], 0
    je .fail
    mov rcx, [g_asm+AsmBuf.data]
    mov r8, [g_asm+AsmBuf.len]
    call .print_mem
    ; ---- HIT duplicado: va = base+0x2008 -> sufixo _2008 ----
    mov qword [g_asm+AsmBuf.len], 0
    lea rcx, [rel g_asm]
    mov rdx, 0x140002008
    lea r8, [rel fake_img]
    sub rsp, 32
    call dex_emit_imp_label
    add rsp, 32
    test eax, eax
    jnz .fail
    cmp qword [g_asm+AsmBuf.len], 0
    je .fail
    mov rcx, [g_asm+AsmBuf.data]
    mov r8, [g_asm+AsmBuf.len]
    call .print_mem
    ; ---- HIT nome unico: va = base+0x2010 -> WriteFile ----
    mov qword [g_asm+AsmBuf.len], 0
    lea rcx, [rel g_asm]
    mov rdx, 0x140002010
    lea r8, [rel fake_img]
    sub rsp, 32
    call dex_emit_imp_label
    add rsp, 32
    test eax, eax
    jnz .fail
    cmp qword [g_asm+AsmBuf.len], 0
    je .fail
    mov rcx, [g_asm+AsmBuf.data]
    mov r8, [g_asm+AsmBuf.len]
    call .print_mem
    ; ---- MISS: va = base+0x2050 (sem slot; buf intacto) ----
    mov qword [g_asm+AsmBuf.len], 0
    lea rcx, [rel g_asm]
    mov rdx, 0x140002050
    lea r8, [rel fake_img]
    sub rsp, 32
    call dex_emit_imp_label
    add rsp, 32
    test eax, eax
    jnz .fail
    cmp qword [g_asm+AsmBuf.len], 0
    jne .fail
    xor ecx, ecx
    call ExitProcess
.fail:
    mov ecx, 2
    call ExitProcess

;-----------------------------------------------------------------------------
; .print_mem — rcx=ptr, r8=len -> stdout (hOut em [rbp-32]).
;-----------------------------------------------------------------------------
.print_mem:
    test r8, r8
    jz .pm_done
    push rbx
    mov rbx, rcx
    mov rdx, rbx
    mov rcx, [rbp-32]
    sub rsp, 48
    mov qword [rsp+32], 0
    lea r9, [rsp+40]
    call WriteFile
    add rsp, 48
    pop rbx
.pm_done:
    ret
