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
extern s_nop

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
s_nosplit    db "nosplit ", 0
s_rel2       db "rel ", 0
s_relpre     db "[rel ", 0
s_crlf       db 13, 10, 0
s_colon_nl   db ":", 13, 10, 0
s_dd_rip     db 13, 10, "    dd ", 0
s_rel32_4    db " - $ - 4", 0
s_minus0x    db " - 0x", 0
s_plus0x     db " + 0x", 0
s_crlf_db    db 13, 10, "    db ", 0
s_call_rel   db "    call [rel ", 0
s_jmp_rel    db "    jmp [rel ", 0
s_call_abs   db "    call [", 0
s_jmp_abs    db "    jmp [", 0
s_short      db " short", 0
s_near       db " strict near", 0
s_rb         db "]", 0
s_global     db "global ", 0

section .bss
align 8
g_emit_hex:  resb 8
; F5 (índice simbólico): rebuild preenche com o array R ordenado (RVAs),
; o count e o image_base; o emissor consulta p/ decidir `label_<VA>` num
; operando SIB-abs (base ausente). g_abs_corr aponta um array paralelo com a
; correção VA->file offset do modo `-m bin` (C = VA - off; 0 = sem correção,
; caso do win64, onde o label já vale a VA). 0 = desligado (numérico).
; Definidos AQUI (não em rebuild) p/ os drivers que linkam só emit_nasm.obj
; fecharem.
global g_abs_vas
global g_abs_n
global g_abs_base
global g_abs_corr
align 8
g_abs_vas:   resq 1
g_abs_n:     resq 1
g_abs_base:  resq 1
g_abs_corr:  resq 1

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
;       r9d=kind (0=db, 1=call[rel], 2=jmp[rel], 5=db com disp32 RIP-rel
;       reemissivel). Kinds 3/4 nunca foram implementados (D-2).
;       kind 5: 5º arg na pilha ([rbp+48]) = VA alvo. O chamador reserva
;       48 B e grava o alvo em [rsp+32] antes do call.
;       Emite "db <prefixo>" + "dd label_<alvo> - $ - 4 [- 0x<imm>]" +
;       "db <imm>" — REL32 que o nasm/linker recalculam (D-19 2c).
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
    cmp r14d, 5
    je .as_db_rip              ; kind 5 não usa impname
    cmp r14d, 0
    je .as_db
    cmp r13, 0
    je .as_db
    cmp r14d, 1
    je .do_imp
    cmp r14d, 2
    jne .as_db
.do_imp:
    ; REX.W/B em `call|jmp [mem]` é redundante e o nasm o descarta (7 -> 6
    ; bytes). Emitir db preserva os bytes; o walker então usa o kind 5 e
    ; relocaliza o disp32 (D-19 fatia 2c: era o shift de 1 byte que fazia
    ; o ponteiro do `.CRT` cair em label+(-1)).
    cmp byte [r12+Insn.has_rex], 0
    jne .as_db
    cmp r14d, 1
    je .do_call
    jmp .do_jmp
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
    xor r13d, r13d             ; i = início
    mov r14d, [r12+Insn.length]
    call .db_list
    test eax, eax
    jnz .fail_i
    jmp .tail_mne

;-----------------------------------------------------------------------------
; .as_db_rip — kind 5: "db <prefixo>" + "dd label_<alvo> - $ - 4 [- 0x<imm>]"
; + "db <imm>". O disp32 (mod00/rm101) deixa de ser constante e vira REL32,
; então o linker recalcula quando move a seção alvo (D-19 fatia 2c).
; Requer disp_size==4 e imm depois do disp; qualquer dúvida -> db comum.
;-----------------------------------------------------------------------------
.as_db_rip:
    mov rax, [rbp+48]             ; tva (5º arg; rbp+16 = shadow)
    mov [rbp-72], rax
    test rax, rax
    jz .as_db
    cmp byte [r12+Insn.disp_size], 4
    jne .as_db
    movzx eax, byte [r12+Insn.imm_size]
    mov [rbp-56], rax             ; imm_size
    mov ecx, [r12+Insn.length]
    sub ecx, eax
    sub ecx, 4                    ; disp_off = len - imm - 4
    cmp ecx, 2                    ; disp vem depois de opcode+modrm
    jb .as_db
    mov [rbp-60], ecx
    ; prefixo (bytes antes do disp)
    lea rdx, [rel s_db]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fail_i
    xor r13d, r13d
    mov r14d, [rbp-60]
    call .db_list
    test eax, eax
    jnz .fail_i
    ; disp relocável
    lea rdx, [rel s_dd_rip]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fail_i
    lea rdx, [rel s_label_pre]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fail_i
    mov rcx, rbx
    mov rdx, [rbp-72]
    xor r8d, r8d
    sub rsp, 32
    call asmbuf_append_u64_hex
    add rsp, 32
    test eax, eax
    jnz .fail_i
    lea rdx, [rel s_rel32_4]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fail_i
    mov r14, [rbp-56]             ; imm_size
    test r14, r14
    jz .asr_done
    ; o disp é relativo ao FIM da instrução (depois do imm)
    lea rdx, [rel s_minus0x]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fail_i
    mov rcx, rbx
    mov rdx, r14
    xor r8d, r8d
    sub rsp, 32
    call asmbuf_append_u64_hex
    add rsp, 32
    test eax, eax
    jnz .fail_i
    ; imm (bytes depois do disp)
    lea rdx, [rel s_crlf_db]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fail_i
    mov r13d, [rbp-60]
    add r13d, 4
    mov r14d, [r12+Insn.length]
    call .db_list
    test eax, eax
    jnz .fail_i
.asr_done:
    jmp .tail_mne

;-----------------------------------------------------------------------------
; .db_list — "0xNN, 0xNN, ..." (sem prefixo) de r13d até r14d (exclusivo).
; Scratch: [rbp-48..-45] do frame do emissor. Chamado com rsp 16-alinhado;
; reserva 40 B (sombra+alinhamento) p/ os calls internos.
; Clobber: rax, rcx, rdx, r8. Preserva: rbx, rbp, r12-r14.
;-----------------------------------------------------------------------------
.db_list:
    sub rsp, 40
.dbl_l:
    cmp r13d, r14d
    jae .dbl_e
    movzx eax, byte [r12+r13+Insn.raw]
    mov byte [rbp-48], '0'
    mov byte [rbp-47], 'x'
    mov ecx, eax
    shr ecx, 4
    cmp ecx, 9
    jbe .dbl_hn
    add ecx, 55
    jmp .dbl_hs
.dbl_hn:
    add ecx, 48
.dbl_hs:
    mov [rbp-46], cl
    and eax, 15
    cmp eax, 9
    jbe .dbl_ln
    add eax, 55
    jmp .dbl_ls
.dbl_ln:
    add eax, 48
.dbl_ls:
    mov [rbp-45], al
    lea rdx, [rbp-48]
    mov rcx, rbx
    mov r8, 4
    call asmbuf_append
    test eax, eax
    jnz .dbl_e
    inc r13d
    cmp r13d, r14d
    jae .dbl_e
    lea rdx, [rel s_comma]
    mov rcx, rbx
    call asmbuf_append_str
    test eax, eax
    jnz .dbl_e
    jmp .dbl_l
.dbl_e:
    add rsp, 40
    ret
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
    ; R-8.2: nop 1-byte (0x90) com forma longa (ex: 66 90) não remonta
    ; exato com `nop` puro → db (pause tem string própria; 0F 1F usa
    ; operandos e cai nas regras de forma).
    lea rcx, [rel s_nop]
    cmp rax, rcx
    jne .en_nopok
    cmp byte [r15+Insn.opcode_len], 1
    jne .en_nopok
    cmp dword [r15+Insn.length], 1
    je .en_nopok
    jmp .en_db
.en_nopok:
    ; D-20: p/ byte-fidelidade em PE MS, ALU/mov reg-reg na forma "load"
    ; (reg=dst: 02/03..3A/3B, 8A/8B) o NASM monta na forma "store"
    ; (89/31/...) — mesmos bytes semanticos, encoding diferente. Cai p/ db
    ; (byte-exato; comportamento identico). Só mod==11 e opcode 1-byte.
    cmp dword [r15+Insn.opcode_len], 1
    jne .en_form_ok
    cmp byte [r15+Insn.has_modrm], 0
    je .en_form_ok
    movzx eax, byte [r15+Insn.modrm]
    and eax, 0xC0
    cmp eax, 0xC0
    jne .en_form_ok
    movzx eax, byte [r15+Insn.opcode]
    cmp eax, 0x8A
    je .en_db
    cmp eax, 0x8B
    je .en_db
    cmp eax, 0x3F
    ja .en_form_ok
    mov ecx, eax
    and ecx, 7
    cmp ecx, 2
    je .en_db
    cmp ecx, 3
    je .en_db
.en_form_ok:
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
    ; R-8.2 f2: jmp rel8→short, rel32→near (caminho comum; EB/E9
    ; definem a forma sozinhos — FF/call/loop caem fora).
    cmp byte [r15+Insn.legacy66], 0
    jne .en_nojmpsuf
    cmp dword [r15+Insn.opcode_len], 1
    jne .en_nojmpsuf
    movzx eax, byte [r15+Insn.opcode]
    cmp al, 0xEB
    je .en_jmp_short
    cmp al, 0xE9
    jne .en_nojmpsuf
    lea rdx, [rel s_near]
    jmp .en_jmp_app
.en_jmp_short:
    lea rdx, [rel s_short]
.en_jmp_app:
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .en_fail
.en_nojmpsuf:
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
    ; R-8.2 f2: forma explícita p/ determinismo (nasm pode travar em
    ; near por ponto-fixo local quando a distância beira 127; explícito
    ; reserva exato já na passada 1). Opcode define a forma (70-7F rel8,
    ; 0F80-8F rel32); cmov/setcc/jcxz caem fora pelos ranges.
    cmp byte [r15+Insn.legacy66], 0
    jne .en_ccsuf_go              ; 66: rel16, sem forma forçada
    cmp dword [r15+Insn.opcode_len], 1
    je .en_cc_short
    cmp dword [r15+Insn.opcode_len], 2
    jne .en_ccsuf_go
    movzx eax, byte [r15+Insn.opcode]
    cmp al, 0x80
    jb .en_ccsuf_go
    cmp al, 0x8F
    ja .en_ccsuf_go
    lea rdx, [rel s_near]
    jmp .en_ccsuf_app
.en_cc_short:
    movzx eax, byte [r15+Insn.opcode]
    cmp al, 0x70
    jb .en_ccsuf_go
    cmp al, 0x7F
    ja .en_ccsuf_go
    lea rdx, [rel s_short]
.en_ccsuf_app:
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .en_fail
.en_ccsuf_go:
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
    ; sem REX, idx 4-7: sempre hi (ah/ch/dh/bh). spl/bpl/sil/dil
    ; EXIGEM REX (SDM); sem ele o nasm forçaria REX e mudaria tudo.
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
    cmp eax, 0x80
    jb .fo_im8pos
    ; negativo (ex 0xFF = -1): "-0x<mag>" (0xFF nu viraria imm32 no nasm)
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
    and eax, 0xFF
    neg eax
    and eax, 0xFF               ; mag em 8 bits
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
.fo_im8pos:
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
    ;         [0xVA] (x32 absoluto) / [seg:base+index*scale±disp]
    ; Prefixo de tamanho (vale p/ TODAS as formas; gcc-native): sem REG
    ; em qualquer op E mne != lea. Decidido aqui; corpos só emitem colchetes.
    ; prefixo de tamanho?
    movzx eax, byte [r12+Insn.opcode]
    cmp eax, 0x8D
    je .fo_memshape             ; lea: nunca prefixo
    ; shifts/rotates por CL (D2/D3): op1=CL é só a contagem e NÃO
    ; determina o tamanho. Quem carrega o tamanho é op0 (r/m): sem o
    ; prefixo o nasm assume byte e troca Ev→Eb (D3→D2). Força explicit.
    cmp dword [r12+Insn.opcode_len], 1
    jne .fo_mem_d23ck
    movzx eax, byte [r12+Insn.opcode]
    cmp eax, 0xD2
    je .fo_memsize
    cmp eax, 0xD3
    je .fo_memsize
.fo_mem_d23ck:
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
    je .fo_memshape
    mov al, [r12+Insn.op1+DexOp.kind]
    cmp al, DEX_OP_REG
    je .fo_memshape
    mov al, [r12+Insn.op2+DexOp.kind]
    cmp al, DEX_OP_REG
    je .fo_memshape
    ; sem REG: prefixo pelo size
.fo_memsize:
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
.fo_memshape:
    ;Prefixo decidido; corpo pela forma (RIP/SIB-abs/abs32/base).
    cmp byte [r13+DexOp.base], DEX_NOBASE
    je .fo_ripabs
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
    ; '+' + "<index>[*<scale>]"
    mov rcx, rbx
    mov edx, '+'
    sub rsp, 32
    call asmbuf_append_char
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    sub rsp, 32
    call .fo_idxemit
    add rsp, 32
    test eax, eax
    jnz .fo_fail
.fo_disp:
    ; disp ausente (size 0) → omitir; disp zero com bytes (size>0) → db
    ; (nasm minimiza [reg+0x0] p/ [reg], encurtando; disp32 zero idem).
    movzx eax, byte [r12+Insn.disp_size]
    test eax, eax
    jz .fo_close
    mov rax, [r13+DexOp.val]
    test rax, rax
    jz .fo_no
    js .fo_dispneg
.fo_dispnz:
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
    ; base==NOBASE: SIB-abs (com ou sem índice) → .fo_sibabs; x64 sem SIB →
    ; RIP [rel label]; x32 sem SIB → absoluto numérico [0xVA] (Fase D1).
    ; (A ordem importa: SIB-abs vale nos dois modos de endereço.)
    cmp byte [r12+Insn.has_sib], 0
    jne .fo_sibabs
    cmp byte [r12+Insn.addr_mode], 1
    je .fo_abs32
    ; RIP: "[" + seg? + "rel " + label + "]"
    mov rcx, rbx
    mov edx, '['
    sub rsp, 32
    call asmbuf_append_char
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    sub rsp, 32
    call .fo_segpre
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    lea rdx, [rel s_rel2]
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
    ; SIB-abs (base ausente): "[<seg>?[abs ]<disp32> + <index>[*<scale>]]" —
    ; `abs` (x64) obrigatório no início quando há disp != 0; com disp==0 sai
    ; só "[<index>[*<scale>]]" (o encoding já força disp32=0).
    mov rcx, rbx
    mov edx, '['
    sub rsp, 32
    call asmbuf_append_char
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    movzx eax, byte [r13+DexOp.seg]
    test eax, eax
    jz .fo_sib_noseg
    sub rsp, 32
    call .fo_segpre
    add rsp, 32
    test eax, eax
    jnz .fo_fail
.fo_sib_noseg:
    movzx eax, byte [r13+DexOp.index]
    cmp eax, 0xFF
    je .fo_abshex
    ; index presente: `nosplit` (senão o nasm re-encoda [rax*2] como
    ; [rax+rax], mais curto => BYTES DIFERENTES). Disp primeiro (em x64
    ; `abs` é obrigatório no INÍCIO da expressão), depois "+<index>[*<scale>]";
    ; disp32==0 omite o disp (a forma SIB-abs já o força como 0).
    lea rdx, [rel s_nosplit]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    mov eax, [r13+DexOp.val]     ; disp32 bruto (low32)
    test eax, eax
    jz .fo_sib_idx               ; disp 0: omite (a forma SIB-abs força 0)
    ; VA rotulável? O R é chaveado por RVA (g_abs_vas/g_abs_n/g_abs_base,
    ; preenchidos por rebuild). x32: VA = low32 zero-estendida. x64: o disp32
    ; é SINAL-ESTENDIDO pela CPU — só endereça a imagem quando positivo
    ; (ImageBase < 2 GiB); acima disso (ex.: 0x140000000) a forma aponta para
    ; fora do módulo e o operando segue numérico (`abs 0x..`), sem símbolo.
    cmp qword [rel g_abs_n], 0
    je .fo_sib_num
    cmp byte [r12+Insn.addr_mode], 1
    je .fo_ab_va32
    movsxd rax, dword [r13+DexOp.val]
    jmp .fo_ab_vahave
.fo_ab_va32:
    mov eax, [r13+DexOp.val]     ; VA absoluta (low32)
.fo_ab_vahave:
    mov rdx, [rel g_abs_base]
    cmp rax, rdx
    jb .fo_sib_num
    sub rax, rdx                 ; rva
    mov r8, [rel g_abs_vas]
    mov r9, [rel g_abs_n]
    xor r10d, r10d               ; lo
    mov r11, r9                  ; hi
.fo_ab_bs:
    cmp r10, r11
    jae .fo_sib_num
    lea rcx, [r10+r11]
    shr rcx, 1                   ; mid
    mov rdx, [r8+rcx*8]          ; key (rva)
    cmp rax, rdx
    je .fo_ab_hit
    jb .fo_ab_bhi
    lea r10, [rcx+1]             ; lo = mid+1
    jmp .fo_ab_bs
.fo_ab_bhi:
    mov r11, rcx                 ; hi = mid
    jmp .fo_ab_bs
.fo_ab_hit:
    ; correção VA->file offset do `-m bin` (g_abs_corr[mid]; 0/ausente =
    ; win64, onde `label_<VA>` já vale a VA). Cabe em r14 (volátil de fato
    ; aqui: .en_fmt_op empilha r14 mas não usa).
    mov r14, [rel g_abs_corr]
    test r14, r14
    jz .fo_ab_hit_lab
    mov r14, [r14+rcx*8]
.fo_ab_hit_lab:
    ; `abs` explícito em x64: o índice já impede RIP, mas documenta a forma.
    cmp byte [r12+Insn.addr_mode], 1
    je .fo_ab_hit_va
    lea rdx, [rel s_abs]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    movsxd rdx, dword [r13+DexOp.val]  ; VA verdadeira (disp sinal-estendido)
    jmp .fo_ab_hit_go
.fo_ab_hit_va:
    mov edx, [r13+DexOp.val]     ; VA (não o rva)
.fo_ab_hit_go:
    mov rcx, rbx
    sub rsp, 32
    call dex_label_emit_va
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    test r14, r14
    jz .fo_ab_plus
    ; prefixo da correção: " + 0x" (C>0) ou " - 0x" (C<0)
    mov rax, r14
    test rax, rax
    js .fo_ab_cneg
    lea rdx, [rel s_plus0x]
    jmp .fo_ab_cpre
.fo_ab_cneg:
    lea rdx, [rel s_minus0x]
.fo_ab_cpre:
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    mov rax, r14
    test rax, rax
    jns .fo_ab_cval
    neg rax
.fo_ab_cval:
    mov rcx, rbx
    mov rdx, rax
    xor r8d, r8d
    sub rsp, 32
    call asmbuf_append_u64_hex
    add rsp, 32
    test eax, eax
    jnz .fo_fail
.fo_ab_plus:
    mov rcx, rbx
    mov edx, '+'
    sub rsp, 32
    call asmbuf_append_char
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    jmp .fo_sib_idx
.fo_sib_num:
    cmp byte [r12+Insn.addr_mode], 1
    je .fo_sib_d0x
    lea rdx, [rel s_abs]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fo_fail
.fo_sib_d0x:
    lea rdx, [rel s_0x]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    mov eax, [r13+DexOp.val]
    mov rcx, rbx
    mov edx, eax
    xor r8d, r8d
    sub rsp, 32
    call asmbuf_append_u64_hex
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    mov rcx, rbx
    mov edx, '+'
    sub rsp, 32
    call asmbuf_append_char
    add rsp, 32
    test eax, eax
    jnz .fo_fail
.fo_sib_idx:
    sub rsp, 32
    call .fo_idxemit
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
    ; Fase D1: "[" + seg? + "0x" + hex(val) + "]" — r13 = op (val = VA abs).
    mov rcx, rbx
    mov edx, '['
    sub rsp, 32
    call asmbuf_append_char
    add rsp, 32
    test eax, eax
    jnz .fo_fail
    sub rsp, 32
    call .fo_segpre
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
; .fo_idxemit — emite "<index>[*<scale>]" (DexOp.index != NOINDEX). rax=0/1.
; Sub-rotina de dex_emit_native (entra com rsp%16==8); usa rbx (buf), r12
; (Insn) e r13 (DexOp). Não faz teardown de função: rax=1 => caller usa
; .fo_fail (db). x32+67 (addr16) não tem forma => 1.
.fo_idxemit:
    sub rsp, 8                  ; realinha (entra com rsp%16==8)
    movzx eax, byte [r13+DexOp.index]
    cmp byte [r12+Insn.legacy67], 0
    je .fo_ie_3264
    cmp byte [r12+Insn.addr_mode], 1
    je .fo_ie_fail
    lea rdx, [rel dex_r32_names]
    jmp .fo_ie_emit
.fo_ie_3264:
    cmp byte [r12+Insn.addr_mode], 1
    je .fo_ie_32
    lea rdx, [rel dex_r64_names]
    jmp .fo_ie_emit
.fo_ie_32:
    lea rdx, [rel dex_r32_names]
.fo_ie_emit:
    mov ecx, eax
    mov rax, [rdx+rcx*8]
    mov rdx, rax
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fo_ie_fail
    movzx eax, byte [r13+DexOp.scale]
    cmp eax, 1
    je .fo_ie_ok
    mov rcx, rbx
    mov edx, '*'
    sub rsp, 32
    call asmbuf_append_char
    add rsp, 32
    test eax, eax
    jnz .fo_ie_fail
    movzx eax, byte [r13+DexOp.scale]
    add eax, '0'               ; '2'/'4'/'8'
    mov edx, eax
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_char
    add rsp, 32
    test eax, eax
    jnz .fo_ie_fail
.fo_ie_ok:
    xor eax, eax
    add rsp, 8
    ret
.fo_ie_fail:
    mov eax, 1
    add rsp, 8
    ret

; .fo_segpre — appende "<seg>:" (es/cs/ss/ds/fs/gs) se DexOp.seg != 0. rax=0/1.
; Sub-rotina de dex_emit_native; realinha a pilha (entra com rsp%16==8).
.fo_segpre:
    movzx eax, byte [r13+DexOp.seg]
    test eax, eax
    jz .fo_seg_ok
    sub rsp, 8
    lea rcx, [rel dex_seg_names]
    mov rdx, [rcx+rax*8]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .fo_seg_bad
    mov rcx, rbx
    mov edx, ':'
    sub rsp, 32
    call asmbuf_append_char
    add rsp, 32
    test eax, eax
    jnz .fo_seg_bad
    add rsp, 8
.fo_seg_ok:
    xor eax, eax
    ret
.fo_seg_bad:
    add rsp, 8
    mov eax, 1
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
