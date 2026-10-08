;=============================================================================
; Dexter/include/macros.inc
; Macros utilitárias. Convenção: preservam registradores salvo documentado.
;=============================================================================
%ifndef DEX_MACROS_INC
%define DEX_MACROS_INC

; Reserva shadow space + alinhamento para 1 call (uso simples).
; Uso: PROLOGUE 0x28  ... EPILOGUE 0x28
%macro PROLOGUE 1
    push rbp
    mov rbp, rsp
    sub rsp, %1
%endmacro

%macro EPILOGUE 1
    add rsp, %1
    pop rbp
%endmacro

; Aloca 32 bytes de shadow antes de call externo (caller deve ter rsp%16==8
; após pushes — este projeto usa frames que garantem alinhamento).
%macro SHADOW_ALLOC 0
    sub rsp, 32
%endmacro

%macro SHADOW_FREE 0
    add rsp, 32
%endmacro

%macro CLEAR_REG 1
    xor %1, %1
%endmacro

%endif
