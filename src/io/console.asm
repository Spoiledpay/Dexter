;=============================================================================
; Dexter/src/io/console.asm
; Saída de console de baixo nível (WriteFile em stdout/stderr).
;
; Requisitos atendidos: R-0.3, CLI (-v/-q, help, dump verbose)
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "win64.inc"

global dex_console_write
global dex_console_print_cstr
global dex_console_print_err
global dex_console_print_u64hex
global dex_console_print_u64dec
global dex_console_newline

extern dex_strlen
extern dex_u64_to_hex
extern dex_u64_to_dec

section .text

;-----------------------------------------------------------------------------
; dex_console_write
; Args:   rcx=handle(-11/-12 ou HANDLE), rdx=buf, r8=len
; Ret:    rax = bytes escritos (0 em erro)
;-----------------------------------------------------------------------------
dex_console_write:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push r12
    sub rsp, 56                ; 4 pushes -> rsp%16==8; 56%16==8 => call alinhado
    mov rbx, rcx
    mov rdi, rdx
    mov r12, r8
    test r12, r12
    jz .zero_w
    cmp rbx, -11
    je .geth_w
    cmp rbx, -12
    je .geth_w
    jmp .wr_w
.geth_w:
    mov rcx, rbx
    sub rsp, 32
    call GetStdHandle
    add rsp, 32
    mov rbx, rax
.wr_w:
    test rbx, rbx
    jz .zero_w
    cmp rbx, -1
    je .zero_w
    mov rcx, rbx
    mov rdx, rdi
    mov r8, r12
    lea r9, [rbp-40]           ; lpNumberOfBytesWritten (local real)
    mov qword [rbp-40], 0
    sub rsp, 48                ; 32 shadow + 8 (5º arg) + 8 p/ alinhar 16
    mov qword [rsp+32], 0      ; lpOverlapped = 0 (dentro do reservado; D-15)
    call WriteFile
    add rsp, 48
    test eax, eax
    jz .zero_w
    mov rax, [rbp-40]
    add rsp, 56
    pop r12
    pop rdi
    pop rbx
    pop rbp
    ret
.zero_w:
    xor eax, eax
    add rsp, 56
    pop r12
    pop rdi
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; dex_console_print_cstr — rcx=str -> stdout. Ret: rax=bytes.
;-----------------------------------------------------------------------------
dex_console_print_cstr:
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 40
    test rcx, rcx
    jz .e_c
    mov rbx, rcx
    call dex_strlen            ; rax = len (frame já alinhado: 2 pushes+32)
    mov r8, rax
    mov rdx, rbx
    mov rcx, -11
    call dex_console_write
    add rsp, 40
    pop rbx
    pop rbp
    ret
.e_c:
    xor eax, eax
    add rsp, 40
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; dex_console_print_err — rcx=str -> stderr. Ret: rax=bytes.
;-----------------------------------------------------------------------------
dex_console_print_err:
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 40
    test rcx, rcx
    jz .e_e
    mov rbx, rcx
    call dex_strlen
    mov r8, rax
    mov rdx, rbx
    mov rcx, -12
    call dex_console_write
    add rsp, 40
    pop rbx
    pop rbp
    ret
.e_e:
    xor eax, eax
    add rsp, 40
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; dex_console_print_u64hex
; Args:   rcx=valor, edx=digits (0=sem pad)
; Ret:    rax=bytes escritos
;-----------------------------------------------------------------------------
dex_console_print_u64hex:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 64                ; 32 shadow + 32 tmp buf
    mov rbx, rcx               ; valor
    mov r12d, edx              ; digits
    lea rdx, [rsp+32]          ; buf tmp
    mov rcx, rbx
    mov r8d, r12d
    call dex_u64_to_hex        ; rax = len
    mov r8, rax
    lea rdx, [rsp+32]
    mov rcx, -11
    call dex_console_write
    add rsp, 64
    pop r12
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; dex_console_print_u64dec — rcx=valor -> stdout decimal. Ret: rax=bytes.
;-----------------------------------------------------------------------------
dex_console_print_u64dec:
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 56
    mov rbx, rcx
    lea rdx, [rsp+32]
    mov rcx, rbx
    call dex_u64_to_dec
    mov r8, rax
    lea rdx, [rsp+32]
    mov rcx, -11
    call dex_console_write
    add rsp, 56
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; dex_console_newline — CRLF em stdout.
;-----------------------------------------------------------------------------
dex_console_newline:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    lea rdx, [rel .crlf_c]
    mov rcx, -11
    mov r8, 2
    call dex_console_write
    add rsp, 32
    pop rbp
    ret

section .rodata
.crlf_c db 13, 10
