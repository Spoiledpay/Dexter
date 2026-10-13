;=============================================================================
; Dexter/src/disasm/prefixes.asm
; dex_decode_prefixes — consome prefixos legacy (máx 4) + REX (último vale).
; Preenche Insn.prefix_count/rex/has_rex/legacy66/legacy67/lock/rep.
;
; Requisitos atendidos: R-2.x
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "dexter.inc"

global dex_decode_prefixes

section .text

;-----------------------------------------------------------------------------
; dex_decode_prefixes
; Args:   rcx = p (cursor), rdx = end (1ª posição inválida), r8 = Insn*
; Ret:    rax = bytes de prefixo consumidos (0..5)
;-----------------------------------------------------------------------------
dex_decode_prefixes:
    test rcx, rcx
    jz .zero_p
    test rdx, rdx
    jz .zero_p
    test r8, r8
    jz .zero_p
    push rbx
    push rsi
    xor eax, eax                ; n
    mov rsi, rcx                ; cursor
    xor ebx, ebx                ; n_legacy
.loop:
    cmp rsi, rdx
    jae .done
    cmp ebx, 4
    jae .rex_try                ; máx 4 legacy: tentar REX e sair
    movzx ecx, byte [rsi]
    cmp cl, 0xF0
    je .legacy
    cmp cl, 0xF2
    je .legacy
    cmp cl, 0xF3
    je .legacy
    cmp cl, 0x2E
    je .seg_cs
    cmp cl, 0x36
    je .seg_ss
    cmp cl, 0x3E
    je .seg_ds
    cmp cl, 0x26
    je .seg_es
    cmp cl, 0x64
    je .seg_fs
    cmp cl, 0x65
    je .seg_gs
    cmp cl, 0x66
    je .l66
    cmp cl, 0x67
    je .l67
    jmp .rex_try
.seg_cs:
    mov byte [r8+Insn.segprefix], 2
    jmp .legacy
.seg_ss:
    mov byte [r8+Insn.segprefix], 3
    jmp .legacy
.seg_ds:
    mov byte [r8+Insn.segprefix], 4
    jmp .legacy
.seg_es:
    mov byte [r8+Insn.segprefix], 1
    jmp .legacy
.seg_fs:
    mov byte [r8+Insn.segprefix], 5
    jmp .legacy
.seg_gs:
    mov byte [r8+Insn.segprefix], 6
    jmp .legacy
.l66:
    mov byte [r8+Insn.legacy66], 1
    jmp .legacy
.l67:
    mov byte [r8+Insn.legacy67], 1
    jmp .legacy
.legacy:
    cmp cl, 0xF0
    jne .not_lock
    mov byte [r8+Insn.lock], 1
    jmp .adv_l
.not_lock:
    cmp cl, 0xF2
    jne .not_rep2
    mov byte [r8+Insn.rep], 0xF2
    jmp .adv_l
.not_rep2:
    cmp cl, 0xF3
    jne .adv_l
    mov byte [r8+Insn.rep], 0xF3
.adv_l:
    inc rsi
    inc rax
    inc ebx
    jmp .loop
.rex_try:
    cmp rsi, rdx
    jae .done
    ; Fase x32: 0x40-0x4F são inc/dec (nunca REX) — não consumir.
    cmp byte [r8+Insn.addr_mode], 1
    je .done
    movzx ecx, byte [rsi]
    cmp cl, 0x40
    jb .done
    cmp cl, 0x4F
    ja .done
    mov [r8+Insn.rex], cl
    mov byte [r8+Insn.has_rex], 1
    inc rsi
    inc rax
    ; após REX, outro REX também vale (último vence); legacy não pode vir depois
.rex_more:
    cmp rsi, rdx
    jae .done
    movzx ecx, byte [rsi]
    cmp cl, 0x40
    jb .done
    cmp cl, 0x4F
    ja .done
    mov [r8+Insn.rex], cl
    inc rsi
    inc rax
    jmp .rex_more
.done:
    mov [r8+Insn.prefix_count], eax
    pop rsi
    pop rbx
    ret
.zero_p:
    xor eax, eax
    ret
