;=============================================================================
; Dexter/src/io/file_read.asm
; Abertura e tamanho de arquivo de entrada (somente leitura).
;
; Requisitos atendidos: R-0.3 (I/O kernel32)
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "win64.inc"
%include "errors.inc"

global dex_open_read
global dex_file_size
global dex_close

section .text

;-----------------------------------------------------------------------------
; dex_open_read
; Args:   rcx = path (NUL, ANSI)
; Ret:    rax = HANDLE ou 0 em erro
;-----------------------------------------------------------------------------
dex_open_read:
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 56                ; shadow(32) + 3 stack slots p/ args 5-7
    mov rbx, rcx
    test rbx, rbx
    jz .fail
    cmp byte [rbx], 0
    je .fail
    mov rcx, rbx               ; lpFileName
    mov edx, GENERIC_READ      ; dwDesiredAccess
    mov r8d, FILE_SHARE_READ   ; dwShareMode
    mov r9, 0                  ; lpSecurityAttributes
    mov dword [rsp+32], OPEN_EXISTING
    mov dword [rsp+40], FILE_ATTRIBUTE_NORMAL
    mov qword [rsp+48], 0      ; hTemplateFile
    call CreateFileA
    cmp rax, -1
    je .fail
    add rsp, 56
    pop rbx
    pop rbp
    ret
.fail:
    xor eax, eax
    add rsp, 56
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; dex_file_size
; Args:   rcx = HANDLE
; Ret:    rax = tamanho (0..1GiB) ou -1 em erro
;-----------------------------------------------------------------------------
dex_file_size:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    test rcx, rcx
    jz .fail_s
    cmp rcx, -1
    je .fail_s
    mov qword [rbp-16], 0
    ; GetFileSizeEx(hFile, &size) — 2 args
    mov rdx, rbp
    sub rdx, 16
    sub rsp, 32
    call GetFileSizeEx
    add rsp, 32
    test eax, eax
    jz .fail_s
    mov rax, [rbp-16]
    test rax, rax
    jz .fail_s                 ; vazio = inválido p/ PE
    cmp rax, DEX_MAX_FILE_SIZE
    ja .fail_s
    add rsp, 48
    pop rbp
    ret
.fail_s:
    mov rax, -1
    add rsp, 48
    pop rbp
    ret

;-----------------------------------------------------------------------------
; dex_close — rcx=HANDLE (0/-1 = no-op)
;-----------------------------------------------------------------------------
dex_close:
    test rcx, rcx
    jz .done_c
    cmp rcx, -1
    je .done_c
    push rbp
    mov rbp, rsp
    sub rsp, 32
    call CloseHandle
    add rsp, 32
    pop rbp
.done_c:
    ret
