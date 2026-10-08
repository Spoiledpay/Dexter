;=============================================================================
; Dexter/include/errors.inc
; Códigos de erro e de saída do Dexter.
;
; Requisitos atendidos: CLI (códigos de retorno 0-5)
; Testes: tests/run_tests.bat (verifica exit codes)
; Autor: Dexter Engineer
;=============================================================================
%ifndef DEX_ERRORS_INC
%define DEX_ERRORS_INC

; ---- Exit codes públicos (CLI) ----
%define EXIT_OK         0
%define EXIT_USAGE      1
%define EXIT_IO         2
%define EXIT_PE         3
%define EXIT_OPCODE     4
%define EXIT_REBUILD    5

; ---- Erros internos (rax de funções) ----
%define ERR_OK          0
%define ERR_USAGE       1
%define ERR_IO          2
%define ERR_PE          3
%define ERR_OPCODE      4
%define ERR_REBUILD     5
%define ERR_OOM         6
%define ERR_OVERFLOW    7
%define ERR_ARGS        8

; ---- Limites de segurança ----
%define DEX_MAX_FILE_SIZE    0x40000000   ; 1 GiB
%define DEX_MAX_SECTIONS     96
%define DEX_MAX_IMPORTS      4096
%define DEX_MAX_RELOCS       65536
%define DEX_MAX_INSN_LEN     15

%endif ; DEX_ERRORS_INC
