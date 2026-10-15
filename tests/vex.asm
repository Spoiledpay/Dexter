; vex.asm — CORPUS R-2.7: VEX/EVEX/x87/3DNow!
; FONTE SAGRADA DO CORPUS: nunca gerar .asm em cima deste arquivo!
; Comportamento: sai com exit code 42. O payload de teste fica APÓS o
; `call ExitProcess` (inalcançável) — presente em .text para o decoder,
; mas nunca executado (logo não depende de suporte AVX/x87 do host).
bits 64
default rel

global main
extern ExitProcess

section .text
main:
    sub rsp, 40                ; alinha p/ call (entry rsp%16==0 -> 8)
    mov ecx, 42
    call ExitProcess

    ; ---- payload de teste (inalcançável) ----
    ; VEX 2 bytes (C5): map 0F
    vaddps xmm1, xmm2, xmm3
    vzeroupper
    vmovups ymm0, [rax]
    ; VEX 3 bytes (C4): map 0F38 (FMA) e map 0F3A (imm8)
    vfmadd213ps ymm0, ymm1, ymm2
    vpermilps ymm0, ymm1, 0x1b
    ; EVEX (62): AVX-512
    vmovups zmm0, [rax]
    ; x87 memória
    fld dword [rax]
    fadd dword [rax]
    fmul qword [rbx]
    fild word [rcx]
    fistp dword [rdx]
    fldcw [rsi]
    ; x87 registro
    fstp st0
    fninit
    fadd st0, st1
    fxch st1
    fcmovb st0, st1
    ffree st2
    faddp st1, st0
    fucompp
    fldz
    fpatan
    fcomi st0, st1
    fnstsw ax
    ; 3DNow!
    pfadd mm0, mm1
    pfsub mm2, mm3
