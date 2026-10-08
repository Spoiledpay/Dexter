;=============================================================================
; Dexter/runtime/pe_stub.inc
; Template do cabeçalho PE para o modo -f bin (Fase 5 do ROADMAP).
; NÃO usado pelo build atual (modo win64 via link.exe). Mantido como
; referência de engenharia para a futura emissão self-contained.
; Uso futuro: %include "runtime/pe_stub.inc" no .asm gerado com -m bin.
;=============================================================================
%ifndef DEX_PE_STUB_INC
%define DEX_PE_STUB_INC

; Parâmetros esperados (definidos pelo gerador antes do %include):
;   DEX_IMAGE_BASE  (ex: 0x140000000)
;   DEX_ENTRY_RVA   (ex: 0x1000)
;   DEX_SEC_ALIGN   (0x1000)
;   DEX_FILE_ALIGN  (0x200)

%ifndef DEX_IMAGE_BASE
%define DEX_IMAGE_BASE 0x140000000
%endif
%ifndef DEX_ENTRY_RVA
%define DEX_ENTRY_RVA 0x1000
%endif

pe_stub_dos:
    db "MZ"
    times 58 db 0
    dd pe_stub_nt - $$          ; e_lfanew (relativo ao início da imagem)
    ; NOTA Fase 5: o gerador deve emitir NT headers + section headers aqui.
    ; Este stub documenta o formato; a emissão completa vive no ROADMAP R-5.x.

%endif
