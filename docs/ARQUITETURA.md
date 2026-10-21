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

## Fase 6 — AST / Lexer / Codegen (2026-10-07, R-6.1–R-6.5 fechados; R-6.6 futura)

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

Estado em 2026-10-19 (R-6.1–R-6.5 fechados; suíte 391/391 em 1.2.390):
`-native` liga
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
dados, `[12b]`) resolvem refs RIP→dados; IAT (fatia 3) FECHADA em 1.2.181
(`[13]`/`[14]`/`[15]`); `-ast-dump`/`-emit` são plumbing sobre `DF_NATIVE`
(R-6.5). `db` continua o default; tabela D como bitmap (D-7) e R ativa.
R-6.6 (IR otimizável + backend próprio) segue futura — ver
`docs/ROADMAP.md` "Pendências abertas".

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
9. **Imports nativos em `-f bin` com correção de delta (R-5.3 F1).** Em
   `-m bin -native` o walker emite `call|jmp [rel __imp_X + K]` e o
   caminho de dados do bin injeta `__imp_X:` nos slots da IAT
   (`.gb_db_slots`). Em `-f bin` cada label vale **file-offset** (não RVA),
   então uma referência entre seções exige
   `K = iat_rva − off(slot) − (vaddr_code − raw_code)`; sem K o `disp32`
   sairia deslocado (e o bin continuaria montando, mas byte-diferente).
   `K==0` (mesma seção) emite o nome puro. Gates `[36]`/`[37]` exigem
   `[rel __imp_` no `.asm` (o fallback `db` é byte-idêntico e passaria em
   silêncio). R-5.3 FECHADA (F1–F4).
10. **Tabela de imports simbólica no `-f bin` (R-5.3 F2).** Em
   `-m bin -native` o `IMAGE_IMPORT_DESCRIPTOR` sai como `label_<VA>:` +
   5 `dd`: `OriginalFirstThunk`/`Name`/`FirstThunk` viram
   `dd label_<alvoVA> + C` (`C = vaddr − raw_ptr` da seção do alvo) e os
   alvos (ILT/nome/IAT) ganham label no ponto exato do stream (mesmo
   fatiamento byte-exato do `.gb_db_slots` que injeta `__imp_X:`). O limite
   do diretório é o **descritor terminador** (o `Size` do dir abarca
   ILT/IAT/nomes, não só descritores). Alvo sem label garantida
   (código/`.pdata`/`.xdata`/sem bytes) sai `dd 0x<rva>` cru. Verificação
   **estrutural**: `tests/pe_impdesc.py` (oráculo = bytes do PE) + `[45]`.
11. **SIB-abs com índice (loads indexados).** Operando sem base
    (`SIB base=101`): `disp32 + idx*scale`. Emitido textual e byte-exato com
    `nosplit` (o NASM "splitaria" `[abs 0x2+rax*2]` para `[rax+rax+0x2]`,
    encurtando); `abs` primeiro em x64; disp32==0 → disp omitido. O disp32
    **não é rotulado** (o emissor compartilhado não tem canal de label p/
    operando absoluto nem correção `+C` fora de `-f bin`) — base simbólica
    do índice fica como fatia futura. Verificação: `tests/sibabs.asm` + `[49]`.
12. **Thunks ILT/IAT simbólicos no `-f bin` (R-5.3 F3).** Cada entrada
   não-nula das arrays `OriginalFirstThunk` (ILT) e `FirstThunk` (IAT) sai
   `dq label_<hint/name VA> + C` (o alvo ganha `label_` no stream); ordinal
   (bit63) ou IAT *bound* (valor > 32 bits) ou alvo não-rotulável → `dq
   0x<v>` cru (byte-fiel, sem label indefinido). O alvo é descoberto
   **independente** do slot: o scanner do bin resolve **1 VA por iteração**
   (menor VA ≥ floor), então o alvo precisa ser redescoberto mesmo depois de
   o slot já ter sido emitido. Verificação: `tests/pe_impdesc.py` estendido
   (percorre OFT/FT do PE) + `[47]`.
13. **Strings de import simbólicas no `-f bin` (R-5.3 F4).** Cada
   `IMAGE_IMPORT_BY_NAME` sai `dw <hint>` + `db "<nome>", 0` e o `Name` do
   descritor sai `db "<dll>", 0`, via `dex_emit_qstr` (emissor de `db "..."`
   com escape de `"`) — **promovido a file-scope** porque os `.gb_*` vivem
   em `dex_generate_bin` e **não** alcançam labels locais de
   `dex_generate_asm` (labels com `.` são escopados ao label não-local
   anterior). Legibilidade por `dex_emit_qstr` só quando o cstring é ASCII
   imprimível (0x20..0x7E), tem NUL dentro da seção e len ≤ 255; senão
   fallback `db` byte-fiel. Verificação: `tests/pe_impdesc.py` (lê
   hint/nome dos bytes) + `[48]`.
14. **`UNWIND_INFO` em qualquer seção (R-5.4).** O MS link funde o `.xdata`
   no `.rdata` em PE real (ex.: `notepad.exe`), então o unwind **não** está
   numa seção nomeada. O núcleo `.uw_bitmap` (inícios na seção, da `.pdata` +
   `chained`) + `.uw_emit` (label + `db` do header/codes + `dd` simbólico dos
   campos RVA) é reusado no caminho bin (`.gb_db_slots`), que reemite cada
   `UNWIND_INFO` intercalado com imports/db — byte-exato. `-m bin -native`
   do notepad byte-idêntico (**D-20 fechada**: ALU/mov reg-reg "load" → `db`;
   prefixo de segmento `gs:`/`fs:` reemitido). O `win64` de PE MS real segue
   **D-19**.
15. **Runs de string com CR/LF (`-strings`).** `.str_run` aceita CR/LF dentro
   do run (1º byte imprimível) e `dex_emit_qstr` **fecha/reabre as aspas** em
   volta de cada escape (estado `open`): `, 13`, `, 10`, `, 34` ficam inline,
   sem `""`, numa única linha NASM — bytes exatos. Verificação:
   `tests/qstr_check.py` + `[50]` (fixture `tests/strings.asm`).
16. **Índice simbólico em x32 (SIB-abs).** Em x32 o disp32 de
   `[disp32+idx*scale]` é uma VA do image (cabe em 32 bits): o scanner
   (`.cs_abs32sib`) registra a **RVA** no R e o emissor sai
   `[nosplit label_<VA>+<idx>*<scale>]`. x64 fica numérico (VA > 32 bits).
   O canal emissor↔rebuild é por **dados** (`g_abs_vas`/`g_abs_n`/
   `g_abs_base`, definidos em `emit_nasm.asm`) — função nova quebraria o link
   dos drivers que não linkam `rebuild.obj`. Verificação: `tests/absidx.asm`
   + `[51]`.
17. **Spans de ponteiro em x32 = 4 bytes (`dd`).** O pré-scan (`.collect_strs`
   passada B) e o emissor (`.wds_emit_span`) usam **stride do arch** (8 = `dq`
   qword; 4 = `dd` dword): tabelas de ponteiro x32 (`dd VA`) viram
   `dd label_<VA>` (código via D-7). Antes: gate `arch==X64` no pré-scan +
   `g_spanflags=1` forçando db em x32. Verificação: `tests/absidx.asm` + `[51]`.

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
  `pe_exports.asm`, `pe_relocs.asm`, `pe_unwind.asm` (SEH: `.pdata`/
  `.xdata` → RUNTIME_FUNCTION/UNWIND_INFO, R-5.4 F1).
- `src/disasm/`: `decoder.asm` (LDE + VEX `C4/C5` + EVEX `62`: prefixo em
  `npre`, mapa 0F/0F38/0F3A, `Insn.enc`), `prefixes.asm`, `modrm.asm`,
  `opcode_tbl.asm` (flags 1/2/38/3A + mnemônicos), `operands.asm`,
  `semantics.asm` (`dex_build_operands`: whitelist; VEX/EVEX → `db`),
  `x87.asm` (`dex_x87_mne`: mnemônico real D8-DF por opcode+ModRM),
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
