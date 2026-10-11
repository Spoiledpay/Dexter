;=============================================================================
; Dexter/src/cli/help.asm
; dex_print_help / dex_print_version.
;
; Requisitos atendidos: Projeto.md §2 (CLI -h/-ver)
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "dexter.inc"

global dex_print_help
global dex_print_version
global dex_print_banner

extern dex_console_print_cstr
extern dex_console_print_u64dec

section .rodata
s_banner_pre db "Dexter disassembler Tool Version ", 0
s_dot        db ".", 0
s_banner_post db 13, 10, "LabsObjects All rights reserved", 13, 10, 0
s_help_txt:
    db "Desassemblador/Reassemblador x64 nativo (NASM/Windows)", 13, 10
    db "Uso: dexter <input.exe> [opcoes]", 13, 10
    db 13, 10
    db "Saida:", 13, 10
    db "  -o <arquivo.asm>       Fonte NASM gerada        (padrao: <input>.asm)", 13, 10
    db "  -O <arquivo.exe>       Caminho do .exe reassemblado (implica -r)", 13, 10
    db "  -m <modo>              win64 | bin              (padrao: win64)", 13, 10
    db "  -r                     Reassemblar apos gerar o .asm", 13, 10
    db "  -L <linker>            Caminho do linker        (padrao: C:\Nasm\link.exe)", 13, 10
    db "  -N <nasm>              Caminho do nasm.exe      (padrao: C:\Nasm\nasm.exe)", 13, 10
    db 13, 10
    db "Controle de desassemblagem:", 13, 10
    db "  -s <nome_secao>        So desassemblar uma secao (.text, ...)", 13, 10
    db "  -start <RVA>           Endereco inicial (hex, ex: 0x1000)", 13, 10
    db "  -end   <RVA>           Endereco final", 13, 10
    db "  -hex                   Emite bytes originais como comentario", 13, 10
    db "  -nop-pad               Preenche gaps com NOPs", 13, 10
    db "  -no-imports            Nao gera stubs de imports", 13, 10
    db "  -no-relocs             Ignora tabela de relocations", 13, 10
    db "  -strings               Detecta strings e cria bloco db", 13, 10
    db "  -native                Emite mnemonicos reais (fallback db)", 13, 10
    db "  -ast-dump              Imprime resumo AST do .asm em stdout", 13, 10
    db "  -overview              Resumo do PE em stdout (inspect-only)", 13, 10
    db "  -json                  Com -overview: saida JSON maquina", 13, 10
    db 13, 10
    db "Diagnostico:", 13, 10
    db "  -v                     Verbose (nivel 1)", 13, 10
    db "  -vv                    Verbose (nivel 2 — dump de tabelas)", 13, 10
    db "  -q                     Silencioso", 13, 10
    db "  -ver                   Mostra versao", 13, 10
    db "  -h, --help             Esta ajuda", 13, 10
    db 13, 10
    db "Codigos de retorno: 0 ok | 1 uso | 2 I/O | 3 PE invalido | 4 opcode | 5 rebuild", 13, 10
    db 13, 10
    db "Exemplos:", 13, 10
    db "  dexter.exe app.exe -o app.asm -hex -v", 13, 10
    db "  dexter.exe app.exe -o app.asm -r -O app_rebuild.exe", 13, 10
    db 0

section .text

;-----------------------------------------------------------------------------
; dex_print_banner — "Dexter disassembler Tool Version M.m.p" + CRLF +
; "LabsObjects All rights reserved" + CRLF (versão via version.inc).
;-----------------------------------------------------------------------------
dex_print_banner:
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 40
    lea rcx, [rel s_banner_pre]
    call dex_console_print_cstr
    mov ecx, DEX_VER_MAJOR
    call dex_console_print_u64dec
    lea rcx, [rel s_dot]
    call dex_console_print_cstr
    mov ecx, DEX_VER_MINOR
    call dex_console_print_u64dec
    lea rcx, [rel s_dot]
    call dex_console_print_cstr
    mov ecx, DEX_VER_PATCH
    call dex_console_print_u64dec
    lea rcx, [rel s_banner_post]
    call dex_console_print_cstr
    add rsp, 40
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; dex_print_help — imprime ajuda em stdout.
;-----------------------------------------------------------------------------
dex_print_help:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    lea rcx, [rel s_help_txt]
    call dex_console_print_cstr
    add rsp, 32
    pop rbp
    ret

;-----------------------------------------------------------------------------
; dex_print_version — mesma linha de versão do banner.
;-----------------------------------------------------------------------------
dex_print_version:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    call dex_print_banner
    add rsp, 32
    pop rbp
    ret
