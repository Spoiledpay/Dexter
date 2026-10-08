# Dexter — Arquitetura

## Blocos

```
input.exe
  │ CreateFileA/Read (file_read) → GetFileSizeEx → CreateFileMapping/MapView (mmap)
  ▼
dex_pe_load ............ valida MZ/PE/AMD64/OPT64 + copia 96 seções (pe_load)
dex_pe_parse_imports .... vetor ImportEntry (pe_imports, degrada p/ 0 se corrompido)
dex_pe_parse_exports .... count + RVAs de nomes (pe_exports)
dex_pe_parse_relocs ..... RVAs u32 (pe_relocs)
  ▼
modo win64:                              modo bin:
  por seção CODE:                          headers db + seções db + overlay
    dex_disasm_one (decoder LDE)             (generate_bin; sem decode)
      prefixes → opcode(tbl1/2/38/3A)
      → modrm/sib/disp → operands(imm/rel)
      fallback db p/ desconhecido
    dex_emit_insn → label + db (+call/jmp [rel __imp]
                    se rewrite; DESATIVADO: db puro)
  por seção DATA: dex_emit_data (db 16/linha; strings se -strings)
  ▼                                        ▼
dex_generate_asm → .asm ──────────────► dex_rebuild
                                           win64: nasm -f win64 → link
                                             /NODEFAULTLIB /SUBSYSTEM:x
                                             /DYNAMICBASE:NO /BASE:idem
                                             /ENTRY:label_<entry>
                                           + dex_patch_dirs (adota
                                             DataDirectories originais
                                             onde o link não gerou)
                                           bin: nasm -f bin (byte-fiel)
```

## Fase 6 — AST / Lexer / Codegen (2026-10-07, em andamento)

```
dex_disasm_one + dex_build_operands (semantics.asm)
  => Insn + DexOp op0/op1/op2 (AST flat, R-4.5) ─┐
                                                 ├─► R-6.1: .walk_code_sec -native?
                                                 │     sim: dex_emit_native (mov rax,rbx / [rel label])
                                                 │     não/falha(1): dex_emit_insn db (default atual, fiel)
                                                 │
  .asm nativo ─► R-6.2 lexer (src/front/lexer.asm: dex_lex_one)
              ─► R-6.3 parser+AST (Func -> Blocks(CFG via target_va/is_branch) -> Instr -> Op)
              ─► R-6.4 lift (DexOp->IR) + codegen (IR->AsmBuf via emit_native)
```

Estado em 2026-10-07 (R-6.1 + R-6.2 + R-6.3 fechados): `-native` liga
`dex_build_operands` + `dex_emit_native` no walker (`.wcs_emit` →
`.wcs_oploop` valida refs com label via `.cs_in_code` → snapshot/rollback
+ fallback `db`); tamanho exato via `strict`/regras de forma em
`semantics`+`emit_nasm`; `dex_lex_one` (`src/front/lexer.asm`, 17 kinds,
`DexToken` 40 B) tokeniza qualquer NASM (golden 164 tokens, 0 unknowns);
`dex_parse_asm` (`src/front/parser.asm`: Pass A call-targets + Pass B
montagem + Pass C resolve/succs) + nós heap (`src/front/ast.asm`,
ownership com free no mesmo nível) montam `Func → Blocks → Instr → Op`
(goldens hello/loop pinados em `[9]`); `dex_lift_insn`
(`src/back/lift.asm`, R-6.4 fatia 1: Insn+DexOp → `DexIR` sem heap,
golden em `[11]`) classifica e resolve alvos (code/data/import);
`dex_codegen_ir` (`src/back/codegen.asm`, fatia 2: label + nativo com
rollback) emite via walker; R-labels (`symtab_to_sorted` + split de
dados, `[12b]`) resolvem refs RIP→dados; IAT (fatia 3) segue.
`db` continua default; tabela D desligada (D-7), R ativa.

## Contratos entre módulos

- `dex_pe_load(img, base, size) → 0/3`. `sections_ptr` fornecido pelo
  chamador (array 96×32). Campos do PE nunca usados sem checar contra o
  tamanho do arquivo.
- `dex_rva_to_offset(img, rva) → off` (0 = fora; `rva < SizeOfHeaders`
  mapeia identidade; `.bss` sem offset retorna 0).
- `dex_disasm_one(img, VA, Insn*) → 1..15 | 0`. Sempre retorna >0 havendo
  byte; desconhecido vira `mne=0` (emitter usa `db` exato).
- `AsmBuf` (asm_buffer) com crescimento via `dex_realloc_grow`.
- `dex_rebuild(cfg, img) → 0/5` via `CreateProcessA` + espera + exit code
  DWORD (lido 32 bits — QWORD pega lixo nos bits altos!).
- Fase 6: `dex_build_operands(Insn*) → 0/1` (0 = DexOp pronto p/ nativo,
  1 = caller usa `db`); `dex_emit_native(buf, Insn*) → 0/1` (mesmo contrato);
  `dex_lex_one(buf,len,pos,Token*) → consumidos (>0)`; `dex_ast_*` com
  ownership em heap (free no mesmo nível); `-native` nunca muda `db` default.

## Decisões (resumo; detalhes em `docs/adr/` quando houver)

1. **Cópia byte-exata + `db`, sem rewrite de IAT.** O linker reordena
   seções, então qualquer reescrita de `disp32`/IAT seria invalidada. Com
   layout idêntico (`/BASE` + `/DYNAMICBASE:NO`), os `disp32` RIP-rel
   originais continuam válidos. Rewrite desativado e documentado.
2. **Modo `bin` (padrão p/ round-trip fiel).** `nasm -f bin` com headers +
   seções + overlay copiados = binário byte-idêntico, sem linker no caminho
   (sem reordenação, sem validação de `.pdata`, sem seções extras).
3. **`dex_patch_dirs`.** O linker não regenera DataDirectories a partir de
   bytes `db`; o rebuild adota os RVAs/tamanhos originais onde o slot do
   rebuild está vazio (nunca sobrescreve o que o link gerou).
4. **Classes de seção NASM fiéis:** `code` p/ executável, `data` p/ escrita,
   `rdata` p/ somente-leitura (funde com `.rdata` do linker em vez de
   duplicar em outro VA).
5. **Trim de `.pdata`/`.xdata` p/ `vsize` (modo win64).** O linker valida
   unwind entries e rejeita padding zero (LNK1223); aparar só se o VA da
   próxima seção não mudar (guarda por `SectionAlignment`).
6. **I/O posicional via `mmap` (`dex_mmap_rw`), não via seek.**
   `SetFilePointerEx`/`OVERLAPPED` falharam empiricamente neste ambiente
   (87) em handles válidos; o mapeamento RW cobre leitura+patch sem seek.
7. **Falhas de alocação nunca mascaradas; sem `TODO`/stub com sucesso falso.**
   Desconhecido no decoder = `db` real (preserva bytes), não erro falso.
8. **`-start`/`-end` limitam desassemblagem (código); dados saem inteiros.**

## Mapa de arquivos

- `include/`: `win64.inc` (kernel32), `dexter.inc` (DexConfig/PeImage/
  PeSection/Insn/ImportEntry/AsmBuf/SymbolTable), `pe.inc` (offsets PE),
  `errors.inc`, `macros.inc`.
- `src/cli/`: `parse_args.asm` (GetCommandLineA + tokenizer próprio, dup de
  strings — sem use-after-free), `help.asm`.
- `src/io/`: `file_read.asm` (open/size/close), `file_write.asm`
  (open/open_rw/write_all/write_cstr), `mmap.asm` (mmap_read/rw/unmap),
  `console.asm` (WriteFile stdout/stderr, hex/dec).
- `src/pe/`: `pe_load.asm`, `pe_sections.asm`, `rva.asm`, `pe_imports.asm`,
  `pe_exports.asm`, `pe_relocs.asm`.
- `src/disasm/`: `decoder.asm`, `prefixes.asm`, `modrm.asm`,
  `opcode_tbl.asm` (flags 1/2/38/3A + mnemônicos), `operands.asm`,
  `emit_nasm.asm` (db + labels + `-hex`).
- `src/gen/`: `asm_buffer.asm`, `labels.asm`, `symbols.asm`, `strings.asm`
  (pool), `rebuild.asm` (generate win64/bin + rebuild + patch_dirs).
- `src/front/`: `lexer.asm` (`dex_lex_one`: buf/len/pos + `DexToken` →
  consumidos; puro, sem heap; testado por `tests/lex_check.asm`),
  `parser.asm` (`dex_parse_asm`: Pass A/B/C; testado por
  `tests/ast_check.asm`), `ast.asm` (`dex_ast_*`: nós heap + free).
- `src/util/`: `memory.asm` (HeapAlloc wrappers, cap 1 GiB), `string.asm`,
  `hash.asm` (FNV-1a), `log.asm`.
- `runtime/`: templates Fase 5 (`-f bin` avançado com import table própria).
