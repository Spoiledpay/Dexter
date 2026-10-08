;=============================================================================
; Dexter/src/io/file_write.asm
; Criação/escrita de arquivos de saída (.asm / .exe rebuild).
;
; Requisitos atendidos: R-4.x (escrita do .asm + FlushFileBuffers)
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "win64.inc"

global dex_open_write
global dex_open_rw
global dex_write_all
global dex_write_cstr

extern dex_strlen

section .text

;-----------------------------------------------------------------------------
; dex_open_write — rcx=path -> rax=HANDLE ou 0
;-----------------------------------------------------------------------------
dex_open_write:
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 56
    mov rbx, rcx
    test rbx, rbx
    jz .fail_w
    cmp byte [rbx], 0
    je .fail_w
    mov rcx, rbx
    mov edx, GENERIC_WRITE
    mov r8d, FILE_SHARE_READ   ; permitir que nasm/link leiam concorrentemente
    mov r9, 0
    mov dword [rsp+32], CREATE_ALWAYS
    mov dword [rsp+40], FILE_ATTRIBUTE_NORMAL
    mov qword [rsp+48], 0
    call CreateFileA
    cmp rax, -1
    je .fail_w
    add rsp, 56
    pop rbx
    pop rbp
    ret
.fail_w:
    xor eax, eax
    add rsp, 56
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; dex_write_all
; Args:   rcx=HANDLE, rdx=buf, r8=len
; Ret:    rax = 0 OK, 2 erro I/O
; Escreve em loop até completar (WriteFile pode ser parcial).
;-----------------------------------------------------------------------------
dex_write_all:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    sub rsp, 48
    mov rbx, rcx               ; handle
    mov rsi, rdx               ; cursor
    mov r12, r8                ; restante
    test rbx, rbx
    jz .fail_a
    test r12, r12
    jz .ok                     ; len 0 = OK
.loop:
    mov rcx, rbx
    mov rdx, rsi
    mov r8, r12
    cmp r8, 0x1000000
    jbe .sz
    mov r8, 0x1000000          ; chunk 16MiB
.sz:
    lea r9, [rbp-16]
    mov qword [rbp-16], 0
    mov rdi, r8                ; pedido
    sub rsp, 32
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 32
    test eax, eax
    jz .fail_a
    mov rax, [rbp-16]
    test rax, rax
    jz .fail_a
    add rsi, rax
    sub r12, rax
    jnz .loop
.ok:
    ; FlushFileBuffers(handle)
    mov rcx, rbx
    sub rsp, 32
    call FlushFileBuffers
    add rsp, 32
    xor eax, eax
    add rsp, 48
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret
.fail_a:
    mov eax, 2
    add rsp, 48
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; dex_open_rw — rcx=path -> rax=HANDLE r/w (OPEN_EXISTING) ou 0
;-----------------------------------------------------------------------------
dex_open_rw:
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 56
    mov rbx, rcx
    test rbx, rbx
    jz .fail_rw
    cmp byte [rbx], 0
    je .fail_rw
    mov rcx, rbx
    mov edx, GENERIC_READ | GENERIC_WRITE
    mov r8d, FILE_SHARE_READ
    mov r9, 0
    mov dword [rsp+32], OPEN_EXISTING
    mov dword [rsp+40], FILE_ATTRIBUTE_NORMAL
    mov qword [rsp+48], 0
    call CreateFileA
    cmp rax, -1
    je .fail_rw
    add rsp, 56
    pop rbx
    pop rbp
    ret
.fail_rw:
    xor eax, eax
    add rsp, 56
    pop rbx
    pop rbp
    ret

dex_write_cstr:
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
    call dex_write_all
    add rsp, 32
    pop r12
    pop rbx
    pop rbp
    ret
