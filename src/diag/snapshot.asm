;=============================================================================
; Dexter/src/diag/snapshot.asm
; dex_snapshot â€” fingerprint JSON de um binÃ¡rio em arquivo (FNV-1a 64 +
; size + layout PE). Write-only nesta fase (R-7.4, marco.md).
;
; O quÃª: calcula FNV-1a dos bytes mapeados e grava JSON com size, base,
;  entry, seÃ§Ãµes e imports (mesmas chaves do -overview mais size/fnv1a).
; Por quÃª: fingerprint compacto e estÃ¡vel p/ detecÃ§Ã£o de mudanÃ§a
;  (snapshots estilo REA); FNV-1a documentado como NÃƒO-criptogrÃ¡fico.
; Contrato:
;   Args: rcx = DexConfig* (snapshot_path vÃ¡lido), rdx = PeImage*.
;   Ret:  eax = 0 ok | 2 I/O ou OOM (mensagem do chamador via cÃ³digo).
;   Sem I/O alÃ©m do arquivo destino; sem heap alÃ©m do AsmBuf (liberado).
;   Clobber: rax, rcx, rdx, r8-r11.
;   Preserva: rbx, rbp, rdi, rsi, r12-r15.
; Como testar: tests\run_tests.bat seÃ§Ã£o [19] (+ validaÃ§Ã£o JSON real).
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "dexter.inc"

global dex_snapshot

extern dex_fnv1a
extern dex_u64_to_dec
extern asmbuf_new
extern asmbuf_append
extern asmbuf_append_str
extern asmbuf_append_char
extern asmbuf_append_u64_hex
extern asmbuf_data
extern asmbuf_len
extern asmbuf_free
extern dex_open_write
extern dex_write_all
extern dex_close

section .rodata
s_s_open     db '{"tool":"dexter","version":"', 0
s_s_dot      db ".", 0
s_s_size     db '","size":', 0
s_s_fnv      db ',"fnv1a":"0x', 0
s_s_base     db '","image_base":"0x', 0
s_s_entry    db '","entry_rva":"0x', 0
s_s_nsec     db '","num_sections":', 0
s_s_secs     db ',"sections":[', 0
s_s_sopen    db '{"name":"', 0
s_s_sva      db '","vaddr":"0x', 0
s_s_svsz     db '","vsize":"0x', 0
s_s_sraw     db '","raw_size":"0x', 0
s_s_sclose   db '"}', 0
s_s_comma    db ",", 0
s_s_secs_e   db "],", 0
s_s_nimp     db '"imports_count":', 0
s_s_imps     db ',"imports":[', 0
s_s_iopen    db '{"dll":"', 0
s_s_ifunc    db '","func":"', 0
s_s_iord     db '","ordinal":', 0
s_s_iordb    db ',"is_ordinal":', 0
s_s_iiat     db ',"iat_rva":"0x', 0
s_s_iclose   db '"}', 0
s_s_imps_e   db "],", 0
s_s_exp      db '"exports_count":', 0
s_s_rel      db ',"relocs_count":', 0
s_s_close    db "}", 0

section .text

;-----------------------------------------------------------------------------
; dex_snapshot â€” rcx=cfg, rdx=img -> eax=0 | 2.
; Frame: 8 pushes + sub 328 = 392. jtmp [rbp-384]=[RSP]; buf [-72],
; handle [-80], hash [-88]; dectmp [rbp-120,rbp-88).
;-----------------------------------------------------------------------------
dex_snapshot:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15                     ; 8 pushes (64B) + sub 328 = 392
    sub rsp, 328
    mov rbx, rcx                 ; cfg
    mov r15, rdx                 ; img
    mov qword [rbp-72], 0        ; buf (0 = sem buf; .oom_free Ã© NULL-safe)
    mov qword [rbp-80], 0        ; handle (0 = fechado)
    mov rax, [rbx+DexConfig.snapshot_path]
    test rax, rax
    jz .oom_free                 ; sem destino (sÃ³ via chamada direta)
    ; hash = fnv1a(file_buffer, file_size)
    mov rcx, [r15+PeImage.file_buffer]
    mov rdx, [r15+PeImage.file_size]
    sub rsp, 32
    call dex_fnv1a
    add rsp, 32
    mov [rbp-88], rax            ; hash
    mov ecx, 65536
    sub rsp, 32
    call asmbuf_new
    add rsp, 32
    test rax, rax
    jz .oom_free2
    mov [rbp-72], rax            ; buf
    ; ---- emite JSON no buffer ----
    lea rdx, [rel s_s_open]
    mov rcx, [rbp-72]
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .oom_free
    mov ecx, DEX_VER_MAJOR
    call .s_dec
    test eax, eax
    jnz .oom_free
    lea rdx, [rel s_s_dot]
    call .s_str
    test eax, eax
    jnz .oom_free
    mov ecx, DEX_VER_MINOR
    call .s_dec
    test eax, eax
    jnz .oom_free
    lea rdx, [rel s_s_dot]
    call .s_str
    test eax, eax
    jnz .oom_free
    mov ecx, DEX_VER_PATCH
    call .s_dec
    test eax, eax
    jnz .oom_free
    lea rdx, [rel s_s_size]
    call .s_str
    test eax, eax
    jnz .oom_free
    mov rcx, [r15+PeImage.file_size]
    call .s_dec
    test eax, eax
    jnz .oom_free
    lea rdx, [rel s_s_fnv]
    call .s_str
    test eax, eax
    jnz .oom_free
    mov rcx, [rbp-88]
    xor edx, edx
    call .s_hex
    test eax, eax
    jnz .oom_free
    lea rdx, [rel s_s_base]
    call .s_str
    test eax, eax
    jnz .oom_free
    mov rcx, [r15+PeImage.image_base]
    xor edx, edx
    call .s_hex
    test eax, eax
    jnz .oom_free
    lea rdx, [rel s_s_entry]
    call .s_str
    test eax, eax
    jnz .oom_free
    mov rcx, [r15+PeImage.entry_point]
    xor edx, edx
    call .s_hex
    test eax, eax
    jnz .oom_free
    lea rdx, [rel s_s_nsec]
    call .s_str
    test eax, eax
    jnz .oom_free
    mov ecx, [r15+PeImage.num_sections]
    call .s_dec
    test eax, eax
    jnz .oom_free
    lea rdx, [rel s_s_secs]
    call .s_str
    test eax, eax
    jnz .oom_free
    mov r12d, [r15+PeImage.num_sections]
    mov r13, [r15+PeImage.sections_ptr]
    xor r14d, r14d
.s_sec:
    cmp r14d, r12d
    jae .s_secs_e
    test r14d, r14d
    jz .s_sec0
    lea rdx, [rel s_s_comma]
    call .s_str
    test eax, eax
    jnz .oom_free
.s_sec0:
    mov eax, r14d
    imul eax, SIZEOF_PE_SECTION
    lea rsi, [r13+rax]           ; sec (rsi livre? rsi non-vol intacto aqui)
    lea rdx, [rel s_s_sopen]
    call .s_str
    test eax, eax
    jnz .oom_free
    mov eax, r14d                ; re-resolve: rsi morreu na call acima
    imul eax, SIZEOF_PE_SECTION
    lea rsi, [r13+rax]
    lea rdi, [rbp-384]           ; jtmp
    mov rax, [rsi+PeSection.name]
    mov [rdi], rax
    mov byte [rdi+8], 0
    mov rdx, rdi
    call .s_str
    test eax, eax
    jnz .oom_free
    lea rdx, [rel s_s_sva]
    call .s_str
    test eax, eax
    jnz .oom_free
    mov eax, r14d                ; re-resolve: rsi morreu na call acima
    imul eax, SIZEOF_PE_SECTION
    lea rsi, [r13+rax]
    mov ecx, [rsi+PeSection.vaddr]
    xor edx, edx
    call .s_hex
    test eax, eax
    jnz .oom_free
    lea rdx, [rel s_s_svsz]
    call .s_str
    test eax, eax
    jnz .oom_free
    mov eax, r14d                ; re-resolve: rsi morreu na call acima
    imul eax, SIZEOF_PE_SECTION
    lea rsi, [r13+rax]
    mov ecx, [rsi+PeSection.vsize]
    xor edx, edx
    call .s_hex
    test eax, eax
    jnz .oom_free
    lea rdx, [rel s_s_sraw]
    call .s_str
    test eax, eax
    jnz .oom_free
    mov eax, r14d                ; re-resolve: rsi morreu na call acima
    imul eax, SIZEOF_PE_SECTION
    lea rsi, [r13+rax]
    mov ecx, [rsi+PeSection.raw_size]
    xor edx, edx
    call .s_hex
    test eax, eax
    jnz .oom_free
    lea rdx, [rel s_s_sclose]
    call .s_str
    test eax, eax
    jnz .oom_free
    inc r14d
    jmp .s_sec
.s_secs_e:
    lea rdx, [rel s_s_secs_e]
    call .s_str
    test eax, eax
    jnz .oom_free
    lea rdx, [rel s_s_nimp]
    call .s_str
    test eax, eax
    jnz .oom_free
    mov ecx, [r15+PeImage.imports_count]
    call .s_dec
    test eax, eax
    jnz .oom_free
    lea rdx, [rel s_s_imps]
    call .s_str
    test eax, eax
    jnz .oom_free
    mov r12d, [r15+PeImage.imports_count]
    mov r13, [r15+PeImage.imports_ptr]
    xor r14d, r14d
.s_imp:
    cmp r14d, r12d
    jae .s_imps_e
    test r14d, r14d
    jz .s_imp0
    lea rdx, [rel s_s_comma]
    call .s_str
    test eax, eax
    jnz .oom_free
.s_imp0:
    mov eax, r14d
    imul eax, SIZEOF_IMPORT_ENTRY
    lea rsi, [r13+rax]           ; entry
    lea rdx, [rel s_s_iopen]
    call .s_str
    test eax, eax
    jnz .oom_free
    mov eax, r14d                ; re-resolve: rsi morreu na call acima
    imul eax, SIZEOF_IMPORT_ENTRY
    lea rsi, [r13+rax]
    mov rsi, [rsi+ImportEntry.dll_name]
    lea rdi, [rbp-384]
    mov edx, 255
    call .s_esc                  ; dll c/ escape (leaf, sem calls)
    lea rdx, [rbp-384]           ; início (rdi avançou até o NUL)
    call .s_str
    test eax, eax
    jnz .oom_free
    lea rdx, [rel s_s_ifunc]
    call .s_str
    test eax, eax
    jnz .oom_free
    ; func (ou "" se ordinal): re-resolve a entry (determinÃ­stico)
    mov eax, r14d
    imul eax, SIZEOF_IMPORT_ENTRY
    lea rsi, [r13+rax]
    cmp byte [rsi+ImportEntry.is_ordinal], 0
    jne .s_imp_nof
    mov rsi, [rsi+ImportEntry.func_name]
    lea rdi, [rbp-384]
    mov edx, 255
    call .s_esc
    lea rdx, [rbp-384]           ; início (rdi avançou até o NUL)
    call .s_str
    test eax, eax
    jnz .oom_free
.s_imp_nof:
    lea rdx, [rel s_s_iord]
    call .s_str
    test eax, eax
    jnz .oom_free
    mov eax, r14d
    imul eax, SIZEOF_IMPORT_ENTRY
    lea rsi, [r13+rax]
    movzx ecx, word [rsi+ImportEntry.ordinal]
    call .s_dec
    test eax, eax
    jnz .oom_free
    lea rdx, [rel s_s_iordb]
    call .s_str
    test eax, eax
    jnz .oom_free
    mov eax, r14d
    imul eax, SIZEOF_IMPORT_ENTRY
    lea rsi, [r13+rax]
    movzx ecx, byte [rsi+ImportEntry.is_ordinal]
    call .s_dec
    test eax, eax
    jnz .oom_free
    lea rdx, [rel s_s_iiat]
    call .s_str
    test eax, eax
    jnz .oom_free
    mov eax, r14d
    imul eax, SIZEOF_IMPORT_ENTRY
    lea rsi, [r13+rax]
    mov ecx, [rsi+ImportEntry.iat_rva]
    xor edx, edx
    call .s_hex
    test eax, eax
    jnz .oom_free
    lea rdx, [rel s_s_iclose]
    call .s_str
    test eax, eax
    jnz .oom_free
    inc r14d
    jmp .s_imp
.s_imps_e:
    lea rdx, [rel s_s_imps_e]
    call .s_str
    test eax, eax
    jnz .oom_free
    lea rdx, [rel s_s_exp]
    call .s_str
    test eax, eax
    jnz .oom_free
    mov r13, [r15+PeImage.exports_ptr]
    test r13, r13
    jz .s_exp0
    mov rcx, [r13]
    call .s_dec
    test eax, eax
    jnz .oom_free
    jmp .s_rel
.s_exp0:
    mov ecx, 0
    call .s_dec
    test eax, eax
    jnz .oom_free
.s_rel:
    lea rdx, [rel s_s_rel]
    call .s_str
    test eax, eax
    jnz .oom_free
    mov ecx, [r15+PeImage.relocs_count]
    call .s_dec
    test eax, eax
    jnz .oom_free
    lea rdx, [rel s_s_close]
    call .s_str
    test eax, eax
    jnz .oom_free
    ; newline final (arquivo termina com CRLF; JSON tolera)
    mov rcx, [rbp-72]
    mov edx, 13
    sub rsp, 32
    call asmbuf_append_char
    add rsp, 32
    test eax, eax
    jnz .oom_free
    mov rcx, [rbp-72]
    mov edx, 10
    sub rsp, 32
    call asmbuf_append_char
    add rsp, 32
    test eax, eax
    jnz .oom_free
    ; ---- grava arquivo ----
    mov rcx, [rbx+DexConfig.snapshot_path]
    sub rsp, 32
    call dex_open_write
    add rsp, 32
    test rax, rax
    jz .oom_free2
    mov [rbp-80], rax            ; handle
    mov rcx, [rbp-72]
    sub rsp, 32
    call asmbuf_data
    add rsp, 32
    mov rsi, rax
    mov rcx, [rbp-72]
    sub rsp, 32
    call asmbuf_len
    add rsp, 32
    mov r8, rax
    mov rcx, [rbp-80]
    mov rdx, rsi
    sub rsp, 32
    call dex_write_all
    add rsp, 32
    test eax, eax
    jnz .w_fail
    mov rcx, [rbp-80]
    sub rsp, 32
    call dex_close
    add rsp, 32
    mov rcx, [rbp-72]
    sub rsp, 32
    call asmbuf_free
    add rsp, 32
    xor eax, eax
    add rsp, 328
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret
.w_fail:
    mov rcx, [rbp-80]
    sub rsp, 32
    call dex_close
    add rsp, 32
    mov rcx, [rbp-72]
    sub rsp, 32
    call asmbuf_free
    add rsp, 32
    jmp .io_fail_code
.oom_free2:
    mov rcx, [rbp-72]
    sub rsp, 32
    call asmbuf_free
    add rsp, 32
    jmp .io_fail_code
.oom_free:
    mov rcx, [rbp-72]
    test rcx, rcx
    jz .io_fail_code
    sub rsp, 32
    call asmbuf_free
    add rsp, 32
    jmp .io_fail_code
.io_fail_code:
    mov eax, 2
    add rsp, 328
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
; Helpers de emissÃ£o no AsmBuf ([rbp-72]). Todos com shadow pelo chamador.
; Usam sÃ³ rax,rcx,rdx,r8 (+ calls que preservam non-volÃ¡teis); rsi/rdi/rbx
; e r12-r15 sobrevivem. Chamador recomputa operandos a cada passo mesmo
; assim (regra: nada volÃ¡til atravessa calls).
;-----------------------------------------------------------------------------
.s_str:
    mov rcx, [rbp-72]
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    ret
.s_hex:
    mov r8d, edx
    mov rdx, rcx
    mov rcx, [rbp-72]
    sub rsp, 32
    call asmbuf_append_u64_hex
    add rsp, 32
    ret
.s_dec:
    mov rax, rcx                 ; valor
    lea rdx, [rbp-120]           ; buf (min 21B; tmp tem 32)
    mov rcx, rax                 ; valor (dex_u64_to_dec: rcx=valor, rdx=buf)
    sub rsp, 32
    call dex_u64_to_dec          ; rax=len (tmp [rbp-120..))
    add rsp, 32
    mov r8, rax
    lea rdx, [rbp-120]
    mov rcx, [rbp-72]
    sub rsp, 32
    call asmbuf_append
    add rsp, 32
    ret
; .s_esc â€” rsi=src(NUL), rdi=dst, edx=maxlen -> NUL-termina. Leaf.
.s_esc:
    xor ecx, ecx
    xor r8d, r8d
.se_l:
    cmp ecx, edx
    jae .se_end
    cmp r8d, 254
    jae .se_end
    mov al, [rsi+rcx]
    test al, al
    jz .se_end
    cmp al, '"'
    je .se_esc
    cmp al, '\'
    je .se_esc
    cmp al, 0x20
    jb .se_q
    mov [rdi], al
    inc rdi
    inc r8d
    inc ecx
    jmp .se_l
.se_q:
    mov byte [rdi], '?'
    inc rdi
    inc r8d
    inc ecx
    jmp .se_l
.se_esc:
    cmp r8d, 253
    ja .se_end
    mov byte [rdi], '\'
    inc rdi
    mov [rdi], al
    inc rdi
    add r8d, 2
    inc ecx
    jmp .se_l
.se_end:
    mov byte [rdi], 0
    ret
