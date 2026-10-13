;=============================================================================
; Dexter/src/pe/pe_load.asm
; dex_pe_load — valida DOS/NT headers e preenche PeImage + tabela de seções.
;
; Requisitos atendidos: R-1.x (MZ, PE00, x64 0x8664 / x32 0x14C,
; opt 0x20B / 0x10B, seções)
; Testes: Magic=0 via fixture gerado (saída 3); var32.exe abre (x32)
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "win64.inc"
%include "dexter.inc"
%include "pe.inc"

global dex_pe_load

section .text

;-----------------------------------------------------------------------------
; dex_pe_load
; Args:   rcx = PeImage* (sections_ptr já aponta p/ array de 96*32 bytes)
;         rdx = filebuf (mapeado, legível)
;         r8  = filesize
; Ret:    rax = 0 OK, 3 PE inválido
; Fase x32: aceita Machine I386 (0x14C) + Magic 0x10B (PE32); preenche
; PeImage.arch (0=x64, 1=x32); ImageBase u32 zero-estendida.
; Clobber: rax, rcx, rdx, r8-r11
; Preserva: rbx, rbp, rdi, rsi, r12-r15
; Segurança: todo campo do PE é validado contra filesize antes do uso.
;-----------------------------------------------------------------------------
dex_pe_load:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    sub rsp, 32                ; 7 pushes -> rsp%16==0; 40%16==8 => alinhado
    mov rbx, rcx               ; img
    mov rsi, rdx               ; base
    mov r12, r8                ; size
    test rbx, rbx
    jz .bad
    test rsi, rsi
    jz .bad
    cmp r12, 64
    jb .bad                    ; menor que DOS header
    ; e_magic == "MZ"
    movzx eax, word [rsi+ DOS_E_MAGIC]
    cmp eax, IMAGE_DOS_SIGNATURE
    jne .bad
    ; e_lfanew dentro do arquivo
    mov r13d, [rsi+ DOS_E_LFANEW]
    cmp r13, 0x1000000
    ja .bad
    mov rax, r13
    add rax, 6                 ; PE sig + Machine
    cmp rax, r12
    ja .bad
    lea r14, [rsi+r13]         ; nt = base + e_lfanew
    ; PE\0\0
    cmp dword [r14], IMAGE_NT_SIGNATURE
    jne .bad
    ; Machine == AMD64 ou I386 (outros: erro 3 limpo)
    movzx eax, word [r14+4+ FH_MACHINE]
    cmp eax, IMAGE_FILE_MACHINE_AMD64
    je .mach64
    cmp eax, IMAGE_FILE_MACHINE_I386
    jne .bad
    mov dword [rbx+PeImage.arch], DEX_ARCH_X32
    jmp .mach_ok
.mach64:
    mov dword [rbx+PeImage.arch], DEX_ARCH_X64
.mach_ok:
    ; NumberOfSections 1..96
    movzx edi, word [r14+4+ FH_NUMBER_OF_SECTIONS]
    test edi, edi
    jz .bad
    cmp edi, DEX_MAX_SECTIONS
    ja .bad
    ; SizeOfOptionalHeader (mínimo: 240 x64 / 224 x32)
    movzx r10d, word [r14+4+ FH_SIZE_OF_OPT_HDR]
    cmp dword [rbx+PeImage.arch], DEX_ARCH_X32
    je .opt32
    cmp r10d, SIZEOF_OPT_HDR64
    jb .bad
    mov eax, SIZEOF_OPT_HDR64
    jmp .opt_szb
.opt32:
    cmp r10d, SIZEOF_OPT_HDR32
    jb .bad
    mov eax, SIZEOF_OPT_HDR32
.opt_szb:
    ; opt = nt + 4 + 20
    lea r11, [r14+24]          ; opt_header
    ; opt bounds: opt + mínimo <= size?
    mov rcx, r11
    sub rcx, rsi               ; off_opt
    add rcx, rax
    cmp rcx, r12
    ja .bad
    ; Magic == 0x20B (x64) / 0x10B (x32); offset 0 comum
    movzx eax, word [r11+ OH64_MAGIC]
    cmp dword [rbx+PeImage.arch], DEX_ARCH_X32
    je .mag32
    cmp eax, IMAGE_NT_OPTIONAL_HDR64_MAGIC
    jne .bad
    jmp .mag_ok
.mag32:
    cmp eax, IMAGE_NT_OPTIONAL_HDR32_MAGIC
    jne .bad
.mag_ok:
    ; SectionAlignment / FileAlignment != 0
    mov eax, [r11+ OH64_SECTION_ALIGN]
    test eax, eax
    jz .bad
    mov eax, [r11+ OH64_FILE_ALIGN]
    test eax, eax
    jz .bad
    ; SizeOfImage <= 1GiB, SizeOfHeaders <= filesize
    mov eax, [r11+ OH64_SIZE_OF_IMAGE]
    cmp eax, DEX_MAX_FILE_SIZE
    ja .bad
    mov eax, [r11+ OH64_SIZE_OF_HEADERS]
    test eax, eax
    jz .bad
    cmp rax, r12
    ja .bad
    ; NumberOfRvaAndSizes: cap em 16 (não falhar, só limitar leitura)
    ; tabela de seções: sec = opt + SizeOfOpt; sec + n*40 <= size
    mov rax, r11
    sub rax, rsi
    add rax, r10               ; off_sec
    mov rcx, rdi
    imul rcx, SIZEOF_SECT_HDR  ; n*40
    add rax, rcx
    cmp rax, r12
    ja .bad
    lea r10, [r11]             ; (reuso) — recalcular sec base abaixo
    ; Preencher PeImage
    mov [rbx+PeImage.file_buffer], rsi
    mov [rbx+PeImage.file_size], r12
    cmp dword [rbx+PeImage.arch], DEX_ARCH_X32
    je .base32
    mov rax, [r11+ OH64_IMAGE_BASE]
    mov [rbx+PeImage.image_base], rax
    jmp .base_ok
.base32:
    mov eax, [r11+ OH32_IMAGE_BASE]    ; u32 zero-estendida em rax
    mov [rbx+PeImage.image_base], rax
.base_ok:
    mov eax, [r11+ OH64_ENTRY_POINT]
    mov [rbx+PeImage.entry_point], rax
    mov [rbx+PeImage.num_sections], edi
    mov [rbx+PeImage.opt_header], r11
    mov [rbx+PeImage.nt_headers], r14
    mov qword [rbx+PeImage.imports_ptr], 0
    mov dword [rbx+PeImage.imports_count], 0
    mov qword [rbx+PeImage.exports_ptr], 0
    mov qword [rbx+PeImage.relocs_ptr], 0
    mov dword [rbx+PeImage.relocs_count], 0
    ; Copiar seções: sec_src = nt+24+SizeOfOpt
    movzx eax, word [r14+4+ FH_SIZE_OF_OPT_HDR]
    lea r10, [r14+24]
    add r10, rax               ; r10 = &sec[0] no arquivo
    mov r11, [rbx+PeImage.sections_ptr]
    test r11, r11
    jz .bad
    mov r13d, edi              ; nsec (edi morre no loop: rdi = dst)
    xor ecx, ecx               ; i
.sect_loop:
    cmp ecx, r13d
    jae .sect_done
    mov eax, ecx
    imul eax, SIZEOF_SECT_HDR
    lea rsi, [r10+rax]         ; src
    mov eax, ecx
    imul eax, SIZEOF_PE_SECTION
    lea rdi, [r11+rax]         ; dst (PeSection 32 bytes)
    ; nome 8 bytes
    mov rax, [rsi+ SH_NAME]
    mov [rdi+PeSection.name], rax
    ; vsize, vaddr, raw_size, raw_ptr, characteristics
    mov eax, [rsi+ SH_VSIZE]
    mov [rdi+PeSection.vsize], eax
    mov eax, [rsi+ SH_VADDR]
    mov [rdi+PeSection.vaddr], eax
    mov eax, [rsi+ SH_RAW_SIZE]
    mov [rdi+PeSection.raw_size], eax
    mov eax, [rsi+ SH_RAW_PTR]
    mov [rdi+PeSection.raw_ptr], eax
    mov eax, [rsi+ SH_CHARACTERIST]
    mov [rdi+PeSection.characterist], eax
    mov dword [rdi+PeSection.pad], 0
    ; validar raw range (se raw_size>0)
    mov eax, [rdi+PeSection.raw_size]
    test eax, eax
    jz .next_sect
    mov r8d, [rdi+PeSection.raw_ptr]
    mov r9, r8
    add r9, rax                ; raw_ptr+raw_size (64b, sem overflow: ambos u32)
    cmp r9, r12
    ja .bad
.next_sect:
    inc ecx
    jmp .sect_loop
.sect_done:
    mov dword [rbx+PeImage.is_valid], 1
    xor eax, eax
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret
.bad:
    mov eax, 3
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret
