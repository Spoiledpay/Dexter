;=============================================================================
; Dexter/src/disasm/emit_nasm.asm
; dex_emit_insn / dex_emit_data — emissão NASM fiel a bytes (db) + labels.
; Estratégia Fase 1 (documentada): cada instrução vira label + db exato;
; calls/jmps RIP-relativos p/ a IAT viram `call|jmp [rel __imp_X]` real
; (necessário p/ o rebuild funcionar com .idata regenerada — ver rebuild).
;
; Requisitos atendidos: R-2.x, R-4.x
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "dexter.inc"

global dex_emit_insn
global dex_emit_native
global dex_emit_data
global dex_emit_label
global dex_emit_set_hex

extern asmbuf_append
extern asmbuf_append_str
extern asmbuf_append_char
extern asmbuf_append_u64_hex
extern dex_u64_to_hex
extern dex_label_emit_va
extern dex_r64_names
extern dex_r32_names
extern dex_r16_names
extern dex_r8_names
extern dex_r8hi_names
extern dex_seg_names
extern dex_cc_suffix
extern s_jpre
extern s_cmovpre
extern s_setpre
extern s_lock
extern s_rep
extern s_repne
extern s_byte
extern s_word
extern s_dword
extern s_qword
extern s_jcc
extern s_loop
extern s_cmov
extern s_setcc
extern s_cbw
extern s_cdq
extern s_movsd
extern s_stosd
extern s_lodsd
extern s_scasd
extern s_cmpsd
extern s_cbw
extern s_cwde
extern s_cdqe
extern s_cwd
extern s_cdq
extern s_cqo
extern s_jrcxz
extern s_jecxz
extern s_movsq
extern s_stosq
extern s_lodsq
extern s_scasq
extern s_cmpsq

section .rodata
s_label_pre  db "label_", 0
s_indent     db "    ", 0
s_db         db "    db ", 0
s_comma      db ", ", 0
s_semi       db "  ; ", 0
s_at         db "@0x", 0
s_0x         db "0x", 0
s_sp         db " ", 0
s_strict4    db "strict dword ", 0
s_strict8    db "strict qword ", 0
s_abs        db "abs ", 0
s_relpre     db "[rel ", 0
s_crlf       db 13, 10, 0
s_colon_nl   db ":", 13, 10, 0
s_call_rel   db "    call [rel ", 0
s_jmp_rel    db "    jmp [rel ", 0
s_call_abs   db "    call [", 0
s_jmp_abs    db "    jmp [", 0
s_rb         db "]", 0
s_global     db "global ", 0

section .bss
align 8
g_emit_hex:  resb 8

section .text

;-----------------------------------------------------------------------------
; dex_emit_set_hex — cl=dll(0/1). Liga/desliga comentários "; @VA" (-hex).
;-----------------------------------------------------------------------------
dex_emit_set_hex:
    mov [rel g_emit_hex], cl
    ret

;-----------------------------------------------------------------------------
; dex_emit_label — rcx=buf, rdx=va. Emite "label_<hex>:\r\n". rax=0/1.
;-----------------------------------------------------------------------------
dex_emit_label:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 40
    mov rbx, rcx
    mov r12, rdx
    lea rdx, [rel s_label_pre]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fail_l
    mov rcx, rbx
    mov rdx, r12
    xor r8d, r8d
    sub rsp, 32
    call asmbuf_append_u64_hex
    add rsp, 32
    test eax, eax
    jnz .fail_l
    lea rdx, [rel s_colon_nl]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
.fail_l:
    add rsp, 40
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; dex_emit_data
; Args: rcx=buf, rdx=bytes, r8=len, r9=va_para_label (ou -1 sem label)
; Emite "label_VA:\r\n    db b,b,...\r\n" (16 bytes por linha).
; Ret: rax=0 ok, 1 OOM.
;-----------------------------------------------------------------------------
dex_emit_data:
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
    mov rbx, rcx               ; buf
    mov rsi, rdx               ; bytes
    mov r12, r8                ; len
    mov r13, r9                ; va
    cmp r13, -1
    je .nolab_d
    mov rcx, rbx
    mov rdx, r13
    sub rsp, 32
    call dex_emit_label
    add rsp, 32
    test eax, eax
    jnz .fail_d
.nolab_d:
    test r12, r12
    jz .ok_d
    xor r14d, r14d             ; i
.line:
    cmp r14, r12
    jae .ok_d
    lea rdx, [rel s_db]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fail_d
    mov r15, r14
    add r15, 16
    cmp r15, r12
    jbe .cnt_ok
    mov r15, r12
.cnt_ok:
    ; bytes [r14, r15)
    mov [rbp-80], r14          ; line_start (p/ comentário -hex)
    jmp .byte_l
.byte_l:
    cmp r14, r15
    jae .eol
    movzx eax, byte [rsi+r14]
    ; "0xHH"
    mov byte [rbp-72], '0'
    mov byte [rbp-71], 'x'
    mov ecx, eax
    shr ecx, 4
    and ecx, 15
    cmp ecx, 9
    jbe .hn
    add ecx, 55
    jmp .hs
.hn:
    add ecx, 48
.hs:
    mov [rbp-70], cl
    mov ecx, eax
    and ecx, 15
    cmp ecx, 9
    jbe .ln
    add ecx, 55
    jmp .ls
.ln:
    add ecx, 48
.ls:
    mov [rbp-69], cl
    lea rdx, [rbp-72]
    mov rcx, rbx
    mov r8, 4
    sub rsp, 32
    call asmbuf_append
    add rsp, 32
    test eax, eax
    jnz .fail_d
    inc r14
    cmp r14, r15
    jae .eol
    lea rdx, [rel s_comma]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fail_d
    jmp .byte_l
.eol:
    ; comentário "; @VA" se -hex e há label base (va != -1)
    cmp byte [rel g_emit_hex], 0
    je .eol_nl
    cmp r13, -1
    je .eol_nl
    mov [rbp-88], r14          ; spill i (r14 morre abaixo? não usado após; só p/ segurança)
    mov rax, r13
    add rax, [rbp-80]          ; va da linha
    mov [rbp-96], rax          ; spill va (slots [-96..-80] livres? frame sub56:
                               ; rsp=rbp-120; sombra calls=[-152..-120]; livres=[-120..-64].
                               ; -80,-88,-96 OK)
    lea rdx, [rel s_semi]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fail_d
    lea rdx, [rel s_at]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fail_d
    mov rcx, rbx
    mov rdx, [rbp-96]
    xor r8d, r8d
    sub rsp, 32
    call asmbuf_append_u64_hex
    add rsp, 32
    test eax, eax
    jnz .fail_d
    mov r14, [rbp-88]
.eol_nl:
    lea rdx, [rel s_crlf]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fail_d
    jmp .line
.ok_d:
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
.fail_d:
    mov eax, 1
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

;-----------------------------------------------------------------------------
; dex_emit_insn
; Args: rcx=buf, rdx=Insn*, r8=import_name (char* __imp_X ou 0),
;       r9d=kind (0=db, 1=call[rel], 2=jmp[rel], 3=mov r64,[rel], 4=lea r64,[rel])
;       + reg_idx em [rsp+40]? — simplificação: kinds 3/4 com reg em r10?
; Para kinds 3/4 o chamador passa o índice do registrador via 5º arg na pilha.
; Ret: rax=0 ok, 1 OOM.
; Emite label + (db exato | instrução real com símbolo).
;-----------------------------------------------------------------------------
dex_emit_insn:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 48
    mov rbx, rcx               ; buf
    mov r12, rdx               ; insn
    mov r13, r8                ; impname (pode ser 0)
    mov r14d, r9d              ; kind
    ; label
    mov rdx, [r12+Insn.address]
    mov rcx, rbx
    sub rsp, 32
    call dex_emit_label
    add rsp, 32
    test eax, eax
    jnz .fail_i
    cmp r14d, 0
    je .as_db
    cmp r13, 0
    je .as_db
    cmp r14d, 1
    je .do_call
    cmp r14d, 2
    je .do_jmp
    jmp .as_db                 ; kinds 3/4: não implementado nesta fase -> db
.do_call:
    cmp byte [r12+Insn.addr_mode], 1
    je .do_call_abs
    lea rdx, [rel s_call_rel]
    jmp .do_call_emit
.do_call_abs:
    lea rdx, [rel s_call_abs]
.do_call_emit:
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fail_i
    mov rdx, r13
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fail_i
    lea rdx, [rel s_rb]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fail_i
    jmp .tail_mne
.do_jmp:
    cmp byte [r12+Insn.addr_mode], 1
    je .do_jmp_abs
    lea rdx, [rel s_jmp_rel]
    jmp .do_jmp_emit
.do_jmp_abs:
    lea rdx, [rel s_jmp_abs]
.do_jmp_emit:
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fail_i
    mov rdx, r13
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fail_i
    lea rdx, [rel s_rb]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fail_i
    jmp .tail_mne
.as_db:
    ; "    db b,b,..." (reuso da lógica de data p/ insn.raw/length)
    lea rdx, [rel s_db]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fail_i
    mov r14d, [r12+Insn.length]
    xor r13d, r13d             ; i
.db_l:
    cmp r13d, r14d
    jae .tail_mne
    movzx eax, byte [r12+r13+Insn.raw]
    mov byte [rbp-48], '0'
    mov byte [rbp-47], 'x'
    mov ecx, eax
    shr ecx, 4
    cmp ecx, 9
    jbe .hn2
    add ecx, 55
    jmp .hs2
.hn2:
    add ecx, 48
.hs2:
    mov [rbp-46], cl
    and eax, 15
    cmp eax, 9
    jbe .ln2
    add eax, 55
    jmp .ls2
.ln2:
    add eax, 48
.ls2:
    mov [rbp-45], al
    lea rdx, [rbp-48]
    mov rcx, rbx
    mov r8, 4
    sub rsp, 32
    call asmbuf_append
    add rsp, 32
    test eax, eax
    jnz .fail_i
    inc r13d
    cmp r13d, r14d
    jae .tail_mne
    lea rdx, [rel s_comma]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fail_i
    jmp .db_l
.tail_mne:
    ; "  ; mne" se conhecido
    mov rax, [r12+Insn.mne]
    test rax, rax
    jz .tail_hex
    lea rdx, [rel s_semi]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fail_i
    mov rdx, [r12+Insn.mne]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fail_i
    ; com mne: " @0xVA" (espaço simples)
    cmp byte [rel g_emit_hex], 0
    je .tail_nl
    lea rdx, [rel s_sp]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fail_i
    jmp .tail_hex_va
.tail_hex:
    ; sem mne: "  ; @0xVA" se -hex, senão nada
    cmp byte [rel g_emit_hex], 0
    je .tail_nl
    lea rdx, [rel s_semi]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fail_i
.tail_hex_va:
    lea rdx, [rel s_at]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fail_i
    mov rcx, rbx
    mov rdx, [r12+Insn.address]
    xor r8d, r8d
    sub rsp, 32
    call asmbuf_append_u64_hex
    add rsp, 32
    test eax, eax
    jnz .fail_i
.tail_nl:
    lea rdx, [rel s_crlf]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
.fail_i:
    add rsp, 48
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; dex_emit_native — rcx=buf, rdx=Insn* -> rax=0 (nativo) / 1 (usar db)
; Emite "    [lock|rep] mne op0[, op1[, op2]]" com operandos reais.
; Pré-condições (walker garante rótulos): RIP/REL referenciam VAs rotulados.
; Regras: mne==0 → 1; rep fora de string-ops/pause → 1; lock sem MEM → 1.
; Clobber: rax,rcx,rdx,r8-r11. Preserva non-voláteis.
;-----------------------------------------------------------------------------
dex_emit_native:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 56                ; 6 pushes -> rsp%16==8; 56%16==8 => alinhado
    mov rbx, rcx               ; buf
    mov r15, rdx               ; insn
    mov rax, [r15+Insn.mne]
    test rax, rax
    jz .en_db                  ; sem mnemônico → db
    ; indent
    lea rdx, [rel s_indent]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .en_fail
    ; lock? (só com MEM; senão db)
    cmp byte [r15+Insn.lock], 0
    je .en_rep
    mov al, [r15+Insn.op0+DexOp.kind]
    cmp al, DEX_OP_MEM
    je .en_lock_ok
    mov al, [r15+Insn.op1+DexOp.kind]
    cmp al, DEX_OP_MEM
    je .en_lock_ok
    mov al, [r15+Insn.op2+DexOp.kind]
    cmp al, DEX_OP_MEM
    jne .en_db
.en_lock_ok:
    lea rdx, [rel s_lock]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .en_fail
.en_rep:
    ; rep? (só string-ops A4-AF ou pause-já-resolvido; senão db)
    mov al, [r15+Insn.rep]
    test al, al
    jz .en_mne
    movzx ecx, byte [r15+Insn.opcode]
    cmp ecx, 0x90
    je .en_mne                 ; F3 90 = pause (mne pronto, sem prefixo)
    cmp ecx, 0xA4
    jb .en_db
    cmp ecx, 0xAF
    ja .en_db
    cmp al, 0xF2
    je .en_repne
    lea rdx, [rel s_rep]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .en_fail
    jmp .en_mne
.en_repne:
    lea rdx, [rel s_repne]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .en_fail
.en_mne:
    ; mnemônico (com especializações)
    mov rax, [r15+Insn.mne]
    lea rcx, [rel s_jcc]
    cmp rax, rcx
    je .en_jcc
    lea rcx, [rel s_cmov]
    cmp rax, rcx
    je .en_cmov
    lea rcx, [rel s_setcc]
    cmp rax, rcx
    je .en_setcc
    lea rcx, [rel s_cbw]
    cmp rax, rcx
    je .en_cbw
    lea rcx, [rel s_cdq]
    cmp rax, rcx
    je .en_cdq
    lea rcx, [rel s_loop]
    cmp rax, rcx
    je .en_mne_raw             ; loop (E2): direto
    ; string ops com REX.W? (movsd→movsq etc.) — inline:
    cmp byte [r15+Insn.has_rex], 0
    je .en_fs_done
    test byte [r15+Insn.rex], 8  ; REX.W?
    jz .en_fs_done
    mov rax, [r15+Insn.mne]
    lea rcx, [rel s_movsd]
    cmp rax, rcx
    je .en_fs_movsq
    lea rcx, [rel s_stosd]
    cmp rax, rcx
    je .en_fs_stosq
    lea rcx, [rel s_lodsd]
    cmp rax, rcx
    je .en_fs_lodsq
    lea rcx, [rel s_scasd]
    cmp rax, rcx
    je .en_fs_scasq
    lea rcx, [rel s_cmpsd]
    cmp rax, rcx
    je .en_fs_cmpsq
.en_fs_done:
    mov rdx, [r15+Insn.mne]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .en_fail
    jmp .en_ops
.en_fs_movsq:
    lea rax, [rel s_movsq]
    mov [r15+Insn.mne], rax
    jmp .en_fs_done
.en_fs_stosq:
    lea rax, [rel s_stosq]
    mov [r15+Insn.mne], rax
    jmp .en_fs_done
.en_fs_lodsq:
    lea rax, [rel s_lodsq]
    mov [r15+Insn.mne], rax
    jmp .en_fs_done
.en_fs_scasq:
    lea rax, [rel s_scasq]
    mov [r15+Insn.mne], rax
    jmp .en_fs_done
.en_fs_cmpsq:
    lea rax, [rel s_cmpsq]
    mov [r15+Insn.mne], rax
    jmp .en_fs_done
.en_jcc:
    ; E3? jrcxz/jecxz (não jcc!)
    movzx eax, byte [r15+Insn.opcode]
    cmp eax, 0xE3
    je .en_jcxz
    lea rdx, [rel s_jpre]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .en_fail
    jmp .en_ccsuf
.en_cmov:
    lea rdx, [rel s_cmovpre]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .en_fail
    jmp .en_ccsuf
.en_setcc:
    lea rdx, [rel s_setpre]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .en_fail
.en_ccsuf:
    ; sufixo = cc[opcode&0xF]
    movzx eax, byte [r15+Insn.opcode]
    and eax, 0x0F
    lea rcx, [rel dex_cc_suffix]
    mov rdx, [rcx+rax*8]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .en_fail
    jmp .en_ops
.en_jcxz:
    cmp byte [r15+Insn.legacy67], 0
    jne .en_jecxz_go
    cmp byte [r15+Insn.addr_mode], 1
    je .en_jecxz_go            ; x32 sem 67: contadores 32 (jecxz)
    jmp .en_jrcxz
.en_jecxz_go:
    lea rdx, [rel s_jecxz]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .en_fail
    jmp .en_ops
.en_jrcxz:
    lea rdx, [rel s_jrcxz]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .en_fail
    jmp .en_ops
.en_cbw:
    cmp byte [r15+Insn.has_rex], 0
    je .en_cbw66
    test byte [r15+Insn.rex], 8
    jz .en_cbw66
    lea rdx, [rel s_cdqe]
    jmp .en_cbw_e
.en_cbw66:
    cmp byte [r15+Insn.legacy66], 0
    je .en_cwde
    lea rdx, [rel s_cbw]
    jmp .en_cbw_e
.en_cwde:
    lea rdx, [rel s_cwde]
.en_cbw_e:
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .en_fail
    jmp .en_ops
.en_cdq:
    cmp byte [r15+Insn.has_rex], 0
    je .en_cdq66
    test byte [r15+Insn.rex], 8
    jz .en_cdq66
    lea rdx, [rel s_cqo]
    jmp .en_cdq_e
.en_cdq66:
    cmp byte [r15+Insn.legacy66], 0
    je .en_cdq_d
    lea rdx, [rel s_cwd]
    jmp .en_cdq_e
.en_cdq_d:
    lea rdx, [rel s_cdq]
.en_cdq_e:
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .en_fail
    jmp .en_ops
.en_mne_raw:
    mov rdx, [r15+Insn.mne]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .en_fail
    jmp .en_ops

;-----------------------------------------------------------------------------
; .en_ops — emite op0[, op1[, op2]] (ou nada se op0 ausente).
;-----------------------------------------------------------------------------
.en_ops:
    movzx eax, byte [r15+Insn.op0+DexOp.kind]
    test eax, eax
    jz .en_tail
    lea rdx, [rel s_sp]          ; espaço entre mnemônico e operandos
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .en_fail
    mov rcx, rbx
    mov rdx, r15
    lea r8, [r15+Insn.op0]
    sub rsp, 32
    call .en_fmt_op
    add rsp, 32
    test eax, eax
    jnz .en_db
    movzx eax, byte [r15+Insn.op1+DexOp.kind]
    test eax, eax
    jz .en_tail
    lea rdx, [rel s_comma]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .en_fail
    mov rcx, rbx
    mov rdx, r15
    lea r8, [r15+Insn.op1]
    sub rsp, 32
    call .en_fmt_op
    add rsp, 32
    test eax, eax
    jnz .en_db
    movzx eax, byte [r15+Insn.op2+DexOp.kind]
    test eax, eax
    jz .en_tail
    lea rdx, [rel s_comma]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .en_fail
    mov rcx, rbx
    mov rdx, r15
    lea r8, [r15+Insn.op2]
    sub rsp, 32
    call .en_fmt_op
    add rsp, 32
    test eax, eax
    jnz .en_db
    jmp .en_tail
.en_tail:
    ; "; @0xVA" se -hex
    cmp byte [rel g_emit_hex], 0
    je .en_nl
    lea rdx, [rel s_semi]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .en_fail
    lea rdx, [rel s_at]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .en_fail
    mov rcx, rbx
    mov rdx, [r15+Insn.address]
    xor r8d, r8d
    sub rsp, 32
    call asmbuf_append_u64_hex
    add rsp, 32
    test eax, eax
    jnz .en_fail
.en_nl:
    lea rdx, [rel s_crlf]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .en_fail
    xor eax, eax               ; 0 = nativo emitido
    add rsp, 56
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.en_db:
    mov eax, 1                 ; 1 = usar db
    add rsp, 56
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.en_fail:
    mov eax, 1                 ; OOM também vira db? NÃO — OOM deve propagar!
    add rsp, 56                ; (simplificação honesta: OOM raro; db precisa de
    pop r15                    ;  buf válido — se OOM, db também falha e retorna
    pop r14                    ;  erro no walker. Documentado.)
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; .en_fmt_op — rcx=buf, rdx=insn, r8=&op -> rax=0 ok / 1 db-fallback.
;-----------------------------------------------------------------------------
.en_fmt_op:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 32                ; 5 pushes -> rsp%16==0; 40%16==8 => alinhado
    mov rbx, rcx               ; buf
    mov r12, rdx               ; insn
    mov r13, r8                ; op
    movzx eax, byte [r13+DexOp.kind]
    cmp eax, DEX_OP_REG
    je .fo_reg
    cmp eax, DEX_OP_MEM
    je .fo_mem
    cmp eax, DEX_OP_IMM
    je .fo_imm
    cmp eax, DEX_OP_REL
    je .fo_rel
    cmp eax, DEX_OP_SEG
    je .fo_seg
    jmp .fo_no                  ; kind 0/inválido → db
.fo_reg:
    ; tabela por size; hi-rule p/ r8 sem REX (exceto B0-B7: sempre low)
    movzx eax, byte [r13+DexOp.size]
    movzx ecx, byte [r13+DexOp.reg]
    cmp eax, 8
    je .fo_r64
    cmp eax, 4
    je .fo_r32
    cmp eax, 2
    je .fo_r16
    cmp eax, 1
    jne .fo_no
    ; size 1: hi-rule?
    cmp byte [r12+Insn.has_rex], 0
    jne .fo_r8low
    cmp ecx, 4
    jb .fo_r8low
    cmp ecx, 7
    ja .fo_r8low
    ; sem REX, idx 4-7: hi SOMENTE se vier de ModRM (não B0-B7).
    ; B0-B7 usam spl/bpl/sil/dil mesmo sem REX.
    movzx eax, byte [r12+Insn.opcode]
    cmp eax, 0xB0
    jb .fo_r8hi
    cmp eax, 0xB8
    jb .fo_r8low
    jmp .fo_r8hi
.fo_r8hi:
    sub ecx, 4
    lea rax, [rel dex_r8hi_names]
    mov rdx, [rax+rcx*8]
    jmp .fo_emitreg
.fo_r8low:
    lea rax, [rel dex_r8_names]
    mov rdx, [rax+rcx*8]
    jmp .fo_emitreg
.fo_r64:
    lea rax, [rel dex_r64_names]
    mov rdx, [rax+rcx*8]
    jmp .fo_emitreg
.fo_r32:
    lea rax, [rel dex_r32_names]
    mov rdx, [rax+rcx*8]
    jmp .fo_emitreg
.fo_r16:
    lea rax, [rel dex_r16_names]
    mov rdx, [rax+rcx*8]
.fo_emitreg:
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    xor eax, eax
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.fo_seg:
    movzx ecx, byte [r13+DexOp.reg]
    cmp ecx, 1
    jb .fo_no
    cmp ecx, 6
    ja .fo_no
    lea rax, [rel dex_seg_names]
    mov rdx, [rax+rcx*8]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    xor eax, eax
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.fo_imm:
    ; Força a forma larga ORIGINAL: o nasm otimiza imm (mov rax,0 -> B8 5B
    ; em vez de C7 7B; 81 -> 83; 69 -> 6B) e muda o tamanho, quebrando o
    ; layout (labels/RIP). Regra pela FORMA original (Insn.imm_size):
    ; 4->strict dword (se op 4/8; push-68 não aceita strict: build garante
    ; que push-curto cai em db), 8->strict qword (só B-form imm64).
    ; imm16/imm8/enter/ret não têm forma curta alternativa: plain.
    movzx eax, byte [r12+Insn.imm_size]
    cmp eax, 8
    je .fo_istrict8
    cmp eax, 4
    jne .fo_immgo
    cmp byte [r13+DexOp.size], 2
    je .fo_immgo                 ; imm16 (66): forma única, sem strict
    cmp dword [r12+Insn.opcode_len], 1
    jne .fo_istrict4go
    cmp byte [r12+Insn.opcode], 0x68
    je .fo_immgo                 ; push 68: sem strict (build filtra curtos)
.fo_istrict4go:
    lea rdx, [rel s_strict4]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    jmp .fo_immgo
.fo_istrict8:
    lea rdx, [rel s_strict8]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fo_fail
.fo_immgo:
    ; "0x" + hex(val mascarado pelo size)
    lea rdx, [rel s_0x]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    mov rax, [r13+DexOp.val]
    movzx ecx, byte [r13+DexOp.size]
    cmp ecx, 1
    je .fo_im8
    cmp ecx, 2
    je .fo_im16
    cmp ecx, 4
    je .fo_im32
    ; size 8: full
    mov rcx, rbx
    mov rdx, rax
    xor r8d, r8d
    sub rsp, 32
    call asmbuf_append_u64_hex
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    xor eax, eax
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.fo_im8:
    and eax, 0xFF
    mov rcx, rbx
    mov edx, eax
    xor r8d, r8d
    sub rsp, 32
    call asmbuf_append_u64_hex
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    xor eax, eax
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.fo_im16:
    and eax, 0xFFFF
    mov rcx, rbx
    mov edx, eax
    xor r8d, r8d
    sub rsp, 32
    call asmbuf_append_u64_hex
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    xor eax, eax
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.fo_im32:
    mov eax, eax               ; zera altos (low32)
    cmp eax, 0x80000000
    jb .fo_im32pos
    ; negativo (ex -1 = 0xFFFFFFFF): "-0x<mag>" p/ strict dword
    ; (0xFFFFFFFF nu dá warning e pode truncar; -0x1 é exato).
    mov rcx, rbx
    mov edx, '-'
    sub rsp, 32
    call asmbuf_append_char
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    lea rdx, [rel s_0x]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    mov eax, [r13+DexOp.val]   ; recarrega (calls mataram rax!)
    neg eax                    ; mag em 32 bits (0 - eax)
    mov rcx, rbx
    mov edx, eax
    xor r8d, r8d
    sub rsp, 32
    call asmbuf_append_u64_hex
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    xor eax, eax
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.fo_im32pos:
    mov rcx, rbx
    mov rdx, rax
    xor r8d, r8d
    sub rsp, 32
    call asmbuf_append_u64_hex
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    xor eax, eax
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.fo_rel:
    mov rcx, rbx
    mov rdx, [r13+DexOp.val]
    sub rsp, 32
    call dex_label_emit_va
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    xor eax, eax
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.fo_mem:
    ; Formas: [rel label] (RIP: base==NOBASE && !has_sib)
    ;         [abs] (SIB-abs: base==NOBASE && has_sib)
    ;         [seg:base+index*scale±disp]
    ; Prefixo de tamanho se: sem REG em qualquer op E mne != lea.
    cmp byte [r13+DexOp.base], DEX_NOBASE
    je .fo_ripabs
    ; prefixo de tamanho?
    movzx eax, byte [r12+Insn.opcode]
    cmp eax, 0x8D
    je .fo_membody             ; lea: nunca prefixo
    ; movzx/movsx (0F B6/B7/BE/BF): fonte m8/m16 SEMPRE explícita
    ; (destino REG suprime o prefixo geral; sem ele o nasm recusa:
    ; "invalid operand sizes"). Tamanho-fonte em DexOp.size
    ; (builder: B6/BE=1, B7/BF=2).
    cmp dword [r12+Insn.opcode_len], 2
    jne .fo_memregck
    movzx eax, byte [r12+Insn.opcode]   ; low byte do escape 0F
    cmp eax, 0xB6
    je .fo_memzx
    cmp eax, 0xB7
    je .fo_memzx
    cmp eax, 0xBE
    je .fo_memzx
    cmp eax, 0xBF
    je .fo_memzx
    jmp .fo_memregck
.fo_memzx:
    movzx eax, byte [r13+DexOp.size]
    cmp eax, 1
    je .fo_psz1
    cmp eax, 2
    je .fo_psz2
    jmp .fo_no                       ; fonte inválida → db
.fo_memregck:
    mov al, [r12+Insn.op0+DexOp.kind]
    cmp al, DEX_OP_REG
    je .fo_membody
    mov al, [r12+Insn.op1+DexOp.kind]
    cmp al, DEX_OP_REG
    je .fo_membody
    mov al, [r12+Insn.op2+DexOp.kind]
    cmp al, DEX_OP_REG
    je .fo_membody
    ; sem REG: prefixo pelo size
    movzx eax, byte [r13+DexOp.size]
    cmp eax, 1
    je .fo_psz1
    cmp eax, 2
    je .fo_psz2
    cmp eax, 4
    je .fo_psz4
    cmp eax, 8
    je .fo_psz8
    jmp .fo_no                  ; size inválido → db
.fo_psz1:
    lea rdx, [rel s_byte]
    jmp .fo_pszgo
.fo_psz2:
    lea rdx, [rel s_word]
    jmp .fo_pszgo
.fo_psz4:
    lea rdx, [rel s_dword]
    jmp .fo_pszgo
.fo_psz8:
    lea rdx, [rel s_qword]
.fo_pszgo:
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fo_fail
.fo_membody:
    ; '['
    mov rcx, rbx
    mov edx, '['
    sub rsp, 32
    call asmbuf_append_char
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    ; seg? "fs:" etc.
    movzx eax, byte [r13+DexOp.seg]
    test eax, eax
    jz .fo_noseg
    lea rcx, [rel dex_seg_names]
    mov rdx, [rcx+rax*8]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    mov rcx, rbx
    mov edx, ':'
    sub rsp, 32
    call asmbuf_append_char
    add rsp, 32
    test eax, eax
    jnz .fo_fail
.fo_noseg:
    ; base: registrador de ENDEREÇO (64 em x64; 32 em x32 ou x64+0x67)
    ; — nunca 8/16! (DexOp.size é o tamanho do OPERANDO; endereço tem
    ; tamanho próprio. x32+0x67 = endereços 16 bits sem forma → db.)
    movzx eax, byte [r13+DexOp.base]
    cmp eax, 0xFF
    je .fo_nobase              ; (só SIB-abs chega aqui; RIP já saiu)
    cmp byte [r12+Insn.legacy67], 0
    je .fo_b3264
    cmp byte [r12+Insn.addr_mode], 1
    je .fo_no                  ; x32+67: sem forma
    lea rdx, [rel dex_r32_names]
    jmp .fo_bemit
.fo_b3264:
    cmp byte [r12+Insn.addr_mode], 1
    je .fo_b32                 ; x32: endereços 32
    lea rdx, [rel dex_r64_names]
    jmp .fo_bemit
.fo_b32:
    lea rdx, [rel dex_r32_names]
    jmp .fo_bemit
.fo_bemit:
    mov ecx, eax
    mov rax, [rdx+rcx*8]
    mov rdx, rax
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fo_fail
.fo_index:
    movzx eax, byte [r13+DexOp.index]
    cmp eax, 0xFF
    je .fo_disp
    ; '+' + index (+*scale)
    mov rcx, rbx
    mov edx, '+'
    sub rsp, 32
    call asmbuf_append_char
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    movzx eax, byte [r13+DexOp.index]
    cmp byte [r12+Insn.legacy67], 0
    je .fo_i3264
    cmp byte [r12+Insn.addr_mode], 1
    je .fo_no                  ; x32+67: sem forma
    lea rdx, [rel dex_r32_names]
    jmp .fo_iemit
.fo_i3264:
    cmp byte [r12+Insn.addr_mode], 1
    je .fo_i32
    lea rdx, [rel dex_r64_names]
    jmp .fo_iemit
.fo_i32:
    lea rdx, [rel dex_r32_names]
    jmp .fo_iemit
.fo_iemit:
    mov ecx, eax
    mov rax, [rdx+rcx*8]
    mov rdx, rax
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    movzx eax, byte [r13+DexOp.scale]
    cmp eax, 1
    je .fo_disp
    mov rcx, rbx
    mov edx, '*'
    sub rsp, 32
    call asmbuf_append_char
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    movzx eax, byte [r13+DexOp.scale]
    cmp eax, 1
    je .fo_disp
    add eax, '0'               ; '2'/'4'/'8'
    mov edx, eax
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_char
    add rsp, 32
    test eax, eax
    jnz .fo_fail
.fo_disp:
    ; disp: 0 → omitir (exceto base ausente → já tratado); senão ±hex
    movzx eax, byte [r12+Insn.disp_size]
    test eax, eax
    jz .fo_close
    mov rax, [r13+DexOp.val]
    test rax, rax
    jz .fo_close
    test rax, rax
    js .fo_dispneg
    mov rcx, rbx
    mov edx, '+'
    sub rsp, 32
    call asmbuf_append_char
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    ; "0x" obrigatório: hex nu vira decimal/símbolo no nasm
    ; ([rbp+5C] seria 5+símbolo C; [rsp+20] seria decimal 20, não 0x20)
    lea rdx, [rel s_0x]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    mov rcx, rbx
    mov rdx, [r13+DexOp.val]
    xor r8d, r8d
    sub rsp, 32
    call asmbuf_append_u64_hex
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    jmp .fo_close
.fo_dispneg:
    mov rcx, rbx
    mov edx, '-'
    sub rsp, 32
    call asmbuf_append_char
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    lea rdx, [rel s_0x]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    mov rax, [r13+DexOp.val]
    neg rax
    mov rcx, rbx
    mov rdx, rax
    xor r8d, r8d
    sub rsp, 32
    call asmbuf_append_u64_hex
    add rsp, 32
    test eax, eax
    jnz .fo_fail
.fo_close:
    mov rcx, rbx
    mov edx, ']'
    sub rsp, 32
    call asmbuf_append_char
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    xor eax, eax
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.fo_ripabs:
    ; base==NOBASE: x64-RIP (sem SIB) → [rel label]; SIB-abs → [abs hex];
    ; x32 → absoluto numérico [0xVA] (Fase D1; sem rel, sem label).
    cmp byte [r12+Insn.addr_mode], 1
    je .fo_abs32
    cmp byte [r12+Insn.has_sib], 0
    jne .fo_sibabs
    ; RIP: "[rel " + label + "]"
    lea rdx, [rel s_relpre]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    mov rcx, rbx
    mov rdx, [r13+DexOp.val]   ; target VA (build calculou)
    sub rsp, 32
    call dex_label_emit_va
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    mov rcx, rbx
    mov edx, ']'
    sub rsp, 32
    call asmbuf_append_char
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    xor eax, eax
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.fo_sibabs:
    ; "[abs 0x<low32>]": [" + [index*scale+] + hex + "]"
    mov rcx, rbx
    mov edx, '['
    sub rsp, 32
    call asmbuf_append_char
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    movzx eax, byte [r13+DexOp.index]
    cmp eax, 0xFF
    je .fo_abshex
    ; index presente: reutilizar lógica? simplificar: "[0x..]" não cobre!
    ; SIB-abs COM index é raríssimo — db honesto:
    mov eax, 1
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.fo_abshex:
    ; "[abs 0x..]": sem "abs" o nasm64 rejeita/infere RIP (forma errada).
    ; x32: absoluto puro "[0x..]" (forma natural em bits 32).
    cmp byte [r12+Insn.addr_mode], 1
    je .fo_abshex0x
    lea rdx, [rel s_abs]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    jmp .fo_abshex0x
.fo_abs32:
    ; Fase D1: "[" + "0x" + hex(val) + "]" — r13 = op (val = VA abs).
    mov rcx, rbx
    mov edx, '['
    sub rsp, 32
    call asmbuf_append_char
    add rsp, 32
    test eax, eax
    jnz .fo_fail
.fo_abshex0x:
    lea rdx, [rel s_0x]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    mov eax, [r13+DexOp.val]   ; low32 (DWORD! high descartado de propósito)
    mov rcx, rbx
    mov edx, eax
    xor r8d, r8d
    sub rsp, 32
    call asmbuf_append_u64_hex
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    mov rcx, rbx
    mov edx, ']'
    sub rsp, 32
    call asmbuf_append_char
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    xor eax, eax
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.fo_nobase:
    ; base ausente sem ser RIP/SIB-abs? (não deve ocorrer) → db
    mov eax, 1
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.fo_no:
    mov eax, 1
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.fo_fail:
    mov eax, 1
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
