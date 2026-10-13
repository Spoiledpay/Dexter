;=============================================================================
; Dexter/src/disasm/operands.asm
; dex_decode_operands — consome imediatos/offsets após opcode+ModRM.
; Usa a flag da tabela (tbl1/tbl2/tbl38/tbl3a) + casos especiais por valor
; (grupos 80-83/C0-C1/F6-F7/C6-C7/B0-BF/A0-A3/C2-CA-C8/E4-E7).
; Preenche Insn.imm/imm_size. Retorna bytes consumidos (0 ou -1 OOB).
;
; Requisitos atendidos: R-2.x
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "dexter.inc"

global dex_decode_operands

extern dex_tbl1_flag
extern dex_tbl2_flag
extern dex_tbl38_flag
extern dex_tbl3a_flag

section .text

;-----------------------------------------------------------------------------
; dex_decode_operands
; Args:   rcx = Insn*, rdx = p (após modrm), r8 = end
; Ret:    rax = bytes de imm consumidos (0 se nenhum; -1 se OOB)
; Clobber: rax, rcx, rdx, r8-r11
;-----------------------------------------------------------------------------
dex_decode_operands:
    test rcx, rcx
    jz .oob_o
    test r8, r8
    jz .oob_o
    push rbx
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40                ; 6 pushes -> rsp%16==8; 40%16==8 => alinhado
    mov r15, rcx               ; insn
    mov rsi, rdx               ; p
    mov r12, r8                ; end
    mov r13d, [r15+Insn.opcode]      ; opcode (0..0x3FFFF)
    mov r14d, [r15+Insn.opcode_len]  ; 1,2,3
    ; buscar flag
    cmp r14d, 1
    je .f1
    cmp r14d, 2
    je .f2
    ; len 3: qual escape? bit16: 0x38 / 0x3A
    mov eax, r13d
    shr eax, 8
    and eax, 0xFF
    cmp eax, 0x38
    je .f38
    lea rbx, [rel dex_tbl3a_flag]
    jmp .fidx
.f38:
    lea rbx, [rel dex_tbl38_flag]
    jmp .fidx
.f2:
    lea rbx, [rel dex_tbl2_flag]
    jmp .fidx
.f1:
    lea rbx, [rel dex_tbl1_flag]
.fidx:
    mov eax, r13d
    and eax, 0xFF
    movzx r11d, byte [rbx+rax]   ; flag (índice sempre = low byte)
    ; casos especiais por valor têm prioridade sobre a flag genérica
    mov eax, r13d
    and eax, 0xFF              ; low byte (p/ len1) — p/ len2 usar r13d cheio
    cmp r14d, 1
    jne .len23
    ; ---------- opcode de 1 byte ----------
    cmp eax, 0xA0
    jb .ck_grp1
    cmp eax, 0xA3
    jbe .moffs                 ; A0-A3
.ck_grp1:
    cmp eax, 0x80
    jb .ck_c2
    cmp eax, 0x83
    jbe .grp80                 ; 80-83
.ck_c2:
    cmp eax, 0xC2
    je .ret16
    cmp eax, 0xCA
    je .ret16                  ; CA = ret imm16
    cmp eax, 0xC3
    je .ret0
    cmp eax, 0xCB
    je .ret0
    cmp eax, 0xC8
    je .enter                  ; C8 enter imm16,imm8
    cmp eax, 0xC6
    je .c6                     ; C6 /0 imm8 (flag já tem I8; só confirmar)
    cmp eax, 0xC7
    je .c7
    cmp eax, 0xB0
    jb .use_flag
    cmp eax, 0xBF
    jbe .mov_ri                ; B0-BF
    jmp .use_flag
.ret0:
    mov byte [r15+Insn.is_ret], 1
    jmp .use_flag
.ret16:
    mov byte [r15+Insn.is_ret], 1
    jmp .imm16s
.enter:
    jmp .enter3
.len23:
    ; ---------- 0F xx / 0F38 / 0F3A: só a flag decide ----------
    jmp .use_flag

.grp80:
    cmp eax, 0x80
    je .imm8
    cmp eax, 0x82
    je .imm8                   ; 82 = alias do 80
    cmp eax, 0x83
    je .imm8                   ; 83 = imm8 estendido
    jmp .imm_v                 ; 81 = imm v
.moffs:
    ; A0-A3: offset = 8 (addr64), 4 (addr32/0x67 em x64; default em x32)
    ; ou 2 (addr16: x32 com 0x67).
    cmp byte [r15+Insn.addr_mode], 1
    je .moffs32
    cmp byte [r15+Insn.legacy67], 0
    jne .moffs4
    jmp .imm64m
.moffs32:
    cmp byte [r15+Insn.legacy67], 0
    jne .moffs16
    jmp .imm32u
.moffs16:
    jmp .imm16s
.moffs4:
    jmp .imm32u
.c6:
    jmp .imm8                  ; /0 ib (único válido; outros /n seriam db? NÃO:
                               ; C6 só tem /0; se /n != 0, ainda consome ib
                               ; pois o byte é do encoding. Correto.)
.c7:
    jmp .imm_v
.mov_ri:
    cmp eax, 0xB7
    jbe .imm8                  ; B0-B7: imm8
    ; B8-BF: imm v ou imm64
    cmp byte [r15+Insn.has_rex], 0
    je .b8_no_rex
    test byte [r15+Insn.rex], 0x08
    jz .b8_no_rex
    jmp .imm64u                ; REX.W: imm64
.b8_no_rex:
    cmp byte [r15+Insn.legacy66], 0
    je .imm32u
    jmp .imm16s
.use_flag:
    ; r11d = flag
    test r11d, 0x02            ; I8
    jnz .imm8
    test r11d, 0x04            ; IV
    jnz .imm_v
    test r11d, 0x08            ; I32
    jz .ck_i64
    ; acumulador-imm com 66? (05..3D passo 8 + A9 test): imm16,
    ; não imm32 (ex: 66 25 iw tem 2 bytes de imm, não 4).
    cmp byte [r15+Insn.legacy66], 0
    je .imm32u
    mov eax, r13d
    and eax, 0xFF
    cmp eax, 0xA9
    je .imm16s
    cmp eax, 0x40
    jae .imm32u
    and eax, 7
    cmp eax, 5
    je .imm16s
    jmp .imm32u
.ck_i64:
    test r11d, 0x10            ; I64
    jnz .imm64u
    test r11d, 0x20            ; R8
    jnz .rel8
    test r11d, 0x40            ; R32
    jnz .rel32
    ; bit GRP ou NONE: grupos com imm dependente de reg (F6/F7/C0/C1/D0-D3/FE/FF)
    test r11d, 0x80
    jz .no_imm
    ; grupo: decidir por (opcode, modrm.reg)
    movzx eax, byte [r15+Insn.modrm]
    shr eax, 3
    and eax, 7                 ; /n
    mov ecx, [r15+Insn.opcode]
    and ecx, 0xFF
    cmp ecx, 0xF6
    je .g_f6
    cmp ecx, 0xF7
    je .g_f7
    cmp ecx, 0xC0
    je .imm8
    cmp ecx, 0xC1
    je .imm8
    cmp ecx, 0xFF
    je .g_ff
    cmp ecx, 0xBA               ; 0F BA grupo 8 (len2; len1 nunca tem GRP aqui)
    je .g_ba
    jmp .no_imm                ; D0-D3/FE/00/01 sem imm
.g_ff:
    cmp eax, 2
    je .ff_call
    cmp eax, 4
    je .ff_jmp
    jmp .no_imm
.ff_call:
    mov byte [r15+Insn.is_call], 1
    jmp .no_imm
.ff_jmp:
    mov byte [r15+Insn.is_branch], 1
    jmp .no_imm
.g_ba:
    cmp eax, 4
    jb .no_imm                 ; /0-/3 sem imm
    jmp .imm8                  ; /4-/7 imm8
.g_f6:
    test eax, eax
    jz .imm8                   ; /0 TEST ib
    cmp eax, 1
    je .imm8                   ; /1 TEST ib (Intel: também tem imediato)
    jmp .no_imm
.g_f7:
    test eax, eax
    jz .imm_f7_0               ; /0 TEST Iv
    cmp eax, 1
    je .imm_f7_0               ; /1 TEST Iv (idem)
    jmp .no_imm
.imm_f7_0:
    cmp byte [r15+Insn.legacy66], 0
    je .imm32u
    jmp .imm16s
.no_imm:
    xor eax, eax
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rbx
    ret

; ---- leitores (rsi=p, r12=end, r15=insn; ret rax=n ou -1) ----
.imm8:
    mov rax, r12
    sub rax, rsi
    cmp rax, 1
    jb .oob_r
    movsx rax, byte [rsi]
    mov [r15+Insn.imm], rax
    mov byte [r15+Insn.imm_size], 1
    mov eax, 1
    jmp .ok_r
.rel8:
    mov rax, r12
    sub rax, rsi
    cmp rax, 1
    jb .oob_r
    movsx rax, byte [rsi]      ; rel8 com sinal
    mov [r15+Insn.imm], rax
    mov byte [r15+Insn.imm_size], 1
    mov byte [r15+Insn.is_branch], 1
    mov eax, 1
    jmp .ok_r
.imm_v:
    cmp byte [r15+Insn.legacy66], 0
    je .imm32u
    jmp .imm16s
.imm16s:
    mov rax, r12
    sub rax, rsi
    cmp rax, 2
    jb .oob_r
    movsx rax, word [rsi]
    mov [r15+Insn.imm], rax
    mov byte [r15+Insn.imm_size], 2
    mov eax, 2
    jmp .ok_r
.imm32u:
    mov rax, r12
    sub rax, rsi
    cmp rax, 4
    jb .oob_r
    mov eax, [rsi]
    mov [r15+Insn.imm], rax    ; zero-estendido
    mov byte [r15+Insn.imm_size], 4
    mov eax, 4
    jmp .ok_r
.rel32:
    mov rax, r12
    sub rax, rsi
    cmp rax, 4
    jb .oob_r
    movsxd rax, dword [rsi]
    mov [r15+Insn.imm], rax
    mov byte [r15+Insn.imm_size], 4
    mov byte [r15+Insn.is_branch], 1
    cmp r13d, 0xE8             ; call rel32 também é call
    jne .rel32_done
    mov byte [r15+Insn.is_call], 1
.rel32_done:
    mov eax, 4
    jmp .ok_r
.imm64u:
    mov rax, r12
    sub rax, rsi
    cmp rax, 8
    jb .oob_r
    mov rax, [rsi]
    mov [r15+Insn.imm], rax
    mov byte [r15+Insn.imm_size], 8
    mov eax, 8
    jmp .ok_r
.imm64m:                        ; moffs64: 8 bytes sem sinal
    mov rax, r12
    sub rax, rsi
    cmp rax, 8
    jb .oob_r
    mov rax, [rsi]
    mov [r15+Insn.imm], rax
    mov byte [r15+Insn.imm_size], 8
    mov eax, 8
    jmp .ok_r
.enter3:                        ; C8 ENTER imm16,imm8 = 3 bytes
    mov rax, r12
    sub rax, rsi
    cmp rax, 3
    jb .oob_r
    movzx eax, word [rsi]
    movzx ecx, byte [rsi+2]
    shl ecx, 16
    or eax, ecx
    mov [r15+Insn.imm], rax
    mov byte [r15+Insn.imm_size], 3
    mov eax, 3
    jmp .ok_r
.ok_r:
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rbx
    ret
.oob_o:
    mov rax, -1
    ret
.oob_r:
    mov rax, -1
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rbx
    ret
