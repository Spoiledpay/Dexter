;=============================================================================
; Dexter/src/back/lift.asm
; dex_lift_insn — classifica (Insn+DexOp) em IR + resolve o alvo.
;
; O quê: (Insn*, ctx*) -> DexIR (cls + tkind/tva/imp), sem heap.
;   Chamadas internas só para os helpers file-scope (.li_imp_find,
;   .li_in_code), sempre com shadow e preservando r9-r11.
; Por quê: o codegen (R-6.4 fatia 2) e o walker consomem decisões prontas
;   (que mnemônico reemitir, para onde aponta, se é import) em vez de
;   reinterpretar opcode/ModRM; base futura da IR otimizável (Opção C).
; Contrato:
;   Args: rcx=Insn* (com op0-2 de dex_build_operands), rdx=DexLiftCtx*
;         (img não nulo), r8=&DexIR (24 B).
;   Ret:  eax=0 sempre (IR preenchido) | 8 args nulos.
;   Total: mne==0 (byte desconhecido) vira IR_DB (caller emite db, como
;   hoje); refs RIP sem SIB com alvo em import viram IRT_IMPORT (mesmo
;   em INSTR comum, ex `mov rax,[rel __imp_X]`); CODE vs DATA via scan
;   de seções (abaixo); trva fora de 32 bits ou abaixo da base nunca
;   casa (sem wrap); imports_ptr NULL ou count 0 = miss (sem crash).
;   Predicado de código espelha `.cs_in_code` (rebuild.asm), incluindo o
;   span max(vsize,raw_size): mudar um exige mudar o outro (ver D-9).
;   Chamadas internas (.li_imp_find/.li_in_code) sempre com shadow
;   32 bytes; ambas preservam r9-r11 e só usam voláteis no resto.
; Como testar: tests\lift_check.asm (12 Insns craftados, golden
;   LIFT/TKIND) + round-trips da fatia 2.
;
; Requisitos atendidos: R-6.4 (lift DexOp->IR, fatia 1)
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "dexter.inc"
%include "pe.inc"

global dex_lift_insn

section .text

;-----------------------------------------------------------------------------
; dex_lift_insn — rcx=Insn*, rdx=ctx*, r8=&DexIR -> eax=0 | 8.
; r10=ir, r11=insn, r9=img. Demais só voláteis (rax,rcx,rdx,r8).
;-----------------------------------------------------------------------------
dex_lift_insn:
    test rcx, rcx
    jz .li_args
    test rdx, rdx
    jz .li_args
    test r8, r8
    jz .li_args
    mov r10, r8                  ; ir
    mov r11, rcx                 ; insn
    mov dword [r10+DexIR.cls], IR_DB
    mov dword [r10+DexIR.tkind], IRT_NONE
    mov qword [r10+DexIR.tva], 0
    mov qword [r10+DexIR.imp], 0
    cmp qword [r11+Insn.mne], 0
    je .li_ok                    ; byte desconhecido -> DB (como hoje)
    mov r9, [rdx+DexLiftCtx.img]
    test r9, r9
    jz .li_args
    cmp byte [r11+Insn.is_ret], 0
    jne .li_ret
    cmp byte [r11+Insn.is_call], 0
    jne .li_call
    cmp byte [r11+Insn.is_branch], 0
    jne .li_branch
    jmp .li_instr
.li_ret:
    mov dword [r10+DexIR.cls], IR_RET
    jmp .li_ok
.li_args:
    mov eax, ERR_ARGS
    ret
.li_ok:
    xor eax, eax
    ret

;-----------------------------------------------------------------------------
; .li_call — is_call. op0 REL -> CALL/CODE; MEM RIP -> CALLIMP/IMPORT ou
; CALL/DATA; resto (REG, MEM com base, SIB) -> CALL/NONE.
;-----------------------------------------------------------------------------
.li_call:
    mov al, [r11+Insn.op0+DexOp.kind]
    cmp al, DEX_OP_REL
    je .li_call_rel
    cmp al, DEX_OP_MEM
    jne .li_call_ind
    cmp byte [r11+Insn.op0+DexOp.base], DEX_NOBASE
    jne .li_call_ind
    cmp byte [r11+Insn.has_sib], 0
    jne .li_call_ind              ; SIB-abs: numérico, sem alvo
    mov rax, [r11+Insn.op0+DexOp.val]
    mov qword [r10+DexIR.tva], rax
    sub rsp, 40                  ; shadow (sem frame aqui: entry 8-8=0)
    call .li_imp_find            ; rdx=imp*|0 (r9-r11 preservados)
    add rsp, 40
    test rdx, rdx
    jz .li_call_codat
    mov dword [r10+DexIR.cls], IR_CALLIMP
    mov dword [r10+DexIR.tkind], IRT_IMPORT
    mov [r10+DexIR.imp], rdx
    xor eax, eax
    ret
.li_call_codat:
    mov rax, [r10+DexIR.tva]
    sub rsp, 40                  ; shadow (sem frame aqui: entry 8-8=0)
    call .li_in_code             ; eax=1 se alvo em código
    add rsp, 40
    mov dword [r10+DexIR.cls], IR_CALL
    test eax, eax
    jz .li_call_data
    mov dword [r10+DexIR.tkind], IRT_CODE
    xor eax, eax
    ret
.li_call_data:
    mov dword [r10+DexIR.cls], IR_CALL
    mov dword [r10+DexIR.tkind], IRT_DATA
    xor eax, eax
    ret
.li_call_rel:
    mov rax, [r11+Insn.op0+DexOp.val]
    mov [r10+DexIR.tva], rax
    sub rsp, 40                  ; shadow (sem frame aqui: entry 8-8=0)
    call .li_in_code
    add rsp, 40
    mov dword [r10+DexIR.cls], IR_CALL
    test eax, eax
    jz .li_call_data
    mov dword [r10+DexIR.tkind], IRT_CODE
    xor eax, eax
    ret
.li_call_ind:
    mov dword [r10+DexIR.cls], IR_CALL
    xor eax, eax                 ; tkind segue NONE
    ret

;-----------------------------------------------------------------------------
; .li_branch — is_branch (não-call). REL: E9/EB len1 -> JMP, resto ->
; BRANCH (jcc/loop/jcxz); MEM RIP -> JMPIMP/IMPORT ou JMP/DATA; resto ->
; JMP/NONE (indireto).
;-----------------------------------------------------------------------------
.li_branch:
    mov al, [r11+Insn.op0+DexOp.kind]
    cmp al, DEX_OP_REL
    je .li_br_rel
    cmp al, DEX_OP_MEM
    jne .li_br_ind
    cmp byte [r11+Insn.op0+DexOp.base], DEX_NOBASE
    jne .li_br_ind
    cmp byte [r11+Insn.has_sib], 0
    jne .li_br_ind
    mov rax, [r11+Insn.op0+DexOp.val]
    mov qword [r10+DexIR.tva], rax
    sub rsp, 40                  ; shadow (sem frame aqui: entry 8-8=0)
    call .li_imp_find
    add rsp, 40
    test rdx, rdx
    jz .li_br_codat
    mov dword [r10+DexIR.cls], IR_JMPIMP
    mov dword [r10+DexIR.tkind], IRT_IMPORT
    mov [r10+DexIR.imp], rdx
    xor eax, eax
    ret
.li_br_codat:
    mov rax, [r10+DexIR.tva]
    sub rsp, 40                  ; shadow (sem frame aqui: entry 8-8=0)
    call .li_in_code
    add rsp, 40
    mov dword [r10+DexIR.cls], IR_JMP
    test eax, eax
    jz .li_br_data
    mov dword [r10+DexIR.tkind], IRT_CODE
    xor eax, eax
    ret
.li_br_data:
    mov dword [r10+DexIR.cls], IR_JMP
    mov dword [r10+DexIR.tkind], IRT_DATA
    xor eax, eax
    ret
.li_br_rel:
    mov eax, [r11+Insn.opcode]
    cmp dword [r11+Insn.opcode_len], 1
    jne .li_br_cc
    cmp eax, 0xE9
    je .li_br_jmp
    cmp eax, 0xEB
    je .li_br_jmp
.li_br_cc:
    mov dword [r10+DexIR.cls], IR_BRANCH
    jmp .li_br_code
.li_br_jmp:
    mov dword [r10+DexIR.cls], IR_JMP
.li_br_code:
    mov rax, [r11+Insn.op0+DexOp.val]
    mov [r10+DexIR.tva], rax
    sub rsp, 40                  ; shadow (sem frame aqui: entry 8-8=0)
    call .li_in_code
    add rsp, 40
    test eax, eax
    jz .li_br_reldata
    mov dword [r10+DexIR.tkind], IRT_CODE
    xor eax, eax
    ret
.li_br_reldata:
    mov dword [r10+DexIR.tkind], IRT_DATA
    xor eax, eax
    ret
.li_br_ind:
    mov dword [r10+DexIR.cls], IR_JMP
    xor eax, eax                 ; tkind segue NONE
    ret

;-----------------------------------------------------------------------------
; .li_instr — resto. Primeiro MEM RIP (op0..2) -> IMPORT/DATA; senão
; primeiro REL -> CODE; senão INSTR/NONE.
;-----------------------------------------------------------------------------
.li_instr:
    xor r8d, r8d                 ; k = 0..2
.li_i_mem:
    cmp r8d, 3
    jae .li_i_rel0
    mov eax, r8d
    shl eax, 4                   ; *16 (DexOp)
    lea rcx, [r11+Insn.op0]
    add rcx, rax                 ; &op[k]
    cmp byte [rcx+DexOp.kind], DEX_OP_MEM
    jne .li_i_memnx
    cmp byte [rcx+DexOp.base], DEX_NOBASE
    jne .li_i_memnx
    cmp byte [r11+Insn.has_sib], 0
    jne .li_i_memnx
    mov rax, [rcx+DexOp.val]
    mov qword [r10+DexIR.tva], rax
    sub rsp, 40                  ; shadow (sem frame aqui: entry 8-8=0)
    call .li_imp_find
    add rsp, 40
    test rdx, rdx
    jz .li_i_codat
    cmp dword [r9+PeImage.arch], DEX_ARCH_X32
    je .li_i_codat             ; Fase D1: sem rewrite IAT em x32 (db via gates)
    mov dword [r10+DexIR.cls], IR_INSTR
    mov dword [r10+DexIR.tkind], IRT_IMPORT
    mov [r10+DexIR.imp], rdx
    xor eax, eax
    ret
.li_i_codat:
    mov rax, [r10+DexIR.tva]
    sub rsp, 40                  ; shadow (sem frame aqui: entry 8-8=0)
    call .li_in_code
    add rsp, 40
    mov dword [r10+DexIR.cls], IR_INSTR
    test eax, eax
    jz .li_i_data
    mov dword [r10+DexIR.tkind], IRT_CODE
    xor eax, eax
    ret
.li_i_data:
    mov dword [r10+DexIR.cls], IR_INSTR
    mov dword [r10+DexIR.tkind], IRT_DATA
    xor eax, eax
    ret
.li_i_memnx:
    inc r8d
    jmp .li_i_mem
.li_i_rel0:
    xor r8d, r8d
.li_i_rel:
    cmp r8d, 3
    jae .li_i_none
    mov eax, r8d
    shl eax, 4
    lea rcx, [r11+Insn.op0]
    add rcx, rax
    cmp byte [rcx+DexOp.kind], DEX_OP_REL
    jne .li_i_relnx
    mov rax, [rcx+DexOp.val]
    mov [r10+DexIR.tva], rax
    sub rsp, 40                  ; shadow (sem frame aqui: entry 8-8=0)
    call .li_in_code
    add rsp, 40
    mov dword [r10+DexIR.cls], IR_INSTR
    test eax, eax
    jz .li_i_reldata
    mov dword [r10+DexIR.tkind], IRT_CODE
    xor eax, eax
    ret
.li_i_reldata:
    mov dword [r10+DexIR.cls], IR_INSTR
    mov dword [r10+DexIR.tkind], IRT_DATA
    xor eax, eax
    ret
.li_i_relnx:
    inc r8d
    jmp .li_i_rel
.li_i_none:
    mov dword [r10+DexIR.cls], IR_INSTR
    xor eax, eax                 ; tkind segue NONE
    ret

;-----------------------------------------------------------------------------
; .li_imp_find — rax=VA, r9=img -> rdx=ImportEntry* ou 0.
; Preserva r9, r10, r11 (push interno); clobber rax, rcx, rdx, r8.
; Chamador recarrega val/tva de [r10+DexIR.tva] depois (voláteis morrem).
;-----------------------------------------------------------------------------
.li_imp_find:
    push r10
    push r11
    mov rcx, [r9+PeImage.image_base]
    cmp rax, rcx
    jb .li_if_miss
    sub rax, rcx                 ; rva
    mov rdx, rax
    shr rdx, 32
    jnz .li_if_miss              ; não cabe em 32 bits: nunca é IAT
    mov edx, eax                 ; rva32
    mov rcx, [r9+PeImage.imports_ptr]
    test rcx, rcx
    jz .li_if_miss
    mov r8d, [r9+PeImage.imports_count]
    test r8d, r8d
    jz .li_if_miss
    mov rax, rcx                 ; entry (bump +32)
    xor ecx, ecx                 ; i
.li_if_l:
    cmp ecx, r8d
    jae .li_if_miss
    cmp dword [rax+ImportEntry.iat_rva], edx
    je .li_if_hit
    add rax, SIZEOF_IMPORT_ENTRY
    inc ecx
    jmp .li_if_l
.li_if_hit:
    mov rdx, rax
    pop r11
    pop r10
    ret
.li_if_miss:
    xor edx, edx
    pop r11
    pop r10
    ret

;-----------------------------------------------------------------------------
; .li_in_code — rax=VA, r9=img -> eax=1 se cai em seção CODE/EXEC.
; Espelha `.cs_in_code` (rebuild.asm), incluindo span max(vsize,raw_size)
; e predicado CNT_CODE|MEM_EXECUTE. Preserva r9, r10, r11 (push
; interno); clobber rax, rcx, rdx, r8.
;-----------------------------------------------------------------------------
.li_in_code:
    push r10
    push r11
    mov rcx, [r9+PeImage.image_base]
    cmp rax, rcx
    jb .li_ic_no
    sub rax, rcx                 ; rva
    mov rdx, rax
    shr rdx, 32
    jnz .li_ic_no                ; >32 bits: nunca seção
    mov edx, eax                 ; trva32
    mov ecx, [r9+PeImage.num_sections]
    mov r8, [r9+PeImage.sections_ptr]
    test ecx, ecx
    jz .li_ic_no
    test r8, r8
    jz .li_ic_no
.li_ic_l:
    test ecx, ecx
    jz .li_ic_no
    dec ecx
    mov eax, ecx
    imul eax, SIZEOF_PE_SECTION
    add rax, r8                  ; sec
    cmp edx, [rax+PeSection.vaddr]
    jb .li_ic_l
    mov r10d, [rax+PeSection.vsize]
    mov r11d, [rax+PeSection.raw_size]
    cmp r10d, r11d
    jae .li_ic_span
    mov r10d, r11d
.li_ic_span:
    mov r11d, edx
    sub r11d, [rax+PeSection.vaddr] ; delta (edx/trva intacto p/ próx.)
    cmp r11d, r10d
    jae .li_ic_l
    mov eax, [rax+PeSection.characterist]
    test eax, IMAGE_SCN_CNT_CODE
    jnz .li_ic_yes
    test eax, IMAGE_SCN_MEM_EXECUTE
    jz .li_ic_l
.li_ic_yes:
    mov eax, 1
    pop r11
    pop r10
    ret
.li_ic_no:
    xor eax, eax
    pop r11
    pop r10
    ret
