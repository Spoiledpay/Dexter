# Dexter — Roadmap (requisitos R-x.y + status real)

Legenda: `[x]` implementado + testado em Windows (`tests\run_tests.bat`
**438/438 OK** em 1.2.422; lenta `run_slow.bat` **7/7**); `[ ]` futuro.
IDs estáveis para branches/commits. **Fonte única da fila de execução:**
`marco.md` §8 — este arquivo registra o status por requisito.

## Fila de execução (2026-10-22, após 1.2.417)

> Ordem de execução em `marco.md` §8. Nada aqui vira `[x]` sem teste verde.

- [x] **D-19 fatia 2b** — import table simbólica no `win64 -native` (port da
  R-5.3 F1–F4): descritores `dd label wrt ..imagebase`, thunks
  `dd label wrt ..imagebase, 0`, hint/name e nomes de DLL simbólicos; gaps
  via `.wds_chunks`/`.wds_gap_win`. Fechada 1.2.407, `[56]` 9 checks
  (suíte **402/402**). No caminho, corrigido o parser de imports (spill de
  `di` volátil): `exc` 1→69, `var64` 14→62. `PE_NOTES §26`, ADR-0003.
- [x] **D-19 fatia 2c — fix** (1.2.415, `[57]`): `db` com disp32 RIP-relative
  vira `db <prefixo>` + `dd label_<alvo> - $ - 4 [- 0x<imm>]` + `db <imm>`
  (REL32 do COFF x64; o link recalcula). `exc` 42→0, `var64` 47→0,
  `notepad` 14 corrigíveis→0. Junto: `call|jmp [mem]` com REX → `db`
  (encoding 7→6 B encolhia e deslocava labels; `.CRT` agora byte-idêntico)
  e seção uninit → classe `bss` (nobits; sem `-w+zeroing`/`LNK4078`).
  Comportamento provado: `var64 -native -r` → exit 0. `PE_NOTES §28`.
- [x] **D-19 fatia 2c-2 — recusa honesta** (1.2.417, ADR-0004): o `win64
  -native -r` detecta `__gxx_personality_*`/`__gcc_personality_*` na import
  table e recusa com exit 4 (mensagem `pcrel` + `-m bin`). As tabelas C++ do
  GCC são posicionais e o `link.exe` não as relocaliza; `-m bin -native -r`
  segue fiel (`exc` exit 42). `-native` sem `-r` continua gerando/auditando.
  Pós-patch do LSDA (parser DWARF EH) fica como evolução futura.
- [x] **D-19 fatia 2c-3** (1.2.417): `.data` com `vsize > raw` emite o tail
  zerado (`times N db 0`) com `label_` nos alvos R; `.ptr_tgt_ok` aceita
  `off < vsize` no modo link. `notepad`: 1238 refs com label (`rip_audit` 0
  falsos; `ptr_audit` 0). Fixture `tests/taildata.asm` + patch/check;
  `-m bin` segue byte-idêntico. `PE_NOTES §29`.
- [x] **Base simbólica do índice em x64** (1.2.422, `[59]` 12 checks) — x32
  já saía `[nosplit label_<VA>+idx*scale]` (1.2.379); em x64 o disp32 é
  **sinal-estendido**, então só é VA da imagem quando positiva (base < 2
  GiB). Fix: coletor `.cs_abs64sib` (`movsxd` + gate `mod00/rm100/has_sib`
  antes do teste RIP) e emissor aceitando ambos os modos. No `-m bin` o
  label vale file offset → `+ 0x<C>` com `C = VA - off` via `g_abs_corr`;
  novo `.gb_rchunks` semeia `label_<VA>:` nos dados (seção sem imports,
  gaps e resto de `.gb_db_slots`). Fixture `tests/absidx64.asm` (base
  `0x400000`), `tests/absidx64_check.py`; bin byte-idêntico + exit 42.
  `PE_NOTES §31`.
- [ ] **Semântica de operandos VEX/EVEX/x87** — decodificação/limites são
  byte-exatos (R-2.7), mas o nativo emite `db`; falta a semântica de
  label/operando.
- [ ] **R-6.6 (opção C)** — IR otimizável + backend próprio (`-f bin` sem
  nasm). Depende de R-6.1–R-6.5 (fechados) e do corpus estável.
- [ ] **Cobertura de imports por ordinal** no `-overview`/`-json` (R-7.1):
  limite honesto sem caso no corpus atual.

## Fase 0 — Esqueleto, CLI e I/O `[x]`

- [x] R-0.1 Pastas + `build.bat` (nasm+link autodetect) + `clean.bat`
- [x] CTX (`ctx.exe`) na pipeline: `build.bat` registra proveniência
  (`ctx build record out\dexter.exe`) + atualiza índice (`ctx scan`) a cada
  build (best-effort); uso em `skill.md` §10; `.ctx/` ignorado, `.ctx.yaml`
  versionado. Higiene: `tests/ld.lld.asm` (734 MB gerado, versionado desde o
  baseline) destrackeado via `git rm --cached` + `.gitignore` — era o que fazia
  o índice do CTX ir a ~3 GB
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
- [x] R-2.7 VEX/EVEX (`C4/C5/62`), x87, 3DNow! rotulados (1.2.327): decoder
  VEX2/VEX3/EVEX em x64 (prefixo em `npre`, mapa 0F/0F38/0F3A, flags/imm das
  tabelas 2/38/3A, `Insn.enc` 1/2, mnemônico `vex`/`evex`); x87 com mnemônico
  REAL (`src/disasm/x87.asm`: 64 mem + 512 reg, 576 codificações vs capstone
  5.0.7 = 0 divergências); 3DNow! com o byte-sufixo (`tbl2_flag[0F]` agora
  `F_MODRM|F_I8`); `semantics` recusa VEX/EVEX no nativo (db garantido).
  Corpus `tests/vex.asm` + driver `tests/x87_check.asm` + `[39]` (29 checks):
  limites byte-a-byte (VEX2/VEX3/0F38/0F3A/EVEX/3DNow) + round-trip
  byte-idêntico + comportamento (`exit 42`). Limite honesto: semântica de
  label/operando de VEX/EVEX segue futura (db byte-exato)

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

## Fase 5 — Fidelidade total e modo `bin` `[x]`

> R-5.1–R-5.4 fechadas. O que resta de fidelidade em PE real no modo
> `win64` é **layout/link** (D-19, Fase 8), não o motor de desassemblagem
> nem o modo `bin`.

- [x] R-5.1 `-m bin`: headers+seções+overlay em `db` + `times` pad →
  `nasm -f bin` = **byte-idêntico** (hello 2560 B e var64 91872 B:
  `fc /b` igual + comportamento igual)
- [x] R-5.2 round-trip testado: win64/hello (`hi`, exit 0) e bin/hello+var64
- [x] R-5.3 `-f bin` com import table REGENERADA. **F1 FECHADA** (1.2.341): em
  `-m bin -native` os imports deixam de cair em `db` — o walker emite
  `call|jmp [rel __imp_X + K]` e o caminho de dados do bin injeta
  `__imp_X:` nos slots da IAT (`.gb_db_slots`). **K é a correção de delta
  obrigatória**: em `-f bin` os labels valem FILE-OFFSET, então uma
  referência RIP-relativa entre seções sai com `disp32` errado por
  `K = iat_rva − off(slot) − (vaddr_code − raw_code)` (hello/var64:
  0xE00/0x6600). Prova: hello/var64 (e gcc 2 MB + ld.lld 68 MB na lenta)
  `fc /b` 0 diffs **com** `[rel __imp_` no `.asm`; `[36]`/`[37]` travam o
  gate (db silencioso seria byte-idêntico e passaria). **F2 FECHADA** (1.2.347): os `IMAGE_IMPORT_DESCRIPTOR` viram
  `label_<VA>:` + 5 `dd` no `-m bin -native` — `OriginalFirstThunk`/`Name`/
  `FirstThunk` saem `dd label_<alvoVA> + C` (`C = vaddr − raw_ptr` da seção do
  alvo; igual ao `.pdata` da F3) e os alvos (ILT/nome/IAT) são rotulados;
  limite do dir = **descritor terminador** (o `Size` abarca ILT/nomes, não só
  descritores); alvo não-rotulável → `dd 0x<rva>` (byte-idêntico, sem label
  indefinido). Gate **estrutural** `tests/pe_impdesc.py` + `[45]` (330/330).
  Prova: hello/var64/gcc `fc /b` 0 diffs + comportamento. Limite honesto:
  `ld.lld -m bin -native` já falhava no nasm **antes** da F2 (PE_NOTES §14).
  **F3 FECHADA** (1.2.364): as arrays de thunks (OFT/ILT e FT/IAT) deixam de
  ser `db` — cada entrada não-nula sai `dq label_<hint/name VA> + C` (mesma
  constante `C`; o alvo ganha `label_`); ordinal (bit63) ou IAT *bound*
  (valor > 32 bits) ou alvo não-rotulável → `dq 0x<v>` cru (byte-fiel). O
  alvo é registrado **independente** do slot (o scanner resolve 1 VA por
  iteração). Gate: `tests/pe_impdesc.py` estendido + `[47]` (343/343);
  hello/var64/exc/gcc/notepad `fc /b` 0 diffs. Prova do ramo cru: notepad
  (`thunks=630 sym=620 raw=10`). **F4 FECHADA** (1.2.367): a import table
  fica **100% regenerada** — cada `IMAGE_IMPORT_BY_NAME` sai
  `dw <hint>` + `db "<nome>", 0` e o `Name` do descritor sai
  `db "<dll>", 0` (via `dex_emit_qstr`, promovido a file-scope: os `.gb_*`
  moram em `dex_generate_bin` e não alcançavam o antigo local
  `.emit_qstr` de `dex_generate_asm`). Gate `[48]` (350/350); prova:
  hello `hint=6 nomes=1`, notepad `hint=620 nomes=50`, todos `ruins=0`.
  Não-ASCII/não-imprimível ou sem NUL → fallback `db` (byte-fiel).
- [x] R-5.4 strings em code-flow, jump tables, SEH/unwind reemitido,
  fuzz `tests\fuzz_pe.py` — **TODAS as fatias fechadas** (detalhe abaixo).
  Base 1.2.250 (3b: pré-scan `.collect_strs` insere starts de runs +
  alvos de ponteiros em g_symR; `.wds_emit_span` emite `dq label_` em
  `-native`, `s_tab` simbólica, round-trip strings provado, `[21]` verde)
  + 1.2.257 (base rotulada via R + corpus `jtable.asm` + `[27]` + fix
  `jmp/call r64` sem REX (`.l1_ffmem`)).
  **Fatia "loads indexados" FECHADA** (1.2.371): operandos **SIB-abs COM
  índice** (`[disp32 + idx*scale]`, base ausente — o `[idx*scale]` de x64 e
  o `[0x40A000+eax*4]` de x32) deixam de cair em `db` e saem textuais e
  byte-exatos: `[nosplit abs 0x<disp>+<idx>*<scale>]` (x64) /
  `[nosplit 0x<disp>+<idx>*<scale>]` (x32); disp32==0 omite o disp. Gate
  `[49]` (fixture `tests/sibabs.asm`, byte-idêntico + exit 42); notepad
  `-m bin -native` `fc /b` 0 diffs. Base simbólica na fatia seguinte
  (x32 fechada; x64 segue numérico — ver "Pendências abertas").
  **Fatia "base simbólica do índice" FECHADA** (1.2.379, x32): em x32 o
  disp32 de um SIB-abs é uma VA do image (base ~0x400000, cabe em 32 bits);
  o scanner (`.cs_abs32sib`) registra a VA no R e o emissor sai
  `[nosplit label_<VA>+<idx>*<scale>]` (antes `0x402008` cru). O emissor
  consulta o R via globais próprios (`g_abs_vas`/`g_abs_n`/`g_abs_base`,
  preenchidos pelo rebuild) — **dados, não função**, p/ os drivers que linkam
  só `emit_nasm.obj` fecharem. x64 fica numérico (VA da imagem não cabe em
  32 bits e `-f bin` precisaria de `+C`). Gate `[51]` + `tests/absidx.asm`
  (`jmp [jtab+eax*4]` switch real, round-trip exit 42).
  **Fatia "jump-to-code (alvos)" FECHADA** (1.2.381): em **x32** os spans de
  dados são de **4 bytes** (`dd`), não 8 (`dq`): `.collect_strs` passada B lê
  dword (arch-aware) e `.wds_emit_span` usa `stride` 4/8 + diretiva `dd`/`dq`.
  A entrada da tabela que aponta p/ **código** (D-7, `.code_tgt_ok`) sai
  `dd label_<VA>` (antes `db 0x..`); a `g_spanflags=1` que forçava db em x32
  foi removida. Prova: `tests/absidx.asm` → `dd label_401017`/`40101E`/... +
  round-trip exit 42. Gate `[51]`.
  **Fatia ".str_run com `\r\n`" FECHADA** (1.2.375): `.str_run` aceita
  CR/LF **dentro** do run (o 1º byte tem de ser imprimível) e o emissor de
  string (`dex_emit_qstr`) fecha/reabre as aspas em volta de cada escape
  (`, 13`, `, 10`, `, 34`) — tudo numa linha NASM, sem `""`. Antes, runs
  com CR/LF eram rejeitados e saíam `db` byte a byte. Gate `[50]` +
  `tests/qstr_check.py` (fixture `tests/strings.asm` com s1/s2/s3).
- [x] R-5.4 SEH/unwind reemitido (F1–F4 FECHADAS — detalhe da fatia acima): **F1** (1.2.329) —
  parser `src/pe/pe_unwind.asm` (`dex_unwind_count`/`dex_unwind_rf`/
  `dex_unwind_info`): decodifica `RUNTIME_FUNCTION` (.pdata) e
  `UNWIND_INFO` completo (.xdata) com validação de limites; driver
  `tests/unwind_check.asm` + `[40]`. **F2 FECHADA** (1.2.33x) — emissão
  win64 SIMBÓLICA (`rebuild.asm .emit_pdata_sec`/`.emit_xdata_sec`):
  `.pdata` vira `dd label_<VA> wrt ..imagebase` e `.xdata` reconstrói
  cada `UNWIND_INFO` (label por info + handler/chained como `dd label
  wrt ..imagebase`); o linker recalcula as RVAs e o EXCEPTION_DIRECTORY
  (ataca D-19). `[41]` (7 checks: seções simbólicas + nasm + link +
  EXC dir válido). **F3 FECHADA** (1.2.33x) — emissão bin SIMBÓLICA e
  **byte-idêntica**: RVA em `-f bin` vira `dd label_<VA> + C` (C =
  `vaddr − raw_ptr` da seção do alvo; expressão constante); `.xdata`
  usa **bitmap** de inícios (os unwind RVAs da `.pdata` NÃO são
  monotônicos) + propagação de `chained`; cauda não-múltipla-de-12 da
  `.pdata` sai `db`. `[42]` (4 checks). Gate: `fc /b` 0 diffs em todo o
  corpus + gcc (2 MB) + ld.lld (68 MB) e comportamento. **F4 FECHADA**
  (1.2.338, `[43]` 6 checks): corpus de **exceção real** `tests/exc.exe`
  (`tests/exc_cpp.cpp`, C++ `throw`/`catch`; 117 `RUNTIME_FUNCTION` com
  handler `__CxxFrameHandler3`) — `-m bin -native` byte-idêntico **e** o
  reconstruído roda o throw/catch (**exit 42**), provando que a
  `.pdata`/`.xdata` simbólica é funcional, não só fiel. Modo win64 do
  fixture segue **D-19** (`0xC000007B`: o link funde 18→16 seções e o
  Import Directory cego aponta p/ `.bss` — `PE_NOTES §11`).
- [x] **R-5.4 estendido** — `UNWIND_INFO` em QUALQUER seção (1.2.356): o MS
  link funde o `.xdata` no `.rdata` em PE real (ex.: `notepad.exe`), então o
  unwind **não** está numa seção nomeada. Núcleo `.uw_bitmap` (inícios na
  seção, da `.pdata` + `chained` propagado) + `.uw_emit` (label + `db` do
  header/codes + `dd` simbólico dos campos RVA via `.pd_field`), reusado no
  bin (`.gb_db_slots`) intercalado com imports/db — byte-exato. Corpus
  `tests/notepad.exe` + `[46]` (5 checks): `-m bin` byte-idêntico; `-m bin
  -native` COMPILA (antes: 386 `symbol not defined` da `.pdata`). **D-20
  FECHADA**: `-m bin -native` do notepad agora **byte-idêntico** — ALU/mov
  reg-reg na forma "load" cai p/ `db` + prefixo de segmento (`gs:`/`fs:`)
  reemitido nos caminhos sem base (`src/disasm/emit_nasm.asm`). win64 de PE
  MS real segue **D-19**. `PE_NOTES §15`.
- [x] R-5.4-fuzz `tests\fuzz_pe.py` mínimo (1.2.253, determinístico por
  seed: flips + miradas em MZ/lfanew/seções/imports + truncamento;
  mutante nunca executado; passa = saída em {0,1,2,3,5}; `[22]` com
  20 casos seed 7; 1 hang real achado (imports, D-8) e corrigido;
  **F4** amplia p/ `.pdata`/`.xdata`: ops EXC dir / flip pdata / flip xdata
  / `UnwindData` corrompido + flag `--bin-native`; 300 (win64) + 300
  (bin-native) casos em `tests/exc.exe` sem crash/hang)

## Fase 6 — AST / Lexer / Geração de código nativo `[x]` (R-6.6 futura)

> Decisão documentada em `docs/adr/0001-ast-lexer-codegen.md` (2026-10-07).
> **R-6.1–R-6.5 FECHADOS**: `-native` liga o caminho nativo no walker
> (`build_operands` + `emit_native` + fallback `db`, tamanho exato
> garantido); lexer/parser/AST + lifter/codegen entregues e testados;
> `db` continua o default. **R-6.6** (IR otimizável/backend próprio)
> segue `[ ]` na fila de pendências.

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
  `[16]` na suíte (texto/json/inspect-only/`imports_count`=62 no
  var64). Limite honesto: imports por ordinal (`func` vazio) sem
  cobertura no corpus atual.
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
  FECHADO 1.2.245, `[19]` na suíte)
- [x] R-7.5 `--doctor` (nasm/link/kernel32/versão; FECHADO 1.2.248:
  `src/diag/doctor.asm`, `dex_doctor(cfg,img) → 0`, inspect-only,
  `-q` não suprime, existência via open (`ok`/`missing` honesto),
  aceita `-doctor` e `--doctor`; `[20]` na suíte)

## Fase 8 — Layout robusto (R-8.x) — R-8.1/R-8.2 fechadas; D-19 2b/2c fechadas

> PEs reais têm `.bss`/`.tls`/seções que o path win64 (link.exe) não
> preserva. N.1 (R-8.1) fecha o nível asm; R-8.2 fechou o **caminho fiel**
> `-m bin` (byte-idêntico em PE grande). O que resta é o **win64** em PE
> real (D-19). Detalhe e sondas em `docs/REVISAO.md`.

- [x] R-8.1 `.bss` com `resb` + labels (`src/gen/rebuild.asm`: `.wds_bss`
  (label do início + `resb` fatiado nos alvos R) + `.ptr_tgt_ok` que
  aceita `off<vsize` se `raw==0` + `s_resb`; `[35]` com 7 checks
  (resb/labels/`dq` no var64, resb no gcc)). Oráculo capstone: 24 VAs
  interiores distintas referenciadas no var64 (start-label só não
  bastava); soma `resb` == vsize exato (0xB90); monta com 0 erros.
  Limite honesto: no modo **win64** o comportamento em PE grande segue
  pendente (D-19); o caminho `-m bin` foi fechado em R-8.2 f3.
- [x] R-8.2 fatia 1 — bin com `.text` nativa em PE simples (1.2.308,
  `[36]` 7 checks): `-m bin` + `-native` em x64 gera CODE via walker
  (gate mesma-seção + imp→db; refs `dex_generate_asm.*` sem reescopo)
  e DATA db-verbatim; prova: hello byte-idêntico + `hi` + AST 217
  instrs, tiny exit 42 = original. Raiz do disp: sem `vstart`, labels
  valem file-offset (sondas `rel`/`vstart` documentam).
- [x] R-8.2 fatia 2 — exatidão byte-a-byte em PE real (1.2.315, `[37]`):
  var64 `-native-bin` byte-idêntico + comportamento idêntico; 5 classes
  fechadas por iteração `fc`+listing (disp-zero→db; nop-longo→db;
  jcc/jmp short//near explícitos contra ponto-fixo local do nasm;
  imm8-negativo `-0x`; grp2 com `rcl` faltando); oráculo capstone.
- [x] R-8.2 matriz pequenos (1.2.315, `[38]` 15 checks): loop/strings/
  no_relocs/jtable/t32 `-native-bin` byte-idênticos + comportamentais;
  t32 sem fonte (oráculo = exit do original); memsz sem run (fixture
  com AV pré-existente); var64-win64 documentado (AV por D-19, f3).
- [x] R-8.2 fatia 3 — PE grande (gcc `-native-bin`, 1.2.325): `-m bin
  -native` do gcc gera 17 MB `.asm`, `nasm -f bin` 0 erros, `fc /b`
  **byte-idêntico** (2.064.976 B) + comportamento provado por swap do
  toolchain (gcc reassemblado compila `tests/hello_f3.c` → `hi`, restore
  verificado por hash). 2 bugs reais fechados: (a) `semantics .l2_bt`
  forçava `s_bt` p/ A3/AB/B3/BB (BTS/BTR/BTC saíam `bt`) → mne por
  opcode + tbl2 `B3→s_btr`/`BB→s_btc`; (b) shift/rotate por CL (D2/D3)
  MEM sem prefixo de tamanho (nasm assumia byte, `D3→D2`) →
  `emit_nasm .fo_mem` força prefixo por op0.size. `[S2]` em
  `tests\run_slow.bat`.
- [x] Núcleo da Fase 8 fechado (R-8.1 + R-8.2 f1–f3): o caminho fiel
  `-m bin` é byte-idêntico do corpus pequeno ao PE grande (gcc/ld.lld).
- [x] D-19 **fatia 2b FECHADA** (2026-10-21, 1.2.407): import table
  simbólica no `win64 -native` (port R-5.3 F1–F4). `[56]` 9 checks; suíte
  **402/402**; `pe_impdesc.py win64` no `exc` = 42 campos / 138 thunks /
  138 hints / 14 nomes, `ruins=0`; rebuildado com `imports_count=69` e
  `pe_dirs.py` 5/5. Corrigido junto o parser de imports (spill de `di`
  volátil em `.fill`): `exc` 1→69, `var64` 14→62. Falta o **fecho da
  fatia 2** (comportamento do `.exe`: fusão de `.bss`/`.tls`/`.CRT`).
  `PE_NOTES §26`, ADR-0003. Detalhe na fila do topo e em `marco.md` §8.
- [x] **D-19 fatia 2c-3** (2026-10-22, 1.2.417): tail de `.data` com
  `vsize > raw` emitido (`times N db 0` + `label_` nos alvos R);
  `.ptr_tgt_ok` aceita `off < vsize` no modo link. `notepad`: 1238 refs com
  label, `ptr_audit` 0; fixture `tests/taildata.asm` (original e rebuild
  exit 42). `-m bin` intacto. `PE_NOTES §29`.
- [x] **D-19 fatia 2c-2** (2026-10-22, 1.2.417): recusa honesta do EH C++
  do GCC (`__gxx/__gcc_personality_*` + `-native -r` no modo link → exit 4,
  recomenda `-m bin`). `-m bin -native -r` do `exc` segue exit 42.
  `PE_NOTES §30`, ADR-0004. Pós-patch do LSDA fica como evolução futura.

## Dívida técnica conhecida e regras (honestas, com ID)

> `[x]` = fechada/provada por teste. **D-8..D-18** são regras/lições
> consolidadas (não pendências); **D-19** está fechada para o escopo medido:
> 2a/2b/2c/2c-3 corrigidas e 2c-2 resolvida por decisão (ADR-0004: recusa
> honesta; pós-patch do LSDA é evolução, não regressão).

- [x] D-1 convenção ADR estabelecida (2026-10-12): `docs/adr/0001-ast-lexer-codegen.md`
  existe e numerado; dívida original ("sem ADRs numerados") superada;
  novas decisões seguem `NNNN-<título>.md`.
- [x] D-2 `.bss` com `resb` + labels (R-8.1 FECHADA 1.2.303: `.wds_bss` +
  `.ptr_tgt_ok` aceita `off<vsize`; soma `resb`==vsize, 100+ refs
  simbólicas no var64, monta 0 erros; `[35]` trava). Comportamento em
  PE grande no **win64** pendente de layout (D-19); o caminho fiel
  `-m bin` foi fechado em R-8.2 f3.
- [x] D-3 `symtab`/`strpool` FECHADOS com testes dedicados: `symtab`
  (`tests/sym_check.asm` + `[15]`, golden `SYM n=5`) e `strpool`/
  `asm_buffer` (`tests/strpool_check.asm` + `[44]`, golden
  `STRPOOL o=0 6 B len=11`: offsets estáveis 0/6/11, len 17, `get` por
  offset com `dex_streq`, borda `off>=len -> 0`). `labels-imp` segue
  coberto indiretamente pelo `[13]`/`[14]` (imp_check).
- [x] D-4 I/O posicional removido de vez (2026-10-12): externs mortos
  `dex_file_read_at`/`dex_file_write_at` extirpados de `rebuild.asm`
  (declarados, nunca chamados); `mmap_rw` é o desenho.
- [x] D-5 `-no-imports` × `-native` seguro (2026-10-12): sem parse cai em
  `db` (0 `__imp_`, rebuild `hi`); `[26]` trava o combo.
- [x] D-6 `-start`/`-end` auditados (2026-10-12): dados sempre inteiros,
  como documentado — MAIS bug real: `-end` ignorado com `-start`
  presente (`.wcs_oor_l` só conhecia `< start`, lote vazio reentrava
  como in-range); fix 2 linhas + `[25]` com round-trip.
- [x] D-7 Tabela D REATIVADA como bitmap (1.2.266, fecha a dívida): 1 bit por
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
   Instância 2026-10-21 (D-19 2b): o spill de `di` em `[rbp-72]` ficava
   **depois** de três calls no mesmo `.fill`; `r10d` já era lixo e o laço
   morria no 1º descritor (`exc` 1 import, `var64` 14). Fix: spill de `di`
   no topo (junto de `[rbp-64]/[rbp-68]`), antes dos calls.
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
- D-15 FECHADA (1.2.341): `dex_console_write` reservava só 32 B
   (`sub rsp,32`) e escrevia o 5º arg (`lpOverlapped=0`) em `[rsp+32]`, que
   caía no fundo do frame (benigno por sorte). Agora `sub rsp,48`/
   `add rsp,48` — o slot do 5º arg fica **dentro** do reservado (32 shadow
   + 8 arg + 8 alinhamento).
- D-16 FECHADA (1.2.341, auditoria): o "prólogo duplicado" descrito em
   2026-10-11 **não existe** no código atual (`asmbuf_append_u64_hex` com
   prólogo/epílogo únicos; nenhum caller passa `digits>16`). Comentário de
   alinhamento enganoso ("FALHA!") corrigido; buffer do hex movido p/
   `[rbp-72]` (32 B, acima da shadow) => cobre `digits<=32` sem tocar os
   registradores salvos.
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
- [ ] D-19 `link.exe` funde seções (2026-10-14, R-8.1: provado por 3 sondas
  + `secdump` — `.bss`/`.tls`/`.xdata` do `.obj` somem no `.exe`,
  conteúdo fundido em `.data`; `resb` no nasm vira zeros inicializados,
  nunca nobits; `dex_patch_dirs` (R-4.3) copia RVAs cegamente e aponta
  p/ seção errada após o remanejo — `imp`/`iat` do var64 caíram dentro
  da `.reloc` nova). Consequência: rebuild `-native` via link só
  garante comportamento em PEs simples; PEs reais pedem o fecho da D-19
  (win64) — o caminho `-m bin` já é fiel (R-8.2).
  **Fatia 1 FECHADA** (2026-10-17, 1.2.385): `UNWIND_INFO` em QUALQUER seção
  também no win64. O caminho `asm` só emitia unwind simbólico p/ seção
  `.xdata` literal; com o `.xdata` do MS link fundido na `.rdata`, a `.pdata`
  referenciava 193 alvos (386 refs) sem label → nasm abortava com 386
  `symbol not defined` (`notepad.exe -native`). Fix: `.walk_data_sec` +
  `.uw_bitmap` + caminho `.wds_plain_uw` (fatia por início de unwind; gaps via
  `.wds_chunks` p/ preservar R-labels/spans; unwind via `.uw_emit`), com
  `.uw_next_bit` novo; desligado sob `-s` (D-17/D-21). `[53]` (5 checks).
  Prova: notepad win64 0 erros (antes 386) + 8 outros alvos; `-m bin` intacto;
  `-native -r` já linka (exit 0). **Fatia 2 pendente:** `dex_patch_dirs` cego
  + fusão de seções (comportamento do exe reconstruído). `PE_NOTES §23`.
  **Fatia 2a FECHADA** (2026-10-17, 1.2.386): `dex_patch_dirs` remapeia cada
  DataDirectory por **(seção, offset)** — novo `.pd_remap` (seção original →
  offset → seção homônima rebuildada, `/NNN`→`_NNN`); não copia se não houver
  homônima (nunca RVA velha). Provado: `exc -native -r` mudou de `0xC000007B`
  (imagem inválida; IMPORT apontava p/ a `.bss` nova) para `0xC0000005` (AV) —
  a imagem **carrega**. Oráculo `tests/pe_dirs.py` + `[54]` (4 checks).
  **Fatia 2b FECHADA** (2026-10-21, 1.2.407): as RVAs internas do `.idata`
  (OFT/Name/FirstThunk, thunks ILT/IAT, hint/name e nomes de DLL) agora são
  simbólicas no win64 (`dd label_<VA> wrt ..imagebase`; IAT como
  `dd label, 0`), com gaps via `.wds_chunks`/`.wds_gap_win`. O link recalcula
  as RVAs mesmo reordenando seções. Bug de parser achado junto (di volátil no
  `.fill`): `exc` 69 imports (antes 1), `var64` 62 (antes 14). `[56]` 9 checks;
  `PE_NOTES §26`, ADR-0003. **Falta o fecho da fatia 2**: comportamento do
  `.exe`. **Fatia 2c (diagnóstico) FECHADA** (2026-10-21, sem `src/`): a
  causa é `db` com disp32 RIP-relative congelado (`mov rax,[rip+0xdb69]` da
  IAT → `.bss` nova → `call 0`; `exc` 42 sites, `var64` 47, `notepad` 1252,
  `hello` 0) + `.bss` progbits (`LNK4078`); `.tls`/`.CRT` descartados (TLS
  Directory simbólica, LNK4210 é aviso). Fix provado em sonda:
  `dd label - $ - 4` (REL32). `PE_NOTES §27`,
  `docs/SESSAO-2026-10-21-D19-2C.md`.
  **Fatia 2c (fix) FECHADA** (1.2.415, `[57]` 11 checks): kind 5 no emissor
  (`db` + `dd label - $ - 4` + `db imm`) com gate por label
  (`.ptr_tgt_ok`/`.code_tgt_ok`); REX em `call|jmp [mem]` → `db` (encoding
  exato; era o shift de 1 B que quebrava o `.CRT`); seção uninit → `bss`
  (nobits). Prova: `exc` 42→0, `var64` 47→0, `notepad` 14→0 corrigíveis,
  `label_drift` 0, **`var64 -native -r` exit 0**. **Fatia 2c-3 FECHADA**
  (1.2.417): `.data` `vsize>raw` emite tail `times N db 0` + labels R;
  `notepad` 1238 refs com label e `ptr_audit` 0; fixture `taildata` exit 42.
  **Fatia 2c-2 FECHADA por decisão** (1.2.417, ADR-0004): EH C++ do GCC é
  pcrel; `-native -r` no modo link recusa com exit 4 e recomenda `-m bin`
  (caminho fiel, `exc` exit 42). Pós-patch do LSDA é evolução futura.
  `PE_NOTES §28/§29/§30`.
- [x] D-20 FECHADA (2026-10-16): o codegen nativo agora é byte-fiel em PE MS
  real. Duas classes: (1) ALU/mov **reg-reg na forma "load"** (`02/03..3A/3B`,
  `8A/8B`: reg=dst) cai p/ `db` (o NASM montaria na forma "store" `89/31`);
  (2) **prefixo de segmento** (`gs:`/`fs:`) era descartado nos caminhos sem
  base (`[abs …]`/`[rel …]`) → reemitido via `.fo_segpre`
  (`src/disasm/emit_nasm.asm`). Prova: `-m bin -native` do `tests/notepad.exe`
  = `fc /b` 0; gcc/ld.lld seguem byte-idênticos. `[46]`. `PE_NOTES §15`.
- [x] D-21 FECHADA (2026-10-17): `-s <seção>` × reemissão simbólica SEH. A
  `.pdata`/`.xdata` simbólica (R-5.4) era emitida mesmo com a seção dos alvos
  filtrada-fora (que vira `db` sem `label_` por-VA) → 234 erros de nasm
  (`symbol not defined` + `label changed during code generation`) em
  `tests/exc.exe -s .rdata -native`; sem `-s` o mesmo binário montava 0 erros.
  Fix: `section_filter != 0` pula a exceção `.pdata`/`.xdata` no `.walk_data`
  (caem no `db` comum) — D-17/direção segura. O gap chamado "-s + RIP" **não
  era o RIP** (19 probes em `-m bin` byte-idênticos): era o cruzamento com a
  R-5.4. Limite honesto (fechado pela D-22 em 1.2.390): `-s` filtrando a
  seção do entry + `-r` falhava no link (`LNK2001`/exit 5). `[52]` (7 checks).
  `PE_NOTES §22`.
- [x] D-22 FECHADA (2026-10-19, 1.2.390): `-s <seção>` + `-r` no win64/win32
  falhava no link (`LNK2001: unresolved external symbol label_<entry>`) quando
  o filtro não era a seção do entrypoint: a seção do entry vira `db` e o
  `label_<entry>` nunca era definido (o header só emitia `global`). Fix:
  `.emit_entry_alias` fecha o `.asm` com `label_<entryVA> equ
  label_<secVA> + 0x<delta>`; delta 0 não emite (o label da seção já é o
  entry) e `-s` na seção do entry não emite alias (sem duplicata). Gate
  `[55]` 6 checks: x64 native/db, `-s .text` sem equ redundante e x32 delta 0;
  suíte **391/391**. `PE_NOTES §25`. Detalhe/handoff:
  `docs/SESSAO-2026-10-19-D22.md`.
