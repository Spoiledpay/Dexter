;=============================================================================
; Dexter/src/disasm/x87.asm
; Mnemônicos x87 (opcodes D8-DF) resolvidos por (opcode, ModRM).
;
; R-2.7 resolve o NOME (comentário); 2a acrescenta a FORMA de operando
; (mem por tamanho, st(i), st0/st(i), ax) para emissão NATIVA byte-exata.
; A forma memória depende apenas do campo reg; a forma registro (mod=11)
; depende do grupo do ModRM. `fstpnce` (D9 D8-DF) não tem mnemônico no
; NASM → db byte-exato (8 codificações; ver PE_NOTES §32).
;
; Fonte da verdade: capstone 5.0.7 (sweep exaustivo 8x256 em
; tests/x87_check.asm, golden tests/expected/x87.txt). Encoding inválido
; → 0 (o emitter cai em `db` sem comentário).
;
; Requisitos atendidos: R-2.7
; Testes: tests/x87_check.asm + tests/expected/x87.txt ([39])
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "dexter.inc"

global dex_x87_mne
global dex_x87_form

section .rodata

; ---- strings (uma por mnemônico) ----
s_x87_f2xm1: db "f2xm1", 0
s_x87_fabs: db "fabs", 0
s_x87_fadd: db "fadd", 0
s_x87_faddp: db "faddp", 0
s_x87_fbld: db "fbld", 0
s_x87_fbstp: db "fbstp", 0
s_x87_fchs: db "fchs", 0
s_x87_fcmovb: db "fcmovb", 0
s_x87_fcmovbe: db "fcmovbe", 0
s_x87_fcmove: db "fcmove", 0
s_x87_fcmovnb: db "fcmovnb", 0
s_x87_fcmovnbe: db "fcmovnbe", 0
s_x87_fcmovne: db "fcmovne", 0
s_x87_fcmovnu: db "fcmovnu", 0
s_x87_fcmovu: db "fcmovu", 0
s_x87_fcom: db "fcom", 0
s_x87_fcomi: db "fcomi", 0
s_x87_fcomp: db "fcomp", 0
s_x87_fcomip: db "fcomip", 0
s_x87_fcompp: db "fcompp", 0
s_x87_fcos: db "fcos", 0
s_x87_fdecstp: db "fdecstp", 0
s_x87_fndisi: db "fndisi", 0
s_x87_fdiv: db "fdiv", 0
s_x87_fdivp: db "fdivp", 0
s_x87_fdivr: db "fdivr", 0
s_x87_fdivrp: db "fdivrp", 0
s_x87_fneni: db "fneni", 0
s_x87_ffree: db "ffree", 0
s_x87_ffreep: db "ffreep", 0
s_x87_fiadd: db "fiadd", 0
s_x87_ficom: db "ficom", 0
s_x87_ficomp: db "ficomp", 0
s_x87_fidiv: db "fidiv", 0
s_x87_fidivr: db "fidivr", 0
s_x87_fild: db "fild", 0
s_x87_fimul: db "fimul", 0
s_x87_fincstp: db "fincstp", 0
s_x87_fist: db "fist", 0
s_x87_fistp: db "fistp", 0
s_x87_fisttp: db "fisttp", 0
s_x87_fisub: db "fisub", 0
s_x87_fisubr: db "fisubr", 0
s_x87_fld: db "fld", 0
s_x87_fld1: db "fld1", 0
s_x87_fldcw: db "fldcw", 0
s_x87_fldenv: db "fldenv", 0
s_x87_fldl2e: db "fldl2e", 0
s_x87_fldl2t: db "fldl2t", 0
s_x87_fldlg2: db "fldlg2", 0
s_x87_fldln2: db "fldln2", 0
s_x87_fldpi: db "fldpi", 0
s_x87_fldz: db "fldz", 0
s_x87_fmul: db "fmul", 0
s_x87_fmulp: db "fmulp", 0
s_x87_fnclex: db "fnclex", 0
s_x87_fninit: db "fninit", 0
s_x87_fnop: db "fnop", 0
s_x87_fnsave: db "fnsave", 0
s_x87_fnstcw: db "fnstcw", 0
s_x87_fnstenv: db "fnstenv", 0
s_x87_fnstsw: db "fnstsw", 0
s_x87_fpatan: db "fpatan", 0
s_x87_fprem: db "fprem", 0
s_x87_fprem1: db "fprem1", 0
s_x87_fptan: db "fptan", 0
s_x87_frndint: db "frndint", 0
s_x87_frstor: db "frstor", 0
s_x87_fscale: db "fscale", 0
s_x87_fsetpm: db "fsetpm", 0
s_x87_fsin: db "fsin", 0
s_x87_fsincos: db "fsincos", 0
s_x87_fsqrt: db "fsqrt", 0
s_x87_fst: db "fst", 0
s_x87_fstp: db "fstp", 0
s_x87_fstpnce: db "fstpnce", 0
s_x87_fsub: db "fsub", 0
s_x87_fsubp: db "fsubp", 0
s_x87_fsubr: db "fsubr", 0
s_x87_fsubrp: db "fsubrp", 0
s_x87_ftst: db "ftst", 0
s_x87_fucom: db "fucom", 0
s_x87_fucomi: db "fucomi", 0
s_x87_fucomp: db "fucomp", 0
s_x87_fucomip: db "fucomip", 0
s_x87_fucompp: db "fucompp", 0
s_x87_fxam: db "fxam", 0
s_x87_fxch: db "fxch", 0
s_x87_fxtract: db "fxtract", 0
s_x87_fyl2x: db "fyl2x", 0
s_x87_fyl2xp1: db "fyl2xp1", 0

; ---- x87_mem[64] (mod != 11): índice = (opcode-0xD8)*8 + reg ----
x87_mem:
    dq s_x87_fadd, s_x87_fmul, s_x87_fcom, s_x87_fcomp, s_x87_fsub, s_x87_fsubr, s_x87_fdiv, s_x87_fdivr
    dq s_x87_fld, 0, s_x87_fst, s_x87_fstp, s_x87_fldenv, s_x87_fldcw, s_x87_fnstenv, s_x87_fnstcw
    dq s_x87_fiadd, s_x87_fimul, s_x87_ficom, s_x87_ficomp, s_x87_fisub, s_x87_fisubr, s_x87_fidiv, s_x87_fidivr
    dq s_x87_fild, s_x87_fisttp, s_x87_fist, s_x87_fistp, 0, s_x87_fld, 0, s_x87_fstp
    dq s_x87_fadd, s_x87_fmul, s_x87_fcom, s_x87_fcomp, s_x87_fsub, s_x87_fsubr, s_x87_fdiv, s_x87_fdivr
    dq s_x87_fld, s_x87_fisttp, s_x87_fst, s_x87_fstp, s_x87_frstor, 0, s_x87_fnsave, s_x87_fnstsw
    dq s_x87_fiadd, s_x87_fimul, s_x87_ficom, s_x87_ficomp, s_x87_fisub, s_x87_fisubr, s_x87_fidiv, s_x87_fidivr
    dq s_x87_fild, s_x87_fisttp, s_x87_fist, s_x87_fistp, s_x87_fbld, s_x87_fild, s_x87_fbstp, s_x87_fistp

; ---- x87_reg[512] (mod == 11): índice = (opcode-0xD8)*64 + (modrm & 0x3F) ----
x87_reg:
    dq s_x87_fadd, s_x87_fadd, s_x87_fadd, s_x87_fadd, s_x87_fadd, s_x87_fadd, s_x87_fadd, s_x87_fadd
    dq s_x87_fmul, s_x87_fmul, s_x87_fmul, s_x87_fmul, s_x87_fmul, s_x87_fmul, s_x87_fmul, s_x87_fmul
    dq s_x87_fcom, s_x87_fcom, s_x87_fcom, s_x87_fcom, s_x87_fcom, s_x87_fcom, s_x87_fcom, s_x87_fcom
    dq s_x87_fcomp, s_x87_fcomp, s_x87_fcomp, s_x87_fcomp, s_x87_fcomp, s_x87_fcomp, s_x87_fcomp, s_x87_fcomp
    dq s_x87_fsub, s_x87_fsub, s_x87_fsub, s_x87_fsub, s_x87_fsub, s_x87_fsub, s_x87_fsub, s_x87_fsub
    dq s_x87_fsubr, s_x87_fsubr, s_x87_fsubr, s_x87_fsubr, s_x87_fsubr, s_x87_fsubr, s_x87_fsubr, s_x87_fsubr
    dq s_x87_fdiv, s_x87_fdiv, s_x87_fdiv, s_x87_fdiv, s_x87_fdiv, s_x87_fdiv, s_x87_fdiv, s_x87_fdiv
    dq s_x87_fdivr, s_x87_fdivr, s_x87_fdivr, s_x87_fdivr, s_x87_fdivr, s_x87_fdivr, s_x87_fdivr, s_x87_fdivr
    dq s_x87_fld, s_x87_fld, s_x87_fld, s_x87_fld, s_x87_fld, s_x87_fld, s_x87_fld, s_x87_fld
    dq s_x87_fxch, s_x87_fxch, s_x87_fxch, s_x87_fxch, s_x87_fxch, s_x87_fxch, s_x87_fxch, s_x87_fxch
    dq s_x87_fnop, 0, 0, 0, 0, 0, 0, 0
    dq s_x87_fstpnce, s_x87_fstpnce, s_x87_fstpnce, s_x87_fstpnce, s_x87_fstpnce, s_x87_fstpnce, s_x87_fstpnce, s_x87_fstpnce
    dq s_x87_fchs, s_x87_fabs, 0, 0, s_x87_ftst, s_x87_fxam, 0, 0
    dq s_x87_fld1, s_x87_fldl2t, s_x87_fldl2e, s_x87_fldpi, s_x87_fldlg2, s_x87_fldln2, s_x87_fldz, 0
    dq s_x87_f2xm1, s_x87_fyl2x, s_x87_fptan, s_x87_fpatan, s_x87_fxtract, s_x87_fprem1, s_x87_fdecstp, s_x87_fincstp
    dq s_x87_fprem, s_x87_fyl2xp1, s_x87_fsqrt, s_x87_fsincos, s_x87_frndint, s_x87_fscale, s_x87_fsin, s_x87_fcos
    dq s_x87_fcmovb, s_x87_fcmovb, s_x87_fcmovb, s_x87_fcmovb, s_x87_fcmovb, s_x87_fcmovb, s_x87_fcmovb, s_x87_fcmovb
    dq s_x87_fcmove, s_x87_fcmove, s_x87_fcmove, s_x87_fcmove, s_x87_fcmove, s_x87_fcmove, s_x87_fcmove, s_x87_fcmove
    dq s_x87_fcmovbe, s_x87_fcmovbe, s_x87_fcmovbe, s_x87_fcmovbe, s_x87_fcmovbe, s_x87_fcmovbe, s_x87_fcmovbe, s_x87_fcmovbe
    dq s_x87_fcmovu, s_x87_fcmovu, s_x87_fcmovu, s_x87_fcmovu, s_x87_fcmovu, s_x87_fcmovu, s_x87_fcmovu, s_x87_fcmovu
    dq 0, 0, 0, 0, 0, 0, 0, 0
    dq 0, s_x87_fucompp, 0, 0, 0, 0, 0, 0
    dq 0, 0, 0, 0, 0, 0, 0, 0
    dq 0, 0, 0, 0, 0, 0, 0, 0
    dq s_x87_fcmovnb, s_x87_fcmovnb, s_x87_fcmovnb, s_x87_fcmovnb, s_x87_fcmovnb, s_x87_fcmovnb, s_x87_fcmovnb, s_x87_fcmovnb
    dq s_x87_fcmovne, s_x87_fcmovne, s_x87_fcmovne, s_x87_fcmovne, s_x87_fcmovne, s_x87_fcmovne, s_x87_fcmovne, s_x87_fcmovne
    dq s_x87_fcmovnbe, s_x87_fcmovnbe, s_x87_fcmovnbe, s_x87_fcmovnbe, s_x87_fcmovnbe, s_x87_fcmovnbe, s_x87_fcmovnbe, s_x87_fcmovnbe
    dq s_x87_fcmovnu, s_x87_fcmovnu, s_x87_fcmovnu, s_x87_fcmovnu, s_x87_fcmovnu, s_x87_fcmovnu, s_x87_fcmovnu, s_x87_fcmovnu
    dq s_x87_fneni, s_x87_fndisi, s_x87_fnclex, s_x87_fninit, s_x87_fsetpm, 0, 0, 0
    dq s_x87_fucomi, s_x87_fucomi, s_x87_fucomi, s_x87_fucomi, s_x87_fucomi, s_x87_fucomi, s_x87_fucomi, s_x87_fucomi
    dq s_x87_fcomi, s_x87_fcomi, s_x87_fcomi, s_x87_fcomi, s_x87_fcomi, s_x87_fcomi, s_x87_fcomi, s_x87_fcomi
    dq 0, 0, 0, 0, 0, 0, 0, 0
    dq s_x87_fadd, s_x87_fadd, s_x87_fadd, s_x87_fadd, s_x87_fadd, s_x87_fadd, s_x87_fadd, s_x87_fadd
    dq s_x87_fmul, s_x87_fmul, s_x87_fmul, s_x87_fmul, s_x87_fmul, s_x87_fmul, s_x87_fmul, s_x87_fmul
    dq 0, 0, 0, 0, 0, 0, 0, 0
    dq 0, 0, 0, 0, 0, 0, 0, 0
    dq s_x87_fsubr, s_x87_fsubr, s_x87_fsubr, s_x87_fsubr, s_x87_fsubr, s_x87_fsubr, s_x87_fsubr, s_x87_fsubr
    dq s_x87_fsub, s_x87_fsub, s_x87_fsub, s_x87_fsub, s_x87_fsub, s_x87_fsub, s_x87_fsub, s_x87_fsub
    dq s_x87_fdivr, s_x87_fdivr, s_x87_fdivr, s_x87_fdivr, s_x87_fdivr, s_x87_fdivr, s_x87_fdivr, s_x87_fdivr
    dq s_x87_fdiv, s_x87_fdiv, s_x87_fdiv, s_x87_fdiv, s_x87_fdiv, s_x87_fdiv, s_x87_fdiv, s_x87_fdiv
    dq s_x87_ffree, s_x87_ffree, s_x87_ffree, s_x87_ffree, s_x87_ffree, s_x87_ffree, s_x87_ffree, s_x87_ffree
    dq 0, 0, 0, 0, 0, 0, 0, 0
    dq s_x87_fst, s_x87_fst, s_x87_fst, s_x87_fst, s_x87_fst, s_x87_fst, s_x87_fst, s_x87_fst
    dq s_x87_fstp, s_x87_fstp, s_x87_fstp, s_x87_fstp, s_x87_fstp, s_x87_fstp, s_x87_fstp, s_x87_fstp
    dq s_x87_fucom, s_x87_fucom, s_x87_fucom, s_x87_fucom, s_x87_fucom, s_x87_fucom, s_x87_fucom, s_x87_fucom
    dq s_x87_fucomp, s_x87_fucomp, s_x87_fucomp, s_x87_fucomp, s_x87_fucomp, s_x87_fucomp, s_x87_fucomp, s_x87_fucomp
    dq 0, 0, 0, 0, 0, 0, 0, 0
    dq 0, 0, 0, 0, 0, 0, 0, 0
    dq s_x87_faddp, s_x87_faddp, s_x87_faddp, s_x87_faddp, s_x87_faddp, s_x87_faddp, s_x87_faddp, s_x87_faddp
    dq s_x87_fmulp, s_x87_fmulp, s_x87_fmulp, s_x87_fmulp, s_x87_fmulp, s_x87_fmulp, s_x87_fmulp, s_x87_fmulp
    dq 0, 0, 0, 0, 0, 0, 0, 0
    dq 0, s_x87_fcompp, 0, 0, 0, 0, 0, 0
    dq s_x87_fsubrp, s_x87_fsubrp, s_x87_fsubrp, s_x87_fsubrp, s_x87_fsubrp, s_x87_fsubrp, s_x87_fsubrp, s_x87_fsubrp
    dq s_x87_fsubp, s_x87_fsubp, s_x87_fsubp, s_x87_fsubp, s_x87_fsubp, s_x87_fsubp, s_x87_fsubp, s_x87_fsubp
    dq s_x87_fdivrp, s_x87_fdivrp, s_x87_fdivrp, s_x87_fdivrp, s_x87_fdivrp, s_x87_fdivrp, s_x87_fdivrp, s_x87_fdivrp
    dq s_x87_fdivp, s_x87_fdivp, s_x87_fdivp, s_x87_fdivp, s_x87_fdivp, s_x87_fdivp, s_x87_fdivp, s_x87_fdivp
    dq s_x87_ffreep, s_x87_ffreep, s_x87_ffreep, s_x87_ffreep, s_x87_ffreep, s_x87_ffreep, s_x87_ffreep, s_x87_ffreep
    dq 0, 0, 0, 0, 0, 0, 0, 0
    dq 0, 0, 0, 0, 0, 0, 0, 0
    dq 0, 0, 0, 0, 0, 0, 0, 0
    dq s_x87_fnstsw, 0, 0, 0, 0, 0, 0, 0
    dq s_x87_fucomip, s_x87_fucomip, s_x87_fucomip, s_x87_fucomip, s_x87_fucomip, s_x87_fucomip, s_x87_fucomip, s_x87_fucomip
    dq s_x87_fcomip, s_x87_fcomip, s_x87_fcomip, s_x87_fcomip, s_x87_fcomip, s_x87_fcomip, s_x87_fcomip, s_x87_fcomip
    dq 0, 0, 0, 0, 0, 0, 0, 0

; ---- forma de operando (2a: emissão nativa) ----
; x87_shape[64] (mod == 11): índice = (opcode-0xD8)*8 + grupo(modrm>>3).
;   conjunto de operandos por grupo; o índice st(i) vem de modrm&7.
align 8
x87_shape:
    db X87_SH_ST, X87_SH_ST, X87_SH_ST, X87_SH_ST, X87_SH_ST, X87_SH_ST, X87_SH_ST, X87_SH_ST
    db X87_SH_ST, X87_SH_ST, X87_SH_NONE, X87_SH_DB, X87_SH_NONE, X87_SH_NONE, X87_SH_NONE, X87_SH_NONE
    db X87_SH_ST0_ST, X87_SH_ST0_ST, X87_SH_ST0_ST, X87_SH_ST0_ST, X87_SH_DB, X87_SH_NONE, X87_SH_DB, X87_SH_DB
    db X87_SH_ST0_ST, X87_SH_ST0_ST, X87_SH_ST0_ST, X87_SH_ST0_ST, X87_SH_NONE, X87_SH_ST0_ST, X87_SH_ST0_ST, X87_SH_DB
    db X87_SH_ST_ST0, X87_SH_ST_ST0, X87_SH_ST_ST0, X87_SH_ST_ST0, X87_SH_ST_ST0, X87_SH_ST_ST0, X87_SH_ST_ST0, X87_SH_ST_ST0
    db X87_SH_ST, X87_SH_DB, X87_SH_ST, X87_SH_ST, X87_SH_ST, X87_SH_ST, X87_SH_DB, X87_SH_DB
    db X87_SH_ST_ST0, X87_SH_ST_ST0, X87_SH_DB, X87_SH_NONE, X87_SH_ST_ST0, X87_SH_ST_ST0, X87_SH_ST_ST0, X87_SH_ST_ST0
    db X87_SH_ST, X87_SH_DB, X87_SH_DB, X87_SH_DB, X87_SH_AX, X87_SH_ST0_ST, X87_SH_ST0_ST, X87_SH_DB

; x87_memsz[64] (mod != 11): índice = (opcode-0xD8)*8 + reg. 0 = inválido.
; Tamanho do operando conforme Intel SDM (o NASM exige o keyword correto;
; 80 bits é `tword`, não `tbyte`). DEX_MEM_NOSZ: fldenv/fnstenv/frstor/fnsave.
x87_memsz:
    db 4, 4, 4, 4, 4, 4, 4, 4
    db 4, 0, 4, 4, DEX_MEM_NOSZ, 2, DEX_MEM_NOSZ, 2
    db 4, 4, 4, 4, 4, 4, 4, 4
    db 4, 4, 4, 4, 0, DEX_MEM_TWORD, 0, DEX_MEM_TWORD
    db 8, 8, 8, 8, 8, 8, 8, 8
    db 8, 8, 8, 8, DEX_MEM_NOSZ, 0, DEX_MEM_NOSZ, 2
    db 2, 2, 2, 2, 2, 2, 2, 2
    db 2, 2, 2, 2, DEX_MEM_TWORD, 8, DEX_MEM_TWORD, 8

section .text

;-----------------------------------------------------------------------------
; dex_x87_mne
; Resolve o mnemônico x87 de uma instrução com opcode 0xD8-0xDF.
;
; Args:   rcx = Insn* (Insn.opcode = 0xD8-0xDF; Insn.modrm = byte ModRM).
; Ret:    rax = char* mnemônico estático, ou 0 se encoding inválido/fora.
; Clobber: rax, rcx, rdx
; Preserva: rbx, rbp, rdi, rsi, r12-r15
;-----------------------------------------------------------------------------
dex_x87_mne:
    test rcx, rcx
    jz .zero
    movzx eax, byte [rcx+Insn.opcode]
    sub eax, 0xD8
    cmp eax, 7
    ja .zero                    ; fora de x87
    shl eax, 6                  ; (op-0xD8)*64
    movzx edx, byte [rcx+Insn.modrm]
    mov ecx, edx
    shr ecx, 6
    cmp ecx, 3
    je .reg
    ; memória: mnemônico depende só do campo reg
    shr eax, 3                  ; (op-0xD8)*8
    mov ecx, edx
    shr ecx, 3
    and ecx, 7
    add eax, ecx
    lea rdx, [rel x87_mem]
    mov rax, [rdx+rax*8]
    ret
.reg:
    and edx, 0x3F
    add eax, edx
    lea rdx, [rel x87_reg]
    mov rax, [rdx+rax*8]
    ret
.zero:
    xor eax, eax
    ret

;-----------------------------------------------------------------------------
; dex_x87_form
; Resolve a FORMA de operando de uma instrução x87 (2a: emissão nativa).
; O chamador resolve o mnemônico antes (dex_x87_mne != 0); encodings com
; mnemônico mas sem forma no NASM (D9 D8-DF, `fstpnce`) retornam X87_SH_DB.
;
; Args:   rcx = Insn* (Insn.opcode 0xD8-0xDF; Insn.modrm já decodificado)
; Ret:    eax = X87_SH_* ; edx = tamanho do operando de memória
;         (1/2/4/8, DEX_MEM_TWORD, DEX_MEM_NOSZ) quando eax == X87_SH_MEM;
;         0 nos demais casos.
; Clobber: rax, rcx, rdx, r8
; Preserva: rbx, rbp, rdi, rsi, r9-r15
;-----------------------------------------------------------------------------
dex_x87_form:
    test rcx, rcx
    jz .db_f
    movzx eax, byte [rcx+Insn.opcode]
    sub eax, 0xD8
    cmp eax, 7
    ja .db_f                    ; fora de x87 (wrap incluso)
    movzx edx, byte [rcx+Insn.modrm]
    mov r8d, edx
    shr r8d, 6
    cmp r8d, 3
    je .reg_f
    ; memória: tamanho depende só do campo reg
    mov r8d, edx
    shr r8d, 3
    and r8d, 7
    shl eax, 3                  ; (op-0xD8)*8
    add eax, r8d
    lea r8, [rel x87_memsz]
    movzx edx, byte [r8+rax]
    mov eax, X87_SH_MEM
    ret
.reg_f:
    ; registro: conjunto de operandos por (op-0xD8, grupo)
    mov r8d, edx
    shr r8d, 3
    and r8d, 7
    shl eax, 3
    add eax, r8d
    lea r8, [rel x87_shape]
    movzx eax, byte [r8+rax]
    cmp eax, X87_SH_DB
    je .db_f
    xor edx, edx
    ret
.db_f:
    mov eax, X87_SH_DB
    xor edx, edx
    ret
