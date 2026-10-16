;=============================================================================
; Dexter/src/pe/pe_unwind.asm
; Parser SEH/unwind: .pdata (RUNTIME_FUNCTION) + .xdata (UNWIND_INFO).
;
; R-5.4 (SEH/unwind reemitido): este módulo DECODIFICA as estruturas de
; exceção x64 para que o emissor possa regerá-las simbolicamente (em vez de
; copiar bytes crus). Aqui não se emite nada — só leitura validada contra o
; tamanho do arquivo (campos do PE são não-confiáveis).
;
; Fonte do formato: Intel SDM + PE/COFF (RUNTIME_FUNCTION 3x u32; UNWIND_INFO:
; byte0 = version(3)|flags(5), byte1 = prolog, byte2 = count_codes, byte3 =
; frame_reg(4)|frame_off(4); depois count_codes x u16 [+pad2 se ímpar]; se
; CHAININFO -> 3 u32 (RUNTIME_FUNCTION encadeado); se EHANDLER/UHANDLER ->
; 1 u32 (RVA do handler)).
;
; Requisitos atendidos: R-5.4
; Testes: tests/unwind_check.asm ([40])
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "dexter.inc"

global dex_unwind_count
global dex_unwind_rf
global dex_unwind_info

extern dex_pe_find_section
extern dex_rva_to_offset

section .rodata
s_pdata  db ".pdata", 0
s_xdata  db ".xdata", 0

section .text

;-----------------------------------------------------------------------------
; dex_unwind_count
; Número estrutural de RUNTIME_FUNCTION em .pdata (raw_size / 12).
;
; Args:   rcx = PeImage* (ou 0)
; Ret:    rax = nº de entradas (0 se .pdata ausente/malformado)
; Clobber: rax, rcx, rdx, r8-r11
; Preserva: rbx, rbp, rdi, rsi, r12-r15
;-----------------------------------------------------------------------------
dex_unwind_count:
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 40                ; rbp+1 push -> rsp%16==8; 40 -> alinhado
    test rcx, rcx
    jz .zero
    mov rbx, rcx
    lea rdx, [rel s_pdata]
    mov rcx, rbx
    sub rsp, 32
    call dex_pe_find_section
    add rsp, 32
    test rax, rax
    jz .zero
    mov eax, [rax+PeSection.raw_size]
    xor edx, edx
    mov ecx, SIZEOF_RUNTIME_FUNCTION
    div ecx                    ; eax = count; resto (tail parcial) ignorado
    add rsp, 40
    pop rbx
    pop rbp
    ret
.zero:
    xor eax, eax
    add rsp, 40
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; dex_unwind_rf
; Lê uma RUNTIME_FUNCTION de índice edx da .pdata.
;
; Args:   rcx = PeImage*; edx = índice; r8 = RuntimeFunction* (12 B; zero se
;         índice inválido)
; Ret:    rax = 0 ok, 1 inválido/fora
; Clobber: rax, rcx, rdx, r8-r11
; Preserva: rbx, rbp, rdi, rsi, r12-r15
;-----------------------------------------------------------------------------
dex_unwind_rf:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 32                ; rbp+4 pushes -> rsp%16==0
    test rcx, rcx
    jz .bad
    test r8, r8
    jz .bad
    mov rbx, rcx
    mov r12d, edx              ; idx
    mov r13, r8                ; out
    ; zera a saída
    xor eax, eax
    mov [r13+0], rax
    mov dword [r13+8], 0
    lea rdx, [rel s_pdata]
    mov rcx, rbx
    sub rsp, 32
    call dex_pe_find_section
    add rsp, 32
    test rax, rax
    jz .bad
    mov r14, rax               ; PeSection* .pdata
    mov eax, [r14+PeSection.raw_size]
    xor edx, edx
    mov ecx, SIZEOF_RUNTIME_FUNCTION
    div ecx
    cmp r12d, eax
    jae .bad                   ; fora (>= count)
    mov rax, [rbx+PeImage.file_buffer]
    mov ecx, [r14+PeSection.raw_ptr]
    add rax, rcx
    mov ecx, r12d
    imul ecx, SIZEOF_RUNTIME_FUNCTION
    add rax, rcx               ; p = &rf[idx]
    mov ecx, [rax]
    mov [r13+RuntimeFunction.begin], ecx
    mov ecx, [rax+4]
    mov [r13+RuntimeFunction.end], ecx
    mov ecx, [rax+8]
    mov [r13+RuntimeFunction.unwind], ecx
    xor eax, eax
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.bad:
    mov eax, 1
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; dex_unwind_info
; Decodifica um UNWIND_INFO a partir de uma RVA (edx) que cai na .xdata.
;
; Args:   rcx = PeImage*; edx = RVA do UNWIND_INFO; r8 = UnwindInfo* (zero
;         em caso de erro)
; Ret:    rax = 0 ok, 1 rva inválida/estrutura fora do arquivo
; Clobber: rax, rcx, rdx, r8-r11
; Preserva: rbx, rbp, rdi, rsi, r12-r15
;-----------------------------------------------------------------------------
dex_unwind_info:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 32
    test rcx, rcx
    jz .bad
    test r8, r8
    jz .bad
    mov rbx, rcx
    mov r12d, edx              ; xrva
    mov r13, r8                ; out
    xor eax, eax
    mov [r13+0], rax
    mov [r13+8], rax
    mov dword [r13+16], eax
    mov rcx, rbx
    mov edx, r12d
    sub rsp, 32
    call dex_rva_to_offset
    add rsp, 32
    test rax, rax
    jz .bad
    mov r14, rax               ; off
    ; cabe o header no arquivo? off+4 <= file_size
    mov rcx, [rbx+PeImage.file_size]
    mov rdx, r14
    add rdx, 4
    cmp rdx, rcx
    ja .bad
    mov rdx, [rbx+PeImage.file_buffer]
    add rdx, r14               ; p
    movzx eax, byte [rdx]      ; version|flags
    mov ecx, eax
    and eax, 7
    mov [r13+UnwindInfo.version], al
    mov eax, ecx
    shr eax, 3
    and eax, 0x1F
    mov [r13+UnwindInfo.flags], al
    movzx eax, byte [rdx+1]
    mov [r13+UnwindInfo.prolog], al
    movzx eax, byte [rdx+2]    ; count_codes
    mov [r13+UnwindInfo.ncodes], al
    movzx ecx, byte [rdx+3]
    mov eax, ecx
    and eax, 0x0F
    mov [r13+UnwindInfo.framereg], al
    shr ecx, 4
    mov [r13+UnwindInfo.frameoff], cl
    ; total = 4 (header) + ncodes*2 + (ncodes&1 ? 2) + rvacnt*4
    movzx ecx, byte [r13+UnwindInfo.ncodes]
    mov eax, ecx
    shl eax, 1                 ; codes bytes
    test cl, 1
    jz .nopad
    add eax, 2                 ; padding (alinhamento 4)
.nopad:
    add eax, 4                 ; header
    mov dword [r13+UnwindInfo.rvacnt], 0
    mov dword [r13+UnwindInfo.rvaoff], -1
    movzx ecx, byte [r13+UnwindInfo.flags]
    test ecx, UNW_FLAG_CHAININFO
    jz .chk_handler
    mov dword [r13+UnwindInfo.rvacnt], 3
    mov [r13+UnwindInfo.rvaoff], eax
    add eax, 12
    jmp .settotal
.chk_handler:
    test ecx, UNW_FLAG_EHANDLER|UNW_FLAG_UHANDLER
    jz .settotal
    mov dword [r13+UnwindInfo.rvacnt], 1
    mov [r13+UnwindInfo.rvaoff], eax
    add eax, 4
.settotal:
    mov [r13+UnwindInfo.total], eax
    ; off + total <= file_size
    mov rdx, r14
    mov ecx, eax               ; zero-estende total
    add rdx, rcx
    mov rcx, [rbx+PeImage.file_size]
    cmp rdx, rcx
    ja .bad
    xor eax, eax
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.bad:
    mov eax, 1
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
