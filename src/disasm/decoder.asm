;=============================================================================
; Dexter/src/disasm/decoder.asm
; dex_disasm_one — decodifica UMA instrução x86-64 (LDE real + fallback db).
; Contrato: retorna 1..15 sempre que houver byte disponível; 0 só se VA
; inválido/sem bytes. Desconhecido => mne=0 (emitter usa db exato).
;
; Slots locais: [rbp-72]=npre [rbp-80]=flag [rbp-88]=base [rbp-96]=end
;                [rbp-104]=oplen [rbp-112]=modrm_len
; Requisitos atendidos: R-2.x
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "dexter.inc"
%include "pe.inc"

global dex_disasm_one

extern dex_rva_to_offset
extern dex_decode_prefixes
extern dex_decode_modrm
extern dex_decode_operands
extern dex_tbl1_flag      
extern dex_tbl1_mne       
extern dex_tbl2_flag      
extern dex_tbl2_mne       
extern dex_tbl38_flag     
extern dex_tbl3a_flag     
extern dex_vex2_flags
extern dex_build_operands
extern s_vex
extern s_evex

section .text

;-----------------------------------------------------------------------------
; dex_disasm_one
; Args:   rcx = PeImage*, rdx = VA, r8 = Insn*
; Ret:    rax = bytes consumidos (1..15) ou 0 (VA inválido)
;-----------------------------------------------------------------------------
dex_disasm_one:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 56
    test rcx, rcx
    jz .fail
    test r8, r8
    jz .fail
    mov rbx, rcx               ; img
    mov r14, rdx               ; va
    mov r15, r8                ; insn
    xor eax, eax
    mov [r15+0], rax
    mov [r15+8], rax
    mov [r15+16], rax
    mov [r15+24], rax
    mov [r15+32], rax
    mov [r15+40], rax
    mov [r15+48], rax
    mov [r15+56], rax
    mov [r15+64], rax
    mov [r15+72], rax
    mov [r15+80], rax
    mov [r15+88], rax
    mov [r15+96], rax
    mov [r15+104], rax
    mov [r15+112], rax
    mov [r15+120], rax
    mov [r15+128], rax
    mov [r15+136], rax
    mov [r15+144], rax
    mov [r15+152], rax
    mov [r15+Insn.address], r14
    ; modo de endereço (Fase x32): 0 = 64 bits, 1 = 32 bits.
    ; Prefixos/ModRM/operandos consultam Insn.addr_mode (sem REX nem
    ; RIP-rel em x32). build_operands recusa x32 (db fiel).
    mov eax, [rbx+PeImage.arch]
    mov [r15+Insn.addr_mode], al
    mov rax, [rbx+PeImage.image_base]
    cmp r14, rax
    jb .fail
    sub r14, rax               ; r14 = rva
    mov rax, r14
    shr rax, 32
    test eax, eax
    jnz .fail                  ; rva não cabe em 32 bits
    mov rcx, rbx
    mov edx, r14d
    sub rsp, 32
    call dex_rva_to_offset
    add rsp, 32
    mov r13, rax               ; off
    test rax, rax
    jnz .have_off
    mov rax, [rbx+PeImage.opt_header]
    mov eax, [rax+ OH64_SIZE_OF_HEADERS]  ; mov eax zera os 32 altos
    cmp r14, rax
    jae .fail
.have_off:
    mov rax, [rbx+PeImage.file_buffer]
    mov [rbp-88], rax          ; base
    mov rcx, [rbx+PeImage.file_size]
    sub rcx, r13               ; avail
    jbe .fail
    cmp rcx, 15
    jbe .av_ok
    mov rcx, 15
.av_ok:
    mov rax, [rbp-88]
    lea r13, [rax+r13]         ; r13 = p
    lea r12, [r13+rcx]         ; r12 = end
    mov [rbp-96], r12
    ; ---- prefixos ----
    mov rcx, r13
    mov rdx, r12
    mov r8, r15
    sub rsp, 32
    call dex_decode_prefixes
    add rsp, 32
    mov [rbp-72], eax          ; npre (u32 lógico)
    lea r10, [r13+rax]         ; op
    cmp r10, r12
    jae .fallback_all
    ; ---- opcode ----
    movzx eax, byte [r10]
    ; ---- R-2.7: VEX/EVEX (só x64; C4/C5/62 são prefixos) ----
    cmp byte [r15+Insn.addr_mode], 0
    jne .not_vex
    cmp al, 0xC5
    je .vex2
    cmp al, 0xC4
    je .vex3
    cmp al, 0x62
    je .evex
.not_vex:
    cmp al, 0x0F
    je .esc0F
    movzx ecx, al              ; b0
    lea rdx, [rel dex_tbl1_flag]
    movzx eax, byte [rdx+rcx]
    mov [rbp-80], eax          ; flag
    lea rdx, [rel dex_tbl1_mne]
    mov rax, [rdx+rcx*8]       ; mne
    mov [r15+Insn.mne], rax
    mov [r15+Insn.opcode], ecx ; opcode = b0
    mov dword [r15+Insn.opcode_len], 1
    mov dword [rbp-104], 1     ; oplen
    jmp .got_op
.esc0F:
    lea rax, [r10+1]
    cmp rax, r12
    jae .fallback_all
    movzx ecx, byte [r10+1]    ; b1
    cmp cl, 0x38
    je .esc38
    cmp cl, 0x3A
    je .esc3A
    lea rdx, [rel dex_tbl2_flag]
    movzx eax, byte [rdx+rcx]
    mov [rbp-80], eax
    lea rdx, [rel dex_tbl2_mne]
    mov rax, [rdx+rcx*8]
    mov [r15+Insn.mne], rax
    or ecx, 0x0F00
    mov [r15+Insn.opcode], ecx
    mov dword [r15+Insn.opcode_len], 2
    mov dword [rbp-104], 2
    jmp .got_op
.esc38:
    lea rax, [r10+2]
    cmp rax, r12
    jae .fallback_all
    movzx ecx, byte [r10+2]    ; b2
    lea rdx, [rel dex_tbl38_flag]
    movzx eax, byte [rdx+rcx]
    mov [rbp-80], eax
    mov qword [r15+Insn.mne], 0
    or ecx, 0x3800
    mov [r15+Insn.opcode], ecx
    mov dword [r15+Insn.opcode_len], 3
    mov dword [rbp-104], 3
    jmp .got_op
.esc3A:
    lea rax, [r10+2]
    cmp rax, r12
    jae .fallback_all
    movzx ecx, byte [r10+2]
    lea rdx, [rel dex_tbl3a_flag]
    movzx eax, byte [rdx+rcx]
    mov [rbp-80], eax
    mov qword [r15+Insn.mne], 0
    or ecx, 0x3A00
    mov [r15+Insn.opcode], ecx
    mov dword [r15+Insn.opcode_len], 3
    mov dword [rbp-104], 3
.got_op:
    ; x32: 0x63 é arpl com ModRM (não movsxd); sem mne fiel → db.
    ; (flag F_MODRM já está certa; só o mnemônico mente.)
    cmp byte [r15+Insn.addr_mode], 1
    jne .got_op_ok
    cmp dword [r15+Insn.opcode_len], 1
    jne .got_op_ok
    cmp dword [r15+Insn.opcode], 0x63
    jne .got_op_ok
    mov qword [r15+Insn.mne], 0
.got_op_ok:
    mov eax, [rbp-80]
    and eax, 1
    mov [r15+Insn.has_modrm], al
    mov dword [rbp-112], 0     ; modrm_len
    test al, al
    jz .no_modrm
    mov eax, [rbp-72]          ; npre
    add eax, [rbp-104]         ; + oplen
    lea rcx, [r13+rax]
    mov rdx, r12
    mov r8, r15
    sub rsp, 32
    call dex_decode_modrm
    add rsp, 32
    cmp rax, -1
    je .fallback_all
    mov [rbp-112], eax
.no_modrm:
    mov eax, [rbp-72]          ; npre (dword: slots são u32 lógicos)
    add eax, [rbp-104]         ; + oplen
    add eax, [rbp-112]         ; + modrm_len
    lea rdx, [r13+rax]         ; p_imm
    mov rcx, r15
    mov r8, r12
    sub rsp, 32
    call dex_decode_operands
    add rsp, 32
    cmp rax, -1
    je .fallback_all
    ; length = npre+oplen+modrm+imm (tudo < 64: 32 bits bastam)
    mov ecx, [rbp-72]
    add ecx, [rbp-104]
    add ecx, [rbp-112]
    add rcx, rax               ; rcx = length
    cmp rcx, 15
    ja .fail                   ; sanidade: nunca > 15
    jmp .finish
.fallback_all:
    mov rcx, r12
    sub rcx, r13               ; length = end - p
    jbe .fail
    cmp rcx, 15
    jbe .finish
    mov rcx, 15
.finish:
    ; rcx = length (1..15): copiar raw, set length, calcular target
    mov [r15+Insn.length], ecx
    mov rax, rcx
    lea rsi, [r13]             ; src = p
    lea rdi, [r15+Insn.raw]    ; dst
    rep movsb
    ; target p/ branch/call relativo com imm 1/4
    mov al, [r15+Insn.is_branch]
    or al, [r15+Insn.is_call]
    jz .done_d
    movzx eax, byte [r15+Insn.imm_size]
    cmp al, 1
    je .tgt
    cmp al, 4
    jne .done_d
.tgt:
    mov rax, [r15+Insn.address]
    mov ecx, [r15+Insn.length]
    add rax, rcx
    add rax, [r15+Insn.imm]
    mov [r15+Insn.target_va], rax
.done_d:
    ; construir operandos (R-4.5; não afeta length; falha → db)
    mov rcx, r15
    sub rsp, 32
    call dex_build_operands
    add rsp, 32
    mov eax, [r15+Insn.length]
    add rsp, 56
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret
.fail:
    xor eax, eax
    add rsp, 56
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

;=============================================================================
; R-2.7 — prefixos VEX (C4/C5) e EVEX (62), só x64. Alcançados por jmp.
; Estado: r11d = mapa (1=0F, 2=0F38, 3=0F3A), r8d = tamanho do prefixo,
; eax = enc (1=VEX, 2=EVEX), r9 = ponteiro do byte de opcode. O prefixo
; entra em npre p/ que ModRM/imm caiam no offset certo; mnemônico é
; genérico (vex/evex) e o emissor sempre usa db (sem semântica de operando).
;=============================================================================
.vex2:
    lea r9, [r10+2]
    cmp r9, r12
    jae .fallback_all
    mov r11d, 1
    mov r8d, 2
    mov eax, 1
    jmp .vex_go
.vex3:
    lea r9, [r10+3]
    cmp r9, r12
    jae .fallback_all
    movzx r11d, byte [r10+1]
    and r11d, 0x1F                   ; mmmmm (mapa)
    cmp r11d, 1
    jb .fallback_all
    cmp r11d, 3
    ja .fallback_all
    mov r8d, 3
    mov eax, 1
    jmp .vex_go
.evex:
    lea r9, [r10+4]
    cmp r9, r12
    jae .fallback_all
    movzx r11d, byte [r10+1]         ; P0
    test r11d, 0x0C                  ; bits 3:2 reservados (devem ser 0)
    jnz .fallback_all
    and r11d, 0x03                   ; mm (mapa)
    cmp r11d, 1
    jb .fallback_all
    movzx ecx, byte [r10+2]          ; P1
    test ecx, 0x04                   ; bit 2 reservado (deve ser 1)
    jz .fallback_all
    mov r8d, 4
    mov eax, 2
.vex_go:
    add [rbp-72], r8d                ; npre += tamanho do prefixo
    mov [r15+Insn.enc], al
    ; R-2.7/2b: campos do prefixo p/ a semântica (pp/L/W/vvvv/mm + extensões).
    ; r11d = mapa, r10 = início do prefixo, r8d = tamanho (2/3/4).
    mov byte [r15+Insn.vex_mm], r11b
    mov [r15+Insn.vex_npre], r8b
    cmp r8d, 2
    jne .vex_f3
    movzx ecx, byte [r10+1]          ; VEX2: R̄ vvvv L pp
    mov eax, ecx
    and eax, 0x80
    shr eax, 7
    xor eax, 1
    shl eax, 3
    mov [r15+Insn.vex_r], al
    mov byte [r15+Insn.vex_b], 0
    mov byte [r15+Insn.vex_x], 0
    mov byte [r15+Insn.vex_w], 0
    jmp .vex_fc
.vex_f3:
    movzx ecx, byte [r10+1]          ; P0 (VEX3/EVEX): R̄ X̄ B̄ ...
    mov eax, ecx
    and eax, 0x80
    shr eax, 7
    xor eax, 1
    shl eax, 3
    mov [r15+Insn.vex_r], al
    mov eax, ecx
    and eax, 0x40
    shr eax, 6
    xor eax, 1
    shl eax, 3
    mov [r15+Insn.vex_x], al
    mov eax, ecx
    and eax, 0x20
    shr eax, 5
    xor eax, 1
    shl eax, 3
    mov [r15+Insn.vex_b], al
    movzx ecx, byte [r10+2]          ; P1: W ...
    mov eax, ecx
    shr eax, 7
    mov [r15+Insn.vex_w], al
.vex_fc:
    cmp r8d, 2
    jne .vex_fc3
    movzx ecx, byte [r10+1]          ; VEX2: pp/vvvv/L no byte2
    jmp .vex_fcgo
.vex_fc3:
    movzx ecx, byte [r10+2]          ; VEX3/EVEX: P1
.vex_fcgo:
    mov eax, ecx
    shr eax, 3
    not eax
    and eax, 0xF
    mov [r15+Insn.vex_vvvv], al      ; valor LÓGICO (campo é invertido)
    mov eax, ecx
    and eax, 3
    mov [r15+Insn.vex_pp], al
    cmp r8d, 4
    jne .vex_lok
    movzx ecx, byte [r10+3]          ; EVEX: L'L = P2 bits 6:5
    shr ecx, 5
    and ecx, 3
    xor eax, eax
    test ecx, ecx
    jz .vex_lset
    mov eax, 1
.vex_lset:
    mov [r15+Insn.vex_l], al
    jmp .vex_fdone
.vex_lok:
    mov eax, ecx
    shr eax, 2
    and eax, 1
    mov [r15+Insn.vex_l], al
.vex_fdone:
    movzx ecx, byte [r9]             ; byte de opcode
    mov dword [rbp-104], 1           ; oplen = 1
    cmp r11d, 1
    je .vex_map0f
    cmp r11d, 2
    je .vex_map38
    lea rdx, [rel dex_tbl3a_flag]
    movzx r10d, byte [rdx+rcx]
    mov [rbp-80], r10d
    or ecx, 0x3A00
    mov dword [r15+Insn.opcode_len], 3
    jmp .vex_set
.vex_map38:
    lea rdx, [rel dex_tbl38_flag]
    movzx r10d, byte [rdx+rcx]
    mov [rbp-80], r10d
    or ecx, 0x3800
    mov dword [r15+Insn.opcode_len], 3
    jmp .vex_set
.vex_map0f:
    ; 2b: flags de decode da tabela VEX2 (ModRM/imm) quando houver entrada;
    ; a tabela legada tem lacunas (ex.: 0F F2 sem ModRM) e desalinharia.
    movzx r8d, byte [r9]             ; byte de opcode
    cmp byte [r15+Insn.enc], 1
    jne .vex_m0f_legacy
    cmp byte [r15+Insn.vex_npre], 2   ; só VEX2 (C5); VEX3 (C4) tem tabela própria (2c)
    jne .vex_m0f_legacy
    push r8                          ; o callee clobbra r8-r11 (ABI)
    mov rcx, r15
    mov edx, r8d
    sub rsp, 40
    call dex_vex2_flags
    add rsp, 40
    pop r8
    test eax, 0x100
    jz .vex_m0f_legacy
    and eax, 3
    mov [rbp-80], eax
    mov ecx, r8d
    or ecx, 0x0F00
    mov dword [r15+Insn.opcode_len], 2
    jmp .vex_set
.vex_m0f_legacy:
    lea rdx, [rel dex_tbl2_flag]
    movzx r10d, byte [rdx+r8]
    mov [rbp-80], r10d
    mov ecx, r8d
    or ecx, 0x0F00
    mov dword [r15+Insn.opcode_len], 2
.vex_set:
    mov [r15+Insn.opcode], ecx
    lea rdx, [rel s_vex]
    cmp byte [r15+Insn.enc], 1
    je .vex_smne
    lea rdx, [rel s_evex]
.vex_smne:
    mov [r15+Insn.mne], rdx
    jmp .got_op
