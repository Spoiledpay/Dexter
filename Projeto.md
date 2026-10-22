Dexter — Desassemblador/Reassemblador nativo x64 em NASM
Vou entregar o blueprint completo do projeto (estrutura de pastas, CLI, módulos, protótipos de funções, headers, build e pipeline). É um projeto sério — desassemblar x86-64 corretamente exige decoder de opcode, tabela ModRM/SIB, prefixos VEX/REX e reconstrução de tabelas PE (imports, relocs, seções). Vamos por partes.

1. Estrutura de pastas
text
Dexter/
├── build.bat                    # Compila src/*.asm -> out/dexter.exe
├── clean.bat
├── README.md
├── docs/
│   ├── CLI.md
│   ├── ARQUITETURA.md
│   └── ROADMAP.md
├── include/
│   ├── win64.inc                # Protótipos kernel32/ntdll
│   ├── dexter.inc               # Constantes globais
│   ├── pe.inc                   # Estruturas PE/COFF
│   ├── errors.inc               # Códigos de erro
│   └── macros.inc               # Macros utilitárias (%macro)
├── src/
│   ├── main.asm                 # _start / WinMain, dispatcher
│   ├── cli/
│   │   ├── parse_args.asm
│   │   └── help.asm
│   ├── io/
│   │   ├── file_read.asm
│   │   ├── file_write.asm
│   │   ├── mmap.asm
│   │   └── console.asm
│   ├── pe/
│   │   ├── pe_load.asm          # Valida DOS/NT, mapeia seções
│   │   ├── pe_sections.asm
│   │   ├── pe_imports.asm
│   │   ├── pe_exports.asm
│   │   ├── pe_relocs.asm
│   │   └── rva.asm              # rva_to_offset / offset_to_rva
│   ├── disasm/
│   │   ├── decoder.asm          # Loop principal de decode
│   │   ├── prefixes.asm         # Legacy + REX + VEX/EVEX
│   │   ├── modrm.asm            # ModRM + SIB + disp
│   │   ├── opcode_tbl.asm       # Tabelas de 1/2/3 bytes
│   │   ├── operands.asm         # Tipos de operando (r/m, imm, rel)
│   │   └── emit_nasm.asm        # Emite mnemônico -> texto NASM
│   ├── gen/
│   │   ├── asm_buffer.asm       # Buffer dinâmico de saída
│   │   ├── labels.asm           # Gerência de labels (L_xxx)
│   │   ├── symbols.asm          # Symbol table + hash
│   │   ├── strings.asm          # Pool de strings
│   │   └── rebuild.asm          # Orquestra geração do .asm final
│   └── util/
│       ├── memory.asm           # HeapAlloc/HeapFree wrappers
│       ├── string.asm           # strlen, strcpy, itoa, hex
│       ├── hash.asm             # FNV-1a para symbol table
│       └── log.asm              # Debug/log
├── runtime/
│   ├── pe_stub.inc              # Stub PE para modo -f bin
│   └── imports_stub.inc         # Stub import table
├── tests/
│   ├── hello.exe
│   ├── calc.exe
│   ├── run_tests.bat
│   └── expected/
└── out/                         # Binários gerados
2. Linha de comando (CLI)
text
Dexter v0.1 — Desassemblador/Reassemblador x64 nativo
Uso: dexter <input.exe> [opções]

Entrada:
  <input.exe>            Arquivo PE x64 de entrada (obrigatório)

Saída:
  -o <arquivo.asm>       Fonte NASM gerada        (padrão: <input>.asm)
  -O <arquivo.exe>       Caminho do .exe reassemblado
  -m <modo>              win64 | bin              (padrão: win64)
  -r                     Reassemblar após gerar o .asm
  -L <linker>            Caminho do linker (link.exe/lld-link/golink)
  -N <nasm>              Caminho do nasm.exe      (padrão: nasm.exe no PATH)

Controle de desassemblagem:
  -s <nome_secao>        Só desassemblar uma seção (.text, .data, ...)
  -start <RVA>           Endereço inicial (hex, ex: 0x1000)
  -end   <RVA>           Endereço final
  -hex                   Emite bytes originais como comentário à direita
  -nop-pad               Preenche gaps com NOPs
  -no-imports            Não gera stubs de imports (só marca símbolos)
  -no-relocs             Ignora tabela de relocations
  -strings               Detecta strings e cria bloco db

Diagnóstico:
  -v                     Verbose (nível 1)
  -vv                    Verbose (nível 2 — dump de tabelas)
  -q                     Silencioso
  -ver                   Mostra versão
  -h, --help             Ajuda

Códigos de retorno:
  0  sucesso
  1  uso incorreto
  2  erro de I/O
  3  PE inválido
  4  opcode não suportado
  5  falha no reassembly
Exemplos:

text
dexter.exe app.exe -o app.asm -hex -v
dexter.exe app.exe -o app.asm -r -O app_rebuild.exe
dexter.exe driver.sys -s .text -start 0x1000 -end 0x2000
3. Estruturas de dados (include/dexter.inc)
nasm
;=====================================================================
; dexter.inc — Estruturas globais
;=====================================================================
%ifndef DEXTER_INC
%define DEXTER_INC

%define DEXTER_VERSION_MAJOR 0
%define DEXTER_VERSION_MINOR 1

; ---- Configuração em runtime (preenchida por parse_args) ----
struc DexConfig
    .input_path     resq 1
    .output_asm     resq 1
    .output_exe     resq 1
    .nasm_path      resq 1
    .linker_path    resq 1
    .mode           resd 1     ; 0=win64, 1=bin
    .section_filter resq 1     ; pode ser NULL
    .start_rva      resq 1
    .end_rva        resq 1
    .flags          resd 1     ; ver DF_*
    .verbose        resd 1
endstruc

%define DF_REBUILD      0x0001
%define DF_HEXDUMP      0x0002
%define DF_NOP_PAD      0x0004
%define DF_NO_IMPORTS   0x0008
%define DF_NO_RELOCS    0x0010
%define DF_STRINGS      0x0020
%define DF_QUIET        0x0040

; ---- Estado global do PE carregado ----
struc PeImage
    .file_buffer    resq 1     ; ponteiro para bytes originais
    .file_size      resq 1
    .image_base     resq 1
    .entry_point    resq 1     ; RVA
    .num_sections   resd 1
    .sections_ptr   resq 1     ; -> array de PeSection
    .imports_ptr    resq 1
    .exports_ptr    resq 1
    .relocs_ptr     resq 1
    .relocs_count   resd 1
    .opt_header     resq 1     ; -> IMAGE_OPTIONAL_HEADER64
endstruc

struc PeSection
    .name           resb 8     ; "não-terminado", usar memcmp
    .vsize          resd 1
    .vaddr          resd 1     ; RVA
    .raw_size       resd 1
    .raw_ptr        resd 1     ; offset no arquivo
    .characterist   resd 1
endstruc
%define SIZEOF_PE_SECTION 24

; ---- Instrução decodificada ----
struc Insn
    .address        resq 1     ; VA onde começa
    .length         resd 1
    .prefix_legacy  resd 1     ; bits: LOCK, REP, SEG, 66, 67
    .rex            resb 1
    .opcode         resd 1     ; opcode principal (após prefixos)
    .opcode_len     resb 1
    .modrm          resb 1
    .sib            resb 1
    .disp           resq 1
    .disp_size      resb 1
    .imm            resq 1
    .imm_size       resb 1
    .mne            resq 1     ; ponteiro para string do mnemônico
    .op1_type       resd 1
    .op1_value      resq 1
    .op2_type       resd 1
    .op2_value      resq 1
    .op3_type       resd 1
    .op3_value      resq 1
    .is_target      resb 1     ; é alvo de jump/call (precisa label)
endstruc

%endif ; DEXTER_INC
4. Estruturas PE (include/pe.inc) — resumido
nasm
; ---- DOS Header ----
struc IMAGE_DOS_HEADER
    .e_magic     resw 1     ; 0x5A4D "MZ"
    .e_cblp      resw 1
    .e_cp        resw 1
    .e_crlc      resw 1
    .e_cparhdr   resw 1
    .e_minalloc  resw 1
    .e_maxalloc  resw 1
    .e_ss        resw 1
    .e_sp        resw 1
    .e_csum      resw 1
    .e_ip        resw 1
    .e_cs        resw 1
    .e_lfarlc    resw 1
    .e_ovno      resw 1
    .e_res       resw 4
    .e_oemid     resw 1
    .e_oeminfo   resw 1
    .e_res2      resw 10
    .e_lfanew    resd 1     ; offset para NT headers
endstruc

; ---- File Header ----
struc IMAGE_FILE_HEADER
    .Machine                resw 1
    .NumberOfSections       resw 1
    .TimeDateStamp          resd 1
    .PointerToSymbolTable   resd 1
    .NumberOfSymbols        resd 1
    .SizeOfOptionalHeader   resw 1
    .Characteristics        resw 1
endstruc

; ---- Optional Header 64 ----
struc IMAGE_OPTIONAL_HEADER64
    .Magic                      resw 1  ; 0x20B
    .MajorLinkerVersion         resb 1
    .MinorLinkerVersion         resb 1
    .SizeOfCode                 resd 1
    .SizeOfInitializedData      resd 1
    .SizeOfUninitializedData    resd 1
    .AddressOfEntryPoint        resd 1
    .BaseOfCode                 resd 1
    .ImageBase                  resq 1
    .SectionAlignment           resd 1
    .FileAlignment              resd 1
    .MajorOSVersion             resw 1
    .MinorOSVersion             resw 1
    .MajorImageVersion          resw 1
    .MinorImageVersion          resw 1
    .MajorSubsystemVersion      resw 1
    .MinorSubsystemVersion      resw 1
    .Win32VersionValue          resd 1
    .SizeOfImage                resd 1
    .SizeOfHeaders              resd 1
    .CheckSum                   resd 1
    .Subsystem                  resw 1
    .DllCharacteristics         resw 1
    .SizeOfStackReserve         resq 1
    .SizeOfStackCommit          resq 1
    .SizeOfHeapReserve          resq 1
    .SizeOfHeapCommit           resq 1
    .LoaderFlags                resd 1
    .NumberOfRvaAndSizes        resd 1
    .DataDirectory              resq 16 * 2  ; 16 entries (RVA,Size)
endstruc
5. Protótipos de funções (ABI Windows x64 — RCX, RDX, R8, R9, shadow space 32 bytes)
Convenção: rcx, rdx, r8, r9 = args 1‑4; retorno em rax. Preservar RBX, RBP, RDI, RSI, R12‑R15.

CLI
nasm
; DexConfig *dex_parse_args(int argc, char **argv);
; Retorna ponteiro para DexConfig alocado ou NULL em erro.
global dex_parse_args

; void dex_print_help(void);
global dex_print_help
I/O
nasm
; HANDLE dex_open_read(const char *path);       ; CreateFileA GENERIC_READ
; HANDLE dex_open_write(const char *path);      ; CREATE_ALWAYS
; u64    dex_file_size(HANDLE h);               ; GetFileSizeEx
; void*  dex_mmap_read(HANDLE h, u64 size);     ; CreateFileMapping + MapViewOfFile
; void   dex_unmap(void *base);
; void   dex_write(HANDLE h, const void *buf, u64 n);
global dex_open_read, dex_open_write, dex_file_size
global dex_mmap_read, dex_unmap, dex_write
PE
nasm
; int dex_pe_load(PeImage *img, void *filebuf, u64 size);
;   retorna 0 OK, 3 se inválido. Preenche PeImage.
global dex_pe_load

; PeSection *dex_pe_find_section(PeImage *img, const char *name8);
global dex_pe_find_section

; u64 dex_rva_to_offset(PeImage *img, u32 rva);
; u32 dex_offset_to_rva(PeImage *img, u64 offset);
global dex_rva_to_offset, dex_offset_to_rva

; void dex_pe_parse_imports(PeImage *img);
; void dex_pe_parse_exports(PeImage *img);
; void dex_pe_parse_relocs (PeImage *img);
global dex_pe_parse_imports, dex_pe_parse_exports, dex_pe_parse_relocs
Disassembler
nasm
; int dex_disasm_one(PeImage *img, u64 va, Insn *out);
;   Retorna bytes consumidos (>0) ou 0 se opcode inválido.
;   Preenche *out com tudo.
global dex_disasm_one

; int dex_decode_prefixes(const u8 *p, const u8 *end, Insn *insn);
; int dex_decode_opcode  (const u8 *p, const u8 *end, Insn *insn);
; int dex_decode_modrm   (const u8 *p, const u8 *end, Insn *insn);
; int dex_decode_operands(Insn *insn);
global dex_decode_prefixes, dex_decode_opcode
global dex_decode_modrm, dex_decode_operands
Emissor NASM
nasm
; int dex_emit_insn(AsmBuf *out, Insn *insn, SymbolTable *sym);
;   Traduz Insn -> texto NASM, resolvendo labels/símbolos.
global dex_emit_insn

; int dex_emit_data(AsmBuf *out, u8 *bytes, u64 len, const char *label);
global dex_emit_data
Buffer de saída
nasm
; AsmBuf *asmbuf_new(u64 initial_cap);
; void    asmbuf_append(AsmBuf *b, const void *src, u64 n);
; void    asmbuf_append_str(AsmBuf *b, const char *s);
; void    asmbuf_append_u64(AsmBuf *b, u64 v);
; void    asmbuf_append_hex(AsmBuf *b, u64 v, int digits);
; void    asmbuf_free(AsmBuf *b);
global asmbuf_new, asmbuf_append, asmbuf_append_str
global asmbuf_append_u64, asmbuf_append_hex, asmbuf_free
Symbol table / labels
nasm
; SymbolTable *symtab_new(u32 buckets);
; Symbol *symtab_lookup(SymbolTable *t, u64 va);
; Symbol *symtab_insert(SymbolTable *t, u64 va, const char *name);
; char   *symtab_label_for(SymbolTable *t, u64 va);  ; cria se não existir
global symtab_new, symtab_lookup, symtab_insert, symtab_label_for
Rebuild
nasm
; int dex_rebuild(DexConfig *cfg);
;   1) chama nasm -f win64 -o out.obj out.asm
;   2) chama linker (link.exe /entry:... out.obj) -> out.exe
;   retorna 0 OK, 5 falha.
global dex_rebuild
6. main.asm — esqueleto
nasm
;=====================================================================
; Dexter — main.asm
; Entry point. Chama parse_args -> pe_load -> disasm loop -> writer.
;=====================================================================
bits 64
default rel

extern dex_parse_args
extern dex_print_help
extern dex_open_read, dex_file_size, dex_mmap_read, dex_unmap
extern dex_pe_load, dex_rva_to_offset
extern dex_disasm_one
extern dex_emit_insn
extern asmbuf_new, asmbuf_append_str, asmbuf_free
extern dex_rebuild
extern GetCommandLineA, ExitProcess, GetStdHandle, WriteFile

global main

section .data
    banner      db "Dexter v0.1 — Desassemblador x64", 13, 10, 0
    asm_header  db "; Gerado por Dexter — não editar manualmente", 13, 10
                db "bits 64", 13, 10
                db "default rel", 13, 10, 13, 10, 0
    err_usage   db "Uso: dexter <input.exe> [opções]  (-h para ajuda)", 13, 10, 0
    err_pe      db "ERRO: PE inválido ou não suportado.", 13, 10, 0

section .bss
    cfg         resq 1
    img         resq 1
    out_buf     resq 1
    insn        resb 256

section .text
main:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 0x40           ; shadow space + align

    ; --- 1. Parse CLI ---
    call    dex_parse_args
    test    rax, rax
    jz      .usage
    mov     [cfg], rax

    ; --- 2. Abrir e mapear input ---
    mov     rcx, [rax + DexConfig.input_path]
    call    dex_open_read
    test    rax, rax
    jz      .io_error
    mov     rbx, rax            ; HANDLE

    mov     rcx, rbx
    call    dex_file_size       ; rax = tamanho
    mov     r12, rax

    mov     rcx, rbx
    mov     rdx, r12
    call    dex_mmap_read
    test    rax, rax
    jz      .io_error
    mov     r13, rax            ; ponteiro para o PE

    ; --- 3. Carregar PE ---
    mov     rcx, img             ; (na prática alocar antes)
    ; ... chamar dex_pe_load(img, r13, r12)
    ; ... validar retorno == 0

    ; --- 4. Criar buffer de saída ---
    mov     rcx, 0x10000
    call    asmbuf_new
    mov     [out_buf], rax

    mov     rcx, rax
    lea     rdx, [asm_header]
    call    asmbuf_append_str

    ; --- 5. Loop de desassemblagem (delegar a dex_generate) ---
    ; ... chamar função de alto nível que percorre seções

    ; --- 6. Escrever .asm em disco ---
    ; ... chamar dex_file_write(cfg->output_asm, buf, len)

    ; --- 7. Rebuild opcional ---
    test    dword [cfg + DexConfig.flags], DF_REBUILD
    jz      .done
    mov     rcx, [cfg]
    call    dex_rebuild
    test    rax, rax
    jnz     .rebuild_fail

.done:
    xor     ecx, ecx
    call    ExitProcess

.usage:
    lea     rcx, [err_usage]
    ; write to stdout...
    mov     ecx, 1
    call    ExitProcess

.io_error:
    mov     ecx, 2
    call    ExitProcess

.rebuild_fail:
    mov     ecx, 5
    call    ExitProcess
7. Núcleo: disasm/decoder.asm — esqueleto
nasm
;=====================================================================
; dex_disasm_one — decodifica UMA instrução x86-64
; rcx = PeImage*, rdx = VA, r8 = Insn*
; retorna rax = bytes consumidos, ou 0 se erro
;=====================================================================
extern dex_decode_prefixes
extern dex_decode_opcode
extern dex_decode_modrm
extern dex_decode_operands

global dex_disasm_one

section .text
dex_disasm_one:
    push    rbx
    push    rdi
    push    rsi
    sub     rsp, 0x28

    mov     rbx, rcx            ; img
    mov     rsi, rdx            ; VA
    mov     rdi, r8             ; insn

    ; traduzir VA -> ponteiro real no buffer
    ; offset = rva_to_offset(VA - ImageBase)
    mov     rcx, rbx
    mov     rdx, rsi
    sub     rdx, [rbx + PeImage.image_base]
    call    dex_rva_to_offset
    test    rax, rax
    jz      .fail

    mov     r9, [rbx + PeImage.file_buffer]
    add     r9, rax              ; r9 = p (cursor)
    mov     [rdi + Insn.address], rsi

    ; 1) prefixos (atualiza p, e conta bytes)
    mov     rcx, r9
    mov     rdx, r9              ; end (ajustar)
    add     rdx, 15              ; máx. 15 bytes por instrução
    mov     r8, rdi
    call    dex_decode_prefixes
    add     r9, rax

    ; 2) opcode principal
    mov     rcx, r9
    mov     rdx, r9
    add     rdx, 15
    mov     r8, rdi
    call    dex_decode_opcode
    add     r9, rax

    ; 3) ModRM/SIB/disp (se aplicável)
    mov     rcx, r9
    mov     rdx, r9
    add     rdx, 15
    mov     r8, rdi
    call    dex_decode_modrm
    add     r9, rax

    ; 4) imediatos / offsets relativos
    mov     rcx, rdi
    call    dex_decode_operands

    ; 5) calcular tamanho total
    mov     rax, r9
    mov     rdx, [rbx + PeImage.file_buffer]
    ; + offset base
    sub     rax, rdx
    ; (omitido cálculo exato — retornar r9 - p_inicial)
    mov     rax, r9
    ; ...
    jmp     .out
.fail:
    xor     eax, eax
.out:
    add     rsp, 0x28
    pop     rsi
    pop     rdi
    pop     rbx
    ret
8. Tabela de opcodes (formato sugerido)
Em vez de switch gigante, use tabela indexada (src/disasm/opcode_tbl.asm):

nasm
; Entrada de tabela (16 bytes por opcode de 1 byte):
;   mne_ptr  (qword)  -> string do mnemônico ("mov", "add", ...)
;   flags    (dword)  -> opcode class (ver OP_*)
;   optype1  (byte)   -> TipoOp1
;   optype2  (byte)   -> TipoOp2
;   optype3  (byte)
;   len      (byte)   -> tamanho base dos imediatos
;   pad      (2 bytes)

%define OP_NONE     0
%define OP_RM_R     1       ; r/m, reg  (0x8B mov r64, r/m64)
%define OP_R_RM     2       ; reg, r/m
%define OP_R_IMM    3
%define OP_RM_IMM   4
%define OP_REL8     5
%define OP_REL32    6
%define OP_PLUS_RD  7       ; opcode + reg (ex: push r64)

section .rodata
align 16
one_byte_tbl:
    ; 0x00: add r/m8, r8
    dq s_add
    dd OP_RM_R
    db TO_RM8, TO_R8, TO_NONE, 0, 0, 0
    ; 0x01: add r/m, r
    dq s_add
    dd OP_RM_R
    db TO_RM, TO_R, TO_NONE, 0, 0, 0
    ; 0x02: add r8, r/m8
    dq s_add
    dd OP_R_RM
    db TO_R8, TO_RM8, TO_NONE, 0, 0, 0
    ; 0x03: add r, r/m
    dq s_add
    dd OP_R_RM
    db TO_R, TO_RM, TO_NONE, 0, 0, 0
    ; ... (256 entradas)
Para os 3 grandes blocos:

one_byte_tbl — 256 entradas

two_byte_tbl (prefixo 0x0F) — 256 entradas

three_byte_tbl (0x0F 0x38/0x3A) — 256 entradas cada

9. Emissor NASM (disasm/emit_nasm.asm)
Regras para saída NASM válida e reassemblável:

Elemento	Formato NASM
Instrução simples	mov rax, rbx
Memória	mov rax, [rbx+rcx*4+0x10]
Tamanho forçado	mov qword [rbx], 0x10
RIP-relativo	lea rax, [rel label_140001000]
Salto	jmp label_140001200
Call	call label_140001500
Import	call [rel __imp_ExitProcess]
Dados	db 0x48, 0x8B, 0xC3
Strings	db "hello", 0
Alinhamento	align 16
Símbolos externos são declarados:

nasm
extern ExitProcess
extern GetStdHandle
; e no rodapé:
section .idata
__imp_ExitProcess: dq ExitProcess
10. Pipeline de reassembly
Modo win64 (recomendado, funciona hoje):

text
out.asm  --[nasm -f win64 -o out.obj]--> out.obj --[link.exe]--> out.exe
Comando gerado pelo Dexter:

text
nasm.exe -f win64 -o out.obj out.asm
link.exe /nologo /subsystem:console /entry:start out.obj ^
         /out:out.exe kernel32.lib
Modo bin (purista, sem linker):

Você gera o .asm com:

nasm
org 0x140000000
bits 64
; --- cabeçalho PE escrito byte a byte ---
pe_header:
    db "MZ"
    ; ...
E usa:

text
nasm.exe -f bin -o out.exe out.asm
Isso exige que o Dexter construa o PE header no próprio asm, incluindo import directory table, reloc directory, section headers, checksum. Funciona, mas é avançado — sugira como fase 3 do roadmap.

11. Build script (build.bat)
bat
@echo off
setlocal
if not exist out mkdir out
if not exist obj mkdir obj

set NASM=nasm.exe
set SRC=src\main.asm src\cli\parse_args.asm src\cli\help.asm ^
        src\io\file_read.asm src\io\file_write.asm src\io\mmap.asm ^
        src\io\console.asm src\pe\pe_load.asm src\pe\pe_sections.asm ^
        src\pe\pe_imports.asm src\pe\pe_exports.asm src\pe\pe_relocs.asm ^
        src\pe\rva.asm src\disasm\decoder.asm src\disasm\prefixes.asm ^
        src\disasm\modrm.asm src\disasm\opcode_tbl.asm ^
        src\disasm\operands.asm src\disasm\emit_nasm.asm ^
        src\gen\asm_buffer.asm src\gen\labels.asm src\gen\symbols.asm ^
        src\gen\strings.asm src\gen\rebuild.asm ^
        src\util\memory.asm src\util\string.asm src\util\hash.asm ^
        src\util\log.asm

echo [1/2] Assembling...
for %%F in (%SRC%) do (
    %NASM% -f win64 -I include\ -o obj\%%~nF.obj %%F
    if errorlevel 1 goto :fail
)

echo [2/2] Linking...
link.exe /nologo /subsystem:console /entry:main ^
    /out:out\dexter.exe obj\*.obj kernel32.lib
if errorlevel 1 goto :fail

echo OK: out\dexter.exe
goto :eof
:fail
echo BUILD FAILED
exit /b 1
12. Roadmap de implementação (para a IA seguir)
Fase 0 — Esqueleto (1–2 dias)

Criar todas as pastas, build.bat, main.asm com ExitProcess(0).

Implementar parse_args + help funcionando.
Implementar I/O (file_read, file_write, mmap) com kernel32.

Fase 1 — PE Loader (3–5 dias)

pe_load: validar MZ, PE\0\0, 0x20B (x64).
Extrair ImageBase, EntryPoint, tabela de seções.
rva_to_offset / offset_to_rva.
Dump verbose: imprimir seções, entrypoint.

Fase 2 — Decoder básico (1–2 semanas)
Prefixos legacy (66 67 F0 F2 F3, segmentos).
Prefixo REX (40–4F).
Opcode 1 byte — ~80 mnemônicos mais comuns (mov, add, sub, jmp, call, push, pop, ret, lea, xor, cmp, test, inc, dec).
ModRM + SIB.
Emissão NASM de cada instrução.

Fase 3 — Imports/Exports/Relocs (1 semana)
Parse da Import Directory (IMAGE_IMPORT_DESCRIPTOR).
Gerar extern + __imp_X para cada import.
Parse das relocations (usado para labelar dados).

Fase 4 — Loop completo + rebuild (1 semana)
Percorrer .text linear-sweep com follow de jumps.
Gerar .asm completo com seções e cabeçalho.
Integrar com nasm.exe + link.exe.

Fase 5 — Refinamentos

2-byte opcodes (0x0F ...) incl. SSE/AVX básico.
Detecção de strings.
Modo -f bin (PE self-contained).

Testes de ida-e-volta (round-trip: app.exe -> app.asm -> app.exe comparando comportamento).

13. Testes essenciais
Criar tests/run_tests.bat:

bat
@echo off
setlocal enabledelayedexpansion
set PASS=0
set FAIL=0
for %%T in (tests\*.exe) do (
    echo === Testando %%T ===
    out\dexter.exe %%T -o tests\out\%%~nT.asm -r -O tests\out\%%~nT.exe -q
    if errorlevel 1 (
        echo   FALHA no rebuild
        set /a FAIL+=1
    ) else (
        fc /b %%T tests\out\%%~nT.exe >nul 2>&1
        if errorlevel 1 (
            echo   AVISO: bytes diferem (ok se comportamento igual)
        )
        echo   OK
        set /a PASS+=1
    )
)
echo Passaram: %PASS%  Falharam: %FAIL%
14. Observações técnicas críticas
Windows x64 ABI: sempre reservar 32 bytes de shadow space antes de call; pilha alinhada em 16 bytes.

Imports em x64 são sempre indiretos via IAT: call [rel __imp_Func]. Isso simplifica muito o reassembly.

Relocations: um .exe x64 típico não tem relocs se é carregado no ImageBase preferido. Mas para robustez, gere-o com relocs.

RIP-relativo é onipresente em x64. Seu emitter precisa detectar ModRM.mod=00 && rm=101 e resolver o alvo VA → label.

Código vs. dados: nenhum desassemblador linear-sweep é 100% correto. Espere ter que corrigir casos onde dados estão misturados ao código (tabelas jump, strings).

Assinaturas: não copie assinatura digital do original — o rebuild terá nova assinatura. Isso quebra antivírus, mas é esperado.

SEH / unwind info: x64 não usa SEH baseado em pilha, mas pdata/xdata. Se você regenerar .pdata de forma errada, exceções quebram. Comece ignorando e depois adicione.

Seções de recursos (.rsrc): apenas copie bytes brutos com db, não tente desassemblar.

Próximo passo prático
Sugiro começar pela Fase 0 + Fase 1 juntas — em ~300 linhas de NASM você tem um dexter.exe que:

Recebe argumentos

Abre e valida o PE

Imprime seções, entrypoint, image base, imports (nomes)

Escreve um .asm "esqueleto" com section vazias + extern dos imports

Isso já é uma base sólida e testável para plugar o decoder depois.

na pasta tests, tem algums arquivos .exe de exemplos que podemos usar eles como nossos trabalhos iniciais. 
------------------------------------------------------------
15. STATUS DE IMPLEMENTAÇÃO (sessão 2026-10-06, Dexter v0.2.0 — snapshot histórico; estado atual em `marco.md`/`docs/ROADMAP.md`)
Ferramenta real, testada no Windows. Build: nasm 3.01 + link 14.34.
Suíte: tests\\run_tests.bat -> 24/24 OK. Detalhe por requisito: docs/ROADMAP.md.

Estrutura de pastas/arquivos (§1):
[x] build.bat, clean.bat, README.md, docs/ (CLI/ARQUITETURA/ROADMAP + REVISAO/CHANGELOG/PE_NOTES)
[x] include/ (win64/dexter/pe/errors/macros .inc)
[x] src/cli/io/pe/disasm/gen/util (30 módulos .asm, 1 responsabilidade cada)
[x] runtime/ (templates Fase 5), tests/ (corpus + run_tests.bat), out/ obj/
[ ] tests/calc.exe, notepad.exe, tiny.exe, loop.exe, strings.exe, hello.exe, no_relocs.exe
    (corpus §8 parcial: temos hello.asm(golden), var64, var32, for.exe magic-0, link.exe)

CLI (§2):
[x] todas as flags parseadas (-o -O -m -r -L -N -s -start -end -hex -nop-pad
    -no-imports -no-relocs -strings -v -vv -q -ver -h/--help) + códigos 0/1/2/3/5
[x] exemplos do §2 executam de verdade
[ ] -m bin recusa removida: IMPLEMENTADO (era erro, agora é o path mais fiel)

Estruturas (§3) e PE (§4) e protótipos (§5): [x] todos (DexConfig/PeImage/
PeSection/Insn/ImportEntry/AsmBuf/SymbolTable + validação total de limites)

main.asm (§6): [x] dispatcher completo (parse->mmap->load->parses->verbose->
generate->rebuild) + ExitProcess com códigos

Decoder (§7): [x] LDE real + fallback db (nunca erro falso)
Tabela de opcodes (§8): [x] 1/2/38/3A + grupos + mnemônicos (buraco 0x8D achado
em teste e corrigido); [ ] VEX/EVEX/x87 (fallback db correto em bytes)

Emissor (§9): [x] db+labels+mne(+@VA com -hex); .idata copiada byte-exata
(Rewrites __imp_ desativados por decisão documentada: call [rel absolute] não monta)

Pipeline (§10):
[x] win64: nasm -f win64 + link /NODEFAULTLIB /DEBUG:NONE /SUBSYSTEM:x
    /DYNAMICBASE:NO /BASE:idem /ENTRY:label_<entry> + patch de DataDirectories
[x] bin: nasm -f bin -> byte-idêntico (hello 2560B, var64 91872B) + comportamento igual

Build script (§11): [x] com autodetect de nasm/link/kernel32.lib

Roadmap (§12):
[x] Fase 0 (esqueleto+CLI+I/O)
[x] Fase 1 (PE Loader + rva + dump verbose)
[x] Fase 2 (decoder básico + emissor; ~80+ mnemônicos via tabela)
[x] Fase 3 (imports/exports/relocs parseados; stubs __imp_ futuros)
[x] Fase 4 (loop completo + rebuild nasm+link)
[x] Fase 5 parcial (round-trip ida-e-volta PROVADO hello+var64; bin byte-fiel)
[ ] Fase 5 restante (SSE/AVX amplo, strings em code-flow, bin com imports
    regenerados, fuzz_pe.py, corpus §8 completo)

Testes (§13): [x] tests\\run_tests.bat com 24 checagens (inclui negativos que
nunca executam binário suspeito e comparação comportamental)

Observações técnicas (§14): [x] verificadas na prática —
shadow space/alinhamento (bugs reais de rdi/ret corrigidos), IAT via loader
com DataDirectory adotado, .rsrc copiada como db, .pdata aparada p/ vsize
(LNK1223), assinatura NÃO copiada (rebuild tem a própria), .reloc omitida
com -no-relocs, unwind preservado via cópia (bin) / link (win64 simples).

16. EXPANSÃO (sessão 2026-10-06 — banner + versões + corpus completo)
[x] Banner sem argumentos: Dexter disassembler Tool Version M.m.p + LabsObjects
    All rights reserved + opções da CLI, saída 0 (parse retorna 4; cobre path
    quotado e não-quotado via contador de tokens).
[x] Sistema de versão: version.bin (magic DXVB + major/minor/patch, base 1.2.3)
    + tools/bump_version.ps1 (robusto: backup .corrupt + reinit, escrita atômica,
    rollover) na pipeline build.bat [0/3] -> obj/version.inc (-I obj);
    -ver e banner dinâmicos (sem strings hardcoded).
[x] Corpus §8 expandido e 100% operacional: tiny (exit 42), loop (soma+branches),
    strings (.rdata rico), no_relocs (/FIXED sem relocs) — todos com round-trip
    win64 E bin funcionais (comportamento igual ao original).
[x] for.exe/var32/link.exe: documentados como negativos CORRETOS (Windows também
    rejeita for.exe com erro 193; 32-bit fora de escopo) — suíte os verifica (3).
[x] Suíte: tests/run_tests.bat -> 31/31 OK (banner, versão, corpus, round-trips).
17. FASE 6 — AST / LEXER / CODEGEN NATIVO (2026-10-07, R-6.1 + R-6.2 FECHADOS)
Decisão: docs/adr/0001-ast-lexer-codegen.md. Detalhe: docs/ROADMAP.md
R-6.1–R-6.6 + docs/ARQUITETURA.md (diagrama Fase 6) + docs/CLI.md
(-native real; -ast-dump real) + docs/CHANGELOG.md [Unreleased].

Onde paramos (ponto exato):
- R-6.1 FECHADO: -native (DF_NATIVE) liga dex_build_operands +
  dex_emit_native no walker com rollback+fallback db, garantia de
  tamanho exato (strict/regras de forma) e checagem de labels
  (RIP/REL->dados cai em db). Round-trip nativo provado: hello (hi),
  tiny (42), loop (55), strings, no_relocs. Suite 42/42 OK.
- R-6.2 FECHADO (+fix `_` em R-6.3): src/front/lexer.asm (dex_lex_one
  total, 17 kinds, DexToken 40 B) + tests/lex_check.asm (driver) +
  [8] na suíte: golden hello.asm = 164 tokens, 0 unknowns
  (166 antes do fix de `_` no meio do ident). Suite 46/46 OK.
- R-6.3 FECHADO em 2026-10-07: src/front/parser.asm (dex_parse_asm:
  Pass A/B/C) + src/front/ast.asm (dex_ast_* heap+free) +
  tests/ast_check.asm + [9] na suíte com goldens hello
  (1/1/18/3/1/1/8) e loop (1/5/30/9/2/0/8, CFG validado à mão).
  Fixes bloqueadores junto: div-zero ast_grow_arr (spill r9), AV
  free_unit (bi em edi), spill de m ([rbp-72]), bare db/equ +
  diretiva por tok0, imediato com sinal. Sem sondas. Suite 52/52 OK.
- R-6.5 PARCIAL em 2026-10-07: `-ast-dump` (DF_ASTDUMP + dex_ast_dump
  + hook gen_astdump_emit win64/bin; geração byte-idêntica; [10] na
  suíte). Suite 55/55 OK.
- R-6.4 FATIA 1 FECHADA em 2026-10-07: src/back/lift.asm (dex_lift_insn:
  DexIR 24 B sem heap, 8 classes + 4 tkinds, scan espelhando cs_in_code)
  + tests/lift_check.asm + [11] (goldens LIFT/TKIND). Fixes: alinhamento
  driver/lift/dump (D-10). Suite 60/60 OK.
- R-6.4 FATIA 2 FECHADA em 2026-10-07: src/back/codegen.asm
  (dex_codegen_ir com rollback) + walker via lift (oploop morto; 2a
  byte-idêntica via fc nos 5 de tests/ref_native/) + R-labels
  (symtab_to_sorted + split de dados + run-degrade; lea nativo;
  [12]/[12b]). Fixes: spill r10d, symtab_*, rel+índice, mojibake
  (D-11). Suite 75/75 OK.
- R-6.4 FATIA 3 EM ANDAMENTO, BLOQUEADA em 2026-10-07: walker emite
  `call|jmp [rel __imp_X]` + `dex_emit_imp_label` no `.idata` (drivers
  `imp_check`/`sym_check` verdes; 1 rewrite real emitido); AV em
  generate `-native` com conteúdo (db/bin intactos). Git criado
  (controle de mudanças!). Suite honesta: 67 passam, 13 falham
  ([12b]/[13], mesma raiz). Retomada em `docs/SESSAO-2026-10-07-R64.md`.
- Próximo código: fechar R-6.4.3 (caçar AV §4 da sessão), depois R-6.5
  resto (`-emit`), R-3.3/R-4.5, tag. Opção C (IR otimizável) futura.
- ATUALIZAÇÃO 2026-10-11: R-6.4.3 FECHADA (Dexter 1.2.181, suíte 95/95).
  Causa: colisão de slots `[rbp-96]`/`[rbp-100]` em `.wds_chunks`
  (fix: `img`→`[rbp-104]`); `[13]` verde, `[14]`/`[15]` criados,
  goldens `ref_native/` regenerados. Detalhe:
  `docs/SESSAO-2026-10-11-R643.md`.
- ESTADO ATUAL (2026-10-21, Dexter 1.2.415, suíte 413/413 + lenta 7/7):
  R-6.1–R-6.5, R-7.1–R-7.5, R-8.1/R-8.2 e R-5.3/R-5.4 FECHADOS; D-22,
  **D-19 fatia 2b** (import table simbólica) e **D-19 fatia 2c fix**
  (disp32 RIP relocável via `dd label - $ - 4`, REX exato, `bss` nobits)
  fechadas — `var64.exe -native -r` roda exit 0. Fila vigente em
  `marco.md` §8 / `docs/ROADMAP.md`: D-19 **2c-2** (EH C++ do GCC é pcrel;
  `exc` ainda AV em `libstdc++`, caminho fiel `-m bin`), **2c-3** (`.data`
  `vsize>raw`), base simbólica do índice em x64, VEX/EVEX/x87 e R-6.6
  (opção C). Detalhe: `docs/SESSAO-2026-10-21-D19-2C.md`.
