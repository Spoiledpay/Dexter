;=============================================================================
; Dexter/tests/sym_check.asm
; Driver de teste da symtab (R-6.4 fatia 2b + D-3): cria tabela, insere 5
; VAs fora de ordem (+1 duplicada, que não deve duplicar), achata com
; symtab_to_sorted e imprime `SYM n=<n> v=<v0> <v1> ...` em hex.
; Golden ([14]): `SYM n=5 v=1000 1500 2000 2A00 3100` + exit 0.
; Retorno: 0 se confere internamente, 2 em divergência.
;
; Requisitos atendidos: R-6.4 (symtab_to_sorted) + D-3 (teste de symtab)
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "dexter.inc"

global main

extern GetStdHandle
extern WriteFile
extern ExitProcess
extern symtab_new
extern symtab_insert_va
extern symtab_to_sorted
extern symtab_free
extern dex_free

section .rodata
s_p0     db "SYM n=", 0
s_p1     db " v=", 0
s_sp     db " ", 0
s_crlf   db 13, 10, 0
s_nm     db "k", 0
s_exp    dq 0x1000, 0x1500, 0x2000, 0x2A00, 0x3100

section .text

;-----------------------------------------------------------------------------
; main — 3 pushes + sub 64 (24+64=88 ≡ 8). hOut [rbp-32], tab [rbp-40],
; arr [rbp-48], n [rbp-56], dec-tmp 24B [rbp-80,-56).
;-----------------------------------------------------------------------------
main:
    push rbp
    mov rbp, rsp
    push rbx
    push r14                     ; 3 pushes (24B) + sub 64 = 88 ≡ 8
    sub rsp, 64
    mov ecx, -11
    sub rsp, 32
    call GetStdHandle
    add rsp, 32
    mov [rbp-32], rax              ; hOut
    mov ecx, 16
    sub rsp, 32
    call symtab_new
    add rsp, 32
    test rax, rax
    jz .fail
    mov [rbp-40], rax              ; tab
    ; insere 0x2000, 0x1000, 0x3100, 0x1500, 0x2A00, 0x2000(dup)
    mov r14, rax
    mov rcx, rax
    mov rdx, 0x2000
    lea r8, [rel s_nm]
    sub rsp, 32
    call symtab_insert_va
    add rsp, 32
    test rax, rax
    jz .fail
    mov rcx, r14
    mov rdx, 0x1000
    lea r8, [rel s_nm]
    sub rsp, 32
    call symtab_insert_va
    add rsp, 32
    test rax, rax
    jz .fail
    mov rcx, r14
    mov rdx, 0x3100
    lea r8, [rel s_nm]
    sub rsp, 32
    call symtab_insert_va
    add rsp, 32
    test rax, rax
    jz .fail
    mov rcx, r14
    mov rdx, 0x1500
    lea r8, [rel s_nm]
    sub rsp, 32
    call symtab_insert_va
    add rsp, 32
    test rax, rax
    jz .fail
    mov rcx, r14
    mov rdx, 0x2A00
    lea r8, [rel s_nm]
    sub rsp, 32
    call symtab_insert_va
    add rsp, 32
    test rax, rax
    jz .fail
    mov rcx, r14
    mov rdx, 0x2000
    lea r8, [rel s_nm]
    sub rsp, 32
    call symtab_insert_va
    add rsp, 32
    test rax, rax
    jz .fail
    ; achata
    mov rcx, r14
    sub rsp, 32
    call symtab_to_sorted
    add rsp, 32
    test rax, rax
    jz .fail                        ; OOM (n=5: impossível)
    mov [rbp-48], rax              ; arr
    mov [rbp-56], rdx              ; n
    cmp rdx, 5
    jne .fail
    ; imprime SYM n=.. v=.. .. ..
    lea rcx, [rel s_p0]
    call .print_cstr
    mov rcx, [rbp-56]
    call .print_hex
    lea rcx, [rel s_p1]
    call .print_cstr
    xor r14d, r14d                 ; i
.sym_l:
    cmp r14d, 5
    jae .sym_eol
    test r14d, r14d
    jz .sym_first
    lea rcx, [rel s_sp]
    call .print_cstr
.sym_first:
    mov rax, [rbp-48]
    mov rcx, [rax+r14*8]
    call .print_hex
    ; confere ordenado: esperado [1000,1500,2000,2A00,3100][i]
    lea rax, [rel s_exp]
    mov rdx, [rax+r14*8]
    mov rax, [rbp-48]
    cmp [rax+r14*8], rdx
    jne .fail
    inc r14d
    jmp .sym_l
.sym_eol:
    lea rcx, [rel s_crlf]
    call .print_cstr
    mov rcx, [rbp-48]
    sub rsp, 32
    call dex_free
    add rsp, 32
    mov rcx, [rbp-40]
    sub rsp, 32
    call symtab_free
    add rsp, 32
    xor ecx, ecx
    call ExitProcess
.fail:
    mov ecx, 2
    call ExitProcess

;-----------------------------------------------------------------------------
; Helpers (hOut em [rbp-32]; tmp 24B em [rbp-80,-56)).
;-----------------------------------------------------------------------------
.print_cstr:
    push rbx
    mov rbx, rcx
    mov rcx, rbx
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
