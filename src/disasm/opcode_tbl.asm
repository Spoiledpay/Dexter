;=============================================================================
; Dexter/src/disasm/opcode_tbl.asm
; Tabelas de opcode: flags (modrm? imm?) + mnemônicos p/ 1/2/3 bytes.
; Cobertura real: opcodes emitidos por MSVC/LLVM + grupos ModRM + SSE
; escalar comum. Desconhecido => flag 0 (fallback db de 1 byte).
; Limitações documentadas (ROADMAP Fase 5): VEX/EVEX (C4/C5/62), x87,
; 3DNow!, moffs16.
;
; Flag (1 byte): bit0 MODRM | bit1 I8 | bit2 IV(16/32) | bit3 I32 | bit4 I64
;                bit5 R8 | bit6 R32 | bit7 GRP
; Requisitos atendidos: R-2.x
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%define F_NONE  0x00
%define F_MODRM 0x01
%define F_I8    0x02
%define F_IV    0x04
%define F_I32   0x08
%define F_I64   0x10
%define F_R8    0x20
%define F_R32   0x40
%define F_GRP   0x80

global dex_tbl1_flag
global dex_tbl1_mne
global dex_tbl2_flag
global dex_tbl2_mne
global dex_tbl38_flag
global dex_tbl3a_flag
global dex_r64_names
global dex_r32_names
global dex_r16_names
global dex_r8_names
global dex_r8hi_names
global dex_seg_names
global dex_cc_suffix
global dex_grp1_mne
global dex_grp2_mne
global dex_grp3_mne
global dex_grp45_mne
global s_add
global s_or
global s_adc
global s_sbb
global s_and
global s_sub
global s_xor
global s_cmp
global s_push
global s_pop
global s_mov
global s_lea
global s_test
global s_xchg
global s_nop
global s_call
global s_jmp
global s_ret
global s_int3
global s_int
global s_hlt
global s_leave
global s_enter
global s_jcc
global s_loop
global s_imul
global s_movzx
global s_movsx
global s_movsxd
global s_cdq
global s_cqo
global s_cbw
global s_cmov
global s_setcc
global s_bt
global s_bts
global s_btr
global s_btc
global s_bsf
global s_bsr
global s_bswap
global s_emms
global s_cpuid
global s_sysc
global s_rdtsc
global s_shld
global s_shrd
global s_cmpx
global s_xadd
global s_sse
global s_rol
global s_ror
global s_rcl
global s_rcr
global s_shl
global s_shr
global s_sar
global s_not
global s_neg
global s_mul
global s_div
global s_idiv
global s_inc
global s_dec
global s_loopne
global s_loope
global s_jrcxz
global s_jecxz
global s_sysenter
global s_sysexit
global s_sysret
global s_wrmsr
global s_rdmsr
global s_rdpmc
global s_wait
global s_salc
global s_xlatb
global s_aam
global s_aad
global s_pushfq
global s_popfq
global s_sahf
global s_lahf
global s_cwde
global s_cdqe
global s_cwd
global s_clc
global s_stc
global s_cli
global s_sti
global s_cld
global s_std
global s_cmc
global s_int1
global s_ud2
global s_pause
global s_retf
global s_movsb
global s_movsd
global s_movsq
global s_cmpsb
global s_cmpsd
global s_cmpsq
global s_stosb
global s_stosd
global s_stosq
global s_lodsb
global s_lodsd
global s_lodsq
global s_scasb
global s_scasd
global s_scasq
global s_jpre
global s_cmovpre
global s_setpre
global s_lock
global s_rep
global s_repne
global s_byte
global s_word
global s_dword
global s_qword

section .rodata

s_add:   db "add", 0
s_or:    db "or", 0
s_adc:   db "adc", 0
s_sbb:   db "sbb", 0
s_and:   db "and", 0
s_sub:   db "sub", 0
s_xor:   db "xor", 0
s_cmp:   db "cmp", 0
s_push:  db "push", 0
s_pop:   db "pop", 0
s_mov:   db "mov", 0
s_lea:   db "lea", 0
s_test:  db "test", 0
s_xchg:  db "xchg", 0
s_nop:   db "nop", 0
s_call:  db "call", 0
s_jmp:   db "jmp", 0
s_ret:   db "ret", 0
s_int3:  db "int3", 0
s_int:   db "int", 0
s_hlt:   db "hlt", 0
s_leave: db "leave", 0
s_enter: db "enter", 0
s_jcc:   db "jcc", 0
s_loop:  db "loop", 0
s_imul:  db "imul", 0
s_movzx: db "movzx", 0
s_movsx: db "movsx", 0
s_movsxd: db "movsxd", 0
s_cdq:   db "cdq", 0
s_cqo:   db "cqo", 0
s_cbw:   db "cbw", 0
s_cmov:  db "cmov", 0
s_setcc: db "setcc", 0
s_bt:    db "bt", 0
s_bts:   db "bts", 0
s_btr:   db "btr", 0
s_btc:   db "btc", 0
s_bsf:   db "bsf", 0
s_bsr:   db "bsr", 0
s_bswap: db "bswap", 0
s_emms:  db "emms", 0
s_cpuid: db "cpuid", 0
s_sysc:  db "syscall", 0
s_rdtsc: db "rdtsc", 0
s_shld:  db "shld", 0
s_shrd:  db "shrd", 0
s_cmpx:  db "cmpxchg", 0
s_xadd:  db "xadd", 0
s_sse:   db "sse", 0
s_rol:   db "rol", 0
s_ror:   db "ror", 0
s_rcl:   db "rcl", 0
s_rcr:   db "rcr", 0
s_shl:   db "shl", 0
s_shr:   db "shr", 0
s_sar:   db "sar", 0
s_not:   db "not", 0
s_neg:   db "neg", 0
s_mul:   db "mul", 0
s_div:   db "div", 0
s_idiv:  db "idiv", 0
s_inc:   db "inc", 0
s_dec:   db "dec", 0
s_loopne: db "loopne", 0
s_loope: db "loope", 0
s_jrcxz: db "jrcxz", 0
s_jecxz: db "jecxz", 0
s_sysenter: db "sysenter", 0
s_sysexit: db "sysexit", 0
s_sysret: db "sysret", 0
s_wrmsr: db "wrmsr", 0
s_rdmsr: db "rdmsr", 0
s_rdpmc: db "rdpmc", 0
s_wait:  db "wait", 0
s_salc:  db "salc", 0
s_xlatb: db "xlatb", 0
s_aam:   db "aam", 0
s_aad:   db "aad", 0
s_pushfq: db "pushfq", 0
s_popfq: db "popfq", 0
s_sahf:  db "sahf", 0
s_lahf:  db "lahf", 0
s_cwde:  db "cwde", 0
s_cdqe:  db "cdqe", 0
s_cwd:   db "cwd", 0
s_clc:   db "clc", 0
s_stc:   db "stc", 0
s_cli:   db "cli", 0
s_sti:   db "sti", 0
s_cld:   db "cld", 0
s_std:   db "std", 0
s_cmc:   db "cmc", 0
s_int1:  db "int1", 0
s_ud2:   db "ud2", 0
s_pause: db "pause", 0
s_retf:  db "retf", 0
s_movsb: db "movsb", 0
s_movsd: db "movsd", 0
s_movsq: db "movsq", 0
s_cmpsb: db "cmpsb", 0
s_cmpsd: db "cmpsd", 0
s_cmpsq: db "cmpsq", 0
s_stosb: db "stosb", 0
s_stosd: db "stosd", 0
s_stosq: db "stosq", 0
s_lodsb: db "lodsb", 0
s_lodsd: db "lodsd", 0
s_lodsq: db "lodsq", 0
s_scasb: db "scasb", 0
s_scasd: db "scasd", 0
s_scasq: db "scasq", 0
s_rep:   db "rep ", 0
s_repne: db "repne ", 0
s_lock:  db "lock ", 0
s_byte:  db "byte ", 0
s_word:  db "word ", 0
s_dword: db "dword ", 0
s_qword: db "qword ", 0

; ---- tabela 1 byte: flags (256 entradas, 8 por linha) ----
dex_tbl1_flag:
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM, F_I8, F_I32, 0, 0        ; 00
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM, F_I8, F_I32, 0, 0        ; 08
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM, F_I8, F_I32, 0, 0        ; 10
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM, F_I8, F_I32, 0, 0        ; 18
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM, F_I8, F_I32, 0, 0        ; 20
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM, F_I8, F_I32, 0, 0        ; 28
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM, F_I8, F_I32, 0, 0        ; 30
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM, F_I8, F_I32, 0, 0        ; 38
    db 0, 0, 0, 0, 0, 0, 0, 0                                      ; 40 REX
    db 0, 0, 0, 0, 0, 0, 0, 0                                      ; 48 REX
    db 0, 0, 0, 0, 0, 0, 0, 0                                      ; 50 push r64
    db 0, 0, 0, 0, 0, 0, 0, 0                                      ; 58 pop r64
    db 0, 0, 0, F_MODRM, 0, 0, 0, 0                                ; 60 (63 movsxd)
    db F_IV, F_MODRM|F_IV, F_I8, F_MODRM|F_I8, 0, 0, 0, 0          ; 68
    db F_R8, F_R8, F_R8, F_R8, F_R8, F_R8, F_R8, F_R8              ; 70 jcc
    db F_R8, F_R8, F_R8, F_R8, F_R8, F_R8, F_R8, F_R8              ; 78 jcc
    db F_MODRM|F_GRP, F_MODRM|F_GRP, F_MODRM|F_GRP, F_MODRM|F_GRP  ; 80 grupos
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                          ; 84 test/xchg
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                          ; 88 mov
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                          ; 8C (8D lea)
    db 0, 0, 0, 0, 0, 0, 0, 0                                      ; 90 (90 nop)
    db 0, 0, 0, 0, 0, 0, 0, 0                                      ; 98 (98 cbw,99 cdq)
    db 0, 0, 0, 0, 0, 0, 0, 0                                      ; A0 moffs (caso especial)
    db F_I8, F_IV, 0, 0, 0, 0, 0, 0                                ; A8 (A8/A9 test)
    db F_I8, F_I8, F_I8, F_I8, F_I8, F_I8, F_I8, F_I8              ; B0 mov r8
    db F_I64, F_I64, F_I64, F_I64, F_I64, F_I64, F_I64, F_I64      ; B8 mov r,imm
    db F_MODRM|F_GRP, F_MODRM|F_GRP, 0, 0                          ; C0 (C2/C3 ret: especial)
    db 0, 0, F_MODRM|F_I8, F_MODRM|F_IV                            ; C4 (C6/C7 mov rm,imm)
    db 0, 0, 0, 0                                                  ; C8 (C8 enter/C9 leave: especial)
    db 0, F_I8, 0, 0                                               ; CC (CD int imm8)
    db F_MODRM|F_GRP, F_MODRM|F_GRP, F_MODRM|F_GRP, F_MODRM|F_GRP  ; D0 shifts
    db F_I8, F_I8, 0, 0                                            ; D4 (D4/D5 aam/aad)
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                          ; D8 x87 (só LDE;
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                          ; DC  mne segue 0=db)
    db F_R8, F_R8, F_R8, F_R8                                      ; E0 loop/jrcxz
    db F_I8, F_I8, F_I8, F_I8                                      ; E4 in/out imm8
    db F_R32, F_R32, 0, F_R8                                       ; E8 (E8 call,E9 jmp,EB jmp)
    db 0, 0, 0, 0                                                  ; EC in/out dx
    db 0, 0, 0, 0                                                  ; F0 prefixos/F1 int1
    db 0, 0, F_MODRM|F_GRP, F_MODRM|F_GRP                          ; F4 (F6/F7 grupo3)
    db 0, 0, 0, 0                                                  ; F8 flags
    db 0, 0, F_MODRM|F_GRP, F_MODRM|F_GRP                          ; FC (FE/FF grupos)

; ---- tabela 1 byte: mnemônicos (256 qwords) ----
dex_tbl1_mne:
    dq s_add, s_add, s_add, s_add, s_add, s_add, 0, 0
    dq s_or, s_or, s_or, s_or, s_or, s_or, 0, 0
    dq s_adc, s_adc, s_adc, s_adc, s_adc, s_adc, 0, 0
    dq s_sbb, s_sbb, s_sbb, s_sbb, s_sbb, s_sbb, 0, 0
    dq s_and, s_and, s_and, s_and, s_and, s_and, 0, 0
    dq s_sub, s_sub, s_sub, s_sub, s_sub, s_sub, 0, 0
    dq s_xor, s_xor, s_xor, s_xor, s_xor, s_xor, 0, 0
    dq s_cmp, s_cmp, s_cmp, s_cmp, s_cmp, s_cmp, 0, 0
    dq s_inc,s_inc,s_inc,s_inc,s_inc,s_inc,s_inc,s_inc    ; 40 (x32; REX em x64)
    dq s_dec,s_dec,s_dec,s_dec,s_dec,s_dec,s_dec,s_dec    ; 48 (x32; REX em x64)
    dq s_push,s_push,s_push,s_push,s_push,s_push,s_push,s_push
    dq s_pop,s_pop,s_pop,s_pop,s_pop,s_pop,s_pop,s_pop
    dq 0, 0, 0, s_movsxd, 0, 0, 0, 0
    dq s_push, s_imul, s_push, s_imul, 0, 0, 0, 0
    dq s_jcc,s_jcc,s_jcc,s_jcc,s_jcc,s_jcc,s_jcc,s_jcc
    dq s_jcc,s_jcc,s_jcc,s_jcc,s_jcc,s_jcc,s_jcc,s_jcc
    dq 0, 0, 0, 0
    dq s_test, s_test, s_xchg, s_xchg
    dq s_mov, s_mov, s_mov, s_mov
    dq s_mov, s_lea, s_mov, s_pop
    dq s_nop, 0, 0, 0, 0, 0, 0, 0
    dq s_cbw, s_cdq, 0, 0, 0, 0, 0, 0
    dq s_mov,s_mov,s_mov,s_mov,s_mov,s_mov,s_mov,s_mov
    dq s_test, s_test, 0, 0, 0, 0, 0, 0
    dq s_mov,s_mov,s_mov,s_mov,s_mov,s_mov,s_mov,s_mov
    dq s_mov,s_mov,s_mov,s_mov,s_mov,s_mov,s_mov,s_mov
    dq 0, 0, s_ret, s_ret
    dq 0, 0, s_mov, s_mov
    dq s_enter, s_leave, 0, s_ret
    dq s_int3, s_int, 0, 0
    dq 0, 0, 0, 0
    dq 0, 0, 0, 0
    dq 0,0,0,0,0,0,0,0
    dq s_loop, s_loop, s_loop, s_jcc
    dq 0, 0, 0, 0
    dq s_call, s_jmp, 0, s_jmp
    dq 0, 0, 0, 0
    dq 0, 0, 0, 0
    dq s_hlt, 0, 0, 0
    dq 0, 0, 0, 0
    dq 0, 0, 0, 0

; ---- tabela 2 bytes (0F xx): flags ----
dex_tbl2_flag:
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM, 0, 0, 0, 0        ; 00
    db 0, 0, 0, 0, 0, F_MODRM, 0, F_MODRM                    ; 08
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                    ; 10 SSE
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                    ; 14
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                    ; 18
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                    ; 1C
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                    ; 20 mov cr/dr
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                    ; 24
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                    ; 28 SSE
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                    ; 2C
    db 0, 0, 0, 0, 0, 0, 0, 0                                ; 30 sys
    db 0, 0, 0, 0, 0, 0, 0, 0                                ; 38? NÃO: 38/3A são escapes
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM, F_MODRM, F_MODRM, F_MODRM, F_MODRM        ; 40 cmov
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                    ; 44
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                    ; 48
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                    ; 4C
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                    ; 50 SSE
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                    ; 54
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                    ; 58
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                    ; 5C
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                    ; 60 mmx
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                    ; 64
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                    ; 68
    db F_MODRM|F_I8, F_MODRM|F_I8, F_MODRM|F_I8, F_MODRM|F_I8 ; 70 (pshufw/grupos)
    db F_MODRM, F_MODRM, F_MODRM, 0                          ; 74 (77 emms)
    db F_MODRM, F_MODRM, 0, 0                                ; 78 (vmread/vmwrite)
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                    ; 7C
    db F_R32, F_R32, F_R32, F_R32                            ; 80 jcc rel32
    db F_R32, F_R32, F_R32, F_R32                            ; 84
    db F_R32, F_R32, F_R32, F_R32                            ; 88
    db F_R32, F_R32, F_R32, F_R32                            ; 8C
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                    ; 90 setcc
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                    ; 94
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                    ; 98
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                    ; 9C
    db 0, 0, 0, F_MODRM                                      ; A0 (A3 bt)
    db F_MODRM|F_I8, F_MODRM, F_MODRM, F_MODRM               ; A4 (A4 shld)
    db 0, 0, 0, F_MODRM                                      ; A8 (AB bts)
    db F_MODRM|F_I8, F_MODRM, 0, F_MODRM                     ; AC (AC shrd; AF imul)
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                    ; B0
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                    ; B4
    db F_MODRM, F_MODRM, F_MODRM|F_GRP, F_MODRM              ; B8 (BA grupo 8)
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                    ; BC (bsf/bsr/movsxd)
    db F_MODRM, F_MODRM, F_MODRM|F_I8, F_MODRM               ; C0 (C2 cmpps)
    db F_MODRM|F_I8, F_MODRM|F_I8, F_MODRM|F_I8, F_MODRM     ; C4
    db 0, 0, 0, 0                                            ; C8 bswap: sem modrm!
    db 0, 0, 0, 0                                            ; CC
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                    ; D0
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                    ; D4
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                    ; D8
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                    ; DC
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                    ; E0
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                    ; E4
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                    ; E8
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                    ; EC
    db F_MODRM, F_MODRM, 0, F_MODRM                          ; F0 (F1 int1)
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                    ; F4
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                    ; F8
    db F_MODRM, F_MODRM, F_MODRM, F_MODRM                    ; FC

; ---- tabela 2 bytes: mnemônicos ----
dex_tbl2_mne:
    times 16 dq 0
    times 16 dq 0
    times 16 dq s_sse
    times 16 dq s_sse
    times 8 dq 0
    dq 0,0,0,0, s_cmov,s_cmov,s_cmov,s_cmov
    dq s_cmov,s_cmov,s_cmov,s_cmov,s_cmov,s_cmov,s_cmov,s_cmov
    times 32 dq s_sse
    times 8 dq s_sse
    dq s_jcc,s_jcc,s_jcc,s_jcc, s_jcc,s_jcc,s_jcc,s_jcc
    dq s_jcc,s_jcc,s_jcc,s_jcc, s_jcc,s_jcc,s_jcc,s_jcc
    times 16 dq s_setcc
    dq 0,0,s_cpuid,s_bt, s_shld,s_shld,0,0
    dq 0,0,0,s_bt, s_shrd,s_shrd,0,s_imul
    dq s_cmpx,s_cmpx,0,s_bt, 0,0,s_movzx,s_movzx
    dq 0,0,0,s_bt, s_bsf,s_bsr,s_movsx,s_movsx
    dq s_xadd,s_xadd,0,0, 0,0,0,0
    dq s_bswap,s_bswap,s_bswap,s_bswap, s_bswap,s_bswap,s_bswap,s_bswap
    times 48 dq s_sse                  ; D0-FF

; ---- tabelas 3 bytes ----
dex_tbl38_flag:
    times 256 db F_MODRM
dex_tbl3a_flag:
    times 256 db F_MODRM|F_I8

;=============================================================================
; Tabelas do emissor nativo (R-4.5)
;=============================================================================
; Nomes de regs (strings + vetores de ponteiros, idx 0-15)
r_rax: db "rax",0
r_rcx: db "rcx",0
r_rdx: db "rdx",0
r_rbx: db "rbx",0
r_rsp: db "rsp",0
r_rbp: db "rbp",0
r_rsi: db "rsi",0
r_rdi: db "rdi",0
r_r8:  db "r8",0
r_r9:  db "r9",0
r_r10: db "r10",0
r_r11: db "r11",0
r_r12: db "r12",0
r_r13: db "r13",0
r_r14: db "r14",0
r_r15: db "r15",0
dex_r64_names:
    dq r_rax,r_rcx,r_rdx,r_rbx,r_rsp,r_rbp,r_rsi,r_rdi
    dq r_r8,r_r9,r_r10,r_r11,r_r12,r_r13,r_r14,r_r15

e_eax: db "eax",0
e_ecx: db "ecx",0
e_edx: db "edx",0
e_ebx: db "ebx",0
e_esp: db "esp",0
e_ebp: db "ebp",0
e_esi: db "esi",0
e_edi: db "edi",0
e_r8d: db "r8d",0
e_r9d: db "r9d",0
e_r10d: db "r10d",0
e_r11d: db "r11d",0
e_r12d: db "r12d",0
e_r13d: db "r13d",0
e_r14d: db "r14d",0
e_r15d: db "r15d",0
dex_r32_names:
    dq e_eax,e_ecx,e_edx,e_ebx,e_esp,e_ebp,e_esi,e_edi
    dq e_r8d,e_r9d,e_r10d,e_r11d,e_r12d,e_r13d,e_r14d,e_r15d

w_ax: db "ax",0
w_cx: db "cx",0
w_dx: db "dx",0
w_bx: db "bx",0
w_sp: db "sp",0
w_bp: db "bp",0
w_si: db "si",0
w_di: db "di",0
w_r8w: db "r8w",0
w_r9w: db "r9w",0
w_r10w: db "r10w",0
w_r11w: db "r11w",0
w_r12w: db "r12w",0
w_r13w: db "r13w",0
w_r14w: db "r14w",0
w_r15w: db "r15w",0
dex_r16_names:
    dq w_ax,w_cx,w_dx,w_bx,w_sp,w_bp,w_si,w_di
    dq w_r8w,w_r9w,w_r10w,w_r11w,w_r12w,w_r13w,w_r14w,w_r15w

b_al: db "al",0
b_cl: db "cl",0
b_dl: db "dl",0
b_bl: db "bl",0
b_spl: db "spl",0
b_bpl: db "bpl",0
b_sil: db "sil",0
b_dil: db "dil",0
b_r8b: db "r8b",0
b_r9b: db "r9b",0
b_r10b: db "r10b",0
b_r11b: db "r11b",0
b_r12b: db "r12b",0
b_r13b: db "r13b",0
b_r14b: db "r14b",0
b_r15b: db "r15b",0
dex_r8_names:
    dq b_al,b_cl,b_dl,b_bl,b_spl,b_bpl,b_sil,b_dil
    dq b_r8b,b_r9b,b_r10b,b_r11b,b_r12b,b_r13b,b_r14b,b_r15b

b_ah: db "ah",0
b_ch: db "ch",0
b_dh: db "dh",0
b_bh: db "bh",0
dex_r8hi_names:
    dq b_ah,b_ch,b_dh,b_bh

sg_es: db "es",0
sg_cs: db "cs",0
sg_ss: db "ss",0
sg_ds: db "ds",0
sg_fs: db "fs",0
sg_gs: db "gs",0
dex_seg_names:
    dq 0,sg_es,sg_cs,sg_ss,sg_ds,sg_fs,sg_gs

; Sufixos de condição (idx = low nibble do opcode jcc/cmain/setcc)
cc_o:  db "o",0
cc_no: db "no",0
cc_b:  db "b",0
cc_nb: db "nb",0
cc_z:  db "z",0
cc_nz: db "nz",0
cc_be: db "be",0
cc_a:  db "a",0
cc_s:  db "s",0
cc_ns: db "ns",0
cc_p:  db "p",0
cc_np: db "np",0
cc_l:  db "l",0
cc_ge: db "ge",0
cc_le: db "le",0
cc_g:  db "g",0
dex_cc_suffix:
    dq cc_o,cc_no,cc_b,cc_nb,cc_z,cc_nz,cc_be,cc_a
    dq cc_s,cc_ns,cc_p,cc_np,cc_l,cc_ge,cc_le,cc_g

; Prefixos p/ jcc/cmain/setcc compostos no emitter
s_jpre:   db "j",0
s_cmovpre: db "cmov",0
s_setpre: db "set",0

; Mnems de grupo (idx = reg do ModRM)
dex_grp1_mne:
    dq s_add,s_or,s_adc,s_sbb,s_and,s_sub,s_xor,s_cmp
dex_grp2_mne:
    dq s_rol,s_ror,s_rcr,s_shl,s_shr,s_shr,s_shl,s_sar
dex_grp3_mne:
    dq s_test,s_test,s_not,s_neg,s_mul,s_imul,s_div,s_idiv
dex_grp45_mne:
    dq s_inc,s_dec,s_call,s_call,s_jmp,s_jmp,s_push,s_push
