;=============================================================================
; Dexter/src/util/log.asm
; Log mínimo: escreve em stdout/stderr via WriteFile (sem CRT).
;
; Requisitos atendidos: R-0.3 (diagnóstico -v/-q)
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "win64.inc"

global dex_log_msg
global dex_log_err
global dex_log_nl

extern dex_strlen

section .text

;-----------------------------------------------------------------------------
; dex_log_msg — rcx=str -> stdout (silencioso se NULL)
;-----------------------------------------------------------------------------
dex_log_msg:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    sub rsp, 48
    test rcx, rcx
    jz .done
    mov rbx, rcx
    call dex_strlen            ; rax = len
    mov rdi, rax
    mov ecx, STD_OUTPUT_HANDLE
    sub rsp, 32
    call GetStdHandle
    add rsp, 32
    ; rax = handle
    cmp rax, -1
    je .done
    mov rcx, rax               ; hFile
    mov rdx, rbx               ; buf
    mov r8, rdi                ; len
    lea r9, [rbp-24]           ; lpNumberOfBytesWritten
    mov qword [rbp-24], 0
    mov qword [rbp-32], 0      ; lpOverlapped = NULL
    sub rsp, 32                ; shadow(32) + overlapped slot(8)
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 32
.done:
    add rsp, 48
    pop rdi
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; dex_log_err — rcx=str -> stderr
;-----------------------------------------------------------------------------
dex_log_err:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    sub rsp, 48
    test rcx, rcx
    jz .done_e
    mov rbx, rcx
    call dex_strlen
    mov rdi, rax
    mov ecx, STD_ERROR_HANDLE
    sub rsp, 32
    call GetStdHandle
    add rsp, 32
    cmp rax, -1
    je .done_e
    mov rcx, rax
    mov rdx, rbx
    mov r8, rdi
    lea r9, [rbp-24]
    mov qword [rbp-24], 0
    sub rsp, 32
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 32
.done_e:
    add rsp, 48
    pop rdi
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; dex_log_nl — escreve CRLF em stdout
;-----------------------------------------------------------------------------
dex_log_nl:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    lea rcx, [rel .crlf]
    call dex_log_msg
    add rsp, 32
    pop rbp
    ret
section .rodata
.crlf db 13, 10, 0
