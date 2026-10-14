# Dexter — Roadmap (requisitos R-x.y + status real)

Legenda: `[x]` implementado + testado em Windows (`tests\run_tests.bat` 24/24);
`[ ]` futuro. IDs estáveis para branches/commits.

## Fase 0 — Esqueleto, CLI e I/O `[x]`

- [x] R-0.1 Pastas + `build.bat` (nasm+link autodetect) + `clean.bat`
- [x] R-0.2 `main.asm` (`/ENTRY:main`, sem CRT, ExitProcess com códigos 0/1/2/3/5)
- [x] R-0.3 CLI completa (`-o -O -m -r -L -N -s -start -end -hex -nop-pad
  -no-imports -no-relocs -strings -v -vv -q -ver -h/--help`), tokenizer
  próprio sobre `GetCommandLineA`, defaults `C:\Nasm\…`, `-m bin` recusado
  na v0.1 e **aceito** na v0.2 (bin implementado)
- [x] R-0.4 I/O kernel32 (open/size/mmap/write/flush/console), share-read
  em saída (nasm/link leem concorrente), `mmap_rw` p/ patch
- [x] R-0.5 `heap` (cap 1 GiB), `strlen/memcmp/memcpy/streq/hex/dec`,
  `FNV-1a`, log stdout/stderr
- [x] R-0.6 Versionamento de build: `version.bin` (magic `DXVB` +
  major/minor/patch u16/u16/u32, base 1.2.3) + `tools/bump_version.ps1`
  (robusto: ausente/corrompido → backup + reinit; escrita atômica;
  rollover de patch) integrado ao `build.bat` (etapa [0/3] → gera
  `obj/version.inc` via `-I obj\`); banner/`-ver` dinâmicos
  (`Dexter disassembler Tool Version M.m.p` + `LabsObjects All rights
  reserved`); sem args → banner + ajuda, saída 0

## Fase 1 — PE Loader `[x]`

- [x] R-1.1 `dex_pe_load`: MZ, `e_lfanew`, `PE\0\0`, `0x8664` (32-bit → 3),
  `0x20B`, alignments, `SizeOfImage ≤ 1 GiB`, tabela de seções com
  validação `raw_ptr+raw_size ≤ filesize`
- [x] R-1.2 `rva_to_offset` / `offset_to_rva` (headers identidade, `.bss`
  sem offset, cap seções 96)
- [x] R-1.3 `pe_find_section` (p/ `-s`)
- [x] R-1.4 dump `-v` (base/entry/seções/imports/exports/relocs) e `-vv`
  (+hexdump 64 B/seção)

## Fase 2 — Decoder (LDE real + fallback honesto) `[x]`

- [x] R-2.1 legacy (66 67 F0 F2 F3 segmentos) + REX (último vale)
- [x] R-2.2 ModRM+SIB+disp (addr64 e addr32/0x67, RIP-rel, disp com sinal)
- [x] R-2.3 tabelas 1/2/`38`/`3A` (flags modrm/imm/rel/grupo) + mnemônicos
  comuns (MSVC/LLVM: mov/lea/add/sub/call/jmp/ret/push/pop/test/cmp/…)
- [x] R-2.4 grupos `80-83`/`C0-C1`/`F6-F7`/`FE-FF`/`0FBA`, `B0-BF`
  (REX.W→imm64), `A0-A3` moffs, `C2/CA` ret-imm16, `C8` enter,
  `E8/E9/EB/70-7F/0F80-8F` (alvos `VA+len+rel` em `target_va`)
- [x] R-2.5 `dex_disasm_one` retorna 1..15 (0 só sem bytes); desconhecido =
  `mne=0` + `db` exato (nunca erro falso)
- [x] R-2.6 emissor `db` + `label_<VA>:` + `; mne` (+ `; @0xVA` com `-hex`);
  `nop`/`int3` reais com `-nop-pad`
- [ ] R-2.7 VEX/EVEX (`C4/C5/62`), x87, 3DNow! → hoje fallback `db`
  (correto em bytes; semântica de label futura)

## Fase 3 — Imports/Exports/Relocs `[x]`

- [x] R-3.1 import directory → `ImportEntry{dll,func,ordinal,iat_rva}`
  (nomes apontam p/ o mapeamento; corrompido → 0, nunca crash)
- [x] R-3.2 exports (count + RVAs de nomes) e relocs (RVAs u32, cap 65536)
- [x] R-3.3 rewrite de IAT (`call|jmp [rel __imp_X]` regenerado) — ATIVO
  em `-native` via R-6.4.3 (`dex_build_impname` + `dex_emit_imp_label`
  label-at-slot, sem `extern`; codegen kinds 1/2 com fallback `db`;
  auditado: hello 3×`jmp [rel __imp_]` + var64 2×`call [rel __imp_]`/14
  labels, 0 `extern`, round-trip `hi`; `[13]`/`[14]` verdes). Sem
  `-native`, `db-copy` continua o default (decisão ARQUITETURA §1).

## Fase 4 — Geração + rebuild `[x]`

- [x] R-4.1 seções em ordem com classes `code`/`data`/`rdata`, `global`
  do entry-label, `.reloc` omitida com `-no-relocs`, `.pdata`/`.xdata`
  aparadas p/ `vsize` (guarda de VA), `.bss` documentada (v0.2: seção
  vazia; ver R-4.4)
- [x] R-4.2 `dex_rebuild` win64: `nasm -f win64` + `link /NODEFAULTLIB
  /DEBUG:NONE /SUBSYSTEM:x /DYNAMICBASE:NO /BASE:idem
  /ENTRY:label_<entry>` via `CreateProcessA` (exit code DWORD!)
- [x] R-4.3 `dex_patch_dirs`: adota DataDirectories originais onde o link
  deixou vazio (imports/recursos/pdata/debug/tls/…) via `mmap_rw`
- [x] R-4.4 `.bss` (raw 0) sai como seção vazia; o link dimensiona.
  LIMITAÇÃO HONESTA: o `link.exe` reordena seções e pode derrubar vazias,
  então o modo win64 só garante round-trip comportamental em PEs simples
  (hello: OK). O path fiel p/ PEs reais é `-m bin` (R-5.1).
- [x] R-4.5 `call|jmp [rel]` p/ IAT regenerada (pago por R-3.3 em `-native`; ver `[13]`)

## Fase 5 — Fidelidade total e modo `bin` (parcial `[x]`, resto `[ ]`)

- [x] R-5.1 `-m bin`: headers+seções+overlay em `db` + `times` pad →
  `nasm -f bin` = **byte-idêntico** (hello 2560 B e var64 91872 B:
  `fc /b` igual + comportamento igual)
- [x] R-5.2 round-trip testado: win64/hello (`hi`, exit 0) e bin/hello+var64
- [ ] R-5.3 `-f bin` com import table REGENERADA (hoje: copiada — suficiente
  e fiel; regenerar só se preciso)
- [ ] R-5.4 strings em code-flow, jump tables, SEH/unwind reemitido,
  fuzzy corpus expandido, `tests\fuzz_pe.py`
  (PARCIAL 1.2.250, 3b: pré-scan `.collect_strs` insere starts de runs +
  alvos de ponteiros em g_symR; `.wds_emit_span` emite `dq label_` em
  `-native`, `s_tab` simbólica, round-trip strings provado, `[21]` verde;
  RESTA: jump-to-code (alvos), loads indexados `[rbx+n]`, `.str_run`
  com `\r\n`; 1ª fatia 1.2.257: base rotulada via R + corpus
  `jtable.asm` + `[27]` + fix `jmp/call r64` sem REX (`.l1_ffmem`))
- [x] R-5.4-fuzz `tests\fuzz_pe.py` mínimo (1.2.253, determinístico por
  seed: flips + miradas em MZ/lfanew/seções/imports + truncamento;
  mutante nunca executado; passa = saída em {0,1,2,3,5}; `[22]` com
  20 casos seed 7; 1 hang real achado (imports, D-8) e corrigido)

## Fase 6 — AST / Lexer / Geração de código nativo (nova, incremental `[ ]`)

> Decisão documentada em `docs/adr/0001-ast-lexer-codegen.md` (2026-10-07).
> R-6.1 FECHADO em 2026-10-07: `-native` liga o caminho nativo no walker
> (`build_operands` + `emit_native` + fallback `db`, tamanho exato
> garantido); `db` continua o default. Falta o frontend (lexer/parser/AST
> por cima, R-6.2+), sem quebrar o round-trip atual.

- [x] R-6.1 Opção A — emissor nativo opt-in (`-native`, `DF_NATIVE`):
  `walk_code_sec` chama `dex_build_operands` e tenta `dex_emit_native`,
  com rollback (snapshot de `AsmBuf.len`) + fallback `db` byte-exato;
  refs RIP/REL p/ dados caem em `db` (dados sem labels por-VA; R-labels
  em R-6.4); garantia de tamanho exato: `strict dword/qword` p/ imm
  (forma original via `Insn.imm_size`), `db` p/ disp32-curto não-RIP,
  push-68-curto, ALU/teste geral+acumulador e `[abs ..]` p/ SIB-abs;
  teste: `hello/tiny/loop/strings/no_relocs` round-trip win64+nativo
  com comportamento igual (`hi`, `42`, `55`, strings, `fc` igual)
- [x] R-6.2 Opção B — lexer NASM (`src/front/lexer.asm`): `dex_lex_one`
  total (nunca falha por conteúdo; `UNKNOWN` p/ resto) com `DexToken`
  40 B (`kind/val/ptr/len/line/col`); `LABEL` (`x:` exceto seg),
  `REG` (GPR via tabelas + hi/seg, case-insensitive), `NUM` (0x/dec),
  `STR` (`"`/`'`, sem escapes), pontuação, `COMMENT`, `EOL`;
  `tests/lex_check.asm` (driver sem deps do produto) + `[8]` na suíte:
  golden `tests/hello.asm` = 164 tokens, 0 unknowns (166 antes do fix
  `_` em R-6.3; smoke extra: saída nativa 4922 tokens + vazio + bytes
  esquisitos, tudo sem crash)
- [x] R-6.3 Parser + AST (`src/front/parser.asm`, `src/front/ast.asm`):
  `Func(VA entry) → Blocos básicos (alvos REL de target_va) → CFG`
  (`is_branch/is_call/is_ret` de `Insn`); nós `Func/Block/Instr/Op`;
  ownership: AST em heap com free no mesmo nível.
  FECHADO em 2026-10-07 (suzie 52/52): `dex_parse_asm` textual sobre o
  stream do lexer (Pass A call-targets + Pass B montagem + Pass C
  resolve/succs); `dex_lex_match` reusado p/ keywords; `db`/`equ` bare
  (`db 0x90` sem label) e diretiva por tok0 (`bits 64` com NUM);
  imediatos com sinal (`mov ecx, -11`); goldens pinados em `[9]`:
  hello = `funcs=1 blocks=1 instrs=18 succs=3 db=1 equ=1 dir=8`,
  loop = `funcs=1 blocks=5 instrs=30 succs=9 db=2 equ=0 dir=8`
  (CFG validado à mão: 1 bloco/label, tidx exatos, calls externos -1).
  Bugs reais achados e corrigidos (todos com teste que captura):
  div-zero em `ast_grow_arr` (`div r9` com `r9` morto no call),
  AV no free (`bi` em `r10d` volátil), `m` em `r11d` volátil,
  `_` no meio do ident lexado como 2 tokens, `bits 64` caindo em CODE.
- [x] R-6.4 Lifter + codegen (`src/back/lift.asm`, `src/back/codegen.asm`):
  `DexOp → IR (ADD/SUB/MOV/LEA/CALL/JMP/RET)` → reemissão via
  `dex_emit_native`; jump-tables e RIP-em-dados (tabela R da passada 1)
  viram labels reais; `call [rel __imp_X]` reativado só aqui (R-3.3/R-4.5)
  FATIA 1 FECHADA em 2026-10-07 (`dex_lift_insn` em `src/back/lift.asm`:
  `DexIR` 24 B sem heap — cls IR_DB/INSTR/CALL/CALLIMP/JMP/JMPIMP/
  BRANCH/RET + tkind NONE/CODE/DATA/IMPORT com tva/imp; predicado de
  código espelha `.cs_in_code`; `tests/lift_check.asm` + `[11]`:
  goldens `LIFT db=1 instr=3 call=3 callimp=1 jmp=1 jmpimp=1 branch=1
  ret=1` + `TKIND none=4 code=3 data=2 import=3`; suite 60/60).
  FATIA 2 FECHADA em 2026-10-07: `src/back/codegen.asm`
  (`dex_codegen_ir`: label + nativo com rollback, ou 1→db) + walker via
  lift+codegen (oploop manual morto; 2a provada byte-idêntica via `fc /b`
  nos 5 + `tests/ref_native/`) + R-labels (2b: `symtab_to_sorted`
  Shellsort + split da emissão de dados nos alvos R + run-degrade p/
  `-strings`; `lea rdx, [rel label_...]` nativo com round-trip no corpus
   simples; `[12b]` na suíte; suite 75/75). FATIA 3 (rewrite IAT)
   FECHADA em 2026-10-11: causa raiz do AV era colisão de slots em
   `.wds_chunks` (`img` em `[rbp-100]` × `va` em `[rbp-96]`: 2 qwords
   a 4 bytes, corrupção mútua; `img` selvagem chegava a
   `dex_emit_imp_label` como `r8=-1`, fault em `mov rax,[r13+0x10]`,
   provado via VEH temporário (já removido) + `.lst` + dissecção por
   inputs (tiny2 sem R passa, tiny3 com R e sem imports crasha).
   Fix (3 linhas): `img` → `[rbp-104]`; junto: shadow em
   `dex_emit_label` (checklist §6), goldens `ref_native/` regenerados
   p/ saída fatia 3, `[13]` no formato real `__imp_<dll>_<func>` e
   `[14]`(imp)+`[15]`(sym) criados. Suite: 95/95 OK (1.2.181).
   Detalhe em `docs/SESSAO-2026-10-11-R643.md`.
- [x] R-6.5 Flags: `-native` (A, R-6.1); `-ast-dump` (`[10]`); `-emit`
  (1.2.254: `-emit db|native`, `native` ≡ `-native`, last-wins, outro
  valor → 1; só plumbing sobre `DF_NATIVE`, `[23]` com 8 checks)
- [ ] R-6.6 Opção C (futura): IR otimizável + backend próprio (`-f bin`
  com seção `.text` regenerada); depende de R-6.1–R-6.4 verdes + fuzz

Nova estrutura (só entra no `build.bat` quando cada arquivo existir de verdade):

```text
src/front/lexer.asm    ; R-6.2 dex_lex_one [x] (+ DexToken em dexter.inc)
src/front/parser.asm   ; R-6.3 dex_parse_asm
src/front/ast.asm      ; R-6.3 dex_ast_* (new/free/dump)
src/back/lift.asm      ; R-6.4 dex_lift_insn (DexOp -> IR)
src/back/codegen.asm   ; R-6.4 dex_codegen_func (IR -> AsmBuf via emit_native)
```

Regra de transição (zero regressão): `db` continua o default; `-native`
é opt-in; `tests\run_tests.bat` deve continuar 100% OK com e sem `-native`
no corpus simples; PEs complexos continuam em `-m bin`.

## Fase 7 — Views + JSON mínimo (estilo REA, opt-in, inspect-only)

> Acompanhamento fino em `marco.md` §5. Primeira entrega em 2026-10-11.

- [x] R-7.1 `-overview`/`-json` (`src/diag/overview.asm`,
  `dex_overview(cfg,img) → 0`, `DF_OVERVIEW`/`DF_JSON`): inspect-only
  (nunca escreve `.asm`, ignora `-r`; `-q` não suprime, como
  `-ast-dump`); texto no vocabulário do `-v` + JSON compacto de 1
  linha (todos os imports sem cap silencioso, escapes `"`/`\`,
  controle→`?` com cap 255 de dst, hex como string, counts decimais);
  `[16]` na suíte (texto/json/inspect-only/`imports_count`=14 no
  var64). Limite honesto: imports por ordinal (`func` vazio) sem
  cobertura no corpus atual.
- [ ] R-7.2 `-func/-xrefs/-trace` (sobre `target_va`, `truncated:true`
  honesto)
- [x] R-7.2 `-func` (`src/diag/func.asm`, linear-sweep até ret/jmp/
  inválido/fim, sem CFG) + `-xrefs` (`src/diag/xref.asm`: call/jmp/
  branch/data, cap 256) + `-trace` (`src/diag/trace.asm`: first-call
  DFS até `-depth`, `end`+`truncated` honestos, jmp-out p/ import
  registra aresta); `[17]` na suíte (18 checks); JSON validado
  (func/xrefs/trace + not-found/vazio). Bugs reais achados junto
  (todos reproduzidos antes do fix): contadores em `r10d`/`r11d`
  através de calls (decoder destrói voláteis — prova: `total: 0`
  com 1 ref; regra D-8), ponteiro sec morto por `mov eax,[rax+..]`
  (mesma classe do fix R-6.1 `.l1_mv_regfirst`), branch `je`↔`jne`
  invertido no trace, colisão `[rbp-96]`=endcode×entry-spill (D-13).
- [x] R-7.3 `-rsrc` (`src/pe/pe_resources.asm`, `dex_rsrc_list`):
  inventário 3 níveis (tipo/nome/idioma, numéricos ou UTF-16 com
  escape), sem heap, sem recursão (ciclos impossíveis), teto 4MB;
  vazio honesto se ausente, saída 3 explícita se malformado;
  duplicatas listadas (desvio documentado do REA); `[18]` na suíte
  (gcc manifest `24/1/1033`, ld.lld version `16/1/1033`, vazio,
  2 corrompidos, inspect-only) + fuzz manual (subdir/data/nome:
  só 3 ou saída honesta, nunca crash/hang).
- [x] R-7.4 `-snapshot/-compare` (hash FNV-1a + size + layout;
  FECHADO 1.2.245, `[19]` na suíte; linhas antigas abaixo mantidas p/
  histórico)
- [ ] R-7.4 `-snapshot/-compare` (hash FNV-1a + size + layout)
- [x] R-7.5 `--doctor` (nasm/link/kernel32/versão; FECHADO 1.2.248:
  `src/diag/doctor.asm`, `dex_doctor(cfg,img) → 0`, inspect-only,
  `-q` não suprime, existência via open (`ok`/`missing` honesto),
  aceita `-doctor` e `--doctor`; `[20]` na suíte)

## Fase 8 — Layout robusto (R-8.x, nova)

> PEs reais têm `.bss`/`.tls`/seções que o path win64 (link.exe) não
> preserva. N.1 (R-8.1) fecha o nível asm; comportamento em PE grande
> pede R-8.2 (backend próprio). Detalhe e sondas em `docs/REVISAO.md`.

- [x] R-8.1 `.bss` com `resb` + labels (`src/gen/rebuild.asm`: `.wds_bss`
  (label do início + `resb` fatiado nos alvos R) + `.ptr_tgt_ok` que
  aceita `off<vsize` se `raw==0` + `s_resb`; `[35]` com 7 checks
  (resb/labels/`dq` no var64, resb no gcc)). Oráculo capstone: 24 VAs
  interiores distintas referenciadas no var64 (start-label só não
  bastava); soma `resb` == vsize exato (0xB90); monta com 0 erros.
  Limite honesto: comportamento em PE grande segue pendente (D-19).
- [ ] R-8.2 backend próprio com `.text` nativa (R-6.6): controle total
  de layout (sem link.exe); prova = swap + `hello.c` → `hi` com o
  binário `-native`. Caminho fiel hoje: `-m bin` (já prova compilador
  funcional: `gcc_bin.exe` compilou `hello.c` → `hi`).

## Dívida técnica conhecida (honesta, com ID)

- D-1 convenção ADR estabelecida (2026-10-12): `docs/adr/0001-ast-lexer-codegen.md`
  existe e numerado; dívida original ("sem ADRs numerados") superada;
  novas decisões seguem `NNNN-<título>.md`.
- D-2 `.bss` auditada (2026-10-12): win64 emite seção vazia (link
  dimensiona SEM o vsize); var64 tem 0xB90 referenciados e o rebuild
  win64 roda mas imprime vazio (limitação R-4.4 confirmada p/ PEs
  complexos); caminho fiel `-m bin`; contramedida futura: `resb`
  vsize nobits.
- D-3 `symtab`/`strpool`/`labels-imp` implementados e linkados mas sem uso
  no generate atual (biblioteca p/ R-3.3/R-4.5; cobertos por build, sem teste
  dedicado — adicionar teste unitário).
- D-4 I/O posicional removido de vez (2026-10-12): externs mortos
  `dex_file_read_at`/`dex_file_write_at` extirpados de `rebuild.asm`
  (declarados, nunca chamados); `mmap_rw` é o desenho.
- D-5 `-no-imports` × `-native` seguro (2026-10-12): sem parse cai em
  `db` (0 `__imp_`, rebuild `hi`); `[26]` trava o combo.
- D-6 `-start`/`-end` auditados (2026-10-12): dados sempre inteiros,
  como documentado — MAIS bug real: `-end` ignorado com `-start`
  presente (`.wcs_oor_l` só conhecia `< start`, lote vazio reentrava
  como in-range); fix 2 linhas + `[25]` com round-trip.
- D-7 Tabela D REATIVADA como bitmap (1.2.266, fecha a dívida): 1 bit por
  RVA até max(vaddr+raw) das seções, 1 `malloc` zerado, `bts`/`bt` O(1)
  (o hash antigo — 2 `HeapAlloc` + lookup O(n²/256) — travava o `ld.lld`);
  OOM/desligado degrada p/ `db` (legado), sem erro. Leitores reais:
  jump-tables p/ código (`dq label_`, `[28]`) + gates no walker
  (R-membership p/ DATA, bit-D p/ CODE convertem refs sem label em
  `db`); sem eles o var64 `-native` não montava (símbolos `.bss`
  indefinidos + cascata). `g_symD` (hash) extirpado.
- D-8 Regra de slots de spill (2026-10-07, bugs reais desta sessão; EXTENSÃO
  2026-10-13, Fase C: `r13` não sobrevive a calls internos mesmo quando o
  helper dá push nele (`asmbuf_append` preserva rbx/r12 mas o `len` em
  r13d voltou lixo — provado por 8 builds de bisseção no sanitize de
  seção; causa-raiz exata em aberto); regra prática: RECOMPUTAR valores
  após calls em vez de confiar em não-voláteis (ver `.sn_relen`):
  `[rbp-8..-56]` num frame `8 pushes + sub rsp,88` são os registradores
  salvos (nunca usar como spill!); spills só em `[rbp-64..]` (dentro do
  frame, fora da shadow de calls aninhados); registradores não-voláteis
  (`rdi/r13/...`) nunca sobrevivem a `mov rdi, ...` inline — recarregar
  do slot (caso `.collect_syms`: `edi` count vs `rdi` base → hang);
   `r10/r11` morrem em syscalls ntdll (não manter valores através de
   `HeapAlloc`/`WriteFile`); `edx` morre em `.build_rm` (base SIB).
   Instância 2026-10-12 (fuzz): `.fill` de `pe_imports` com `di/vi` em
   `r10d/r11d` através de `dex_rva_to_offset` (que usa `r10d`!) nos
   early-paths → `inc` nunca alcançava `n_desc` (hang em PE corrompido);
   fix: spill `[rbp-64]/[rbp-68]` no topo + reload no `.fill_next`
   (com refresh no `.thunk_end` p/ não perder `vi`).
- D-9 Regras do frontend textual (2026-10-07, R-6.3; todos com
  reproduzir→fix→suite 52/52):
  `div` nunca com divisor vindo de call sem spill (`ast_grow_arr`:
  `r9` elemsz com push + guarda `test r9,r9`; forma sem `div`
  preferida p/ capacidade); índice de loop com calls dentro usa
  registrador não-volátil (`bi` em `edi` no free); `m` (índice do
  mnemônico) vive em spill `[rbp-72]` entre dispatch e code_instr
  (`r11d` volátil morre nos calls de abertura); meio de ident aceita
  `_?#@~.$` (faixa Z..a cai em `.ti_ck1`; golden 166→164);
  diretiva vale por tok0 com qualquer tok1 (`bits 64`); `db`/`equ` bare
  (tok0 é a keyword) viram dados sem label; imediato aceita sinal
  prefixado ao único NUM com fold (`-11`) e size pela magnitude.
- D-10 Regra de alinhamento de pilha (2026-10-07, R-6.4 fatia 1; bug
  real: AV em todo `call` do driver novo): antes de CADA `call`,
  rsp%16==0 (ou seja, `(pushes + sub) % 16 == 8` na entrada, quando
  rsp%16==8). Função sem frame usa shadow `sub rsp, 40` (não 32) nos
  calls internos; contar pushes de verdade (rbp conta!); comentário de
  frame sempre com a conta explícita. Corrigidos juntos: `dex_ast_dump`
  (8 pushes + `sub 32` → `sub 40`; funcionava por sorte) e comentário
  do `dex_ast_free_unit` (7 pushes + 32 = 88, não "6+32=80").
- D-11 Regras da fatia 2 (2026-10-07, todos com reproduzir→fix→suite):
  argumentos em registradores voláteis morrem no `call` — spill de `j`
  (`r10d`) em slot antes do helper (garbage→len gigante→OOM→erro 2);
  `name` de símbolo segue convenção do arquivo (`symtab_*`, não
  `dex_*`); endereçamento x64 não tem `[rel base+índice]` (via
  registrador); nunca editar fonte via round-trip ASCII (mojibake em
  comentários — reparar na hora); `db` de teste com bytes exatos
  (`ImportEntry` tem 33 B com 1 `db` a mais: `iat_rva` desloca).
- D-12 Regras da fatia 3 / depuração (2026-10-07, bloqueador aberto):
  file-scope (`global` ou label sem ponto) no MEIO do arquivo parte o
  escopo dos labels locais — globais novos vão no fim (`dex_emit_imp_label`,
  `dex_build_impname`) ou viram globais in place; `if errorlevel 1`
  IGNORA crash (AV é negativo: falso "OK" + skips silenciosos) — usar
  `if !errorlevel! NEQ 0` em toda checagem de saída do dexter;
  VEH temporário p/ RIP exato vai em `tools/` + hook mínimo (REMOVER
   tudo depois; nunca retornar CONTINUE_SEARCH — sair via ExitProcess);
   sondas que chamam print corrompem a medição se usarem regs vivos
   (`write` usa `r9`!); `select` sem newline é ambíguo; não confiar em
   memória de configs de bisect — re-verificar o estado real (`grep`).
- D-13 Regra de slots qword (2026-10-11, bug real R-6.4.3: `[rbp-96]`/`[rbp-100]`
   a 4 bytes no `.wds_chunks` corrompiam `va`/`img` mutuamente → AV em
   `dex_emit_imp_label`): slots qword SEMPRE em múltiplos de 8 dentro da
   área (`-72,-80,-88,-96,-104`, nunca `-100`); ao revisar frame, listar
   todos os `[rbp-N]` e conferir pares com |…|<8; desconfiar de `mov`
   com disp8 `9C`/`A0` adjacentes no `.lst`.
- D-14 Regra jtmp×RSP (2026-10-11, bug real R-7.4: frame 8 pushes +
   `sub rsp, 320` ⇒ `RSP=RBP-376`, mas jtmp em `[rbp-384]=[RSP-8]`; todo
   `call` leaf sem shadow empurrava o retaddr DENTRO do jtmp e o escape
   o sobrescrevia → `ret` p/ ASCII → AV em `.s_esc`/`.c_esc`): buffers
   de escrita NUNCA em `[RSP-8]`; frame atual 8 pushes + `sub rsp, 328`
   = 392 ⇒ `[rbp-384]=[RSP]` exato; leaf-call sem shadow só toca
   `[RSP-8]` (seguro); ao criar buffer local, provar `[base]≥[RSP]`.
- D-15 `dex_console_write` com 5º arg (`lpOverlapped`) em `[rsp+32]`
   em vez de `[rsp]` (2026-10-11, latente: funciona por lixo benigno).
- D-16 `asmbuf_append_u64_hex` com prólogo duplicado aparente
   (outer+inner, label `dex_append_u64_hex_tmp:` no meio) e epílogo
   único (2026-10-11, latente: funciona em todos os testes — hex
   correto, RBP/RSP íntegros no chamador; NÃO mexer sem prova +
   suite; auditar com `.lst` antes de simplificar).
- D-17 Regra do pré-scan unificado (2026-10-12, 3b `.collect_strs`):
   pré-scan que alimenta g_symR DEVE espelhar o conjunto emitido
   (skip `.reloc`, filtro `-s`, trim-wide pdata/xdata) sempre na direção
   segura (na dúvida NÃO insere → `db` fallback, nunca símbolo
   indefinido); validador compartilhado `.ptr_tgt_ok` rejeita código
   (labels incertas), `.reloc` skipada e fora-do-eff; `dq` só p/ VA com
   label garantida (chunks fatia em todo R do range).
- D-18 `struc` com append quebra fakes manuais dos drivers (2026-10-13,
  Fase D1: `PeImage.arch` no fim fez `lift_check` ler `arch=1` — o
  `fake_img` tinha um `dq` a mais e o `dd 1` (ex-`is_valid`) caiu sobre
  `arch`; goldens viraram CALL/DATA sem IMPORT e a suíte pegou).
  Regra: todo `fake_*` em `tests/` deve espelhar o layout exato do
  `struc` (comparar campo a campo) + zerar `arch` (x64).
- D-19 `link.exe` funde seções (2026-10-14, R-8.1: provado por 3 sondas
  + `secdump` — `.bss`/`.tls`/`.xdata` do `.obj` somem no `.exe`,
  conteúdo fundido em `.data`; `resb` no nasm vira zeros inicializados,
  nunca nobits; `dex_patch_dirs` (R-4.3) copia RVAs cegamente e aponta
  p/ seção errada após o remanejo — `imp`/`iat` do var64 caíram dentro
  da `.reloc` nova). Consequência: rebuild `-native` via link só
  garante comportamento em PEs simples; PEs reais pedem R-8.2.
