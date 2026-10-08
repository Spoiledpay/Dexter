; loop.asm — GOLDEN test binary: loops, branches condicionais, jumps fwd/bwd
; FONTE SAGRADA DO CORPUS: nunca gerar .asm em cima deste arquivo!
; Comportamento: imprime "55" + CRLF (soma 1..10), exit 0.
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
    xor eax, eax               ; soma = 0
    mov ecx, 1                 ; i = 1
.sum_loop:
    cmp ecx, 11
    jge .sum_done               ; forward jump (sai do loop)
    add eax, ecx
    inc ecx
    jmp .sum_loop                ; backward jump
.sum_done:
    cmp eax, 55
    jne .fail
    lea rdx, [rel s55]
    jmp .write
.fail:
    lea rdx, [rel serr]
.write:
    mov r8d, 4
    mov [rsp+32], rdx          ; salva str (slot local)
    mov ecx, -11
    call GetStdHandle
    mov rcx, rax               ; hFile
    mov rdx, [rsp+32]          ; buf
    lea r9, [rsp+40]           ; written
    mov qword [rsp+40], 0
    mov qword [rsp+48], 0      ; overlapped (5º arg após sub)
    sub rsp, 32
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 32
    xor ecx, ecx
    call ExitProcess

section .data
s55  db '55', 13, 10, 0
serr db 'ER', 13, 10, 0
