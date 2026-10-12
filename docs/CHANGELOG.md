# Dexter — Changelog

Formato: Keep a Changelog. Versões: `vX.Y.Z` (motor.novidades.correções).

## [Unreleased] — R-7.5 `--doctor` (2026-10-12)

### Adicionado

- `src/diag/doctor.asm` (`dex_doctor(cfg,img) → 0`, inspect-only):
  `Doctor: dexter M.m.p` + `nasm: <path> ok|missing` + `link: …` +
  `kernel32: ok` + `input: valid PE x64`; existência via `dex_open_read`
  (respeita `-N`/`-L`); aceita `-doctor` e `--doctor`; `-q` não suprime;
  nunca escreve `.asm`, ignora `-r`; flag `DF_DOCTOR` + despacho em
  `main.asm` (precedência overview > doctor > rsrc) + ajuda + seção
  `[20]` (8 checks) na suíte.

## [Unreleased] — R-7.4 `-snapshot`/`-compare` (2026-10-11)

### Adicionado

- `src/diag/snapshot.asm` (`dex_snapshot(cfg,img) → 0|2`):
  fingerprint em arquivo JSON (FNV-1a, size, base, entry, seções,
  imports com escape, exports, relocs); flag `-snapshot <arq>` +
  hook inspect-only + seção `[19]` (snapshot exit 0, arquivo criado,
  `fnv1a`/`size` presentes, inspect-only).
- `src/diag/compare.asm` (`dex_compare(cfg,imgA,pathB) → 0|2|3`):
  diff A vs B em texto (`same`/`DIFF`, `+`/`-`/`~` por seção e
  `dll!func`) e `-json` (`identical` true/false, JSON validado por
  parse); B ilegível/inválido → 2/3; seção `[19]` (self, diff,
  `-json` ambos, 2, 3, inspect-only).

### Corrigido (bugs reais, todos reproduzidos)

- Frame 8 pushes + `sub rsp, 320` punha `[rbp-384]` (jtmp) 8 bytes
  ABAIXO do `[RSP]` real (`RSP=RBP-376`): `call .s_esc`/`.c_esc`
  sem shadow empurrava o retaddr DENTRO do jtmp e a string o
  sobrescrevia → `ret` p/ endereço ASCII → AV. Fix: `sub rsp, 328`
  (frame 392; `[rbp-384]=[RSP]`; bônus: callees com entry alinhado).
  (snapshot.asm + compare.asm; causa exata via VEH correto com
  `ExceptionAddress`/`RIP=[ctx+0xF8]`/base via PEB + dump de GPRs.)
- `.t_find_sec`/`.t_find_sec_a`: candidato em `rax` morria no
  `dex_memcmp` → hit retornava 0 (tudo `-`/`+` espúrio). Fix:
  `push`/`pop rax` por iteração (igual `.t_find_imp`).
- `.tfi_hit_pop`: pops `rdi,r12` fora de ordem (push `rsi,rdi,r12`)
  → trocava R12/RDI do chamador → bound do loop corrompido →
  overrun + AV. Fix: ordem `r12,rdi,rsi`.
- `.t_diff_secs`: `rcx`/`rdx` trocados na chamada `.t_find_sec`
  (count como base). Fix.
- JSON: `s_s_open` ×3, `DEX_VER_MAJOR`/`PATCH` nunca setados,
  `call .s_str` sem `lea rdx` (2×: lixo do tmp-hex), `s_s_imps_e`
  nunca emitido, `","num_sections"` preservado, first-flag de
  vírgulas invertida, `]` do added + `"changed":[` ausentes,
  `}` dos objetos ausentes (8× `s_j_cls`), `rsi` vs `rcx` no
  `.c_esc` dos paths, `0x` duplicado (separador já tinha).

### Conhecido (latente, sem efeito hoje; D-novas no ROADMAP)

- `dex_console_write`: 5º arg (`lpOverlapped`) em `[rsp+32]` em vez
  de `[rsp]` — funciona por sorte (lixo benigno); corrigir.
- `asmbuf_append_u64_hex`: prólogo duplicado aparente com epílogo
  único — funciona (hex correto em todos os testes); auditar com
  `.lst` antes de simplificar.

## [Unreleased] — R-7.3 `-rsrc` (2026-10-11)

### Adicionado

- `src/pe/pe_resources.asm` (`dex_rsrc_list(cfg,img) → 0|3`, sem
  heap): inventário 3 níveis (tipo/nome/idioma, numéricos ou UTF-16
  com escape `"`/`\`, controle→`?`, cap 255), teto dir 4MB, sem
  recursão; vazio honesto se ausente; saída 3 com motivo em stderr
  se malformado; duplicatas listadas (desvio documentado do REA);
  flag `-rsrc` + hook inspect-only (precedência overview > rsrc >
  func > xrefs > trace) + ajuda + seção `[18]` (16 checks: gcc
  manifest, ld.lld version, vazio, 2 corrompidos, inspect-only).

### Corrigido (bugs reais no próprio módulo, todos reproduzidos)

- Slot `[rbp-416+8]` colidia com `[rbp-408]` (=c2): loop corria 33M
  vezes até falhar (D-13); slots isolados (foff/cp/dsize).
- Leitura qword de campo dword (`drva` puxava `size` junto: RVA
  `0x147001FB058`); bounds comparavam offset com ponteiro
  (vacuosos); checagem `foff+dsize` ausente; vírgula JSON invertida.

## [Unreleased] — R-7.2 `-func`/`-xrefs`/`-trace` (2026-10-11)

### Adicionado

- `src/diag/xref.asm` (`dex_xrefs`: call/jmp/branch via `target_va` +
  data via RIP-MEM, cap 256 com `truncated`, detail `__imp_`),
  `src/diag/func.asm` (`dex_func`: bounds linear-sweep + calls/jmps +
  `has_ret`, sem CFG por decisão documentada) e `src/diag/trace.asm`
  (`dex_trace`: first-call DFS até `-depth` 1..64, `end` ∈
  leaf/import/cycle/depth/outside); flags `-func/-xrefs/-trace`
  (VAs hex) + `-depth`, hook inspect-only no main, ajuda, seção
  `[17]` (18 checks). JSON validado via `ConvertFrom-Json` (inclui
  `found:false` e `total:0` honestos).

### Corrigido (bugs reais, todos reproduzidos antes do fix)

- Contadores em registradores voláteis (`r10d`/`r11d`) através de
  `dex_disasm_one`/prints (decoder e helpers destroem voláteis):
  sintoma era `total: 0` com 1 ref impressa + AVs por VA selvagem.
  Migrados p/ slots (`[rbp-80]/[rbp-84]`, `[rbp-164]/[rbp-172]`,
  `[rbp-112]/[rbp-136]`); regra D-8 reafirmada.
- Ponteiro de seção morto por `mov eax,[rax+..]` e reusado depois
  (func `.find_sec`→`.f_in_code`, trace `.t_seclimit`→uso): spill
  (`[rbp-96]` / push `rbx`). Mesma classe do fix R-6.1.
- Branch `je`↔`jne` invertido no dispatch de call do trace.
- Colisão `[rbp-96]` = endcode × spill de entry no print do trace
  (D-13); entry foi p/ `[rbp-144]`. Aresta ganhou `kind` (thunk-jmp
  mostrava `--call-->`).

## [Unreleased] — R-7.1 `-overview`/`-json` (2026-10-11)

### Adicionado

- `src/diag/overview.asm` (`dex_overview(cfg,img) → 0`, sem heap, só
  stack 256B + escapes com budget): `-overview` inspect-only (texto no
  vocabulário do `-v`) + `-json` (objeto compacto, validado via
  `ConvertFrom-Json`: hello 3 seções/3 imports, var64 11/14, gcc
  10/224); `-q` não suprime; PE inválido continua saída 3; seção
  `[16]` (11 checks) na suíte. Limite honesto: ordinal sem corpus.

## [Unreleased] — R-6.4 fatia 3 FECHADA (2026-10-11)

### Corrigido (causa raiz do AV `-native`, com reproduzir→fix→suíte 95/95)

- Colisão de slots em `.wds_chunks` (`src/gen/rebuild.asm`): `img` em
  `[rbp-100]` × `va` em `[rbp-96]` (2 qwords a 4 bytes) corrompiam-se
  mutuamente; `img` selvagem (`r8=-1`) chegava a `dex_emit_imp_label`
  e falhava em `mov rax,[r13+0x10]` (`0xC0000005`, RIP=imp_label+24,
  fault `-1` — provado via VEH temporário já removido + `.lst` +
  dissecção por inputs: binário sem alvos R passa, com R e sem imports
  crasha). Fix: `img` → `[rbp-104]` (3 linhas; regra nova D-13).
- Shadow space em `dex_emit_label` (`src/disasm/emit_nasm.asm`, 3 sites —
  checklist §6; era benigno, agora conforme).
- `[13]`: expectativas no formato real `__imp_<dll>_<func>`
  (`_dll_` de `.dll` sanitizado; `jmp` p/ thunks do hello, `call` p/
  var64). Goldens `tests/ref_native/` regenerados p/ saída fatia 3
  (`lea [rel label_]` + `call|jmp [rel __imp_X]` nativos, round-trips
  provados).

### Adicionado

- `[14]` (`tests/imp_check.asm`: HIT/MISS) + `[15]`
  (`tests/sym_check.asm`: golden `SYM n=5 v=1000 1500 2000 2A00 3100`,
  paga D-3) na suíte. R-split observado de verdade
  (`label_140002008:` no hello `-native`).

## [Unreleased] — R-6.4 fatia 3 (IAT) EM ANDAMENTO, BLOQUEADA (2026-10-07)

### Adicionado (funcionando isolado, sem efeito fim-a-fim ainda)

- `dex_emit_imp_label` (fim de `src/gen/rebuild.asm`, global p/ teste)
  + `dex_build_impname` (globalizado): `__imp_<dll>_<func|ordN>` no
  `.idata` (label-at-slot, sem extern); walker constrói nomes;
  codegen kinds 1/2. Drivers `tests/imp_check.asm` (HIT/MISS, heap-buf)
  e `tests/sym_check.asm` (D-3 pago) verdes isolados.
- Git criado (controle de mudanças, skill 5.1); harness endurecido
  (`if !errorlevel! NEQ 0` em [12b]/[13]).

### Problema aberto (bloqueador)

- Generate `-native` com conteúdo → `0xC0000005` (db/bin intactos);
  13 checks de [12b]/[13] falham (mesma raiz). Detalhe, evidência VEH
  e plano em `docs/SESSAO-2026-10-07-R64.md` §3–§4.

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
