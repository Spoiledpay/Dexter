# Dexter — Changelog

Formato: Keep a Changelog. Versões: `vX.Y.Z` (motor.novidades.correções).

## [Unreleased] — R-6.4 fatia 2: codegen + R-labels (2026-10-07)

### Adicionado

- `src/back/codegen.asm` (`dex_codegen_ir(buf, Insn*, IR*) → 0 | 1 |
  6 | 8`): label do address + `dex_emit_native` com snapshot/rollback
  do `AsmBuf.len`; `DB`/`IMPORT` → 1 (db do walker; IAT na fatia 3).
- Walker `-native` via lift+codegen (oploop manual de ~80 linhas morto;
  `g_liftctx`/`g_ir` em `.bss`, decisão centralizada).
- R-labels: `symtab_to_sorted` (`src/gen/symbols.asm`, Shellsort Ciura
  sem `div`) + split da emissão de dados nos alvos R (plain + gaps +
  run-degrade p/ `-strings`; esquema unificado `label_<VA>`, zero
  mudança no emitter); `call [rel __imp_X]` segue db (fatia 3).
- `tests/ref_native/` (5 `.asm -native` pré-mudança p/ prova `fc /b`).
- `tests/codegen_check.asm` (texto golden + prova de rollback) e
  `[12b]` (`rel label_`, round-trips -native hello/loop/tiny/strings).

### Corrigido (bugs reais, com reproduzir→fix→suite 75/75)

- `r10d` (j) morto no helper → `k` garbage → len gigante → OOM
  (spill em `[rbp-120]`).
- `dex_symtab_to_sorted` com nome `dex_*` (convenção do arquivo é
  `symtab_*`) + `[rel + índice]` (não encoda; via registrador).
- Mojibake ASCII em comentários (reparado na hora; regra D-11).

## [Unreleased] — R-6.4 fatia 1: lifter (2026-10-07)

### Adicionado

- `src/back/lift.asm` (`dex_lift_insn(Insn*, ctx*, &DexIR) → 0 | 8`):
  classifica via `is_ret/is_call/is_branch` + opcode e resolve o alvo
  (`DexIR` 24 B sem heap: cls + tkind NONE/CODE/DATA/IMPORT com
  tva/`ImportEntry*`; `mne==0` → IR_DB; predicado de código espelha
  `.cs_in_code`; helpers file-scope com shadow e preserves
  documentados). Entra no `build.bat` (linkado no produto, sem uso
  ainda — mesmo padrão da D-3/R-6.2).
- `DexIR`/`IR_*`/`IRT_*`/`DexLiftCtx`/`SIZEOF_IMPORT_ENTRY` em
  `include/dexter.inc`.
- `tests/lift_check.asm` (12 Insns craftados, sem file I/O, link só
  `lift.obj`) + seção `[11]`: goldens `LIFT db=1 instr=3 call=3
  callimp=1 jmp=1 jmpimp=1 branch=1 ret=1` + `TKIND none=4 code=3
  data=2 import=3` (driver ainda confere internamente, exit 2 se
  divergir).

### Corrigido (bugs reais, com reproduzir→fix→suite 60/60)

- AV em todo `call` do driver novo: frame 8 pushes + `sub 128`
  (192 ≡ 0; antes de call rsp%16 deve ser 0) — 3 pushes + `sub 144`
  com slots remapeados (regra D-10).
- `dex_lift_insn` sem frame com `sub rsp, 32` nos calls internos
  (entry 8 − 0 = 8 ≠ 0) — shadow `sub rsp, 40` nos 9 sites.
- `dex_ast_dump` desaliado (8 pushes + `sub 32`) — `sub 40`
  (funcionava por sorte); comentário do `free_unit` corrigido.
- Driver apontava IAT para `0x...3100` fora das seções fakes (lookup
  honesto dava miss) — VAs `0x...2100/0x...2108` + warnings
  `imm32` eliminados (via registrador).

## [Unreleased] — R-6.5 parcial: `-ast-dump` (2026-10-07)

### Adicionado

- Flag `-ast-dump` (`DF_ASTDUMP`): após escrever o `.asm` (win64 e
  bin), o produto faz parse-back do buffer em memória
  (`dex_parse_asm`) e imprime em stdout o resumo
  `AST funcs=F blocks=B instrs=I succs=S db=D equ=E dir=R`
  (`dex_ast_dump` em `src/front/ast.asm`, via helpers de
  `src/io/console.asm`; `gen_astdump_emit` em `src/gen/rebuild.asm`).
- Garantias: geração byte-idêntica com/sem a flag (`fc /b` igual);
  produto e `tests/ast_check.asm` concordam no resumo do mesmo `.asm`;
  parse falhou (OOM ou `.asm` >16 MB, ex. `ld.lld`) = aviso em stderr
  (respeita `-q`), nunca erro; `-q` não suprime o resumo (pedido
  explícito).
- Seção `[10]` em `tests/run_tests.bat` (exit 0 + `AST funcs=` em
  stdout + `.asm` existe); link do `ast_check` em `[9]` agora inclui
  `obj\console.obj` (dependência real do `dex_ast_dump`).

## [Unreleased] — R-6.3 parser + AST (2026-10-07)

### Adicionado (R-6.3, FECHADO — suíte 52/52)

- `src/front/parser.asm` (`dex_parse_asm(buf,len,&unit) → 0/6/7/8`):
  parser textual NASM→AST (Pass A call-targets em streaming + Pass B
  montagem via `.lex_line`/`.dispatch` + Pass C resolve tidx + succs
  CALL/BRANCH/JMP/FALL); `LABEL:` pendura (último vence), 1º label de
  código ou alvo de `call` abre Func, label/pós-jmp/jcc/ret abre bloco;
  `db`/`equ` (com ou sem label) e diretivas (`section/global/extern/
  bits/default`) viram `AstData`; resto inválido vira DIR verbatim
  (total: nunca falha por conteúdo, como o lexer).
- `src/front/ast.asm` (`dex_ast_unit_new/func/block/instr/succ/data/
  free_unit`): nós em heap, nomes/verbatim emprestados do fonte,
  índices (não ponteiros) sobrevivem a regrowth, free null-safe e
  parcial-safe.
- `tests/ast_check.asm` + seção `[9]` em `run_tests.bat`: goldens
  pinados `hello = funcs=1 blocks=1 instrs=18 succs=3 db=1 equ=1 dir=8`
  e `loop = funcs=1 blocks=5 instrs=30 succs=9 db=2 equ=0 dir=8`
  (CFG do loop validado à mão bloco a bloco).

### Corrigido (bugs reais, todos com reproduzir→fix→suite 52/52)

- `0xC0000094` (div-zero) em `ast_grow_arr`: `div r9` com `r9`
  (elemsz) destruído pelo `call dex_realloc_grow` (r8–r11 voláteis) —
  spill de `r9` + guarda `test r9,r9` (hipótese §4.3.1 da sessão R63).
- `0xC0000005` no `dex_ast_free_unit`: índice `bi` em `r10d` (volátil)
  através de `call dex_free` → free de bloco errado — `bi` em `edi`.
- Instruções após abertura de func/bloco caíam em verbatim (`nop`
  sozinho!): `m` em `r11d` (volátil) morto nos calls — spill em
  `[rbp-72]` (slot só do `.lex_line`), restore em `.code_hasblock`.
- Lexer partia `msg_len` em 2 tokens (`_` 0x5F na faixa Z..a ia para
  `.ti_no`): meio de ident agora cai em `.ti_ck1` (golden 166→164,
  só os 2 `msg_len` fundidos; R-6.2 segue verde).
- `bits 64` (tok1 NUM) e `db` bare sem label caíam em CODE: diretiva
  agora vale por tok0 com qualquer tok1; bare `db`/`equ` viram dados.
- `mov ecx, -11` caía em verbatim: `.pm_imm` aceita `[+-]?NUM` com
  fold do sinal e size pela magnitude.

## [Unreleased] — R-6.2 lexer NASM (2026-10-07)

### Adicionado (R-6.2 Opção B)

- `src/front/lexer.asm` (`dex_lex_one(buf,len,pos,Token*) → consumidos`):
  lexer NASM total (17 kinds `LEX_*` + `DexToken` 40 B em `dexter.inc`),
  sem heap, sem erro por conteúdo; `LABEL`/`REG` (GPR+hi+seg via
  tabelas, case-insensitive)/`NUM`/`STR`/`COMMENT`/pontuação/`EOL`;
  entra no `build.bat` (linkado no produto p/ R-6.3, sem uso ainda —
  mesmo padrão da D-3).
- `tests/lex_check.asm` (driver sem deps do produto, só kernel32 +
  `lexer.obj` + `opcode_tbl.obj`) + seção `[8]` em `run_tests.bat`:
  golden `tests/hello.asm` pinado (166 tokens, 0 unknowns).

## [Unreleased] — R-6.1 nativo + fixes de coletor (2026-10-07)

### Adicionado (R-6.1 Opção A, opt-in)

- Flag `-native` (`DF_NATIVE`): `walk_code_sec` tenta `dex_emit_native`
  (via `dex_build_operands` no walker) com rollback (`AsmBuf.len`
  snapshot) + fallback `db` byte-exato; refs RIP/REL p/ dados caem em
  `db` (checado via seção de código); ajuda (`-h`) documenta.
- Garantia de tamanho exato no emissor: `strict dword/qword` p/ imm
  (forma original via `Insn.imm_size`, exceto push-68), `[abs ..]` p/
  SIB-abs, espaço `mne ops`, base/índice sempre 64 (32 com `0x67`);
  `db` p/ disp32-curto não-RIP, push-68-curto/imm16, ALU/teste geral +
  acumulador (forma curta do nasm mudaria o tamanho).
- Round-trip nativo provado: `hello` (`hi`), `tiny` (exit 42), `loop`
  (`55`), `strings` e `no_relocs` (comportamento byte-igual).

### Corrigido (bugs reais, todos com reproduzir→fix→suite 42/42)

- Hang do `.collect_syms` em qualquer generate: `edi` (count) vs `rdi`
  (base) no mesmo registrador (`.cs_walk` destruía o count → loop de
  ~1 B seções); count agora em slot `[rbp-60]` recarregado por seção.
- O(n²) da tabela D em binários grandes (`.text` 45 MB do `ld.lld` =
  horas): insert D por-VA desligado (zero leitores hoje); R continua;
  dump `ld.lld` agora em ~15 s (776 MB `.asm`).
- Dispatch `.l1_high2` engolia C0–FF em `.l1_testacc` (ex: C7 MEM virava
  `mov`-reg, FF call sumia): novo `.l1_crest` roteia C0+ corretamente.
- `op0` errado em `mov reg,[SIB]` (ex: `mov rdx,[rsp+..]` saía
  `mov rsp,[..]`): `.l1_mv_regfirst` usava `edx` após `.build_rm`
  destruí-lo (spill em `r10d`).
- `.cs_in_code` mutava `esi` (trva) entre seções: delta em `r10d`.
- Slot `[rbp-56]` do walker é o `r15` salvo: spill do oploop movido
  p/ `[rbp-112]` (crash após `.text` com `-native`).

## [Unreleased] — Fase 6 AST/Lexer/Codegen (2026-10-07, docs)

### Adicionado (documentação, sem mudança de comportamento)

- `docs/adr/0001-ast-lexer-codegen.md`: decisão A+B agora, C futura.
- `docs/ROADMAP.md`: Fase 6 (R-6.1–R-6.6) + estrutura `src/front/` + `src/back/`.
- `docs/ARQUITETURA.md`: diagrama Fase 6 + contratos `build_operands`/`emit_native`/`lex_one`/`ast`.
- `docs/CLI.md`: flags futuras `-native` (R-6.1) e `-ast-dump` (R-6.5).
- `Projeto.md §17` + `guia.md §11`: onde paramos + plano A+B.

### Base já existente e reaproveitada (sem alteração nesta entrada)

- `DexOp` + `dex_build_operands` + `dex_emit_native` + tabelas D/R da passada 1.

## [1.2.x] — 2026-10-06 (pipeline de versão + banner sem args)

NOTA: o terceiro número incrementa a cada `build.bat` (`version.bin`);
a entrada abaixo descreve a funcionalidade, não um release congelado.

### Adicionado

- Sistema de versão: `version.bin` (binário 16 B: magic `DXVB`,
  major/minor u16, patch/build u32 auto-incremental, base 1.2.3) +
  `tools/bump_version.ps1` (robusto: valida magic/tamanho, backup
  `.corrupt.*` + reinit, escrita atômica via `.tmp`, rollover de patch)
  integrado ao `build.bat` como etapa `[0/3]` (gera `obj/version.inc`,
  `-I obj\`).
- Banner sem argumentos: `Dexter disassembler Tool Version M.m.p` +
  `LabsObjects All rights reserved` + ajuda completa, saída 0.
- `-ver` e banner de startup dinâmicos (montados em runtime via
  `dex_u64_to_dec`, sem strings hardcoded de versão).
- `dex_print_banner` (`src/cli/help.asm`); `parse_args` retorna 4 p/
  linha vazia; `dexter.inc` inclui `version.inc` gerado.

## [0.2.0] — 2026-10-06

### Adicionado

- Desassemblador x86-64 real (LDE): prefixos legacy+REX, ModRM/SIB/disp
  (addr64/32, RIP-rel), tabelas 1/2/`38`/`3A` + grupos, imediatos/relativos
  com `target_va`, fallback `db` byte-exato.
- Gerador `.asm` modo `win64` (labels `label_<VA>`, `db`, `; mne`,
  `; @VA` com `-hex`, `nop`/`int3` com `-nop-pad`, `db "..."` com
  `-strings`, trim `.pdata`/`.xdata`, classes `code`/`data`/`rdata`).
- **Modo `-m bin`**: `.asm` byte-fiel (headers+seções+overlay) e rebuild
  `nasm -f bin` com saída **byte-idêntica** (hello 2560 B, var64 91872 B).
- Rebuild win64 (`nasm`+`link` via `CreateProcessA`) com
  `/NODEFAULTLIB /DEBUG:NONE /SUBSYSTEM:x /DYNAMICBASE:NO /BASE:idem
  /ENTRY:label_<entry>` + `dex_patch_dirs` (adota DataDirectories).
- Parser PE completo: validação estrita, `rva/offset`, imports/exports/
  relocs com degradação graciosa, dump `-v`/`-vv`.
- CLI completa conforme `docs/CLI.md`; suíte `tests\run_tests.bat` (24/24).
- Corpus: `tests\hello.asm` (golden rebuildável) + negativos
  (`for.exe` magic-0, `var32.exe`, `link.exe` 32-bit).

### Corrigido (bugs reais encontrados via teste empírico)

- Retorno de `rva.asm` desbalanceado (`sub 40`/`add 32` → endereço de
  retorno corrompido).
- `WriteFile` escrevia `written` sobre o slot do `rdi` salvo (todos os
  registradores após qualquer print ficavam = bytes escritos).
- `use-after-free` dos paths da CLI (apontavam p/ buffer liberado).
- Cursor (`rdx`) perdido em `-m`/`-start`/`-end` após calls internos.
- `GetExitCodeProcess` lido como QWORD (lixo nos 32 altos; falhava
  rebuilds bons).
- Leitura mista dword-store/qword-load nos slots do decoder (falha
  fantasma de `length`).
- Voláteis (`r10`/`r11`, `rcx`, `rdx`) vivos através de calls em
  `pe_imports`, `.cmd_appends` (`rcx=dst` faltando → escrita na `.rodata`
  → AV), `generate` (resultado em `r10d`), entre outros.
- Tabela de opcodes: `0x8D` (LEA) sem flag ModRM (instruções partidas).
- `LNK1223` via trim de `.pdata`/`.xdata`; `.rdata` duplicado via classe
  `rdata`; `LNK4078` mitigado (benigno).

### Removido

- `dex_file_seek`, `dex_file_read_at`, `dex_file_write_at` (falhavam com
  `87` neste ambiente; I/O posicional = `mmap_rw`).
- Rewrite de IAT (`call [rel __imp_X]`) desativado por decisão documentada
  (db-copy preserva; `call [rel absolute]` não monta).

## [0.1.0] — 2026-10-06 (marco inicial)

- Esqueleto: pastas, `build.bat`/`clean.bat`, `main` + `parse_args` + `help`,
  I/O e `pe_load` validando e listando seções (`for.exe` como primeiro alvo).
