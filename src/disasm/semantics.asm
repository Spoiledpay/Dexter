;=============================================================================
; Dexter/src/disasm/semantics.asm
; dex_build_operands — interpreta (opcode, ModRM, prefixos) em operandos
; (DexOp op0/op1/op2) + mnemônico preciso. R-4.5 (emissor nativo).
;
; Entrada: Insn* com opcode/modrm/rex/legacy/disp/imm/target já preenchidos
;          (dex_disasm_one até operands).
; Ret: rax = 0 (operandos construídos, pode emitir nativo)
;            1 (fallback db: inválido, SSE/VEX/x87/moffs/abs32, ou não
;               coberto — chamador usa db, nunca erro falso)
; Regras: whitelist estrita (default=db); tamanhos via op_size (REX.W/66);
;         ModRM inválidos p/ grupo → 1; far forms → 1.
;
; Requisitos atendidos: R-4.5 (AST flat + mnemônicos)
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "dexter.inc"

global dex_build_operands

extern dex_grp1_mne
extern dex_grp2_mne
extern dex_grp3_mne
extern dex_grp45_mne
extern s_nop
extern s_ret
extern s_mov
extern s_test
extern s_sysc
extern s_sse
extern dex_x87_mne
extern dex_x87_form
extern s_retf
extern s_int3
extern s_int
extern s_push
extern s_pop
extern s_enter
extern s_leave
extern s_imul
extern s_movzx
extern s_movsx
extern s_bt
extern s_bts
extern s_btr
extern s_btc
extern s_bsf
extern s_bsr
extern s_shld
extern s_shrd
extern s_cmpx
extern s_xadd
extern s_hlt
extern s_cmc
extern s_clc
extern s_stc
extern s_cli
extern s_sti
extern s_cld
extern s_std
extern s_wait
extern s_salc
extern s_xlatb
extern s_aam
extern s_aad
extern s_pushfq
extern s_popfq
extern s_sahf
extern s_lahf
extern s_sysenter
extern s_sysexit
extern s_sysret
extern s_wrmsr
extern s_rdmsr
extern s_rdpmc
extern s_cpuid
extern s_rdtsc
extern s_pause
extern s_int1
extern s_ud2
extern s_emms
extern s_nop
extern s_movsb
extern s_movsd
extern s_cmpsb
extern s_cmpsd
extern s_stosb
extern s_stosd
extern s_lodsb
extern s_lodsd
extern s_scasb
extern s_scasd
extern s_loopne
extern s_loope
extern s_jrcxz
extern s_jecxz

section .text

;-----------------------------------------------------------------------------
; dex_build_operands — rcx=Insn* -> rax=0/1
; Preserva: rbx, rbp, rdi, rsi, r12-r15. Sem calls (leaf).
;-----------------------------------------------------------------------------
dex_build_operands:
    push rbp
    mov rbp, rsp
    push rbx
    test rcx, rcx
    jz .no
    mov rbx, rcx               ; insn
    ; R-2.7: VEX/EVEX nunca são emitidos nativamente (prefixo não modelado
    ; no emissor) — mnemônico genérico já vem do decoder; força db.
    cmp byte [rbx+Insn.enc], 0
    jne .no
    cmp byte [rbx+Insn.addr_mode], 1
    jne .bm64
    ; x32 Fase D1b: allowlist (resto: db fiel). Classes auditadas p/
    ; semântica 32-bit (sem REX; formas com 66 caem em .no dentro;
    ; x32+0x67 sempre recusa — endereços 16 sem forma).
    cmp byte [rbx+Insn.legacy67], 0
    jne .no
    movzx eax, byte [rbx+Insn.opcode]
    cmp dword [rbx+Insn.opcode_len], 2
    je .bm32_l2
    cmp dword [rbx+Insn.opcode_len], 1
    jne .no
    cmp eax, 0x3E
    jb .bm32go                 ; 00-3D: ALU/mov/test (acc-imm incluso)
    cmp eax, 0x50
    jb .no
    cmp eax, 0x60
    jb .bm32go                 ; push/pop reg (size corrigido em .l1_pushr)
    cmp eax, 0x68
    je .bm32go                 ; push imm32
    cmp eax, 0x6A
    je .bm32go                 ; push imm8
    cmp eax, 0x84
    jb .no
    cmp eax, 0x8C
    jb .bm32go                 ; 84-8B: test/xchg/mov (8C Sreg fora)
    cmp eax, 0x8D
    je .bm32go                 ; lea
    cmp eax, 0xA8
    je .bm32go                 ; test al,imm8
    cmp eax, 0xA9
    je .bm32go                 ; test eAX,imm
    cmp eax, 0xC2
    je .bm32go                 ; ret imm16
    cmp eax, 0xC3
    je .bm32go                 ; ret
    cmp eax, 0xD8
    jb .no
    cmp eax, 0xE0
    jb .bm32go                 ; D8-DF: x87 (2a; memória absoluta em x32)
    cmp eax, 0xE4
    jb .bm32go                 ; loop/jcxz
    cmp eax, 0xE8
    je .bm32go                 ; call rel
    cmp eax, 0xE9
    je .bm32go                 ; jmp rel
    cmp eax, 0xEB
    je .bm32go                 ; jmp rel8
    cmp eax, 0xFE
    je .bm32go                 ; inc/dec r/m8
    cmp eax, 0xFF
    je .bm32go                 ; inc/dec/call/jmp/push r/m (/3,/5,/7 caem em .no)
    jmp .no
.bm32_l2:
    ; len2: movzx/movsx/cmov/setcc (handlers auditados; resto cai em .no)
    cmp eax, 0x40
    jb .no
    cmp eax, 0x50
    jb .bm32go                 ; cmovcc
    cmp eax, 0x90
    jb .no
    cmp eax, 0xA0
    jb .bm32go                 ; setcc
    cmp eax, 0xB6
    je .bm32go                 ; movzx m8
    cmp eax, 0xB7
    je .bm32go                 ; movzx m16
    cmp eax, 0xBE
    je .bm32go                 ; movsx m8
    cmp eax, 0xBF
    je .bm32go                 ; movsx m16
    jmp .no
.bm32go:
    ; cai no dispatch normal abaixo (paths com REX nunca tomados em x32)
.bm64:
    mov r10d, [rbx+Insn.opcode]
    mov r11d, [rbx+Insn.opcode_len]
    cmp r11d, 1
    je .len1
    cmp r11d, 2
    je .len2
    jmp .no                    ; len3 (0F38/3A): db
.no:
    ; limpar ops (evita meio-preenchido → emitter db limpo)
    mov qword [rbx+Insn.op0+0], 0
    mov qword [rbx+Insn.op0+8], 0
    mov qword [rbx+Insn.op1+0], 0
    mov qword [rbx+Insn.op1+8], 0
    mov qword [rbx+Insn.op2+0], 0
    mov qword [rbx+Insn.op2+8], 0
    mov eax, 1
    pop rbx
    pop rbp
    ret
.ok:
    xor eax, eax
    pop rbx
    pop rbp
    ret

; Notas de registradores (sem calls: só voláteis + rbx):
;   rbx=insn, r10d=opcode, r11d=oplen. Scratch: rax,rcx,rdx,r8,r9.
;   r8d = mod/reg/rm expandidos conforme necessário por bloco.

;-----------------------------------------------------------------------------
; .len1 — opcode de 1 byte (b0 em r10d&0xFF)
;-----------------------------------------------------------------------------
.len1:
    mov eax, r10d
    and eax, 0xFF              ; b0
    ; branches relativos? (is_branch||is_call) && imm 1/4 → op0=REL
    mov cl, [rbx+Insn.is_branch]
    or cl, [rbx+Insn.is_call]
    jz .l1_nomrel
    movzx ecx, byte [rbx+Insn.imm_size]
    cmp cl, 1
    je .l1_rel
    cmp cl, 4
    je .l1_rel
.l1_nomrel:
    ; ---- switch por b0 ----
    cmp eax, 0x90
    je .l1_90
    cmp eax, 0xC3
    je .ok                    ; ret (mne tbl, sem ops)
    cmp eax, 0xCB
    je .l1_retf
    cmp eax, 0xC9
    je .ok                    ; leave
    cmp eax, 0xCC
    je .ok                    ; int3
    cmp eax, 0xF4
    je .ok                    ; hlt
    cmp eax, 0xF5
    je .l1_cmc
    cmp eax, 0xF8
    je .l1_clc
    cmp eax, 0xF9
    je .l1_stc
    cmp eax, 0xFA
    je .l1_cli
    cmp eax, 0xFB
    je .l1_sti
    cmp eax, 0xFC
    je .l1_cld
    cmp eax, 0xFD
    je .l1_std
    cmp eax, 0x9B
    je .l1_wait
    cmp eax, 0x9C
    je .l1_pushf
    cmp eax, 0x9D
    je .l1_popf
    cmp eax, 0x9E
    je .l1_sahf
    cmp eax, 0x9F
    je .l1_lahf
    cmp eax, 0xF1
    je .l1_int1
    cmp eax, 0xCD
    je .l1_int
    cmp eax, 0xD4
    je .l1_aam
    cmp eax, 0xD5
    je .l1_aad
    cmp eax, 0xD7
    je .l1_xlat
    cmp eax, 0xC8
    je .l1_enter
    cmp eax, 0xC2
    je .l1_retimm
    cmp eax, 0xCA
    je .l1_retimm_ca
    cmp eax, 0x50
    jb .l1_alu1               ; < 0x50
    cmp eax, 0x60
    jb .l1_pushr               ; 50-5F
    cmp eax, 0x68
    jb .l1_60                  ; 60-67
    cmp eax, 0x70
    jb .l1_pushimm             ; 68-6F
    cmp eax, 0x80
    jb .l1_jcc8                ; 70-7F (op0=REL já tratado acima!)
    cmp eax, 0x84
    jb .l1_grp1                ; 80-83
    cmp eax, 0x88
    jb .l1_testx               ; 84-87
    cmp eax, 0x90
    jb .l1_mov1                ; 88-8F
    jmp .l1_high
.l1_rel:
    mov byte [rbx+Insn.op0+DexOp.kind], DEX_OP_REL
    mov rax, [rbx+Insn.target_va]
    mov [rbx+Insn.op0+DexOp.val], rax
    jmp .ok
.l1_retf:
    lea rax, [rel s_retf]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l1_cmc:
    lea rax, [rel s_cmc]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l1_clc:
    lea rax, [rel s_clc]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l1_stc:
    lea rax, [rel s_stc]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l1_cli:
    lea rax, [rel s_cli]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l1_sti:
    lea rax, [rel s_sti]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l1_cld:
    lea rax, [rel s_cld]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l1_std:
    lea rax, [rel s_std]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l1_wait:
    lea rax, [rel s_wait]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l1_pushf:
    cmp byte [rbx+Insn.legacy66], 0
    jne .no                    ; pushfw: db
    lea rax, [rel s_pushfq]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l1_popf:
    cmp byte [rbx+Insn.legacy66], 0
    jne .no
    lea rax, [rel s_popfq]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l1_sahf:
    lea rax, [rel s_sahf]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l1_lahf:
    lea rax, [rel s_lahf]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l1_int1:
    lea rax, [rel s_int1]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l1_int:
    mov byte [rbx+Insn.op0+DexOp.kind], DEX_OP_IMM
    mov byte [rbx+Insn.op0+DexOp.size], 1
    mov rax, [rbx+Insn.imm]
    mov [rbx+Insn.op0+DexOp.val], rax
    jmp .ok                    ; mne s_int da tabela
.l1_aam:
    lea rax, [rel s_aam]
    mov [rbx+Insn.mne], rax
    mov byte [rbx+Insn.op0+DexOp.kind], DEX_OP_IMM
    mov byte [rbx+Insn.op0+DexOp.size], 1
    mov rax, [rbx+Insn.imm]
    mov [rbx+Insn.op0+DexOp.val], rax
    jmp .ok
.l1_aad:
    lea rax, [rel s_aad]
    mov [rbx+Insn.mne], rax
    mov byte [rbx+Insn.op0+DexOp.kind], DEX_OP_IMM
    mov byte [rbx+Insn.op0+DexOp.size], 1
    mov rax, [rbx+Insn.imm]
    mov [rbx+Insn.op0+DexOp.val], rax
    jmp .ok
.l1_xlat:
    lea rax, [rel s_xlatb]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l1_enter:
    lea rax, [rel s_enter]
    mov [rbx+Insn.mne], rax
    mov rax, [rbx+Insn.imm]    ; combinado: low16 + high8<<16
    mov byte [rbx+Insn.op0+DexOp.kind], DEX_OP_IMM
    mov byte [rbx+Insn.op0+DexOp.size], 2
    movzx ecx, ax
    mov [rbx+Insn.op0+DexOp.val], rcx
    shr rax, 16
    mov byte [rbx+Insn.op1+DexOp.kind], DEX_OP_IMM
    mov byte [rbx+Insn.op1+DexOp.size], 1
    mov [rbx+Insn.op1+DexOp.val], rax
    jmp .ok
.l1_retimm:
    mov byte [rbx+Insn.op0+DexOp.kind], DEX_OP_IMM
    mov byte [rbx+Insn.op0+DexOp.size], 2
    mov rax, [rbx+Insn.imm]
    mov [rbx+Insn.op0+DexOp.val], rax
    jmp .ok                    ; C2 tem s_ret
.l1_retimm_ca:
    lea rax, [rel s_ret]
    mov [rbx+Insn.mne], rax    ; CA tinha mne=0
    mov byte [rbx+Insn.op0+DexOp.kind], DEX_OP_IMM
    mov byte [rbx+Insn.op0+DexOp.size], 2
    mov rax, [rbx+Insn.imm]
    mov [rbx+Insn.op0+DexOp.val], rax
    jmp .ok
.l1_90:
    cmp byte [rbx+Insn.rep], 0xF3
    je .l1_pause
    cmp byte [rbx+Insn.has_rex], 0
    jne .l1_90x
    jmp .ok                    ; nop (mne tbl)
.l1_pause:
    lea rax, [rel s_pause]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l1_90x:
    ; xchg r, eax: op0 = rd(+REX.B), op1 = eax
    movzx eax, byte [rbx+Insn.opcode]
    and eax, 7
    mov ecx, eax
    cmp byte [rbx+Insn.has_rex], 0
    je .l1_90x_nr
    test byte [rbx+Insn.rex], 1
    jz .l1_90x_nr
    add ecx, 8
.l1_90x_nr:
    mov byte [rbx+Insn.op0+DexOp.kind], DEX_OP_REG
    mov [rbx+Insn.op0+DexOp.reg], cl
    mov byte [rbx+Insn.op0+DexOp.size], 4
    cmp byte [rbx+Insn.has_rex], 0
    je .l1_90x32
    test byte [rbx+Insn.rex], 8
    jz .l1_90x32
    mov byte [rbx+Insn.op0+DexOp.size], 8
.l1_90x32:
    mov byte [rbx+Insn.op1+DexOp.kind], DEX_OP_REG
    mov byte [rbx+Insn.op1+DexOp.reg], 0
    mov al, [rbx+Insn.op0+DexOp.size]
    mov [rbx+Insn.op1+DexOp.size], al
    jmp .ok

; ---- 00-4F: ALU/mov/test + push/pop r64 ----
; r9d = opsize comum (REX.W→8, 66→2, senão 4) — 8-bit sobrescreve p/ 1.
.l1_alu1:
    cmp eax, 0x40
    jae .no                    ; 40-4F = REX (nunca opcode; defensivo)
    ; opsize comum
    mov r9d, 4
    cmp byte [rbx+Insn.has_rex], 0
    je .l1_sz66
    test byte [rbx+Insn.rex], 8
    jz .l1_sz66
    mov r9d, 8
    jmp .l1_szok
.l1_sz66:
    cmp byte [rbx+Insn.legacy66], 0
    je .l1_szok
    mov r9d, 2
.l1_szok:
    mov ecx, eax
    and ecx, 7                 ; low3: 0/1 rm,reg | 2/3 reg,rm | 4/5 acc,imm
    cmp ecx, 4
    jae .l1_acc
    ; precisa ModRM?
    cmp byte [rbx+Insn.has_modrm], 0
    je .no
    ; monta r/m + reg (tamanhos)
    movzx edx, byte [rbx+Insn.modrm]
    mov r8d, edx
    shr r8d, 3
    and r8d, 7                 ; reg0-7
    cmp byte [rbx+Insn.has_rex], 0
    je .l1_norx1
    test byte [rbx+Insn.rex], 4  ; REX.R?
    jz .l1_norx1
    add r8d, 8
.l1_norx1:
    ; op1 = reg (sempre); op0 = r/m (reg ou mem)
    mov byte [rbx+Insn.op1+DexOp.kind], DEX_OP_REG
    mov [rbx+Insn.op1+DexOp.reg], r8b
    mov r8d, r9d
    and eax, 1                 ; b0 ímpar? (01,03,...: 32/64; par: 8 bits)
    jz .l1_r8
    mov [rbx+Insn.op1+DexOp.size], r8b
    jmp .l1_rmk
.l1_r8:
    mov byte [rbx+Insn.op1+DexOp.size], 1
    mov r9d, 1                 ; r/m também 8 bits
.l1_rmk:
    ; op0 = r/m (reg ou mem) via helper unificado
    xor r8d, r8d               ; opidx 0
    sub rsp, 32
    call .build_rm
    add rsp, 32
    test eax, eax
    jnz .no
    ; direção: low3 0/1 → op0=r/m (já), op1=reg ✓; 2/3 → TROCAR
    mov eax, r10d
    and eax, 7
    cmp eax, 2
    jb .ok
    jmp .swap01
.l1_acc:
    ; 04/05/...: op0 = AL/eAX(/RAX), op1 = imm
    mov byte [rbx+Insn.op0+DexOp.kind], DEX_OP_REG
    mov byte [rbx+Insn.op0+DexOp.reg], 0
    cmp ecx, 4
    je .l1_acc8
    ; REX.W → rax,imm32 | 66 → ax,imm16 | senão eax,imm32
    cmp byte [rbx+Insn.has_rex], 0
    je .l1_acc66
    test byte [rbx+Insn.rex], 8
    jz .l1_acc66
    mov byte [rbx+Insn.op0+DexOp.size], 8
    mov byte [rbx+Insn.op1+DexOp.kind], DEX_OP_IMM
    mov byte [rbx+Insn.op1+DexOp.size], 4
    mov rax, [rbx+Insn.imm]
    mov [rbx+Insn.op1+DexOp.val], rax
    jmp .ok
.l1_acc66:
    cmp byte [rbx+Insn.legacy66], 0
    je .l1_acc32
    mov byte [rbx+Insn.op0+DexOp.size], 2
    mov byte [rbx+Insn.op1+DexOp.kind], DEX_OP_IMM
    mov byte [rbx+Insn.op1+DexOp.size], 2
    mov rax, [rbx+Insn.imm]
    mov [rbx+Insn.op1+DexOp.val], rax
    jmp .ok
.l1_acc32:
    mov byte [rbx+Insn.op0+DexOp.size], 4
    mov byte [rbx+Insn.op1+DexOp.kind], DEX_OP_IMM
    mov byte [rbx+Insn.op1+DexOp.size], 4
    mov rax, [rbx+Insn.imm]
    mov [rbx+Insn.op1+DexOp.val], rax
    jmp .ok                    ; mne (add/or/...) da tabela
.l1_acc8:
    mov byte [rbx+Insn.op0+DexOp.size], 1
    mov byte [rbx+Insn.op1+DexOp.kind], DEX_OP_IMM
    mov byte [rbx+Insn.op1+DexOp.size], 1
    mov rax, [rbx+Insn.imm]
    mov [rbx+Insn.op1+DexOp.val], rax
    jmp .ok
.l1_pushr:
    ; 50-57 push r / 58-5F pop r (+REX.B em x64); 66 → 16 bits.
    ; x32: sempre 32 bits (sem REX; r8-r15 não existem).
    movzx ecx, al
    and ecx, 7
    cmp byte [rbx+Insn.addr_mode], 1
    je .l1_pr32
    cmp byte [rbx+Insn.has_rex], 0
    je .l1_pr_nr
    test byte [rbx+Insn.rex], 1
    jz .l1_pr_nr
    add ecx, 8
.l1_pr_nr:
    mov byte [rbx+Insn.op0+DexOp.kind], DEX_OP_REG
    mov [rbx+Insn.op0+DexOp.reg], cl
    mov byte [rbx+Insn.op0+DexOp.size], 8
    cmp byte [rbx+Insn.legacy66], 0
    je .ok
    mov byte [rbx+Insn.op0+DexOp.size], 2
    jmp .ok
.l1_pr32:
    mov byte [rbx+Insn.op0+DexOp.kind], DEX_OP_REG
    mov [rbx+Insn.op0+DexOp.reg], cl
    mov byte [rbx+Insn.op0+DexOp.size], 4
    cmp byte [rbx+Insn.legacy66], 0
    je .ok
    mov byte [rbx+Insn.op0+DexOp.size], 2
    jmp .ok
.l1_60:
    cmp eax, 0x63
    je .l1_movsxd
    jmp .no                    ; 60-62,64-67: inválido/prefixo em 64-bit → db
.l1_movsxd:
    ; 63: op0 = r32 (sem REX.W) ou r64 (REX.W), op1 = r/m32
    cmp byte [rbx+Insn.has_modrm], 0
    je .no
    movzx ecx, byte [rbx+Insn.modrm]
    mov edx, ecx
    shr edx, 3
    and edx, 7
    cmp byte [rbx+Insn.has_rex], 0
    je .l1_sxd_nr
    test byte [rbx+Insn.rex], 4
    jz .l1_sxd_nr
    add edx, 8
.l1_sxd_nr:
    mov byte [rbx+Insn.op0+DexOp.kind], DEX_OP_REG
    mov [rbx+Insn.op0+DexOp.reg], dl
    mov byte [rbx+Insn.op0+DexOp.size], 4
    cmp byte [rbx+Insn.has_rex], 0
    je .l1_sxd32
    test byte [rbx+Insn.rex], 8
    jz .l1_sxd32
    mov byte [rbx+Insn.op0+DexOp.size], 8
.l1_sxd32:
    mov r9d, 4                 ; fonte sempre 32 bits
    mov r8d, 1
    sub rsp, 32
    call .build_rm
    add rsp, 32
    test eax, eax
    jnz .no
    jmp .ok                    ; mne s_movsxd da tabela
.l1_pushimm:
    cmp eax, 0x68
    je .l1_pushiv
    cmp eax, 0x6A
    je .l1_pushi8
    ; 69/6B imul
    cmp byte [rbx+Insn.has_modrm], 0
    je .no
    ; op0 = reg(modrm.reg+REX.R), op1 = r/m, op2 = imm
    movzx ecx, byte [rbx+Insn.modrm]
    mov edx, ecx
    shr edx, 3
    and edx, 7
    cmp byte [rbx+Insn.has_rex], 0
    je .l1_im_nr
    test byte [rbx+Insn.rex], 4
    jz .l1_im_nr
    add edx, 8
.l1_im_nr:
    mov byte [rbx+Insn.op0+DexOp.kind], DEX_OP_REG
    mov [rbx+Insn.op0+DexOp.reg], dl
    ; opsize imul: REX.W→8, 66→2, senão 4
    mov r9d, 4
    cmp byte [rbx+Insn.has_rex], 0
    je .l1_im66
    test byte [rbx+Insn.rex], 8
    jz .l1_im66
    mov r9d, 8
    jmp .l1_imsz
.l1_im66:
    cmp byte [rbx+Insn.legacy66], 0
    je .l1_imsz
    mov r9d, 2
.l1_imsz:
    mov [rbx+Insn.op0+DexOp.size], r9b
    ; op1 = r/m (opidx 1, size r9)
    mov r8d, 1                 ; opidx
    sub rsp, 32
    call .build_rm
    add rsp, 32
    test eax, eax
    jnz .no
    ; op2 = imm (tamanho: 6B→1, 69→opsize)
    mov byte [rbx+Insn.op2+DexOp.kind], DEX_OP_IMM
    movzx ecx, byte [rbx+Insn.opcode]
    cmp ecx, 0x6B
    je .l1_im8
    mov [rbx+Insn.op2+DexOp.size], r9b
    jmp .l1_imv
.l1_im8:
    mov byte [rbx+Insn.op2+DexOp.size], 1
.l1_imv:
    mov rax, [rbx+Insn.imm]
    mov [rbx+Insn.op2+DexOp.val], rax
    jmp .ok
.l1_pushiv:
    mov byte [rbx+Insn.op0+DexOp.kind], DEX_OP_IMM
    cmp byte [rbx+Insn.legacy66], 0
    je .l1_pi32
    mov byte [rbx+Insn.op0+DexOp.size], 2
    jmp .l1_piv
.l1_pi32:
    mov byte [rbx+Insn.op0+DexOp.size], 4
.l1_piv:
    mov rax, [rbx+Insn.imm]
    mov [rbx+Insn.op0+DexOp.val], rax
    ; push-68: sem strict possível (68 não tem forma dword): imm16 (66)
    ; sempre diverge (nasm: 6A/68 sem 66) e imm32 curto vira 6A: db.
    cmp byte [rbx+Insn.legacy66], 0
    jne .no
    add rax, 128
    cmp rax, 255
    jbe .no
    jmp .ok
.l1_pushi8:
    mov byte [rbx+Insn.op0+DexOp.kind], DEX_OP_IMM
    mov byte [rbx+Insn.op0+DexOp.size], 1
    mov rax, [rbx+Insn.imm]
    mov [rbx+Insn.op0+DexOp.val], rax
    jmp .ok
.l1_jcc8:
    jmp .no                    ; 70-7F sempre têm rel (tratado acima); defensivo=db
.l1_grp1:
    ; 80-83: mne = grp1[reg], op0 = r/m, op1 = imm
    cmp byte [rbx+Insn.has_modrm], 0
    je .no
    movzx eax, byte [rbx+Insn.modrm]
    shr eax, 3
    and eax, 7
    lea rcx, [rel dex_grp1_mne]
    mov rax, [rcx+rax*8]
    mov [rbx+Insn.mne], rax
    ; opsize do imm: 80/82→1, 81→v, 83→1
    movzx ecx, byte [rbx+Insn.opcode]
    cmp ecx, 0x81
    je .l1_g1v
    mov r9d, 1
    jmp .l1_g1m
.l1_g1v:
    mov r9d, 4
    cmp byte [rbx+Insn.has_rex], 0
    je .l1_g166
    test byte [rbx+Insn.rex], 8
    jz .l1_g166
    mov r9d, 8                ; REX.W: imm32 (sign-ext)? 81 = Iv (imm32, não 64!)
    mov r9d, 4                ; correção: 81 sempre imm32
    jmp .l1_g1m
.l1_g166:
    cmp byte [rbx+Insn.legacy66], 0
    je .l1_g1m
    mov r9d, 2
.l1_g1m:
    ; op0 = r/m (size: 80/82→1, senão opsize)
    movzx ecx, byte [rbx+Insn.opcode]
    cmp ecx, 0x80
    je .l1_g18
    cmp ecx, 0x82
    je .l1_g18
    ; 81/83: size = opsize (REX.W→8, 66→2, senão 4)
    mov ecx, 4
    cmp byte [rbx+Insn.has_rex], 0
    je .l1_g1s66
    test byte [rbx+Insn.rex], 8
    jz .l1_g1s66
    mov ecx, 8
    jmp .l1_g1sz
.l1_g1s66:
    cmp byte [rbx+Insn.legacy66], 0
    je .l1_g1sz
    mov ecx, 2
    jmp .l1_g1sz
.l1_g18:
    mov ecx, 1
.l1_g1sz:
    mov r9d, ecx
    xor r8d, r8d
    sub rsp, 32
    call .build_rm
    add rsp, 32
    test eax, eax
    jnz .no
    mov byte [rbx+Insn.op1+DexOp.kind], DEX_OP_IMM
    mov al, [rbx+Insn.op0+DexOp.size]
    ; imm size: 80/82/83→1; 81→ (66?2:4)
    movzx ecx, byte [rbx+Insn.opcode]
    cmp ecx, 0x81
    je .l1_g1iv
    mov byte [rbx+Insn.op1+DexOp.size], 1
    jmp .l1_g1vv
.l1_g1iv:
    cmp byte [rbx+Insn.legacy66], 0
    je .l1_g1i32
    mov byte [rbx+Insn.op1+DexOp.size], 2
    jmp .l1_g1vv
.l1_g1i32:
    mov byte [rbx+Insn.op1+DexOp.size], 4
.l1_g1vv:
    mov rax, [rbx+Insn.imm]
    mov [rbx+Insn.op1+DexOp.val], rax
    ; Forma geral + acumulador: o nasm prefere a forma curta de acumulador
    ; (04/05/0C../3C/3D, 2-5B) e muda o tamanho — ex: 81 C0 6B -> 05.
    ; 83+acc também (04 2B < 83 3B). Compiladores emitem a forma curta;
    ; a geral+acc só aparece artesanal: db honesto.
    cmp byte [rbx+Insn.op0+DexOp.kind], DEX_OP_REG
    jne .l1_g1nat
    cmp byte [rbx+Insn.op0+DexOp.reg], 0
    jne .l1_g1nat
    movzx eax, byte [rbx+Insn.opcode]
    cmp eax, 0x80
    jb .l1_g1nat
    cmp eax, 0x83
    jbe .no
.l1_g1nat:
    ; 81 largo que cabe em i8: nasm trocaria 81->83 (6B->3B): db.
    ; (81+acc já saiu acima; 66+imm16 sem forma curta alternativa: o 83+66
    ; é MAIS curto que 81+66, então qualquer 81+fits-i8 diverge: db.)
    movzx eax, byte [rbx+Insn.opcode]
    cmp eax, 0x81
    jne .ok
    mov rax, [rbx+Insn.imm]
    add rax, 128
    cmp rax, 255
    jbe .no
    jmp .ok
.l1_testx:
    ; 84/85 test r/m,reg + 86/87 xchg
    cmp byte [rbx+Insn.has_modrm], 0
    je .no
    mov r9d, 4
    cmp byte [rbx+Insn.has_rex], 0
    je .l1_tx66
    test byte [rbx+Insn.rex], 8
    jz .l1_tx66
    mov r9d, 8
    jmp .l1_txsz
.l1_tx66:
    cmp byte [rbx+Insn.legacy66], 0
    je .l1_txsz
    mov r9d, 2
.l1_txsz:
    movzx eax, byte [rbx+Insn.opcode]
    test eax, 1               ; 85/87 (ímpar)? 84/86 têm r/m8
    jnz .l1_txv
    mov r9d, 1
.l1_txv:
    ; op0 = r/m, op1 = reg(modrm.reg+REX.R)
    movzx eax, byte [rbx+Insn.modrm]
    mov ecx, eax
    shr ecx, 3
    and ecx, 7
    cmp byte [rbx+Insn.has_rex], 0
    je .l1_txnr
    test byte [rbx+Insn.rex], 4
    jz .l1_txnr
    add ecx, 8
.l1_txnr:
    mov byte [rbx+Insn.op1+DexOp.kind], DEX_OP_REG
    mov [rbx+Insn.op1+DexOp.reg], cl
    mov [rbx+Insn.op1+DexOp.size], r9b
    xor r8d, r8d
    sub rsp, 32
    call .build_rm
    add rsp, 32
    test eax, eax
    jnz .no
    jmp .ok
.l1_mov1:
    ; 88-8B mov + 8C (mov r/m,Sreg) + 8D (lea) + 8E (mov Sreg,r/m) + 8F (pop)
    movzx eax, byte [rbx+Insn.opcode]
    cmp eax, 0x8C
    je .l1_movS
    cmp eax, 0x8D
    je .l1_lea
    cmp eax, 0x8E
    je .l1_movS2
    cmp eax, 0x8F
    je .l1_poprm
    cmp byte [rbx+Insn.has_modrm], 0
    je .no
    mov r9d, 4
    cmp byte [rbx+Insn.has_rex], 0
    je .l1_mv66
    test byte [rbx+Insn.rex], 8
    jz .l1_mv66
    mov r9d, 8
    jmp .l1_mvsz
.l1_mv66:
    cmp byte [rbx+Insn.legacy66], 0
    je .l1_mvsz
    mov r9d, 2
.l1_mvsz:
    test eax, 1               ; 89/8B (ímpar)? 88/8A são r/m8
    jnz .l1_mvv
    mov r9d, 1
.l1_mvv:
    movzx ecx, byte [rbx+Insn.modrm]
    mov edx, ecx
    shr edx, 3
    and edx, 7
    cmp byte [rbx+Insn.has_rex], 0
    je .l1_mvnr
    test byte [rbx+Insn.rex], 4
    jz .l1_mvnr
    add edx, 8
.l1_mvnr:
    test eax, 1
    jz .l1_mv_rmreg
    ; 89/8B? NÃO: 89=rm,reg; 8B=reg,rm. Ímpar não decide! 89 ímpar→rm,reg; 8B ímpar→reg,rm.
    cmp eax, 0x8B
    je .l1_mv_regfirst
    cmp eax, 0x89
    je .l1_mv_rmfirst
    jmp .no
.l1_mv_rmreg:
    ; 88/8A par: 88=rm,reg; 8A=reg,rm
    cmp eax, 0x8A
    je .l1_mv_regfirst
    ; 0x88: rm,reg
.l1_mv_rmfirst:
    mov byte [rbx+Insn.op1+DexOp.kind], DEX_OP_REG
    mov [rbx+Insn.op1+DexOp.reg], dl
    mov [rbx+Insn.op1+DexOp.size], r9b
    xor r8d, r8d
    sub rsp, 32
    call .build_rm
    add rsp, 32
    test eax, eax
    jnz .no
    jmp .ok
.l1_mv_regfirst:
    ; op0 = reg, op1 = r/m: construir r/m em op1 primeiro (sem swap!)
    ; ATENÇÃO: .build_rm CLOBBERA edx (usa p/ base SIB) — spill em r10d
    ; (preservado por contrato; r10d=opcode morto daqui até .ok).
    ; Bug real 2026-10-07: `mov rdx,[rsp+..]` (SIB) saía `mov rsp,[..]`.
    mov r10d, edx
    mov r8d, 1                 ; opidx 1
    sub rsp, 32
    call .build_rm
    add rsp, 32
    test eax, eax
    jnz .no
    mov byte [rbx+Insn.op0+DexOp.kind], DEX_OP_REG
    mov dl, r10b
    mov [rbx+Insn.op0+DexOp.reg], dl
    mov [rbx+Insn.op0+DexOp.size], r9b
    jmp .ok
.l1_movS:
    ; 8C mov r/m16, Sreg
    cmp byte [rbx+Insn.has_modrm], 0
    je .no
    movzx eax, byte [rbx+Insn.modrm]
    mov ecx, eax
    shr ecx, 3
    and ecx, 7
    cmp ecx, 6
    jae .no                    ; Sreg 6/7 inválido em 64-bit → db
    mov byte [rbx+Insn.op1+DexOp.kind], DEX_OP_SEG
    mov [rbx+Insn.op1+DexOp.reg], cl  ; 0=es..(+1!) — ajustar: tabela usa 1-6!
    inc byte [rbx+Insn.op1+DexOp.reg]
    mov byte [rbx+Insn.op1+DexOp.size], 2
    mov r9d, 2
    xor r8d, r8d
    sub rsp, 32
    call .build_rm
    add rsp, 32
    test eax, eax
    jnz .no
    jmp .ok
.l1_lea:
    ; 8D: op0=reg(full size), op1=mem(sem size prefix — lea infere)
    cmp byte [rbx+Insn.has_modrm], 0
    je .no
    movzx eax, byte [rbx+Insn.modrm]
    mov ecx, eax
    shr ecx, 3
    and ecx, 7
    cmp byte [rbx+Insn.has_rex], 0
    je .l1_lea_nr
    test byte [rbx+Insn.rex], 4
    jz .l1_lea_nr
    add ecx, 8
.l1_lea_nr:
    mov byte [rbx+Insn.op0+DexOp.kind], DEX_OP_REG
    mov [rbx+Insn.op0+DexOp.reg], cl
    mov r9d, 4
    cmp byte [rbx+Insn.has_rex], 0
    je .l1_lea66
    test byte [rbx+Insn.rex], 8
    jz .l1_lea66
    mov r9d, 8
    jmp .l1_leasz
.l1_lea66:
    cmp byte [rbx+Insn.legacy66], 0
    je .l1_leasz
    mov r9d, 2
.l1_leasz:
    mov [rbx+Insn.op0+DexOp.size], r9b
    mov r8d, 1
    sub rsp, 32
    call .build_rm
    add rsp, 32
    test eax, eax
    jnz .no
    jmp .ok                    ; op0=reg, op1=mem (sem swap)
.l1_movS2:
    ; 8E mov Sreg, r/m16
    cmp byte [rbx+Insn.has_modrm], 0
    je .no
    movzx eax, byte [rbx+Insn.modrm]
    mov ecx, eax
    shr ecx, 3
    and ecx, 7
    cmp ecx, 6
    jae .no
    mov byte [rbx+Insn.op0+DexOp.kind], DEX_OP_SEG
    mov [rbx+Insn.op0+DexOp.reg], cl
    inc byte [rbx+Insn.op0+DexOp.reg]
    mov byte [rbx+Insn.op0+DexOp.size], 2
    mov r9d, 2
    mov r8d, 1
    sub rsp, 32
    call .build_rm
    add rsp, 32
    test eax, eax
    jnz .no
    jmp .ok
.l1_poprm:
    ; 8F /0: op0 = r/m (size opsize)
    cmp byte [rbx+Insn.has_modrm], 0
    je .no
    movzx eax, byte [rbx+Insn.modrm]
    shr eax, 3
    and eax, 7
    test eax, eax
    jnz .no                    ; só /0 válido → db
    mov r9d, 4
    cmp byte [rbx+Insn.has_rex], 0
    je .l1_pr66
    test byte [rbx+Insn.rex], 8
    jz .l1_pr66
    mov r9d, 8
    jmp .l1_prsz
.l1_pr66:
    cmp byte [rbx+Insn.legacy66], 0
    je .l1_prsz
    mov r9d, 2
.l1_prsz:
    xor r8d, r8d
    sub rsp, 32
    call .build_rm
    add rsp, 32
    test eax, eax
    jnz .no
    ; 8F pop r/m16/64 (sem forma 32!): size 4 calculado → 8
    cmp byte [rbx+Insn.op0+DexOp.size], 4
    jne .ok
    mov byte [rbx+Insn.op0+DexOp.size], 8
    jmp .ok
.l1_high:
    ; B0-BF mov r,imm | C0-FF grupos e misc | A0-AF | E0-EF | F0-FF
    movzx eax, byte [rbx+Insn.opcode]
    cmp eax, 0x98
    je .ok                    ; cbw/cdq (mne tbl; emitter especializa)
    cmp eax, 0x99
    je .ok
    cmp eax, 0xA4
    jb .l1_high2
    cmp eax, 0xB0
    jb .l1_strop               ; A4-AF string ops
.l1_high2:
    cmp eax, 0xA8
    je .l1_testacc
    cmp eax, 0xA9
    je .l1_testacc
    cmp eax, 0xB0
    jb .no
    cmp eax, 0xC0
    jb .l1_movri
    jmp .l1_crest               ; C0+: dispatch próprio (C0-C7, shifts,
                                ; loops, in/out, F6/F7, FF). Cair em .l1_testacc
                                ; aqui gerava operandos falsos (ex: C7 MEM
                                ; virava mov-reg) — invisível em db, fatal
                                ; no nativo (layout quebra). Fix 2026-10-07.
.l1_testacc:
    ; A8/A9: op0 = AL/eAX(/RAX), op1 = imm
    mov byte [rbx+Insn.op0+DexOp.kind], DEX_OP_REG
    mov byte [rbx+Insn.op0+DexOp.reg], 0
    cmp eax, 0xA8
    je .l1_ta8
    ; A9: REX.W→test rax,imm32 | 66→test ax,imm16 | senão test eax,imm32
    cmp byte [rbx+Insn.has_rex], 0
    je .l1_ta966
    test byte [rbx+Insn.rex], 8
    jz .l1_ta966
    mov byte [rbx+Insn.op0+DexOp.size], 8
    mov byte [rbx+Insn.op1+DexOp.kind], DEX_OP_IMM
    mov byte [rbx+Insn.op1+DexOp.size], 4
    mov rax, [rbx+Insn.imm]
    mov [rbx+Insn.op1+DexOp.val], rax
    jmp .ok
.l1_ta966:
    cmp byte [rbx+Insn.legacy66], 0
    je .l1_ta32
    mov byte [rbx+Insn.op0+DexOp.size], 2
    mov byte [rbx+Insn.op1+DexOp.kind], DEX_OP_IMM
    mov byte [rbx+Insn.op1+DexOp.size], 2
    mov rax, [rbx+Insn.imm]
    mov [rbx+Insn.op1+DexOp.val], rax
    jmp .ok
.l1_ta32:
    mov byte [rbx+Insn.op0+DexOp.size], 4
    mov byte [rbx+Insn.op1+DexOp.kind], DEX_OP_IMM
    mov byte [rbx+Insn.op1+DexOp.size], 4
    mov rax, [rbx+Insn.imm]
    mov [rbx+Insn.op1+DexOp.val], rax
    jmp .ok
.l1_ta8:
    mov byte [rbx+Insn.op0+DexOp.size], 1
    mov byte [rbx+Insn.op1+DexOp.kind], DEX_OP_IMM
    mov byte [rbx+Insn.op1+DexOp.size], 1
    mov rax, [rbx+Insn.imm]
    mov [rbx+Insn.op1+DexOp.val], rax
    jmp .ok
.l1_strop:
    ; A4-AF: mne base (emitter troca p/ ...q com REX.W); sem operandos
    cmp eax, 0xA4
    je .l1_st_movsb
    cmp eax, 0xA5
    je .l1_st_movsd
    cmp eax, 0xA6
    je .l1_st_cmpsb
    cmp eax, 0xA7
    je .l1_st_cmpsd
    cmp eax, 0xAA
    je .l1_st_stosb
    cmp eax, 0xAB
    je .l1_st_stosd
    cmp eax, 0xAC
    je .l1_st_lodsb
    cmp eax, 0xAD
    je .l1_st_lodsd
    cmp eax, 0xAE
    je .l1_st_scasb
    cmp eax, 0xAF
    je .l1_st_scasd
    jmp .no
.l1_st_movsb:
    lea rax, [rel s_movsb]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l1_st_movsd:
    lea rax, [rel s_movsd]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l1_st_cmpsb:
    lea rax, [rel s_cmpsb]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l1_st_cmpsd:
    lea rax, [rel s_cmpsd]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l1_st_stosb:
    lea rax, [rel s_stosb]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l1_st_stosd:
    lea rax, [rel s_stosd]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l1_st_lodsb:
    lea rax, [rel s_lodsb]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l1_st_lodsd:
    lea rax, [rel s_lodsd]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l1_st_scasb:
    lea rax, [rel s_scasb]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l1_st_scasd:
    lea rax, [rel s_scasd]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l1_crest:
    cmp eax, 0xC8
    jb .l1_cx                   ; C0-C7
    cmp eax, 0xD0
    jb .no                     ; C8-CF já tratados (enter/leave/ret/int)
    cmp eax, 0xD8
    jb .l1_shift                ; D0-D7 (D4/D5 já tratados; D6/D7→db aqui? não:
                               ; D4/D5 saíram acima; D0-D3 shifts, D6/D7 db)
    cmp eax, 0xE0
    jb .l1_x87                ; D8-DF x87 → mnemônico real (db byte-exato)
    cmp eax, 0xE4
    jb .l1_e0                   ; E0-E3 (rel, já com op0; só mne!)
    cmp eax, 0xE8
    jb .l1_inout                ; E4-E7 in/out → db (raro)
    cmp eax, 0xEC
    jb .l1_e88                  ; E8-EB (rel, já com op0)
    cmp eax, 0xF0
    jb .no                    ; EC-EF in/out dx → db
    cmp eax, 0xF4
    jb .l1_f0                   ; F0-F3 (F1=int1 já tratado)
    cmp eax, 0xF8
    jb .l1_f47                  ; F4-F7
    cmp eax, 0xFC
    jb .l1_flags2               ; F8-FB (mne já setado? não! setar aqui)
    jmp .l1_ffgrp               ; FC-FF
.l1_x87:
    ; R-2.7 + 2a: resolve o mnemônico real (fld/fadd/fstp/...) E a forma de
    ; operando (tabela x87), permitindo emissão nativa byte-exata. Ponto
    ; único de resolução x87; opcode em 0xD8-0xDF.
    mov rcx, rbx
    sub rsp, 40
    call dex_x87_mne
    add rsp, 40
    test rax, rax
    jz .no
    mov [rbx+Insn.mne], rax
    mov rcx, rbx
    sub rsp, 40
    call dex_x87_form
    add rsp, 40
    mov ecx, eax               ; shape (edx = mem size, só MEM)
    cmp ecx, X87_SH_DB
    je .no                     ; fstpnce: sem forma no NASM → db
    cmp ecx, X87_SH_NONE
    je .ok
    cmp ecx, X87_SH_MEM
    je .l1_x87_mem
    cmp ecx, X87_SH_AX
    je .l1_x87_ax
    ; formas com st(i): índice no ModRM
    movzx eax, byte [rbx+Insn.modrm]
    and eax, 7
    cmp ecx, X87_SH_ST
    je .l1_x87_st
    cmp ecx, X87_SH_ST0_ST
    je .l1_x87_st0st
    ; X87_SH_ST_ST0: st(i), st0
    mov byte [rbx+Insn.op0+DexOp.kind], DEX_OP_ST
    mov [rbx+Insn.op0+DexOp.reg], al
    mov byte [rbx+Insn.op1+DexOp.kind], DEX_OP_ST
    mov byte [rbx+Insn.op1+DexOp.reg], 0
    jmp .ok
.l1_x87_st:
    mov byte [rbx+Insn.op0+DexOp.kind], DEX_OP_ST
    mov [rbx+Insn.op0+DexOp.reg], al
    jmp .ok
.l1_x87_st0st:
    mov byte [rbx+Insn.op0+DexOp.kind], DEX_OP_ST
    mov byte [rbx+Insn.op0+DexOp.reg], 0
    mov byte [rbx+Insn.op1+DexOp.kind], DEX_OP_ST
    mov [rbx+Insn.op1+DexOp.reg], al
    jmp .ok
.l1_x87_ax:
    ; fnstsw ax
    mov byte [rbx+Insn.op0+DexOp.kind], DEX_OP_REG
    mov byte [rbx+Insn.op0+DexOp.reg], 0
    mov byte [rbx+Insn.op0+DexOp.size], 2
    jmp .ok
.l1_x87_mem:
    ; operando de memória: reaproveita .build_rm (ModRM/SIB/disp/seg e as
    ; regras de forma do emissor). r9d = tamanho vindo da tabela x87.
    mov r8d, 0                 ; opidx 0
    mov r9d, edx               ; size code
    sub rsp, 32
    call .build_rm
    add rsp, 32
    test eax, eax
    jnz .no                    ; forma sem db honesto (disp32 curto etc.)
    jmp .ok
.l1_movri:
    ; B0-B7: r8,imm8 | B8-BF: r,imm(v/64)
    mov ecx, eax
    and ecx, 7
    cmp byte [rbx+Insn.has_rex], 0
    je .l1_mri_nr
    test byte [rbx+Insn.rex], 1  ; REX.B?
    jz .l1_mri_nr
    add ecx, 8
.l1_mri_nr:
    mov byte [rbx+Insn.op0+DexOp.kind], DEX_OP_REG
    mov [rbx+Insn.op0+DexOp.reg], cl
    cmp eax, 0xB8
    jb .l1_mri8
    cmp byte [rbx+Insn.has_rex], 0
    je .l1_mrib
    test byte [rbx+Insn.rex], 8
    jz .l1_mrib
    mov byte [rbx+Insn.op0+DexOp.size], 8
    jmp .l1_mriv
.l1_mrib:
    cmp byte [rbx+Insn.legacy66], 0
    je .l1_mri32
    mov byte [rbx+Insn.op0+DexOp.size], 2
    jmp .l1_mriv
.l1_mri32:
    mov byte [rbx+Insn.op0+DexOp.size], 4
    jmp .l1_mriv
.l1_mri8:
    mov byte [rbx+Insn.op0+DexOp.size], 1
.l1_mriv:
    mov byte [rbx+Insn.op1+DexOp.kind], DEX_OP_IMM
    mov al, [rbx+Insn.op0+DexOp.size]
    mov [rbx+Insn.op1+DexOp.size], al
    mov rax, [rbx+Insn.imm]
    mov [rbx+Insn.op1+DexOp.val], rax
    jmp .ok
.l1_cx:
    ; C0/C1 grp2 imm8 | C6/C7 mov r/m,imm
    cmp eax, 0xC2
    jb .l1_sh8
    cmp eax, 0xC4
    jb .no                    ; C2/C3 já tratados
    ; C6/C7:
    cmp byte [rbx+Insn.has_modrm], 0
    je .no
    movzx ecx, byte [rbx+Insn.modrm]
    shr ecx, 3
    and ecx, 7
    test ecx, ecx
    jnz .no                    ; só /0 → db
    cmp eax, 0xC6
    je .l1_movib
    ; C7: size opsize (REX.W→? mov r/m64,imm32! imm é 32, size display 8?/4?)
    ; C7 com REX.W: mov r/m64, imm32 (sign-ext). Display: size 8, imm32.
    mov r9d, 4
    cmp byte [rbx+Insn.has_rex], 0
    je .l1_c766
    test byte [rbx+Insn.rex], 8
    jz .l1_c766
    mov r9d, 8
    jmp .l1_c7sz
.l1_c766:
    cmp byte [rbx+Insn.legacy66], 0
    je .l1_c7sz
    mov r9d, 2
.l1_c7sz:
    xor r8d, r8d
    sub rsp, 32
    call .build_rm
    add rsp, 32
    test eax, eax
    jnz .no
    mov byte [rbx+Insn.op1+DexOp.kind], DEX_OP_IMM
    cmp r9d, 8
    je .l1_c7i32
    mov [rbx+Insn.op1+DexOp.size], r9b
    jmp .l1_c7v
.l1_c7i32:
    mov byte [rbx+Insn.op1+DexOp.size], 4
.l1_c7v:
    mov rax, [rbx+Insn.imm]
    mov [rbx+Insn.op1+DexOp.val], rax
    jmp .ok
.l1_movib:
    mov r9d, 1
    xor r8d, r8d
    sub rsp, 32
    call .build_rm
    add rsp, 32
    test eax, eax
    jnz .no
    mov byte [rbx+Insn.op1+DexOp.kind], DEX_OP_IMM
    mov byte [rbx+Insn.op1+DexOp.size], 1
    mov rax, [rbx+Insn.imm]
    mov [rbx+Insn.op1+DexOp.val], rax
    jmp .ok
.l1_sh8:
    ; C0/C1: mne = grp2[reg], op0 = r/m, op1 = imm8
    cmp byte [rbx+Insn.has_modrm], 0
    je .no
    movzx eax, byte [rbx+Insn.modrm]
    shr eax, 3
    and eax, 7
    lea rcx, [rel dex_grp2_mne]
    mov rax, [rcx+rax*8]
    mov [rbx+Insn.mne], rax
    ; C0 par: opera r/m8 (66 → r/m16); C1: 4/8/2 (idem D0).
    movzx eax, byte [rbx+Insn.opcode]
    test eax, 1
    jnz .l1_sh32
    mov r9d, 1
    cmp byte [rbx+Insn.legacy66], 0
    je .l1_shsz
    mov r9d, 2
    jmp .l1_shsz
.l1_sh32:
    mov r9d, 4
    cmp byte [rbx+Insn.has_rex], 0
    je .l1_sh66
    test byte [rbx+Insn.rex], 8
    jz .l1_sh66
    mov r9d, 8
    jmp .l1_shsz
.l1_sh66:
    cmp byte [rbx+Insn.legacy66], 0
    je .l1_shsz
    mov r9d, 2
.l1_shsz:
    xor r8d, r8d
    sub rsp, 32
    call .build_rm
    add rsp, 32
    test eax, eax
    jnz .no
    mov byte [rbx+Insn.op1+DexOp.kind], DEX_OP_IMM
    mov byte [rbx+Insn.op1+DexOp.size], 1
    mov rax, [rbx+Insn.imm]
    mov [rbx+Insn.op1+DexOp.val], rax
    jmp .ok
.l1_shift:
    ; D0-D3 grp2 (imm1/CL) | D6/D7 → db
    cmp eax, 0xD4
    jae .no
    cmp byte [rbx+Insn.has_modrm], 0
    je .no
    movzx ecx, byte [rbx+Insn.modrm]
    mov edx, ecx
    shr edx, 3
    and edx, 7
    lea rax, [rel dex_grp2_mne]
    mov rax, [rax+rdx*8]
    mov [rbx+Insn.mne], rax
    mov r9d, 4
    cmp byte [rbx+Insn.has_rex], 0
    je .l1_sf66
    test byte [rbx+Insn.rex], 8  ; REX.W?
    jz .l1_sf66
    mov r9d, 8
    jmp .l1_sfs
.l1_sf66:
    cmp byte [rbx+Insn.legacy66], 0
    je .l1_sfs
    mov r9d, 2
.l1_sfs:
    ; D0/D2 operam r/m8 (opcode par)
    movzx ecx, byte [rbx+Insn.opcode]
    test ecx, 1
    jnz .l1_sfs2
    mov r9d, 1
.l1_sfs2:
    xor r8d, r8d
    sub rsp, 32
    call .build_rm
    add rsp, 32
    test eax, eax
    jnz .no
    movzx ecx, byte [rbx+Insn.opcode]
    cmp ecx, 0xD0
    je .l1_sf1
    cmp ecx, 0xD1
    je .l1_sf1
    ; D2/D3: op1 = CL
    mov byte [rbx+Insn.op1+DexOp.kind], DEX_OP_REG
    mov byte [rbx+Insn.op1+DexOp.reg], 1
    mov byte [rbx+Insn.op1+DexOp.size], 1
    jmp .ok
.l1_sf1:
    mov byte [rbx+Insn.op1+DexOp.kind], DEX_OP_IMM
    mov byte [rbx+Insn.op1+DexOp.size], 1
    mov qword [rbx+Insn.op1+DexOp.val], 1
    jmp .ok
.l1_e0:
    ; E0-E2 loop*: mne preciso; E3 jrcxz (emitter especializa jecxz)
    movzx eax, byte [rbx+Insn.opcode]
    cmp eax, 0xE0
    je .l1_loopne
    cmp eax, 0xE1
    je .l1_loope
    jmp .ok                    ; E2 loop / E3 jcc-marker (op0=REL já)
.l1_loopne:
    lea rax, [rel s_loopne]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l1_loope:
    lea rax, [rel s_loope]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l1_inout:
    jmp .no                    ; E4-E7 in/out → db
.l1_e88:
    jmp .ok                    ; E8-E9/EB: op0=REL já; mne tbl ok
.l1_f0:
    jmp .no                    ; F0 prefixo /F1 já tratado /F2/F3 prefixos
.l1_f47:
    ; F6/F7 grp3
    cmp byte [rbx+Insn.has_modrm], 0
    je .no
    movzx eax, byte [rbx+Insn.modrm]
    mov ecx, eax
    shr ecx, 3
    and ecx, 7
    cmp ecx, 1
    ja .l1_f47v               ; /2+ tem só r/m
    ; /0,/1 test: op0=r/m, op1=imm (imm já lido p/ ambos — ver operands fix)
    lea rax, [rel s_test]
    mov [rbx+Insn.mne], rax
    jmp .l1_f47rmi
.l1_f47v:
    lea rax, [rel dex_grp3_mne]
    mov rax, [rax+rcx*8]
    mov [rbx+Insn.mne], rax
    ; op0 = r/m (size: F6→1, F7→opsize)
    movzx eax, byte [rbx+Insn.opcode]
    cmp eax, 0xF6
    je .l1_f478
    mov r9d, 4
    cmp byte [rbx+Insn.has_rex], 0
    je .l1_f4766
    test byte [rbx+Insn.rex], 8
    jz .l1_f4766
    mov r9d, 8
    jmp .l1_f47m
.l1_f4766:
    cmp byte [rbx+Insn.legacy66], 0
    je .l1_f47m
    mov r9d, 2
    jmp .l1_f47m
.l1_f478:
    mov r9d, 1
.l1_f47m:
    xor r8d, r8d
    sub rsp, 32
    call .build_rm
    add rsp, 32
    test eax, eax
    jnz .no
    jmp .ok
.l1_f47rmi:
    ; /0,/1 test: size = REX.W?8 : 66?2 : (F6?1:4)
    movzx eax, byte [rbx+Insn.opcode]
    cmp eax, 0xF6
    je .l1_f47i8
    mov r9d, 4
    cmp byte [rbx+Insn.has_rex], 0
    je .l1_f47i66
    test byte [rbx+Insn.rex], 8
    jz .l1_f47i66
    mov r9d, 8
    jmp .l1_f47im
.l1_f47i66:
    cmp byte [rbx+Insn.legacy66], 0
    je .l1_f47im
    mov r9d, 2
    jmp .l1_f47im2
.l1_f47i8:
    mov r9d, 1
.l1_f47im:
    xor r8d, r8d
    sub rsp, 32
    call .build_rm
    add rsp, 32
    test eax, eax
    jnz .no
    mov byte [rbx+Insn.op1+DexOp.kind], DEX_OP_IMM
    cmp r9d, 8
    je .l1_f47ii32
    mov [rbx+Insn.op1+DexOp.size], r9b
    jmp .l1_f47iv
.l1_f47ii32:
    mov byte [rbx+Insn.op1+DexOp.size], 4
    jmp .l1_f47iv
.l1_f47im2:
    xor r8d, r8d
    sub rsp, 32
    call .build_rm
    add rsp, 32
    test eax, eax
    jnz .no
    mov byte [rbx+Insn.op1+DexOp.kind], DEX_OP_IMM
    mov [rbx+Insn.op1+DexOp.size], r9b
.l1_f47iv:
    mov rax, [rbx+Insn.imm]
    mov [rbx+Insn.op1+DexOp.val], rax
    ; test geral (F6/F7 /0-/1) + acumulador: nasm prefere A8/A9 e muda o
    ; tamanho (F6 3B->A8 2B; F7 7B->A9 6B): db honesto. (A8/A9 originais
    ; seguem outro caminho e são nativos.)
    cmp byte [rbx+Insn.op0+DexOp.kind], DEX_OP_REG
    jne .ok
    cmp byte [rbx+Insn.op0+DexOp.reg], 0
    jne .ok
    jmp .no
.l1_flags2:
    ; F8=clc F9=stc FA=cli FB=sti (sem operandos)
    movzx eax, byte [rbx+Insn.opcode]
    sub eax, 0xF8
    lea rcx, [rel .l1_flags2_tbl]
    mov rax, [rcx+rax*8]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l1_ffgrp:
    ; FE/FF grupos (FE: /0 inc /1 dec; FF: /0 inc /1 dec /2 call /4 jmp /6 push)
    cmp byte [rbx+Insn.has_modrm], 0
    je .no
    movzx eax, byte [rbx+Insn.modrm]
    mov ecx, eax
    shr ecx, 3
    and ecx, 7
    movzx edx, byte [rbx+Insn.opcode]
    cmp edx, 0xFE
    je .l1_fe
    ; FF:
    cmp ecx, 2
    je .l1_ff_ok
    cmp ecx, 4
    je .l1_ff_ok
    cmp ecx, 6
    je .l1_ff_ok
    cmp ecx, 0
    je .l1_ff_ok
    cmp ecx, 1
    je .l1_ff_ok
    jmp .no                    ; /3,/5,/7 (far) → db
.l1_ff_ok:
    lea rax, [rel dex_grp45_mne]
    mov rax, [rax+rcx*8]
    mov [rbx+Insn.mne], rax
    ; call/jmp 16-bit (66) não suportado no emissor → db
    cmp ecx, 2
    je .l1_ffck66
    cmp ecx, 4
    je .l1_ffck66
    jmp .l1_ffmem
.l1_ffck66:
    cmp byte [rbx+Insn.legacy66], 0
    jne .no
    jmp .l1_ffmem
.l1_fe:
    cmp ecx, 1
    ja .no
    lea rax, [rel dex_grp45_mne]
    mov rax, [rax+rcx*8]
    mov [rbx+Insn.mne], rax
    ; FE opera r/m8!
    mov r9d, 1
    xor r8d, r8d
    sub rsp, 32
    call .build_rm
    add rsp, 32
    test eax, eax
    jnz .no
    jmp .ok
.l1_ffmem:
    mov r9d, 4
    cmp byte [rbx+Insn.has_rex], 0
    je .l1_ff66
    test byte [rbx+Insn.rex], 8
    jz .l1_ff66
    mov r9d, 8
    jmp .l1_ffsz
.l1_ff66:
    cmp byte [rbx+Insn.legacy66], 0
    je .l1_ffsz
    mov r9d, 2
.l1_ffsz:
    xor r8d, r8d
    sub rsp, 32
    call .build_rm
    add rsp, 32
    test eax, eax
    jnz .no
    ; FF /2 call, /4 jmp, /6 push: sem forma 32 em 64 bits (só 16/64;
    ; 16 já caiu em db via .l1_ffck66). size 4 calculado aqui → 8.
    movzx eax, byte [rbx+Insn.modrm]
    shr eax, 3
    and eax, 7
    cmp eax, 6
    je .l1_ff64
    cmp eax, 2
    je .l1_ff64
    cmp eax, 4
    jne .ok
.l1_ff64:
    cmp byte [rbx+Insn.addr_mode], 1
    je .ok                    ; x32: size 4 correto (call/jmp/push 32-bit)
    cmp byte [rbx+Insn.op0+DexOp.size], 4
    jne .ok
    mov byte [rbx+Insn.op0+DexOp.size], 8
    jmp .ok

;-----------------------------------------------------------------------------
; .len2 — opcode 0F xx (b1 em r10d&0xFF)
;-----------------------------------------------------------------------------
.len2:
    mov eax, r10d
    and eax, 0xFF              ; b1
    cmp eax, 0x05
    je .l2_syscall
    cmp eax, 0x07
    je .l2_sysret
    cmp eax, 0x0B
    je .l2_ud2
    cmp eax, 0x1F
    je .l2_noprm
    cmp eax, 0x30
    je .l2_wrmsr
    cmp eax, 0x31
    je .l2_rdtsc
    cmp eax, 0x32
    je .l2_rdmsr
    cmp eax, 0x33
    je .l2_rdpmc
    cmp eax, 0x34
    je .l2_sysenter
    cmp eax, 0x35
    je .l2_sysexit
    cmp eax, 0x77
    je .l2_emms
    cmp eax, 0xA0
    je .l2_pushseg
    cmp eax, 0xA1
    je .l2_popseg
    cmp eax, 0xA2
    je .l2_cpuid
    cmp eax, 0xA8
    je .l2_pushseg
    cmp eax, 0xA9
    je .l2_popseg
    cmp eax, 0xF1
    je .l2_int1
    cmp eax, 0x80
    jb .l2_modrm               ; < 0x80: precisa análise (grupos/cmov/etc.)
    cmp eax, 0x90
    jb .l2_jcc32               ; 80-8F: jcc rel32 (op0=REL já!)
    cmp eax, 0xA0
    jb .l2_setcc               ; 90-9F: setcc r/m8
    cmp eax, 0xB0
    jb .l2_ax                  ; A0-AF
    cmp eax, 0xC0
    jb .l2_bx                  ; B0-BF
    cmp eax, 0xD0
    jb .l2_cx                  ; C0-CF (C8+ = bswap, resto db)
    jmp .no                    ; D0-FF: SSE/MMX → db
.l2_syscall:
    lea rax, [rel s_sysc]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l2_sysret:
    lea rax, [rel s_sysret]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l2_ud2:
    lea rax, [rel s_ud2]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l2_noprm:
    ; 0F1F: op0 = r/m (multibyte nop)
    lea rax, [rel s_nop]
    mov [rbx+Insn.mne], rax
    cmp byte [rbx+Insn.has_modrm], 0
    je .no
    mov r9d, 4
    cmp byte [rbx+Insn.has_rex], 0
    je .l2_n66
    test byte [rbx+Insn.rex], 8
    jz .l2_n66
    mov r9d, 8
    jmp .l2_nsz
.l2_n66:
    cmp byte [rbx+Insn.legacy66], 0
    je .l2_nsz
    mov r9d, 2
.l2_nsz:
    xor r8d, r8d
    sub rsp, 32
    call .build_rm
    add rsp, 32
    test eax, eax
    jnz .no
    jmp .ok                    ; mne s_nop? tbl2_mne 1F = s_sse! ajustar:
    ; (0F1F cai aqui com mne genérico; setar nop)
.l2_wrmsr:
    lea rax, [rel s_wrmsr]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l2_rdtsc:
    lea rax, [rel s_rdtsc]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l2_rdmsr:
    lea rax, [rel s_rdmsr]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l2_rdpmc:
    lea rax, [rel s_rdpmc]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l2_sysenter:
    lea rax, [rel s_sysenter]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l2_sysexit:
    lea rax, [rel s_sysexit]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l2_emms:
    lea rax, [rel s_emms]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l2_pushseg:
    jmp .no                    ; push FS/GS: raro, db por ora
.l2_popseg:
    jmp .no
.l2_cpuid:
    lea rax, [rel s_cpuid]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l2_int1:
    lea rax, [rel s_int1]
    mov [rbx+Insn.mne], rax
    jmp .ok
.l2_jcc32:
    ; 80-8F: op0 = REL (como .l1_rel do len1; aqui é explícito porque o
    ; len2 não tem o pré-dispatch de branches). mne jcc genérico: o
    ; emissor especializa via opcode&0xF. Sem isso saía `jl` nu.
    mov byte [rbx+Insn.op0+DexOp.kind], DEX_OP_REL
    mov rax, [rbx+Insn.target_va]
    mov [rbx+Insn.op0+DexOp.val], rax
    jmp .ok
.l2_setcc:
    ; 90-9F: op0 = r/m8
    cmp byte [rbx+Insn.has_modrm], 0
    je .no
    mov r9d, 1
    xor r8d, r8d
    sub rsp, 32
    call .build_rm
    add rsp, 32
    test eax, eax
    jnz .no
    jmp .ok                    ; mne setcc genérico (emitter especializa)
.l2_modrm:
    ; 00-7F exceto singles acima: grupos 00/01, cmov 40-4F, SSE 10-2F, sys 30-37...
    movzx eax, byte [rbx+Insn.opcode]
    cmp eax, 0x00
    je .l2_grp6
    cmp eax, 0x01
    je .l2_grp7
    cmp eax, 0x40
    jb .no                    ; 02-3F: LAR/LSL têm modrm mas raros? 02=LAR,03=LSL:
    cmp eax, 0x50              ; 40-4F cmov
    jb .l2_cmov
    cmp eax, 0x77
    ja .no
    jmp .no                    ; 50-77: SSE → db
.l2_grp6:
.l2_grp7:
    jmp .no                    ; grupos 6/7 (sldt/sidt/...) → db (raros, privilegiados)
.l2_cmov:
    cmp byte [rbx+Insn.has_modrm], 0
    je .no
    mov r9d, 4
    cmp byte [rbx+Insn.has_rex], 0
    je .l2_cv66
    test byte [rbx+Insn.rex], 8
    jz .l2_cv66
    mov r9d, 8
    jmp .l2_cvsz
.l2_cv66:
    cmp byte [rbx+Insn.legacy66], 0
    je .l2_cvsz
    mov r9d, 2
.l2_cvsz:
    movzx eax, byte [rbx+Insn.modrm]
    mov ecx, eax
    shr ecx, 3
    and ecx, 7
    cmp byte [rbx+Insn.has_rex], 0
    je .l2_cvnr
    test byte [rbx+Insn.rex], 4
    jz .l2_cvnr
    add ecx, 8
.l2_cvnr:
    mov byte [rbx+Insn.op0+DexOp.kind], DEX_OP_REG
    mov [rbx+Insn.op0+DexOp.reg], cl
    mov [rbx+Insn.op0+DexOp.size], r9b
    mov r8d, 1
    sub rsp, 32
    call .build_rm
    add rsp, 32
    test eax, eax
    jnz .no
    jmp .ok                    ; mne cmov genérico
.l2_ax:
    ; A3/BT, AB/BTS, B3/BTR, BB/BTC, A4/A5 SHLD, AC/AD SHRD, A6/A7 CMPXCHG
    movzx eax, byte [rbx+Insn.opcode]
    cmp eax, 0xA3
    je .l2_bt
    cmp eax, 0xAB
    je .l2_bt
    cmp eax, 0xB3
    je .l2_bt
    cmp eax, 0xBB
    je .l2_bt
    cmp eax, 0xA4
    je .l2_shld
    cmp eax, 0xAC
    je .l2_shrd
    cmp eax, 0xA5
    je .l2_shldC
    cmp eax, 0xAD
    je .l2_shrdC
    cmp eax, 0xA6
    je .l2_cmpx
    cmp eax, 0xA7
    je .l2_cmpx
    cmp eax, 0xBA
    je .l2_ba
    jmp .no
.l2_bt:
    ; mne por opcode: A3=bt, AB=bts, B3=btr, BB=btc
    movzx eax, byte [rbx+Insn.opcode]
    cmp eax, 0xA3
    je .l2_bt_bt
    cmp eax, 0xAB
    je .l2_bt_bts
    cmp eax, 0xB3
    je .l2_bt_btr
    lea rax, [rel s_btc]
    mov [rbx+Insn.mne], rax
    jmp .l2_btrm
.l2_bt_bt:
    lea rax, [rel s_bt]
    mov [rbx+Insn.mne], rax
    jmp .l2_btrm
.l2_bt_bts:
    lea rax, [rel s_bts]
    mov [rbx+Insn.mne], rax
    jmp .l2_btrm
.l2_bt_btr:
    lea rax, [rel s_btr]
    mov [rbx+Insn.mne], rax
    jmp .l2_btrm
.l2_cmpx:
    lea rax, [rel s_cmpx]
    mov [rbx+Insn.mne], rax
    jmp .l2_btrm
.l2_btrm:
    ; op0 = r/m, op1 = reg
    cmp byte [rbx+Insn.has_modrm], 0
    je .no
    mov r9d, 4
    cmp byte [rbx+Insn.has_rex], 0
    je .l2_bt66
    test byte [rbx+Insn.rex], 8
    jz .l2_bt66
    mov r9d, 8
    jmp .l2_btsz
.l2_bt66:
    cmp byte [rbx+Insn.legacy66], 0
    je .l2_btsz
    mov r9d, 2
.l2_btsz:
    movzx eax, byte [rbx+Insn.modrm]
    mov ecx, eax
    shr ecx, 3
    and ecx, 7
    cmp byte [rbx+Insn.has_rex], 0
    je .l2_btnr
    test byte [rbx+Insn.rex], 4
    jz .l2_btnr
    add ecx, 8
.l2_btnr:
    mov byte [rbx+Insn.op1+DexOp.kind], DEX_OP_REG
    mov [rbx+Insn.op1+DexOp.reg], cl
    mov [rbx+Insn.op1+DexOp.size], r9b
    xor r8d, r8d
    sub rsp, 32
    call .build_rm
    add rsp, 32
    test eax, eax
    jnz .no
    jmp .ok
.l2_shld:
    lea rax, [rel s_shld]
    mov [rbx+Insn.mne], rax
    jmp .l2_shdrm
.l2_shrd:
    lea rax, [rel s_shrd]
    mov [rbx+Insn.mne], rax
    jmp .l2_shdrm
.l2_shdrm:
    cmp byte [rbx+Insn.has_modrm], 0
    je .no
    mov r9d, 4
    cmp byte [rbx+Insn.has_rex], 0
    je .l2_sh66
    test byte [rbx+Insn.rex], 8
    jz .l2_sh66
    mov r9d, 8
    jmp .l2_shsz
.l2_sh66:
    cmp byte [rbx+Insn.legacy66], 0
    je .l2_shsz
    mov r9d, 2
.l2_shsz:
    movzx eax, byte [rbx+Insn.modrm]
    mov ecx, eax
    shr ecx, 3
    and ecx, 7
    cmp byte [rbx+Insn.has_rex], 0
    je .l2_shnr
    test byte [rbx+Insn.rex], 4
    jz .l2_shnr
    add ecx, 8
.l2_shnr:
    mov byte [rbx+Insn.op1+DexOp.kind], DEX_OP_REG
    mov [rbx+Insn.op1+DexOp.reg], cl
    mov [rbx+Insn.op1+DexOp.size], r9b
    xor r8d, r8d
    sub rsp, 32
    call .build_rm
    add rsp, 32
    test eax, eax
    jnz .no
    ; op2 = imm8 (A4/AC) — A5/AD caem aqui por engano? Não: A5/AD vão p/ CL.
    movzx eax, byte [rbx+Insn.opcode]
    cmp eax, 0xA5
    je .l2_shCL
    cmp eax, 0xAD
    je .l2_shCL
    mov byte [rbx+Insn.op2+DexOp.kind], DEX_OP_IMM
    mov byte [rbx+Insn.op2+DexOp.size], 1
    mov rax, [rbx+Insn.imm]
    mov [rbx+Insn.op2+DexOp.val], rax
    jmp .ok
.l2_shCL:
    mov byte [rbx+Insn.op2+DexOp.kind], DEX_OP_REG
    mov byte [rbx+Insn.op2+DexOp.reg], 1
    mov byte [rbx+Insn.op2+DexOp.size], 1
    jmp .ok
.l2_shldC:
    lea rax, [rel s_shld]
    mov [rbx+Insn.mne], rax
    jmp .l2_shCL2
.l2_shrdC:
    lea rax, [rel s_shrd]
    mov [rbx+Insn.mne], rax
.l2_shCL2:
    ; A5/AD: op0=r/m, op1=reg, op2=CL (duplica lógica shdrm + CL)
    cmp byte [rbx+Insn.has_modrm], 0
    je .no
    mov r9d, 4
    cmp byte [rbx+Insn.has_rex], 0
    je .l2_sh66b
    test byte [rbx+Insn.rex], 8
    jz .l2_sh66b
    mov r9d, 8
    jmp .l2_shszb
.l2_sh66b:
    cmp byte [rbx+Insn.legacy66], 0
    je .l2_shszb
    mov r9d, 2
.l2_shszb:
    movzx eax, byte [rbx+Insn.modrm]
    mov ecx, eax
    shr ecx, 3
    and ecx, 7
    cmp byte [rbx+Insn.has_rex], 0
    je .l2_shnrb
    test byte [rbx+Insn.rex], 4
    jz .l2_shnrb
    add ecx, 8
.l2_shnrb:
    mov byte [rbx+Insn.op1+DexOp.kind], DEX_OP_REG
    mov [rbx+Insn.op1+DexOp.reg], cl
    mov [rbx+Insn.op1+DexOp.size], r9b
    xor r8d, r8d
    sub rsp, 32
    call .build_rm
    add rsp, 32
    test eax, eax
    jnz .no
    mov byte [rbx+Insn.op2+DexOp.kind], DEX_OP_REG
    mov byte [rbx+Insn.op2+DexOp.reg], 1
    mov byte [rbx+Insn.op2+DexOp.size], 1
    jmp .ok
.l2_ba:
    ; 0FBA grupo 8: /4=bt /5=bts /6=btr /7=btc + imm8
    cmp byte [rbx+Insn.has_modrm], 0
    je .no
    movzx eax, byte [rbx+Insn.modrm]
    mov ecx, eax
    shr ecx, 3
    and ecx, 7
    cmp ecx, 4
    jb .no
    cmp ecx, 4
    je .l2_ba_bt
    cmp ecx, 5
    je .l2_ba_bts
    cmp ecx, 6
    je .l2_ba_btr
    lea rax, [rel s_btc]
    mov [rbx+Insn.mne], rax
    jmp .l2_ba_rm
.l2_ba_bt:
    lea rax, [rel s_bt]
    mov [rbx+Insn.mne], rax
    jmp .l2_ba_rm
.l2_ba_bts:
    lea rax, [rel s_bts]
    mov [rbx+Insn.mne], rax
    jmp .l2_ba_rm
.l2_ba_btr:
    lea rax, [rel s_btr]
    mov [rbx+Insn.mne], rax
.l2_ba_rm:
    mov r9d, 4
    cmp byte [rbx+Insn.has_rex], 0
    je .l2_ba66
    test byte [rbx+Insn.rex], 8
    jz .l2_ba66
    mov r9d, 8
    jmp .l2_basz
.l2_ba66:
    cmp byte [rbx+Insn.legacy66], 0
    je .l2_basz
    mov r9d, 2
.l2_basz:
    xor r8d, r8d
    sub rsp, 32
    call .build_rm
    add rsp, 32
    test eax, eax
    jnz .no
    mov byte [rbx+Insn.op1+DexOp.kind], DEX_OP_IMM
    mov byte [rbx+Insn.op1+DexOp.size], 1
    mov rax, [rbx+Insn.imm]
    mov [rbx+Insn.op1+DexOp.val], rax
    jmp .ok
.l2_bx:
    ; B6/B7 movzx, B8? (popcnt/inválido→db), B9 grupo10→db, BA (acima? não:
    ; BA está em A0-AF range! 0xBA < 0xC0 mas > 0xAF... meu dispatch: A0-AF
    ; trata A0-AB? .l2_ax cobre A0-AD via compares + BA? NÃO — BA cai em .l2_bx!
    movzx eax, byte [rbx+Insn.opcode]
    cmp eax, 0xB6
    je .l2_mzx
    cmp eax, 0xB7
    je .l2_mzx
    cmp eax, 0xBE
    je .l2_msx
    cmp eax, 0xBF
    je .l2_msx
    cmp eax, 0xBA
    je .l2_ba
    cmp eax, 0xBC
    je .l2_bsf
    cmp eax, 0xBD
    je .l2_bsr
    cmp eax, 0xBB
    je .l2_bt2
    cmp eax, 0xB3
    je .l2_bt2
    cmp eax, 0xB0
    je .l2_cmpx2
    cmp eax, 0xB1
    je .l2_cmpx2
    jmp .no
.l2_mzx:
    lea rax, [rel s_movzx]
    mov [rbx+Insn.mne], rax
    jmp .l2_msz
.l2_msx:
    lea rax, [rel s_movsx]
    mov [rbx+Insn.mne], rax
.l2_msz:
    ; op0=reg(opsize), op1=r/m(1 ou 2: B6/BE→1, B7/BF→2)
    cmp byte [rbx+Insn.has_modrm], 0
    je .no
    mov r9d, 4
    cmp byte [rbx+Insn.has_rex], 0
    je .l2_ms66
    test byte [rbx+Insn.rex], 8
    jz .l2_ms66
    mov r9d, 8
    jmp .l2_mssz
.l2_ms66:
    cmp byte [rbx+Insn.legacy66], 0
    je .l2_mssz
    mov r9d, 2
.l2_mssz:
    movzx eax, byte [rbx+Insn.modrm]
    mov ecx, eax
    shr ecx, 3
    and ecx, 7
    cmp byte [rbx+Insn.has_rex], 0
    je .l2_msnr
    test byte [rbx+Insn.rex], 4
    jz .l2_msnr
    add ecx, 8
.l2_msnr:
    mov byte [rbx+Insn.op0+DexOp.kind], DEX_OP_REG
    mov [rbx+Insn.op0+DexOp.reg], cl
    mov [rbx+Insn.op0+DexOp.size], r9b
    movzx eax, byte [rbx+Insn.opcode]
    cmp eax, 0xB6
    je .l2_ms8
    cmp eax, 0xBE
    je .l2_ms8
    mov r9d, 2
    jmp .l2_ms1
.l2_ms8:
    mov r9d, 1
.l2_ms1:
    mov r8d, 1
    sub rsp, 32
    call .build_rm
    add rsp, 32
    test eax, eax
    jnz .no
    jmp .ok
.l2_bsf:
    lea rax, [rel s_bsf]
    mov [rbx+Insn.mne], rax
    jmp .l2_bsr2
.l2_bsr:
    lea rax, [rel s_bsr]
    mov [rbx+Insn.mne], rax
.l2_bsr2:
    cmp byte [rbx+Insn.has_modrm], 0
    je .no
    mov r9d, 4
    cmp byte [rbx+Insn.has_rex], 0
    je .l2_bs66
    test byte [rbx+Insn.rex], 8
    jz .l2_bs66
    mov r9d, 8
    jmp .l2_bssz
.l2_bs66:
    cmp byte [rbx+Insn.legacy66], 0
    je .l2_bssz
    mov r9d, 2
.l2_bssz:
    movzx eax, byte [rbx+Insn.modrm]
    mov ecx, eax
    shr ecx, 3
    and ecx, 7
    cmp byte [rbx+Insn.has_rex], 0
    je .l2_bsnr
    test byte [rbx+Insn.rex], 4
    jz .l2_bsnr
    add ecx, 8
.l2_bsnr:
    mov byte [rbx+Insn.op0+DexOp.kind], DEX_OP_REG
    mov [rbx+Insn.op0+DexOp.reg], cl
    mov [rbx+Insn.op0+DexOp.size], r9b
    mov r8d, 1
    sub rsp, 32
    call .build_rm
    add rsp, 32
    test eax, eax
    jnz .no
    jmp .ok
.l2_bt2:
    lea rax, [rel s_bt]
    mov [rbx+Insn.mne], rax
    jmp .l2_btrm
.l2_cmpx2:
    lea rax, [rel s_cmpx]
    mov [rbx+Insn.mne], rax
    jmp .l2_btrm
.l2_cx:
    ; C0/C1 xadd, C2? (cmpps SSE→db), C3 movnti, C4/C5 (SSE imm→db),
    ; C6? (shufps→db), C7 grupo9, C8-CF bswap
    movzx eax, byte [rbx+Insn.opcode]
    cmp eax, 0xC0
    je .l2_xadd
    cmp eax, 0xC1
    je .l2_xadd
    cmp eax, 0xC3
    je .l2_movnti
    cmp eax, 0xC7
    je .l2_grp9
    cmp eax, 0xC8
    jb .no
    ; C8-CF bswap (sem modrm!)
    mov ecx, eax
    and ecx, 7
    cmp byte [rbx+Insn.has_rex], 0
    je .l2_bs_nr
    test byte [rbx+Insn.rex], 1
    jz .l2_bs_nr
    add ecx, 8
.l2_bs_nr:
    mov byte [rbx+Insn.op0+DexOp.kind], DEX_OP_REG
    mov [rbx+Insn.op0+DexOp.reg], cl
    mov byte [rbx+Insn.op0+DexOp.size], 4
    cmp byte [rbx+Insn.has_rex], 0
    je .ok
    test byte [rbx+Insn.rex], 8
    jz .ok
    mov byte [rbx+Insn.op0+DexOp.size], 8
    jmp .ok
.l2_xadd:
    lea rax, [rel s_xadd]
    mov [rbx+Insn.mne], rax
    jmp .l2_btrm
.l2_movnti:
    lea rax, [rel s_mov]
    mov [rbx+Insn.mne], rax
    ; op0 = r/m (size opsize), op1 = reg — como mov normal
    cmp byte [rbx+Insn.has_modrm], 0
    je .no
    mov r9d, 4
    cmp byte [rbx+Insn.has_rex], 0
    je .l2_mt66
    test byte [rbx+Insn.rex], 8
    jz .l2_mt66
    mov r9d, 8
    jmp .l2_mtsz
.l2_mt66:
    cmp byte [rbx+Insn.legacy66], 0
    je .l2_mtsz
    mov r9d, 2
.l2_mtsz:
    movzx eax, byte [rbx+Insn.modrm]
    mov ecx, eax
    shr ecx, 3
    and ecx, 7
    cmp byte [rbx+Insn.has_rex], 0
    je .l2_mtnr
    test byte [rbx+Insn.rex], 4
    jz .l2_mtnr
    add ecx, 8
.l2_mtnr:
    mov byte [rbx+Insn.op1+DexOp.kind], DEX_OP_REG
    mov [rbx+Insn.op1+DexOp.reg], cl
    mov [rbx+Insn.op1+DexOp.size], r9b
    xor r8d, r8d
    sub rsp, 32
    call .build_rm
    add rsp, 32
    test eax, eax
    jnz .no
    jmp .ok
.l2_grp9:
    cmp byte [rbx+Insn.has_modrm], 0
    je .no
    movzx eax, byte [rbx+Insn.modrm]
    mov ecx, eax
    shr ecx, 3
    and ecx, 7
    cmp ecx, 1
    je .l2_cxchg
    cmp ecx, 6
    je .l2_rdrand
    cmp ecx, 7
    je .l2_rdseed
    jmp .no
.l2_cxchg:
    lea rax, [rel s_cmpx]
    mov [rbx+Insn.mne], rax
    mov r9d, 8                ; cmpxchg8b (REX.W→16b: raro; simplificar p/ 8?)
    cmp byte [rbx+Insn.has_rex], 0
    je .l2_cxsz
    test byte [rbx+Insn.rex], 8
    jz .l2_cxsz
    mov r9d, 16               ; cmpxchg16b (size 16: emitter trata? NÃO SUPORTADO!)
    jmp .no                    ; honesto: db até suportar size 16
.l2_cxsz:
    xor r8d, r8d
    sub rsp, 32
    call .build_rm
    add rsp, 32
    test eax, eax
    jnz .no
    jmp .ok
.l2_rdrand:
    jmp .no                    ; rdrand/rdseed: db por ora (raro)
.l2_rdseed:
    jmp .no

;-----------------------------------------------------------------------------
; .build_rm — r8d=opidx(0/1/2), r9d=size(1/2/4/8). Constrói r/m (reg ou mem).
; Ret eax=0 ok / 1 (abs32 via 0x67, mod==11? NÃO — mod==11 vira REG aqui
; mesmo; só falha em absoluto-addr32 sem base válida).
; Clobber: rax,rcx,rdx. Preserva rbx/r10/r11 (e non-voláteis via push rsi).
; Chamada COM shadow (sub rsp,32) pelo chamador!
;-----------------------------------------------------------------------------
.build_rm:
    push rsi
    mov ecx, r8d
    shl ecx, 4
    lea rsi, [rbx+Insn.op0+rcx]  ; rsi = &op
    movzx eax, byte [rbx+Insn.modrm]
    mov ecx, eax
    shr ecx, 6                   ; mod
    cmp ecx, 3
    je .br_reg
    ; ---- MEM ----
    mov byte [rsi+DexOp.kind], DEX_OP_MEM
    mov byte [rsi+DexOp.size], r9b
    mov cl, [rbx+Insn.segprefix]
    mov [rsi+DexOp.seg], cl
    mov byte [rsi+DexOp.base], DEX_NOBASE
    mov byte [rsi+DexOp.index], DEX_NOINDEX
    mov byte [rsi+DexOp.scale], 1
    mov rcx, [rbx+Insn.disp]     ; disp (disp8/32 com sinal; RIP sobrescreve)
    mov [rsi+DexOp.val], rcx
    cmp byte [rbx+Insn.legacy67], 0
    jne .br_a32
    ; addr64
    movzx ecx, byte [rbx+Insn.modrm]
    and ecx, 7                   ; rm
    cmp ecx, 4
    je .br_sib
    cmp ecx, 5
    jne .br_base
    ; rm==5: mod==0? RIP (x64) / absoluto (x32) : base rbp
    movzx ecx, byte [rbx+Insn.modrm]
    cmp ecx, 0x40
    jae .br_bp
    cmp byte [rbx+Insn.addr_mode], 1
    je .br_abs32
    ; RIP: val = address + length + disp
    mov rax, [rbx+Insn.address]
    mov ecx, [rbx+Insn.length]
    add rax, rcx
    add rax, [rbx+Insn.disp]
    mov [rsi+DexOp.val], rax
    xor eax, eax
    pop rsi
    ret
.br_abs32:
    ; x32: disp32 é endereço absoluto (VA). val = disp u32
    ; (Insn.disp tem sinal; low32 é o endereço).
    mov eax, [rbx+Insn.disp]
    mov [rsi+DexOp.val], rax     ; rax zero-estendido (mov eax)
    xor eax, eax
    pop rsi
    ret
.br_bp:
    mov ecx, 5
    cmp byte [rbx+Insn.has_rex], 0
    je .br_setbase
    test byte [rbx+Insn.rex], 1  ; REX.B?
    jz .br_setbase
    add ecx, 8                   ; r13
    jmp .br_setbase
.br_base:
    ; base = rm + REX.B
    movzx ecx, byte [rbx+Insn.modrm]
    and ecx, 7
    cmp byte [rbx+Insn.has_rex], 0
    je .br_setbase
    test byte [rbx+Insn.rex], 1
    jz .br_setbase
    add ecx, 8
.br_setbase:
    mov [rsi+DexOp.base], cl
    jmp .br_memret
.br_sib:
    movzx eax, byte [rbx+Insn.sib]
    mov ecx, eax
    shr ecx, 3
    and ecx, 7                   ; idx0-7
    mov edx, eax
    and edx, 7                   ; base0-7
    ; index: 4 sem REX.X → ausente
    cmp ecx, 4
    jne .br_idx
    cmp byte [rbx+Insn.has_rex], 0
    je .br_noidx
    test byte [rbx+Insn.rex], 2  ; REX.X?
    jz .br_noidx
    add ecx, 8                   ; r12
    jmp .br_idxok
.br_noidx:
    jmp .br_idxdone
.br_idx:
    cmp byte [rbx+Insn.has_rex], 0
    je .br_idxok
    test byte [rbx+Insn.rex], 2
    jz .br_idxok
    add ecx, 8
.br_idxok:
    mov [rsi+DexOp.index], cl
.br_idxdone:
    ; scale = 1 << ((sib>>6)&3)
    movzx ecx, byte [rbx+Insn.sib]
    shr ecx, 6
    mov eax, 1
    shl eax, cl
    mov [rsi+DexOp.scale], al
    ; base: 5+mod0 → ausente (disp32 abs, val=disp já); senão base+REX.B
    movzx eax, byte [rbx+Insn.sib]
    and eax, 7
    movzx ecx, byte [rbx+Insn.modrm]
    shr ecx, 6                   ; mod
    test ecx, ecx
    jnz .br_sibbase
    cmp eax, 5
    je .br_sibabs                ; sem base (disp abs já em val)
.br_sibbase:
    cmp byte [rbx+Insn.has_rex], 0
    je .br_sibbok
    test byte [rbx+Insn.rex], 1
    jz .br_sibbok
    add eax, 8
.br_sibbok:
    mov [rsi+DexOp.base], al
    jmp .br_memret
.br_sibabs:
    ; SIB-abs sempre disp32 ([abs ..]): forma única, nativo seguro.
    xor eax, eax
    pop rsi
    ret
;-----------------------------------------------------------------------------
; .br_memret — retorno verificado p/ MEM com base (não-RIP, não-abs).
; disp32 com valor curto: o nasm otimiza p/ disp8 e muda o tamanho; sem
; strict p/ disp no nasm: db honesto. (RIP e SIB-abs retornam direto acima.)
; Comparação em 32 BITS: val é a forma u32 zero-estendida (ex disp32
; -8 = 0xFFFFFFF8); em 64 bits o +128 não envolve e o curto escapa.
;-----------------------------------------------------------------------------
.br_memret:
    cmp byte [rbx+Insn.disp_size], 4
    jne .br_memok
    mov eax, [rsi+DexOp.val]     ; low32: -128..127 vira 0..255
    add eax, 128
    cmp eax, 255
    jbe .br_memdb
.br_memok:
    xor eax, eax
    pop rsi
    ret
.br_memdb:
    mov eax, 1
    pop rsi
    ret
.br_a32:
    ; addr32 (0x67): rm==4? SIB : rm==5&&mod==0? abs→db : base
    movzx eax, byte [rbx+Insn.modrm]
    mov ecx, eax
    and ecx, 7                   ; rm
    shr eax, 6                   ; mod
    cmp ecx, 4
    je .br_a32sib
    cmp ecx, 5
    jne .br_a32base
    test eax, eax
    jz .br_abs                    ; mod00+rm101 = disp32 abs → db
    ; mod 1/2 rm101: base ebp + disp
    mov ecx, 5
    jmp .br_a32set
.br_a32base:
    ; base = rm (REX.B estende mesmo com 67)
    cmp byte [rbx+Insn.has_rex], 0
    je .br_a32set
    test byte [rbx+Insn.rex], 1
    jz .br_a32set
    add ecx, 8
.br_a32set:
    mov [rsi+DexOp.base], cl
    jmp .br_memret
.br_a32sib:
    movzx ecx, byte [rbx+Insn.modrm]
    shr ecx, 6                   ; mod
    movzx eax, byte [rbx+Insn.sib]
    and eax, 7                   ; base
    test ecx, ecx
    jnz .br_a32sb                ; mod!=0: base + disp
    cmp eax, 5
    je .br_abs                    ; base101+mod00 = disp abs → db
.br_a32sb:
    cmp byte [rbx+Insn.has_rex], 0
    je .br_a32ss
    test byte [rbx+Insn.rex], 1
    jz .br_a32ss
    add eax, 8
.br_a32ss:
    mov [rsi+DexOp.base], al
    ; index SIB (igual 64; addr32 ignora REX.X? NÃO — REX vale. mesmo código:)
    movzx eax, byte [rbx+Insn.sib]
    mov ecx, eax
    shr ecx, 3
    and ecx, 7
    cmp ecx, 4
    jne .br_a32ix
    cmp byte [rbx+Insn.has_rex], 0
    je .br_a32done
    test byte [rbx+Insn.rex], 2
    jz .br_a32done
    add ecx, 8
    jmp .br_a32ixs
.br_a32ix:
    cmp byte [rbx+Insn.has_rex], 0
    je .br_a32ixs
    test byte [rbx+Insn.rex], 2
    jz .br_a32ixs
    add ecx, 8
.br_a32ixs:
    mov [rsi+DexOp.index], cl
    movzx ecx, byte [rbx+Insn.sib]
    shr ecx, 6
    mov eax, 1
    shl eax, cl
    mov [rsi+DexOp.scale], al
.br_a32done:
    jmp .br_memret
.br_abs:
    mov eax, 1
    pop rsi
    ret
.br_reg:
    ; mod==11: REG (rm + REX.B), size = r9d
    movzx eax, byte [rbx+Insn.modrm]
    and eax, 7
    mov ecx, eax
    cmp byte [rbx+Insn.has_rex], 0
    je .br_rgok
    test byte [rbx+Insn.rex], 1
    jz .br_rgok
    add ecx, 8
.br_rgok:
    mov byte [rsi+DexOp.kind], DEX_OP_REG
    mov [rsi+DexOp.reg], cl
    mov [rsi+DexOp.size], r9b
    xor eax, eax
    pop rsi
    ret

;-----------------------------------------------------------------------------
; .swap01 — troca op0<->op1 (16+16 bytes). Clobber rax,rcx. Sem calls.
;-----------------------------------------------------------------------------
.swap01:
    mov rax, [rbx+Insn.op0+0]
    mov rcx, [rbx+Insn.op1+0]
    mov [rbx+Insn.op1+0], rax
    mov [rbx+Insn.op0+0], rcx
    mov rax, [rbx+Insn.op0+8]
    mov rcx, [rbx+Insn.op1+8]
    mov [rbx+Insn.op1+8], rax
    mov [rbx+Insn.op0+8], rcx
    jmp .ok

section .rodata
align 8
.l1_flags2_tbl:
    dq s_clc, s_stc, s_cli, s_sti
