;=============================================================================
; Dexter/runtime/imports_stub.inc
; Template da Import Table para o modo -f bin (Fase 5 do ROADMAP).
; NÃO usado pelo build atual. Documenta o layout que o gerador emitirá:
;   Import Directory -> ILT/IAT (qwords) -> Hint/Name -> DLL names.
; Convenção de símbolos (futura): __imp_<Dll>_<Func>  dq <RVA>.
;=============================================================================
%ifndef DEX_IMPORTS_STUB_INC
%define DEX_IMPORTS_STUB_INC

; Exemplo de emissão futura (ilustrativo, não montado hoje):
; section .idata data
; __imp_kernel32_ExitProcess: dq RVA_ExitProcess_thunk
; iid_kernel32:
;     dd RVA_ILT_kernel32, 0, 0, RVA_dllname_kernel32, RVA_IAT_kernel32

%endif
