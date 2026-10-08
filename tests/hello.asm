; hello.asm — GOLDEN test binary for Dexter (minimal x64 console, imports)
; FONTE SAGRADA DO CORPUS: nunca gerar .asm em cima deste arquivo!
; (run_tests.bat verifica este marcador antes de montar.)
bits 64
default rel

global main
extern ExitProcess
extern GetStdHandle
extern WriteFile

section .text
main:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    mov ecx, -11
    call GetStdHandle
    mov [rsp+32], rax              ; handle (local)
    mov rcx, rax                   ; hFile
    lea rdx, [rel msg]             ; buf
    mov r8d, msg_len               ; len
    lea r9, [rsp+40]               ; written
    mov qword [rsp+40], 0
    mov qword [rsp+48], 0          ; overlapped=NULL (5th arg at [rsp+32] of call)
    sub rsp, 32
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 32
    xor ecx, ecx
    call ExitProcess

section .data
msg db 'hi', 13, 10
msg_len equ $ - msg
