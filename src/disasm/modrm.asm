;=============================================================================
; Dexter/src/disasm/modrm.asm
; dex_decode_modrm — consome ModRM [+ SIB + disp] se Insn.has_modrm.
; Suporta addr64 (padrão) e addr32 (legacy 0x67). Preenche modrm/sib,
; has_sib, disp, disp_size. disp com sinal é zero-estendido em u64
; (o emitter imprime em hex; target RIP-rel é calculado no decoder).
;
; Requisitos atendidos: R-2.x
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "dexter.inc"

global dex_decode_modrm

section .text

;-----------------------------------------------------------------------------
; dex_decode_modrm
; Args:   rcx = p (após opcode), rdx = end, r8 = Insn* (has_modrm já setado)
; Ret:    rax = bytes consumidos (0 se has_modrm==0; -1 se falta byte)
;-----------------------------------------------------------------------------
dex_decode_modrm:
    test rcx, rcx
    jz .oob
    test r8, r8
    jz .oob
    cmp byte [r8+Insn.has_modrm], 0
    je .none
    push rbx
    push rsi
    push r12
    mov rsi, rcx               ; cursor
    mov r12, rdx               ; end
    xor eax, eax               ; n
    cmp rsi, r12
    jae .oob_r
    movzx ebx, byte [rsi]      ; modrm
    mov [r8+Insn.modrm], bl
    inc rsi
    inc rax
    ; mod = bl>>6, reg = (bl>>3)&7, rm = bl&7
    mov cl, bl
    shr cl, 6                  ; mod
    mov ch, bl
    shr ch, 3
    and ch, 7                  ; reg (não usado aqui)
    and bl, 7                  ; rm
    cmp cl, 3
    je .done_m                 ; mod==11: só registradores
    cmp byte [r8+Insn.legacy67], 0
    jne .leg67
    cmp byte [r8+Insn.addr_mode], 1
    je .addr32                 ; x32 sem 0x67: endereçamento 32 (mesma forma)
    ; ---- addr64 ----
    cmp bl, 4
    je .sib64
    cmp bl, 5
    je .rip32
    jmp .mod_disp64
.sib64:
    cmp rsi, r12
    jae .oob_r
    movzx ebx, byte [rsi]      ; sib
    mov [r8+Insn.sib], bl
    mov byte [r8+Insn.has_sib], 1
    inc rsi
    inc rax
    ; base = sib&7 (bit REX.B irrelevante p/ tamanho, exceto base==5&&mod==0)
    and bl, 7
    cmp cl, 0
    jne .mod_disp64            ; mod!=0: disp por mod
    cmp bl, 5
    je .disp32                 ; base==5 && mod==0: disp32
    jmp .done_m
.rip32:
    cmp cl, 0
    jne .mod_disp64            ; mod!=0 rm==5: disp por mod
    jmp .disp32                ; mod==0 rm==5: RIP+disp32
.mod_disp64:
    cmp cl, 1
    je .disp8
    cmp cl, 2
    je .disp32
    jmp .done_m                ; mod==0 (rm!=4/5): sem disp
.addr32:
    ; ---- addr32 (0x67 em x64; default em x32): SIB se rm==4;
    ; disp32 se (mod==0 && rm==5). Em x32 o disp32 é ABSOLUTO
    ; (sem semântica RIP; build_operands recusa x32 de todo modo).
    cmp bl, 4
    je .sib32
    cmp bl, 5
    jne .mod_disp64            ; mod==0 rm!=4/5: sem disp; mod 1/2: disp
    cmp cl, 0
    jne .mod_disp64
    jmp .disp32
.leg67:
    cmp byte [r8+Insn.addr_mode], 1
    je .addr16                 ; x32 com 0x67: endereçamento 16 (sem SIB)
    jmp .addr32                ; x64 com 0x67: forma 32
.addr16:
    ; mod==0: rm==6 ? disp16 : sem disp; mod==1: disp8; mod==2: disp16.
    cmp cl, 1
    je .disp8
    cmp cl, 2
    je .disp16
    test cl, cl
    jnz .done_m                ; mod==3 já saiu acima; defensivo
    cmp bl, 6
    je .disp16
    jmp .done_m
.disp16:
    mov rdx, r12
    sub rdx, rsi
    cmp rdx, 2
    jb .oob_r
    movsx ebx, word [rsi]       ; com sinal (como disp8/disp32)
    mov [r8+Insn.disp], rbx
    mov byte [r8+Insn.disp_size], 2
    add rsi, 2
    add rax, 2
    jmp .done_m
.sib32:
    cmp rsi, r12
    jae .oob_r
    movzx ebx, byte [rsi]
    mov [r8+Insn.sib], bl
    mov byte [r8+Insn.has_sib], 1
    inc rsi
    inc rax
    and bl, 7
    cmp cl, 0
    jne .mod_disp64
    cmp bl, 5
    je .disp32
    jmp .done_m
.disp8:
    cmp rsi, r12
    jae .oob_r
    movsx ebx, byte [rsi]
    mov [r8+Insn.disp], rbx
    mov byte [r8+Insn.disp_size], 1
    inc rsi
    inc rax
    jmp .done_m
.disp32:
    mov rdx, r12
    sub rdx, rsi
    cmp rdx, 4
    jb .oob_r
    movsxd rbx, dword [rsi]
    mov [r8+Insn.disp], rbx
    mov byte [r8+Insn.disp_size], 4
    add rsi, 4
    add rax, 4
.done_m:
    pop r12
    pop rsi
    pop rbx
    ret
.none:
    xor eax, eax
    ret
.oob:
    mov rax, -1
    ret
.oob_r:
    mov rax, -1
    pop r12
    pop rsi
    pop rbx
    ret
