;=============================================================================
; Dexter/src/disasm/vex.asm
; Semântica VEX2 (prefixo C5, mapa 0F) — item 2, fatia 2b.
;
; O QUÊ: resolve o descritor (mnemônico + forma de operando) de uma instrução
;   VEX2 a partir da tabela gerada src/disasm/vex2_tbl.inc.
; POR QUÊ: o decoder já entrega limites/opcode byte-exatos (R-2.7), mas o
;   emissor só sabia `db`; sem forma de operando não há emissão nativa.
; CONTRATO: rcx=Insn* (enc=1, vex_mm=1, vex_pp/l/vvvv preenchidos pelo
;   decoder) -> rax=descritor (20 B) ou 0 (sem forma: db). O gate de vvvv
;   (bit 7 de [desc+8]) exige vvvv lógico 0 quando o encoding não o usa.
; TESTES: tests/vex2nat.asm + tests/vex2_native_check.py ([61]).
; Autor: Dexter Engineer
; Requisitos: 2b (fila pós-2c)
;=============================================================================
bits 64
default rel

%include "dexter.inc"
%include "vex2_tbl.inc"

global dex_vex2_desc
global dex_vex2_flags

section .text

;-----------------------------------------------------------------------------
; dex_vex2_desc
; Resolve o descritor da tabela VEX2 (mapa 0F) para a instrução.
;
; Args:   rcx = Insn* (não nulo)
; Ret:    rax = ponteiro p/ descritor de 20 B (ver vex2_tbl.inc) ou 0 = db
; Clobber: rax, rcx, rdx
; Preserva: rbx, rbp, rdi, rsi, r8-r15
;-----------------------------------------------------------------------------
dex_vex2_desc:
    test rcx, rcx
    jz .none
    cmp byte [rcx+Insn.enc], 1
    jne .none
    cmp byte [rcx+Insn.vex_npre], 2   ; VEX2 (C5) apenas
    jne .none
    cmp byte [rcx+Insn.vex_mm], 1
    jne .none
    ; idx = (pp*2 + L)*256 + opcode(low byte); mapa 0F tem oplen 2 (0F00|op)
    movzx eax, byte [rcx+Insn.vex_pp]
    shl eax, 1
    movzx edx, byte [rcx+Insn.vex_l]
    add eax, edx
    shl eax, 8
    movzx edx, byte [rcx+Insn.opcode]
    add eax, edx
    lea rdx, [rel vex2_idx]
    movzx eax, word [rdx+rax*2]
    cmp eax, VEX2_DESC_NONE
    je .none
    imul eax, VEX2_DESC_SIZE
    lea rdx, [rel vex2_desc]
    add rax, rdx
    ; flags em [desc+8]: bit6 = sem forma (db), bit7 = vvvv precisa ser 0
    movzx edx, byte [rax+8]
    test dl, 0x40
    jnz .ok
    test dl, 0x80
    jz .ok
    cmp byte [rcx+Insn.vex_vvvv], 0
    jne .none
.ok:
    ret
.none:
    xor eax, eax
    ret

;-----------------------------------------------------------------------------
; dex_vex2_flags
; Flags de DECODE (F_MODRM/F_I8) para uma VEX2 do mapa 0F, tirados do
; descritor derivado. A tabela legada (dex_tbl2_flag) tem lacunas para
; opcodes SSE que só o VEX usa (ex.: 0F F2 = 0), e o sweep desalinharia.
;
; Args:   rcx = Insn* (vex_pp/vex_l já preenchidos)
;         edx = byte de opcode (mapa 0F)
; Ret:    eax = bit8 setado + flags (bit0 = modrm, bit1 = imm8);
;               eax sem o bit8 = sem entrada (usar a tabela legada)
; Clobber: rax, rcx, rdx, r8-r11
; Preserva: rbx, rbp, rdi, rsi, r12-r15
;-----------------------------------------------------------------------------
dex_vex2_flags:
    mov r8d, edx                 ; opcode
    movzx eax, byte [rcx+Insn.vex_pp]
    shl eax, 1
    movzx edx, byte [rcx+Insn.vex_l]
    add eax, edx
    shl eax, 8
    add eax, r8d
    lea r8, [rel vex2_idx]
    movzx eax, word [r8+rax*2]
    cmp eax, VEX2_DESC_NONE
    je .nof
    imul eax, VEX2_DESC_SIZE
    lea r8, [rel vex2_desc]
    add rax, r8
    movzx ecx, byte [rax+8]      ; bit3 = ModRM, bit4 = imm8
    xor edx, edx
    test cl, 0x08
    jz .fl_nomod
    or edx, 1
.fl_nomod:
    test cl, 0x10
    jz .fl_noimm
    or edx, 2
.fl_noimm:
    mov eax, edx
    or eax, 0x100
    ret
.nof:
    xor eax, eax
    ret
