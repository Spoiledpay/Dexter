;=============================================================================
; Dexter/include/dexter.inc
; Estruturas globais do Dexter (DexConfig, PeImage, PeSection, Insn).
;
; Requisitos atendidos: Projeto.md seções 3 (estruturas de dados)
; Testes: tests/run_tests.bat
; Autor: Dexter Engineer
;=============================================================================
%ifndef DEXTER_INC
%define DEXTER_INC

%include "errors.inc"
%include "version.inc"

%define DEXTER_VERSION_MAJOR DEX_VER_MAJOR
%define DEXTER_VERSION_MINOR DEX_VER_MINOR
%define DEXTER_VERSION_PATCH DEX_VER_PATCH

; ---- Flags de DexConfig.flags (DF_*) ----
%define DF_REBUILD      0x0001
%define DF_HEXDUMP      0x0002
%define DF_NOP_PAD      0x0004
%define DF_NO_IMPORTS   0x0008
%define DF_NO_RELOCS    0x0010
%define DF_STRINGS      0x0020
%define DF_QUIET        0x0040
%define DF_VERBOSE2     0x0080
%define DF_NATIVE       0x0100
%define DF_ASTDUMP      0x0200
%define DF_OVERVIEW     0x0400
%define DF_JSON         0x0800
%define DF_FUNC         0x1000
%define DF_XREFS        0x2000
%define DF_TRACE        0x4000
%define DF_RSRC         0x8000
%define DF_SNAP         0x10000
%define DF_CMP          0x20000
%define DF_DOCTOR       0x40000

; ---- DexConfig.mode ----
%define DEX_MODE_WIN64   0
%define DEX_MODE_BIN     1

; Configuração em runtime (preenchida por dex_parse_args).
; Alocada em .bss do main (g_cfg), passada por ponteiro.
struc DexConfig
    .input_path     resq 1   ; char* (obrigatório)
    .output_asm     resq 1   ; char* (NULL = <input>.asm)
    .output_exe     resq 1   ; char* (NULL = sem rebuild)
    .nasm_path      resq 1   ; char* (padrão "C:\Nasm\nasm.exe")
    .linker_path    resq 1   ; char* (padrão "C:\Nasm\link.exe")
    .section_filter resq 1   ; char* (NULL = todas)
    .start_rva      resq 1
    .end_rva        resq 1
    .has_start      resb 1
    .has_end        resb 1
    .pad_se         resw 1
    .pad_se2        resd 1
    .mode           resd 1   ; DEX_MODE_*
    .flags          resd 1   ; DF_*
    .verbose        resd 1   ; 0,1,2
    .quiet          resd 1
    .func_addr      resq 1   ; -func VA (has_func)
    .xrefs_addr     resq 1   ; -xrefs VA (has_xrefs)
    .trace_addr     resq 1   ; -trace VA (has_trace)
    .depth          resq 1   ; -depth (default 8, 1..64)
    .has_func       resb 1
    .has_xrefs      resb 1
    .has_trace      resb 1
    .has_depth      resb 1
    .pad_q          resd 1
    .snapshot_path  resq 1   ; -snapshot <arq> (NULL = sem snapshot)
    .compare_path   resq 1   ; -compare <arq> (NULL = sem compare)
endstruc

; Estado do PE carregado (preenchido por dex_pe_load).
struc PeImage
    .file_buffer    resq 1
    .file_size      resq 1
    .image_base     resq 1
    .entry_point    resq 1   ; RVA
    .num_sections   resd 1
    .pad_ns         resd 1
    .sections_ptr   resq 1   ; -> array PeSection[96 max]
    .imports_ptr    resq 1   ; -> ImportInfo (ou 0)
    .imports_count  resd 1
    .pad_ic         resd 1
    .exports_ptr    resq 1
    .relocs_ptr     resq 1
    .relocs_count   resd 1
    .pad_rc         resd 1
    .opt_header     resq 1   ; -> IMAGE_OPTIONAL_HEADER64 no file_buffer
    .nt_headers     resq 1   ; -> IMAGE_NT_HEADERS64 no file_buffer
    .is_valid       resd 1
    .pad_v          resd 1
    .arch           resd 1   ; 0 = x64 (PE32+), 1 = x32 (PE32): ver DEX_ARCH_*
    .pad_arch       resd 1
endstruc

; PeImage.arch (Fase x32: loader preenche; decoder/emissor consultam).
%define DEX_ARCH_X64   0
%define DEX_ARCH_X32   1

; Entrada de seção normalizada (copiada do PE, validada).
struc PeSection
    .name           resb 8
    .vsize          resd 1
    .vaddr          resd 1   ; RVA
    .raw_size       resd 1
    .raw_ptr        resd 1   ; offset no arquivo
    .characterist   resd 1
    .pad            resd 1
endstruc
%define SIZEOF_PE_SECTION 32

; Operando decodificado (AST flat p/ emissor nativo R-4.5). 16 bytes exatos.
; kind: 0=ausente 1=reg 2=mem 3=imm 4=rel(label) 5=seg
; reg/base/index: 0-15 (GPR); size: 1/2/4/8; scale: 1/2/4/8 (mem);
; seg: 0=nenhum 1=es 2=cs 3=ss 4=ds 5=fs 6=gs; val: disp(sign-ext)/imm64/alvo.
struc DexOp
    .kind           resb 1
    .reg            resb 1   ; reg ou seg(se kind=5)
    .base           resb 1   ; 0xFF = ausente (RIP)
    .index          resb 1   ; 0xFF = ausente
    .scale          resb 1
    .size           resb 1
    .seg            resb 1
    .pad            resb 1
    .val            resq 1
endstruc
%define DEX_OP_NONE 0
%define DEX_OP_REG  1
%define DEX_OP_MEM  2
%define DEX_OP_IMM  3
%define DEX_OP_REL  4
%define DEX_OP_SEG  5
%define DEX_SEG_NONE 0
%define DEX_SEG_ES 1
%define DEX_SEG_CS 2
%define DEX_SEG_SS 3
%define DEX_SEG_DS 4
%define DEX_SEG_FS 5
%define DEX_SEG_GS 6
%define DEX_NOBASE  0xFF
%define DEX_NOINDEX 0xFF

; Instrução decodificada (saída de dex_disasm_one).
struc Insn
    .address        resq 1   ; VA onde começa
    .length         resd 1
    .prefix_count   resd 1   ; nº bytes de prefixo legacy
    .rex            resb 1
    .has_rex        resb 1
    .has_modrm      resb 1
    .has_sib        resb 1
    .modrm          resb 1
    .sib            resb 1
    .disp_size      resb 1
    .imm_size       resb 1
    .legacy66       resb 1   ; prefixo 0x66 presente
    .legacy67       resb 1   ; prefixo 0x67 presente (addr32)
    .lock           resb 1   ; prefixo 0xF0
    .rep            resb 1   ; 0=nenhum, 0xF2, 0xF3
    .opcode         resd 1
    .opcode_len     resd 1   ; 1,2,3
    .disp           resq 1
    .imm            resq 1
    .mne            resq 1   ; char* mnemônico (ou 0)
    .opclass        resd 1   ; OP_* (opcode_tbl.asm)
    .is_branch      resb 1
    .is_call        resb 1
    .is_ret         resb 1
    .pad            resb 1
    .target_va      resq 1   ; VA alvo (branch/call) ou 0
    .raw            resb 15  ; bytes originais (p/ emitter db)
    .segprefix      resb 1   ; 0=nenhum 1=es..6=gs (R-4.5; prefixes.asm preenche)
    .addr_mode      resb 1   ; 0 = 64 bits, 1 = 32 bits (Fase x32; dex_disasm_one preenche)
    .enc            resb 1   ; R-2.7: 0=legacy, 1=VEX (C4/C5), 2=EVEX (62)
    .pad2           resb 18
    .op0            resb 16  ; DexOp (R-4.5; ver layout acima)
    .op1            resb 16
    .op2            resb 16
endstruc
%define SIZEOF_INSN 160

; Entrada de import normalizada (gen).
struc ImportEntry
    .dll_name       resq 1   ; char* (aponta p/ dentro do file_buffer ou cópia)
    .func_name      resq 1   ; char* (NULL se ordinal)
    .ordinal        resw 1
    .is_ordinal     resb 1
    .pad            resb 5
    .iat_rva        resd 1
    .pad2           resd 1
endstruc

; Buffer dinâmico de saída (gen/asm_buffer.asm).
struc AsmBuf
    .data           resq 1
    .len            resq 1
    .cap            resq 1
endstruc

; Token do lexer NASM (R-6.2; src/front/lexer.asm). 40 bytes exatos.
; kind: LEX_* abaixo. REG (val): bits0-7 idx (0-15 GPR; 1-6 SEG),
; bits8-15 size (1/2/4/8; SEG=2), bit16 HI (ah..bh), bit17 SEG (es..gs).
; NUM (val): valor. STR/LABEL/IDENT/COMMENT (ptr/len): texto fonte
; (STR sem as aspas; COMMENT sem o ';'; LABEL sem o ':').
; line 1-based, col 0-based (custo O(pos) por token; parser R-6.3
; rastreia incremental p/ entradas grandes).
%define LEX_EOF     0
%define LEX_EOL     1
%define LEX_LABEL   2
%define LEX_IDENT   3
%define LEX_REG     4
%define LEX_NUM     5
%define LEX_STR     6
%define LEX_LBR     7
%define LEX_RBR     8
%define LEX_COMMA   9
%define LEX_COLON   10
%define LEX_PLUS    11
%define LEX_MINUS   12
%define LEX_STAR    13
%define LEX_SLASH   14
%define LEX_COMMENT 15
%define LEX_UNKNOWN 16
%define LEX_NKINDS  17
%define LEX_REG_HI  0x10000
%define LEX_REG_SEG 0x20000
struc DexToken
    .kind           resd 1
    .line           resd 1
    .col            resd 1
    .pad            resd 1
    .val            resq 1
    .ptr            resq 1
    .len            resq 1
endstruc
%define SIZEOF_TOKEN 40

; AST do parser textual (R-6.3; src/front/ast.asm + parser.asm).
; Ownership: TUDO em heap (dex_malloc/realloc); nomes/verbatim EMPRESTAM o
; texto-fonte (ptr/len, sem cópia — fonte deve viver além da AST);
; dex_ast_free_unit libera arrays+nós (nunca o fonte). Índices (não
; ponteiros) sobrevivem a regrowth: func↔blocks↔instrs referenciados
; por idx; tidx = (func<<32)|block, ou -1 (externo/irresoluto).
; Nós: AstUnit{funcs[], datas[]} / AstFunc{name,sect,blocks[]} /
; AstBlock{label,instrs[],succs[]} / AstInstr{mne,flags,nops,ops[3](DexOp),
; tname,tidx} / AstSucc{kind,tidx,name} / AstData{kind,label,span,sect}.
; Linhas não-código (db/equ/diretivas) viram AstData VERBATIM (span da
; linha); comentários/EOL são descartados (re-emissão não os preserva —
; limitação documentada R-6.3). Labels empilhados (`a:`+`b:`) ficam com o
; ÚLTIMO (alias raro, sem corpus; documentado).
%define AST_DATA_DB  1
%define AST_DATA_EQU 2
%define AST_DATA_DIR 3
%define AST_SUCC_FALL   0
%define AST_SUCC_CALL   1
%define AST_SUCC_BRANCH 2
%define AST_SUCC_JMP    3
%define AST_F_CALL   0x01
%define AST_F_BRANCH 0x02
%define AST_F_JMP    0x04
%define AST_F_RET    0x08
%define AST_F_LOCK   0x10
%define AST_F_REP    0x20
%define AST_F_A32    0x40
struc AstSucc
    .kind           resd 1
    .padk           resd 1
    .tidx           resq 1
    .name_ptr       resq 1
    .name_len       resq 1
endstruc
%define SIZEOF_SUCC 32
struc AstInstr
    .mne_ptr        resq 1
    .mne_len        resq 1
    .flags          resd 1
    .nops           resd 1
    .op0            resb 16
    .op1            resb 16
    .op2            resb 16
    .tname_ptr      resq 1
    .tname_len      resq 1
    .tidx           resq 1
endstruc
%define SIZEOF_INSTR 96
struc AstBlock
    .label_ptr      resq 1
    .label_len      resq 1
    .ninstrs        resd 1
    .capinstrs      resd 1
    .instrs         resq 1
    .nsucc          resd 1
    .capsucc        resd 1
    .succs          resq 1
endstruc
%define SIZEOF_BLOCK 48
struc AstFunc
    .name_ptr       resq 1
    .name_len       resq 1
    .sect_ptr       resq 1
    .sect_len       resq 1
    .nblocks        resd 1
    .capblocks      resd 1
    .blocks         resq 1
endstruc
%define SIZEOF_FUNC 48
struc AstData
    .kind           resd 1
    .padk           resd 1
    .label_ptr      resq 1
    .label_len      resq 1
    .span_ptr       resq 1
    .span_len       resq 1
    .sect_ptr       resq 1
    .sect_len       resq 1
endstruc
%define SIZEOF_DATA 56
struc AstUnit
    .nfuncs         resd 1
    .capfuncs       resd 1
    .funcs          resq 1
    .ndata          resd 1
    .capdata        resd 1
    .datas          resq 1
endstruc
%define SIZEOF_UNIT 32

; IR do lifter (R-6.4; src/back/lift.asm). 24 bytes exatos, sem heap
; (como DexToken): classificação + alvo resolvido de UMA instrução.
; cls: o que o codegen deve emitir; tkind/tva/imp: para onde (VA sempre
; absoluta; imp = ImportEntry* emprestado do PeImage, só se tkind=3).
%define IR_DB      0
%define IR_INSTR   1
%define IR_CALL    2
%define IR_CALLIMP 3
%define IR_JMP     4
%define IR_JMPIMP  5
%define IR_BRANCH  6
%define IR_RET     7
%define IRT_NONE   0
%define IRT_CODE   1
%define IRT_DATA   2
%define IRT_IMPORT 3
struc DexIR
    .cls            resd 1
    .tkind          resd 1
    .tva            resq 1
    .imp            resq 1
endstruc
%define SIZEOF_IR 24

; Contexto do lifter (tudo emprestado, sem ownership).
struc DexLiftCtx
    .img            resq 1   ; PeImage* (base + seções + imports; não nulo)
endstruc

%define SIZEOF_IMPORT_ENTRY 32

; Símbolo (gen/symbols.asm): tabela hash VA -> nome.
struc DexSymbol
    .va             resq 1
    .name_ptr       resq 1   ; char* (heap, NUL-terminado)
    .next           resq 1   ; encadeamento no bucket
endstruc

struc SymbolTable
    .buckets        resq 1   ; DexSymbol**
    .num_buckets    resd 1
    .count          resd 1
    .label_seq      resd 1
    .pad            resd 1
endstruc

%endif ; DEXTER_INC
