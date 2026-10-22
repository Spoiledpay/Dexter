;=============================================================================
; Dexter/src/back/codegen.asm
; dex_codegen_ir — emite UMA instrução a partir do IR (via emit_native).
;
; O quê: (buf, Insn*, IR*) -> texto NASM (label do address + mnemônico
;   real) ou 1 (caller usa db). Dono do label da instrução e do
;   rollback: se o nativo falhar no meio, trunca AsmBuf.len (emissão
;   parcial descartada) e devolve 1 — o caller nunca vê meio-termo.
; Por quê: centraliza a decisão de emissão do walker; IMPORT com nome
;   emite `call|jmp [rel __imp_X]` (fatia 3; label-at-slot no .idata).
; Contrato:
;   Args: rcx=AsmBuf*, rdx=Insn*, r8=IR*, r9=impname|0 (só lido se IMPORT).
;   Ret:  eax=0 emitido | 1 usar db (cls DB, IMPORT sem nome ou sem
;         forma call/jmp, ou nativo recusou — sempre com rollback feito) |
;         6 OOM (só do label; sem rollback — nada foi emitido) |
;         8 args nulos.
;   tkind DATA emite nativo: as R-labels existem (fatia 2b; data emission
;   parte nos alvos R). tkind IMPORT com nome emite `call|jmp [rel
;   __imp_X]` (fatia 3; o label existe no .idata).
;   Preserva: rbx, rbp, rdi, rsi, r12-r15.
; Como testar: tests\codegen_check.asm (golden de texto + rollback).
;
; Requisitos atendidos: R-6.4 (codegen IR->AsmBuf, fatia 2)
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "dexter.inc"

global dex_codegen_ir

extern dex_emit_label
extern dex_emit_native
extern dex_emit_insn

section .text

;-----------------------------------------------------------------------------
; dex_codegen_ir — rcx=buf, rdx=Insn*, r8=IR*, r9=impname|0
; (só lido se tkind IMPORT) -> eax=0 | 1 | 6 | 8.
;-----------------------------------------------------------------------------
dex_codegen_ir:
    test rcx, rcx
    jz .cg_args
    test rdx, rdx
    jz .cg_args
    test r8, r8
    jz .cg_args
    cmp dword [r8+DexIR.cls], IR_DB
    je .cg_db
    cmp dword [r8+DexIR.tkind], IRT_IMPORT
    je .cg_import
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14                     ; 5 pushes (40B) + sub 32 = 72 ≡ 8
    sub rsp, 32
    mov rbx, rcx                 ; buf
    mov r12, rdx                 ; insn (r8=ir morre; cls/tkind já decididos)
    mov rax, [rbx+AsmBuf.len]
    mov [rbp-48], rax            ; snapshot p/ rollback
    mov rdx, [r12+Insn.address]
    mov rcx, rbx
    sub rsp, 32
    call dex_emit_label
    add rsp, 32
    test eax, eax
    jnz .cg_oom
    mov rcx, rbx
    mov rdx, r12
    sub rsp, 32
    call dex_emit_native
    add rsp, 32
    test eax, eax
    jnz .cg_rollback
    xor eax, eax
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.cg_rollback:
    mov rax, [rbp-48]
    mov [rbx+AsmBuf.len], rax
    mov eax, 1
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.cg_oom:
    mov eax, ERR_OOM
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.cg_db:
    mov eax, 1
    ret
.cg_import:
    ; r8=IR, r9=nome (char* __imp_). Sem nome ou cls sem forma
    ; call/jmp (INSTR mov-from-IAT: kinds 3/4 não existem) -> db.
    ; (r14 NÃO pode ser usado aqui: pushes abaixo salvam o valor do
    ; caller — kind vai p/ slot DEPOIS deles. Bug real: mov r14d,1
    ; antes do push destruía o buf (r14) do walker.)
    test r9, r9
    jz .cg_db
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15                     ; 6 pushes (48B) + sub 40 = 88 ≡ 8
    sub rsp, 40
    mov rbx, rcx                 ; buf
    mov r12, rdx                 ; insn (r8/r9 morrem; kind vai p/ slot)
    mov r13, r9                  ; name
    mov eax, [r8+DexIR.cls]      ; r8 intacto (sem calls até aqui)
    cmp eax, IR_CALL
    je .cg_imp_call
    cmp eax, IR_CALLIMP
    je .cg_imp_call
    cmp eax, IR_JMP
    je .cg_imp_jmp
    cmp eax, IR_JMPIMP
    je .cg_imp_jmp
    jmp .cg_imp_db
.cg_imp_db:
    mov eax, 1
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.cg_imp_call:
    mov dword [rbp-56], 1
    jmp .cg_imp_go
.cg_imp_jmp:
    mov dword [rbp-56], 2
.cg_imp_go:
    ; D-19 2c: `call|jmp [mem]` com REX.W/B não é reencodável pelo nasm
    ; (ele descarta o REX e a instrução encolhe 7->6 B, deslocando todos os
    ; labels seguintes). Devolver 1 faz o walker cair em db + kind 5, que
    ; preserva os bytes e relocaliza o disp32.
    cmp byte [r12+Insn.has_rex], 0
    jne .cg_imp_db
    mov rax, [rbx+AsmBuf.len]
    mov [rbp-64], rax            ; snapshot p/ rollback
    ; SEM label separado: dex_emit_insn kinds 1/2 já emitem label_<VA>:
    ; (label próprio aqui duplicaria e o nasm recusaria.)
    mov rcx, rbx
    mov rdx, r12
    mov r8, r13
    mov r9d, [rbp-56]
    sub rsp, 32
    call dex_emit_insn
    add rsp, 32
    test eax, eax
    jnz .cg_imp_back
    xor eax, eax
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.cg_imp_back:
    mov rax, [rbp-64]
    mov [rbx+AsmBuf.len], rax
    mov eax, 1
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.cg_args:
    mov eax, ERR_ARGS
    ret
