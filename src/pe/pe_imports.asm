;=============================================================================
; Dexter/src/pe/pe_imports.asm
; dex_pe_parse_imports — percorre o Import Directory e preenche vetor de
; ImportEntry { dll_name, func_name, ordinal, iat_rva }.
; Ponteiros de nome apontam para dentro do file_buffer (válido enquanto
; o arquivo estiver mapeado). Degradação graciosa: diretório ausente ou
; corrompido => count 0 (sem imports), nunca crasha.
;
; Requisitos atendidos: R-3.x
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "win64.inc"
%include "dexter.inc"
%include "pe.inc"

global dex_pe_parse_imports

extern dex_rva_to_offset
extern dex_malloc
extern dex_free

section .text

;-----------------------------------------------------------------------------
; dex_pe_parse_imports
; Args:   rcx = PeImage* (já validado por dex_pe_load)
; Ret:    rax = nº de imports (0 = nenhum/indisponível)
;-----------------------------------------------------------------------------
dex_pe_parse_imports:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 88                ; 8 pushes -> rsp%16==8; 56%16==8 => alinhado
    test rcx, rcx
    jz .zero
    mov rbx, rcx               ; img
    mov rsi, [rbx+PeImage.file_buffer]
    test rsi, rsi
    jz .zero
    mov r12, [rbx+PeImage.file_size]
    mov rax, [rbx+PeImage.opt_header]
    test rax, rax
    jz .zero
    mov ecx, [rax+ OH64_NUM_RVA_SIZES]
    cmp ecx, 2
    jb .zero
    mov ecx, [rax+ OH64_DATA_DIR + 8*1]      ; import rva
    mov edx, [rax+ OH64_DATA_DIR + 8*1 + 4]  ; import size
    test ecx, ecx
    jz .zero
    test edx, edx
    jz .zero
    ; off_desc = rva_to_offset(img, ecx)
    mov r14d, ecx
    mov rcx, rbx
    mov edx, r14d
    sub rsp, 32
    call dex_rva_to_offset
    add rsp, 32
    test rax, rax
    jz .zero
    mov rdi, rax               ; desc_off
    ; validar que cabe ao menos o terminador
    mov rax, rdi
    add rax, SIZEOF_IMPORT_DESC
    cmp rax, r12
    ja .zero
    ; ---- passada 1a: contar descriptors (sem calls) ----
    xor r14d, r14d             ; n_desc
.cdesc:
    cmp r14d, 256
    jae .cdesc_done
    mov eax, r14d
    imul eax, SIZEOF_IMPORT_DESC
    add rax, rdi
    add rax, SIZEOF_IMPORT_DESC
    cmp rax, r12
    ja .cdesc_done
    mov eax, r14d
    imul eax, SIZEOF_IMPORT_DESC
    add rax, rdi
    add rax, rsi     ; &desc[i] — ATENÇÃO: rsi+rdi+rax (base+off+i*20)
    mov ecx, [rax+ IID_ORIG_FIRST_THUNK]
    or ecx, [rax+ IID_TIME_DATE]
    or ecx, [rax+ IID_FORWARDER]
    or ecx, [rax+ IID_NAME]
    or ecx, [rax+ IID_FIRST_THUNK]
    jz .cdesc_done
    inc r14d
    jmp .cdesc
.cdesc_done:
    test r14d, r14d
    jz .zero
    ; ---- passada 1b: contar thunks ----
    xor r13d, r13d             ; total
    xor r10d, r10d             ; di
.cth:
    cmp r10d, r14d
    jae .cth_done
    mov eax, r10d
    imul eax, SIZEOF_IMPORT_DESC
    add rax, rdi
    add rax, rsi     ; &desc (rsi=base, rdi=desc_off)
    mov ecx, [rax+ IID_ORIG_FIRST_THUNK]
    test ecx, ecx
    jnz .have_thunk_rva
    mov ecx, [rax+ IID_FIRST_THUNK]
.have_thunk_rva:
    test ecx, ecx
    jz .cth_next
    mov r9d, ecx               ; thunk_rva (rcx morre abaixo)
    mov [rbp-124], r10d        ; spill di (r10 morre no call)
    mov rcx, rbx
    mov edx, r9d
    sub rsp, 32
    call dex_rva_to_offset
    add rsp, 32
    mov r10d, [rbp-124]        ; restore di
    test rax, rax
    jz .cth_next
    mov rcx, rax               ; off_int
.walk:
    mov rdx, rcx
    add rdx, 8
    cmp rdx, r12
    ja .cth_next
    cmp qword [rsi+rcx], 0
    je .cth_next
    inc r13d
    cmp r13d, DEX_MAX_IMPORTS
    jae .cth_done
    add rcx, 8
    jmp .walk
.cth_next:
    inc r10d
    jmp .cth
.cth_done:
    test r13d, r13d
    jz .zero
    ; ---- alocar vetor ----
    mov eax, r13d
    shl eax, 5                 ; *32
    mov rcx, rax
    sub rsp, 32
    call dex_malloc
    add rsp, 32
    test rax, rax
    jz .zero
    mov r15, rax               ; vec
    ; ---- passada 2: preencher ----
    xor r10d, r10d             ; di
    xor r11d, r11d             ; vi
.fill:
    cmp r10d, r14d
    jae .fill_done
    cmp r11d, r13d
    jae .fill_done
    mov eax, r10d
    imul eax, SIZEOF_IMPORT_DESC
    add rax, rdi
    add rax, rsi     ; &desc
    mov ecx, [rax+ IID_FIRST_THUNK]       ; iat_base
    mov edx, [rax+ IID_ORIG_FIRST_THUNK]  ; int_rva (0 => usa iat)
    test edx, edx
    jnz .int_ok2
    mov edx, ecx
.int_ok2:
    mov [rbp-88], ecx          ; iat_base
    mov [rbp-104], edx         ; int_rva
    mov r8d, [rax+ IID_NAME]
    mov [rbp-80], r8d          ; name_rva
    mov [rbp-124], r11d        ; spill vi (r11 morre nos calls abaixo)
    test edx, edx
    jz .fill_next
    ; dll_off = rva_to_offset(img, name_rva)
    mov rcx, rbx
    mov edx, [rbp-80]
    sub rsp, 32
    call dex_rva_to_offset
    add rsp, 32
    test rax, rax
    jz .fill_next
    ; dll = bounded_cstr(base, dll_off, size)
    mov rcx, rsi
    mov edx, eax
    mov r8, r12
    sub rsp, 32
    call .bounded_cstr
    add rsp, 32
    test rax, rax
    jz .fill_next
    mov [rbp-96], rax          ; dll
    ; int_off = rva_to_offset(img, int_rva)
    mov rcx, rbx
    mov edx, [rbp-104]
    sub rsp, 32
    call dex_rva_to_offset
    add rsp, 32
    test rax, rax
    jz .fill_next
    mov [rbp-112], rax         ; int_off
    mov r11d, [rbp-124]        ; restore vi
    mov [rbp-72], r10d         ; spill di
    xor r9d, r9d               ; k
.thunk2:
    mov rcx, [rbp-112]
    mov eax, r9d
    shl rax, 3
    add rcx, rax               ; off_thunk
    mov rdx, rcx
    add rdx, 8
    cmp rdx, r12
    jae .thunk_end
    mov rax, [rsi+rcx]         ; thunk u64
    test rax, rax
    jz .thunk_end
    cmp r11d, r13d
    jae .thunk_end
    mov ecx, r11d
    shl ecx, 5
    lea r10, [r15+rcx]         ; entry (r10 livre: di está em [rbp-72])
    mov rcx, [rbp-96]
    mov [r10+0], rcx           ; dll_name
    mov rdx, rax
    shr rdx, 63                ; bit63
    test edx, edx
    jz .byname2
    mov qword [r10+8], 0       ; func_name = NULL
    mov [r10+16], ax           ; ordinal (low16)
    mov byte [r10+18], 1
    jmp .iat2
.byname2:
    ; spill k/vi (r9/r11 são voláteis e morrem nos calls abaixo)
    mov [rbp-116], r9d
    mov [rbp-120], r11d
    mov rcx, rbx
    mov edx, eax
    sub rsp, 32
    call dex_rva_to_offset
    add rsp, 32
    test rax, rax
    jz .skip_restore
    add rax, 2
    cmp rax, r12
    jae .skip_restore
    mov rcx, rsi
    mov edx, eax
    mov r8, r12
    sub rsp, 32
    call .bounded_cstr
    add rsp, 32
    test rax, rax
    jz .skip_restore
    mov r9d, [rbp-116]
    mov r11d, [rbp-120]
    mov ecx, r11d
    shl ecx, 5
    lea r10, [r15+rcx]         ; rederiva entry (r10 morreu nos calls)
    mov [r10+8], rax           ; func_name
    mov word [r10+16], 0
    mov byte [r10+18], 0
.iat2:
    mov eax, [rbp-88]          ; iat_base_rva
    mov ecx, r9d
    shl rcx, 3
    add rax, rcx
    mov [r10+24], eax          ; iat_rva
    mov dword [r10+28], 0
    inc r11d
    jmp .thunk_next
.skip_restore:
    mov r9d, [rbp-116]
    mov r11d, [rbp-120]
    jmp .thunk_next
.thunk_next:
    inc r9d
    cmp r9d, 4096
    jae .thunk_end
    jmp .thunk2
.thunk_end:
    mov r10d, [rbp-72]         ; restore di
.fill_next:
    inc r10d
    jmp .fill
.fill_done:
    mov [rbx+PeImage.imports_ptr], r15
    mov [rbx+PeImage.imports_count], r11d
    mov eax, r11d
    add rsp, 88
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret
.zero:
    xor eax, eax
    add rsp, 88
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; .bounded_cstr (interna)
; Args: rcx=base, edx=rva_ou_off? AQUI: off (já convertido), r8=filesize
; Ret: rax = ptr (base+off) ou 0 se sem NUL em 256 bytes / OOB
; NOTA: recebe OFFSET (não RVA).
;-----------------------------------------------------------------------------
.bounded_cstr:
    push rbx
    mov rbx, rcx               ; base
    mov eax, edx               ; off
    mov rcx, r8                ; size
    cmp rax, rcx
    jae .bc_no
    xor r8d, r8d               ; i
.bc_l:
    cmp r8d, 256
    jae .bc_no
    mov rdx, rax
    add rdx, r8
    cmp rdx, rcx
    jae .bc_no
    cmp byte [rbx+rdx], 0
    je .bc_yes
    inc r8d
    jmp .bc_l
.bc_yes:
    lea rax, [rbx+rax]
    pop rbx
    ret
.bc_no:
    xor eax, eax
    pop rbx
    ret
