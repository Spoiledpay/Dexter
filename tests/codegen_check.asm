;=============================================================================
; Dexter/tests/codegen_check.asm
; Driver de teste do codegen (R-6.4 fatia 2a): 3 casos sobre AsmBuf
; manual (sem heap) e imprime o texto do caso 1 em stdout:
;   caso 1: mov rax,rbx @0x140001000, IR INSTR/NONE -> ret 0, texto com
;           `label_140001000:` e `mov rax, rbx` (pinado em [12]).
;   caso 2: mne=0, IR DB/NONE -> ret 1, buf vazio (sem emissão).
;   caso 3: mne válido + op0 kind 9 (nativo recusa) -> ret 1 E len==0
;           (prova do rollback: o label parcial foi descartado).
;   caso 4 (R-6.4 fatia 3): IR CALLIMP/IMPORT + nome -> ret 0 com
;           `label_...:` + `    call [rel __imp_...]` (pinado em [12]).
; Retorno: 0 se tudo confere, 2 em divergência.
;
; Requisitos atendidos: R-6.4 (codegen IR->AsmBuf, fatia 2a)
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "dexter.inc"

global main

extern GetStdHandle
extern WriteFile
extern ExitProcess
extern dex_codegen_ir

section .rodata
s_mne    db "mov", 0
s_imp4   db "__imp_KERNEL32_dll_ExitProcess", 0

section .bss
align 8
g_abuf:  resb 4096               ; texto do AsmBuf manual
g_asm:   resb 24                 ; AsmBuf {data, len, cap}
g_ins1:  resb SIZEOF_INSN
g_ins2:  resb SIZEOF_INSN
g_ins3:  resb SIZEOF_INSN
g_ins4:  resb SIZEOF_INSN
g_ins5:  resb SIZEOF_INSN
g_ir1:   resb SIZEOF_IR
g_ir2:   resb SIZEOF_IR
g_ir3:   resb SIZEOF_IR
g_ir4:   resb SIZEOF_IR
g_ir5:   resb SIZEOF_IR

section .text

;-----------------------------------------------------------------------------
; main — 3 pushes + sub 32 (24+32=56 ≡ 8). hOut em [rbp-32].
;-----------------------------------------------------------------------------
main:
    push rbp
    mov rbp, rsp
    push rbx
    push r14                     ; 3 pushes (24B) + sub 32 = 56 ≡ 8
    sub rsp, 32
    mov ecx, -11
    sub rsp, 32
    call GetStdHandle
    add rsp, 32
    mov [rbp-32], rax              ; hOut
    ; ---- AsmBuf manual (sem heap): {abuf, 0, 4096} ----
    lea rax, [rel g_abuf]
    mov [g_asm+AsmBuf.data], rax
    mov qword [g_asm+AsmBuf.len], 0
    mov qword [g_asm+AsmBuf.cap], 4096
    ; ---- caso 1: mov rax,rbx ----
    lea rax, [rel g_ins1]
    lea rcx, [rel s_mne]
    mov [rax+Insn.mne], rcx
    mov rdx, 0x140001000
    mov [rax+Insn.address], rdx
    mov byte [rax+Insn.op0+DexOp.kind], DEX_OP_REG
    mov byte [rax+Insn.op0+DexOp.reg], 0
    mov byte [rax+Insn.op0+DexOp.size], 8
    mov byte [rax+Insn.op1+DexOp.kind], DEX_OP_REG
    mov byte [rax+Insn.op1+DexOp.reg], 3
    mov byte [rax+Insn.op1+DexOp.size], 8
    mov dword [rel g_ir1+DexIR.cls], IR_INSTR
    mov dword [rel g_ir1+DexIR.tkind], IRT_NONE
    lea rcx, [rel g_asm]
    lea rdx, [rel g_ins1]
    lea r8, [rel g_ir1]
    sub rsp, 32
    call dex_codegen_ir
    add rsp, 32
    test eax, eax
    jnz .fail                      ; esperava 0
    cmp qword [g_asm+AsmBuf.len], 0
    je .fail                        ; esperava texto
    ; imprime o buffer (golden textual em [12])
    mov rcx, [g_asm+AsmBuf.data]
    mov r8, [g_asm+AsmBuf.len]
    call .print_mem
    ; ---- caso 2: DB (buf zerado; nada deve sair) ----
    mov qword [g_asm+AsmBuf.len], 0
    mov dword [rel g_ir2+DexIR.cls], IR_DB
    mov dword [rel g_ir2+DexIR.tkind], IRT_NONE
    lea rcx, [rel g_asm]
    lea rdx, [rel g_ins2]          ; todo zero (.bss): mne=0
    lea r8, [rel g_ir2]
    sub rsp, 32
    call dex_codegen_ir
    add rsp, 32
    cmp eax, 1
    jne .fail                        ; esperava 1
    cmp qword [g_asm+AsmBuf.len], 0
    jne .fail                        ; buf intacto
    ; ---- caso 3: nativo recusa (op0 kind 9: presente, inválido) ----
    ; -> ret 1 COM rollback (o label parcial some do buffer).
    mov qword [g_asm+AsmBuf.len], 0
    lea rax, [rel g_ins3]
    lea rcx, [rel s_mne]
    mov [rax+Insn.mne], rcx
    mov rdx, 0x140002000
    mov [rax+Insn.address], rdx
    mov byte [rax+Insn.op0+DexOp.kind], 9
    mov dword [rel g_ir3+DexIR.cls], IR_INSTR
    mov dword [rel g_ir3+DexIR.tkind], IRT_NONE
    lea rcx, [rel g_asm]
    lea rdx, [rel g_ins3]
    lea r8, [rel g_ir3]
    sub rsp, 32
    call dex_codegen_ir
    add rsp, 32
    cmp eax, 1
    jne .fail                        ; esperava 1
    cmp qword [g_asm+AsmBuf.len], 0
    jne .fail                        ; rollback: label descartado
    ; ---- caso 4: CALLIMP/IMPORT + nome -> call [rel __imp_] ----
    mov qword [g_asm+AsmBuf.len], 0
    lea rax, [rel g_ins4]
    lea rcx, [rel s_mne]
    mov [rax+Insn.mne], rcx
    mov rdx, 0x140001800
    mov [rax+Insn.address], rdx
    mov dword [rel g_ir4+DexIR.cls], IR_CALLIMP
    mov dword [rel g_ir4+DexIR.tkind], IRT_IMPORT
    lea rcx, [rel g_asm]
    lea rdx, [rel g_ins4]
    lea r8, [rel g_ir4]
    lea r9, [rel s_imp4]
    sub rsp, 32
    call dex_codegen_ir
    add rsp, 32
    test eax, eax
    jnz .fail                        ; esperava 0
    cmp qword [g_asm+AsmBuf.len], 0
    je .fail
    mov rcx, [g_asm+AsmBuf.data]
    mov r8, [g_asm+AsmBuf.len]
    call .print_mem
    ; ---- caso 5: JMPIMP/IMPORT + nome -> jmp [rel __imp_] ----
    mov qword [g_asm+AsmBuf.len], 0
    lea rax, [rel g_ins5]
    lea rcx, [rel s_mne]
    mov [rax+Insn.mne], rcx
    mov rdx, 0x140001900
    mov [rax+Insn.address], rdx
    mov dword [rel g_ir5+DexIR.cls], IR_JMPIMP
    mov dword [rel g_ir5+DexIR.tkind], IRT_IMPORT
    lea rcx, [rel g_asm]
    lea rdx, [rel g_ins5]
    lea r8, [rel g_ir5]
    lea r9, [rel s_imp4]
    sub rsp, 32
    call dex_codegen_ir
    add rsp, 32
    test eax, eax
    jnz .fail                        ; esperava 0
    cmp qword [g_asm+AsmBuf.len], 0
    je .fail
    mov rcx, [g_asm+AsmBuf.data]
    mov r8, [g_asm+AsmBuf.len]
    call .print_mem
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
