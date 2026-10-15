;=============================================================================
; Dexter/tests/x87_check.asm
; Driver de teste da tabela x87 (R-2.7): varre TODAS as 8x256 codificações
; D8-DF e imprime, por opcode, o total de mnemonics válidos e um FNV-1a 32
; sobre as strings resolvidas. Golden independente (capstone 5.0.7) pinado
; no run_tests.bat [39]; qualquer entrada errada muda o hash.
; Formato (8 linhas): "op=216 n=64 h=<dec>"
; Retorno: 0.
;
; Requisitos atendidos: R-2.7
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "dexter.inc"

global main

extern GetStdHandle
extern WriteFile
extern ExitProcess
extern dex_x87_mne

section .rodata
s_op  db "op=", 0
s_n   db " n=", 0
s_h   db " h=", 0

section .bss
align 8
g_insn: resb SIZEOF_INSN
g_out:  resb 4096

section .text

;-----------------------------------------------------------------------------
; main — varre D8-DF x 00-FF, acumula n + FNV-1a e imprime 8 linhas.
; Frame: push rbp + 5 pushes (rbx,r12,r13,r14,r15) + sub 8 -> rsp%16==0;
;        hOut em [rbp-48]. r15 = cursor de escrita em g_out.
;-----------------------------------------------------------------------------
main:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov ecx, -11
    sub rsp, 32
    call GetStdHandle
    add rsp, 32
    mov [rbp-48], rax               ; hOut
    lea r15, [rel g_out]
    mov r12d, 0xD8                  ; op
.op_loop:
    cmp r12d, 0xE0
    jae .done
    mov r14d, 2166136261            ; FNV-1a 32 offset basis
    xor ebx, ebx                    ; n
    xor r13d, r13d                  ; modrm
.mrm_loop:
    cmp r13d, 256
    jae .print
    mov dword [rel g_insn+Insn.opcode], r12d
    mov byte [rel g_insn+Insn.modrm], r13b
    lea rcx, [rel g_insn]
    sub rsp, 32
    call dex_x87_mne
    add rsp, 32
    test rax, rax
    jz .mrm_next
    inc ebx
.mhash:
    movzx edx, byte [rax]
    test edx, edx
    jz .mrm_next
    xor r14d, edx
    imul r14d, r14d, 16777619
    inc rax
    jmp .mhash
.mrm_next:
    inc r13d
    jmp .mrm_loop
.print:
    lea rcx, [rel s_op]
    call .ecstr
    mov ecx, r12d
    call .edec
    lea rcx, [rel s_n]
    call .ecstr
    mov ecx, ebx
    call .edec
    lea rcx, [rel s_h]
    call .ecstr
    mov ecx, r14d
    call .edec
    mov al, 13
    mov [r15], al
    inc r15
    mov al, 10
    mov [r15], al
    inc r15
    inc r12d
    jmp .op_loop
.done:
    lea rdx, [rel g_out]
    mov r8, r15
    lea rax, [rel g_out]
    sub r8, rax                     ; len = r15 - g_out
    mov rcx, [rbp-48]
    sub rsp, 48
    mov qword [rsp+32], 0
    lea r9, [rsp+40]
    call WriteFile
    add rsp, 48
    xor ecx, ecx
    sub rsp, 32
    call ExitProcess

;-----------------------------------------------------------------------------
; Helpers de saída (usam r15 como cursor; clobber rax,rcx,rdx,r8-r10).
;-----------------------------------------------------------------------------
.ecstr:
    mov dl, [rcx]
    test dl, dl
    jz .ec_d
    mov [r15], dl
    inc r15
    inc rcx
    jmp .ecstr
.ec_d:
    ret

.edec:
    mov rax, rcx
    mov r9, r15
    test rax, rax
    jnz .ed_conv
    mov byte [r15], '0'
    inc r15
    ret
.ed_conv:
    mov r10d, 10
.ed_l:
    xor edx, edx
    div r10
    add dl, '0'
    mov [r15], dl
    inc r15
    test rax, rax
    jnz .ed_l
    lea r10, [r15-1]
.ed_rev:
    cmp r9, r10
    jae .ed_d
    mov al, [r9]
    mov dl, [r10]
    mov [r9], dl
    mov [r10], al
    inc r9
    dec r10
    jmp .ed_rev
.ed_d:
    ret
