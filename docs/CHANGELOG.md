# Dexter — Changelog

Formato: Keep a Changelog. Versões: `vX.Y.Z` (motor.novidades.correções).

## [Unreleased] — README público, licença MIT, CI e financiamento (2026-10-22)

### Adicionado

- **x87 nativo (2a)** (1.2.427): as 2048 codificações `D8-DF` (8 opcodes ×
  256 ModRM) deixam de sair em `db` e passam a instrução real, com forma de
  operando em tabela (`x87_shape`/`x87_memsz` + `dex_x87_form`), novo kind
  `DEX_OP_ST` (`st<i>`), keyword `tword` e tamanho sem keyword
  (`fldenv`/`fnstenv`/`frstor`/`fnsave`). Grafia NASM no texto e no
  comentário (`fneni`/`fndisi`/`fucomip`/`fcomip`). Prova exaustiva:
  `tests/x87nat.asm` + `tests/x87nat32.asm` (gerados por
  `tests/x87_forms_gen.py`), TSV de classificação e
  `tests/x87_native_check.py` — 1796 nativas em x64, 1736 em x32; `fstpnce`
  (8) permanece `db` por não existir no NASM. Seção `[60]` (15 checks);
  round-trip `-m bin -native -r` byte-idêntico e exit 42 nos dois modos.
  Suíte **453/453** e lenta 7/7.
- **Índice simbólico em x64** (1.2.422): `[disp32 + idx*scale]` (SIB-abs,
  base ausente) passa a sair `[nosplit abs label_<VA>+<idx>*<scale>]` também
  em x64, fechando a limitação declarada na 1.2.379 (x32). Em x64 o disp32 é
  sinal-estendido, então a forma só é simbólica quando `ImageBase < 2 GiB`
  (aí endereça a imagem de verdade); acima disso segue numérica e byte-exata.
  No `-m bin` o label vale file offset: o emissor aplica `+ 0x<C>`
  (`C = VA - off`) e o novo `.gb_rchunks` semeia `label_<VA>:` nos dados.
  Fixture `tests/absidx64.asm` + `tests/absidx64_check.py`, seção `[59]`
  (12 checks); suíte **438/438** e lenta 7/7.

- `README.md` reescrito para o estado atual (1.2.419): o que a ferramenta
  faz hoje, modos `win64`/`bin`, `-native`, análise inspect-only, uso,
  flags, testes, limites conhecidos e versão.
- Logo oficial `Dexter_logo_US.png` no topo do README e seção de apoio via
  **GitHub Sponsors**; `.github/FUNDING.yml` habilita o botão Sponsor.
- `.github/workflows/ci.yml`: build em `windows-latest` com MSVC + NASM e
  suíte rápida (`DEXTER_SKIP_LARGE=1`); artefatos `dexter.exe`/map/logs.
- `README.md`, `README.en.md` e `README.zh-CN.md` com seletor de idioma,
  badges de CI/MIT/release e link de download.
- Release `v1.2.419` publicada com `dexter.exe`, zip win64 e
  `SHA256SUMS.txt`; CI run #5 verde no `windows-latest`.

### Alterado

- `LICENSE` MIT com o holder do repositório (`Labsobjects.org | Developer`).
- `.gitignore`: `.Jimi/`, `Jimi.md` e `skill.md` são locais (removidos do
  índice com `git rm --cached`, mantidos no disco).
- `tests/run_tests.bat`: toolchain portável (`LINKER`/`KLIB`/`X86LIB` via
  PATH/SDK) e skip determinístico dos fixtures grandes na CI.
- Fixtures x32 (`Calculator/Case/Char/color/Color2/Contador`), `t32.exe` e
  os pequenos (`loop/tiny/strings/no_relocs`) passam a ser versionados para
  a suíte rodar em clone limpo/CI.
- `.gitattributes`: `*.asm`/`*.inc` em LF (golden do lexer) e binários
  marcados como `binary`.

### Corrigido

- `build.bat`: `exit /b 0` explícito no fim. Sem `ctx` no PATH, o `where ctx`
  deixava `errorlevel=1` e o step Build falhava apesar de gerar
  `out\dexter.exe` (visto na CI).
- `src/cli/parse_args.asm`: defaults de `nasm`/`link` caem para
  `nasm.exe`/`link.exe` no PATH quando `C:\Nasm\...` não existe. Antes, o
  `-r` na CI falhava em todos os rebuilds (`dexter: nasm failed`).
- CI instala `capstone` (usado por `tests/rip_audit.py`).

### Verificado

- `tests\run_tests.bat` **426/426 OK** (local, completo);
  `DEXTER_SKIP_LARGE=1 tests\run_tests.bat` **403/403 OK** (modo CI);
  `tests\run_slow.bat` **7/7 OK**.


## [Unreleased] — D-19 2c-3 (tail de `.data`) + 2c-2 (recusa EH C++ GCC) (2026-10-22)

### Adicionado

- **2c-3 — tail de `.data` com `vsize > raw`**: `.ptr_tgt_ok` aceita
  `off < vsize` no modo link; novo `.wds_tail` emite `times N db 0` com
  `label_<VA>:` nos alvos R do tail. `notepad.exe`: 1238 refs RIP que caíam
  em `db` sem label passam a ter label (`rip_audit` 0 falsos), 2 qwords
  congelados em `.rdata` zeram (`ptr_audit` 0) e `.data` reconstruída mantém
  `vsize=0x2740`/`raw>=vsize`. `-m bin` não muda (byte-fiel).
- Fixture controlado `tests/taildata.asm` + `tests/taildata_patch.py`
  (reduz `SizeOfRawData` de `.data`) + `tests/taildata_check.py` + seção
  `[58]`: original patchado e rebuildado saem 42; labels do tail presentes;
  `-m bin -native` byte-idêntico.
- `rip_audit.py` agora audita só blocos `db` em seção de código (dados que
  parecem instruções, como no `notepad`, não são refs de código).

### Corrigido

- **2c-2 — recusa honesta do EH C++ do GCC** (`docs/adr/0004`): se
  `-native -r` no modo link e a import table traz
  `__gxx_personality_*`/`__gcc_personality_*`, o Dexter sai **4** com
  mensagem citando os encodings pcrel e recomenda `-m bin` (caminho fiel,
  exit 42). `-native` sem `-r` continua gerando/auditando `exc`; o parser de
  imports do `exc` segue travado em 69.
- Gates que usavam rebuild win64 do `exc` migraram para `var64` (5
  DataDirectories, imports 62) e `notepad` (PE MSVC real); a suíte cobre
  recusa, geração, auditorias e comportamento do fixture de tail.

### Verificado

- `build.bat` limpo (1.2.419); `tests\run_tests.bat` **426/426 OK**;
  `tests\run_slow.bat` **7/7 OK**.


## [Unreleased] — D-19 fatia 2c: disp32 RIP relocável + comprimentos exatos (2026-10-21)

### Adicionado

- **Instrução em `db` com disp32 RIP-relative vira REL32**: o emissor ganhou
  `kind 5` (`db <prefixo>` + `dd label_<alvo> - $ - 4 [- 0x<imm>]` +
  `db <imm>`); o nasm emite relocação REL32 no COFF x64 e o `link.exe`
  recalcula o disp quando move a seção alvo. Resolve a classe inteira
  (não só `mov`-from-IAT): `exc` 42 → **0**, `var64` 47 → **0**,
  `notepad` 14 corrigíveis → **0** (1238 seguem como limite honesto).
- Sondas novas em `tests/`: `secdump.py` (PE/COFF + `--diff`),
  `dbg_probe.py` (exceção fatal, RIP/AV/regs/pilha, resolução por módulo),
  `rip_audit.py` (disp32 congelado; gate), `label_drift.py` (comprimento
  por label via listing do nasm), `ptr_audit.py` (qword VA congelado).
- `[57]` na suíte: `dd label_` presente, `.bss` nobits, sem `-w+zeroing`,
  `nasm` 0 erros, `rip_audit`=0 (exc/notepad), `label_drift`=0 (exc) e
  `var64 -native -r` **roda com exit 0** (era `0xC0000005`).

### Corrigido

- **`call|jmp [mem]` com REX.W/B** (7→6 bytes): o nasm descarta o REX
  redundante e a instrução encolhia, deslocando todos os labels seguintes
  (o ponteiro do `.CRT` do `exc` caía em `label-1`). Agora cai em `db`
  (bytes preservados) e o `kind 5` relocaliza o disp.
- **Seção sem bytes no arquivo saía `data` (progbits)**: cada `resb`
  virava zero no arquivo (`-w+zeroing`) e o link via atributos divergentes
  (`LNK4078`). Agora `CNT_UNINIT`/`raw==0 && vsize>0` sai classe `bss`
  (nobits); o `link.exe` funde na `.data` com zero-fill do loader (RVA
  correta, sem bytes no arquivo).

### Limites honestos (abertos)

- **Tabelas de exceção C++ do GCC são posicionais** (`.xdata`/LSDA e as
  seções `/NNN` usam encodings pcrel): quando o `link.exe` move essas
  seções, os offsets relativos congelam e o unwinder salta para endereço
  inválido (`exc -native -r` segue `0xC0000005`, agora dentro de
  `libstdc++-6.dll`). O caminho fiel continua `-m bin -native` (exit 42).
- **`.data` com `vsize > raw_size`**: o tail zerado pelo loader não é
  emitido, então `notepad` mantém 1238 refs RIP sem label (rodam congeladas).

## [Unreleased anterior] — D-19 fatia 2b: import table simbólica no `win64 -native` (2026-10-21)

### Adicionado

- **Import table 100% simbólica no win64** (`-native`): descritores com
  `dd label_<VA> wrt ..imagebase`, thunks ILT/IAT com
  `dd label_<VA> wrt ..imagebase, 0` (RVA de 32 bits zero-estendida em 8 B),
  `dw <hint>` + `db "<nome>", 0` e `db "<dll>", 0`. O `link.exe` recalcula
  as RVAs mesmo reordenando/fundindo seções.
- `tests\pe_impdesc.py` ganhou o modo `win64` (arg 3) para validar a grafia
  simbólica; `[56]` na suíte (9 checks).

### Corrigido

- **`dex_pe_parse_imports` perdia descritores**: `di` (r10d, volátil) era
  gravado em `[rbp-72]` depois de três `call`s e restaurado já como lixo, então
  o laço morria no 1º descritor. `tests\exc.exe` passou de **1 para 69**
  imports e `tests\var64.exe` de **14 para 62** (o gate `[16]` agora exige 62).
- `-strings` × imports: `.wds_gap_win` mantém os runs como qstr nos gaps da
  seção de imports (o `[50]` segue verde) e só degrada p/ chunks quando há
  alvo R no interior do run.
- **`__imp_<dll>_<func>` colidia** quando o mesmo nome aparece em **dois
  slots IAT** (gcc: `_fileno`, `_open`, `_read`, `_close`). A 1ª ocorrência
  mantém o nome puro; as seguintes recebem `_<iat_rva hex>` (regra idêntica no
  walker e em `dex_emit_imp_label`, senão a referência não casa). O `[14]`
  ganhou 2 checks (duplicado com sufixo + nome único puro).

### Verificado

- `build.bat` limpo (1.2.407); `tests\run_tests.bat` **402/402 OK**
  (391 + 9 de `[56]` + 2 de `[14]`).
- `pe_impdesc.py win64` no `exc`: `descs=15 simbolicos=42 thunks=138
  sym=138 hint=138 nomes=14 ruins=0`; `nasm -f win64` 0 erros; `link` 0.
- Rebuildado `exc -native -r`: `-overview` mostra `imports_count=69`
  (14 DLLs) e `pe_dirs.py` 5/5; `hello -native -r` segue `hi`.
- Limite honesto: o `.exe` win64 do `exc` ainda dá `0xC0000005` (fecho da
  fatia 2 — fusão de seções/`.bss`/`.tls`); `-m bin -native` segue exit 42.
- ADR: `docs/adr/0003-win64-import-table-simbolica.md`; notas:
  `docs/PE_NOTES.md §26`; handoff: `docs/SESSAO-2026-10-21-D19-2B.md`.

## [Unreleased] — D-22: `-s` + `-r` com entry label via `equ` (2026-10-19)

### Corrigido

- **`-s <seção>` + `-r` falhava no link (`LNK2001`) quando o filtro não era a
  seção do entrypoint.** A seção do entry era emitida como `db` e o
  `label_<entry>` nunca era definido (o cabeçalho só emitia `global`). Agora
  `.emit_entry_alias` fecha o `.asm` com
  `label_<entryVA> equ label_<secVA> + 0x<delta>`; delta 0 e `-s` na seção do
  entry não emitem alias (sem duplicata nem auto-referência).

### Verificado

- `build.bat` limpo (1.2.390); `tests\run_tests.bat` **391/391 OK** (385 + 6
  de `[55]`); `run_slow.bat` 7/7.
- `tests\exc.exe -s .rdata -native -r` e `-s .rdata -r` linkam (antes exit 5);
  `-s .text -native -r` segue sem `equ` redundante; `tests\tiny32.exe -s
  .rdata -r` cobre x32 com delta 0.
- `[0]` agora valida a integridade de **todos** os fontes sagrados do corpus
  (evita `dexter x.exe -v` sobrescrever `tests\x.asm`).
- Handoff da sessão: `docs/SESSAO-2026-10-19-D22.md`; ADR:
  `docs/adr/0002-entry-label-equ.md`.

## [Unreleased] — D-19 fatia 2a: DataDirectories remapeados por (seção, offset) (2026-10-17)

### Corrigido

- **`dex_patch_dirs` copiava a RVA crua dos DataDirectories.** O `link.exe`
  reordena/funde seções, então a RVA do diretório passa a apontar para outra
  seção (ex.: IMPORT `0x10000` caiu na `.bss` nova em `exc.exe`) → o loader
  rejeitava com `0xC000007B`. Agora um novo `.pd_remap` mapeia por **(seção,
  offset)**: seção original que contém a RVA → offset → `VirtualAddress` da
  seção homônima na rebuildada (nome com `/NNN` → `_NNN`); sem homônima, o
  dir não é copiado (nunca RVA velha). SECURITY/DEBUG são regeneráveis.

### Verificado

- `build.bat` limpo (1.2.386); `tests\run_tests.bat` **385/385 OK** (381 + 4
  novos em `[54]`); `tests\run_slow.bat` **7/7 OK**.
- Oráculo estrutural `tests/pe_dirs.py`: `exc` 5/5 e `hello` 3/3 dirs OK.
  `exc -native -r` passou de `0xC000007B` (imagem inválida) para
  `0xC0000005` (a imagem agora **carrega**). Fatia 2b pendente (RVAs internas
  do `.idata` → import table simbólica no win64).

## [Unreleased] — D-19 fatia 1: `UNWIND_INFO` em qualquer seção (win64) (2026-10-17)

### Corrigido

- **`notepad.exe -native` (win64) abortava com 386 `symbol not defined`.**
  O caminho `asm` só reemitia `UNWIND_INFO` simbólico para uma seção
  literalmente chamada `.xdata`; em PEs do MS link o `.xdata` é fundido na
  `.rdata`, então a `.pdata` emitia `dd label_<unwind VA> wrt ..imagebase`
  para 193 alvos (386 refs) que nunca ganhavam label. Fix: `.walk_data_sec`
  passa a usar `.uw_bitmap` e um novo caminho `.wds_plain_uw` (fatia em
  inícios de unwind; gaps via `.wds_chunks` p/ preservar R-labels/spans;
  unwind simbólico via `.uw_emit`), com `.uw_next_bit` novo; desligado sob
  `-s` (handlers podem estar em seção filtrada — D-17/D-21).

### Verificado

- `build.bat` limpo (1.2.385); `tests\run_tests.bat` **381/381 OK** (376 + 5
  novos em `[53]`); `tests\run_slow.bat` **7/7 OK**.
- notepad win64 `-native`: nasm **0 erros** (antes 386); hello/var64/exc/tiny/
  loop/strings/jtable/no_relocs = 0 erros; `-m bin -native` do notepad segue
  byte-idêntico. `notepad -native -r` já linka (exit 0).

## [Unreleased] — `-s` × SEH simbólico: fim do símbolo indefinido (2026-10-17)

### Corrigido

- **`-s <seção>` + `.pdata`/`.xdata` (R-5.4)** no modo `asm`/`win64 -native`:
  as duas seções eram reemitidas simbolicamente mesmo quando a seção dos alvos
  estava filtrada-fora (e virava `db`, sem `label_` por-VA), gerando
  `dd label_<VA> wrt ..imagebase` para símbolos nunca definidos → o
  `nasm -f win64` abortava com 234 erros em `tests/exc.exe -s .rdata -native`
  (122 `symbol not defined` + 113 `label changed during code generation`).
  Agora, com `section_filter != 0`, a exceção `.pdata`/`.xdata` é pulada no
  `.walk_data` e as duas caem no `db` comum (direção segura do D-17, igual ao
  contrato do `-s`). Sem `-s`, nada muda (o caminho simbólico segue, `[41]`/
  `[46]` verdes); `-m bin` intacto. Limite honesto documentado: `-s`
  filtrando a seção do entry + `-r` falha no link (`LNK2001`/exit 5).

### Verificado

- `build.bat` limpo (1.2.382); `tests\run_tests.bat` **376/376 OK** (369 + 7
  novos em `[52]`); `tests\run_slow.bat` **7/7 OK**.
- `tests/exc.exe -s .rdata -native` → 0 erros (antes 234);
  `-s .rdata -m bin -native` → `fc /b` 0 diffs.

## [Unreleased] — jump-to-code em x32: spans de ponteiro de 4 bytes (`dd`) (2026-10-17)

### Adicionado

- **Spans de ponteiro com stride do arch** (8 = `dq`/qword; 4 = `dd`/dword):
  `.collect_strs` passada B (pré-scan) e `.wds_emit_span` (emissor) passam a
  ler dword e emitir `dd label_<VA>` em x32. Resultado: a tabela de switch x32
  que aponta p/ **código** (D-7 via `.code_tgt_ok`) sai
  `dd label_401017`/`40101E`/... (antes `db 0x..`). Removidos o gate
  `arch==X64` do pré-scan e o `g_spanflags=1` que forçava db em x32
  (`.wds_plain`).

### Verificado

- `build.bat` limpo (1.2.381); `tests\run_tests.bat` **369/369 OK** (368 + 1
  novo em `[51]`); `tests\run_slow.bat` **7/7 OK**.
- `tests/absidx.asm`: `-native` com `dd label_` + round-trip → exit 42;
  `[30]`–`[33]` (x32) e `[49]` (x64 SIB-abs) seguem verdes.

## [Unreleased] — índice simbólico x32 (SIB-abs) (2026-10-17)

### Adicionado

- **Índice simbólico em x32**: em `jmp dword [jtab+eax*4]` (tabela de switch
  absoluta) o disp32 é uma VA do image; o walker/scanner
  (`rebuild.asm .cs_abs32sib`) registra a RVA no R e o emissor
  (`emit_nasm.asm`) sai `[nosplit label_<VA>+<idx>*<scale>]` (antes: `0x402008`
  cru). x64 fica numérico (VA > 32 bits). O emissor consulta o R por globais
  **definidos nele** (`g_abs_vas`/`g_abs_n`/`g_abs_base`, escritos pelo
  rebuild) — dados em vez de função, para os drivers que linkam só
  `emit_nasm.obj` fecharem. Fixes: base do SIB lida nos **bits 2-0**; dispatch
  de SIB antes do check `rm==101` em `.cs_abs32`.

### Verificado

- `build.bat` limpo (1.2.379); `tests\run_tests.bat` **368/368 OK** (361 + 7
  novos: seção `[51]` + `tests/absidx.asm`); `tests\run_slow.bat` **7/7 OK**.
- `absidx` (switch real): `-native` simbólico + round-trip exit 42.

## [Unreleased] — `-strings`: runs com CR/LF numa linha NASM (2026-10-17)

### Adicionado

- **`.str_run` aceita CR(13)/LF(10) dentro do run** (o 1º byte continua
  imprimível) e **`dex_emit_qstr` fecha/reabre as aspas** em volta de cada
  escape (estado `open`): `, 13`, `, 10`, `, 34` saem inline, sem `""`, tudo
  numa linha NASM (`db "alpha-one", 13, 10, 0` /
  `db "say ", 34, "hi", 34, " ok", 13, 10, 0`). Antes, runs com CR/LF eram
  rejeitados e saíam como `db` byte a byte. Só afeta o **texto** (bin ignora
  `-strings`): bytes preservados.

### Verificado

- `build.bat` limpo (1.2.375); `tests\run_tests.bat` **361/361 OK** (357 + 4
  novos: seção `[50]` + `tests/qstr_check.py`); `tests\run_slow.bat` **7/7 OK**.
- `[21]` (round-trip comportamental de `strings.exe -strings`) segue verde;
  `[50]` valida as linhas exatas e o `nasm -f win64`.

## [Unreleased] — SIB-abs com índice: loads indexados (R-5.4) (2026-10-17)

### Adicionado

- **Operandos SIB-abs COM índice** (`[disp32 + idx*scale]`, base ausente)
  deixam de cair em `db` e passam a ser emitidos textual e **byte-exatos** em
  `src/disasm/emit_nasm.asm`: `[nosplit abs 0x<disp>+<idx>*<scale>]` (x64) /
  `[nosplit 0x<disp>+<idx>*<scale>]` (x32); `disp32==0` omite o disp. O
  `nosplit` é obrigatório porque o NASM re-encoda `[abs 0x2+rax*2]` como
  `[rax+rax+0x2]` (4 bytes em vez de 7). Refator: a emissão de `index*scale`
  virou a sub-rotina `.fo_idxemit` (reusada por base+index e SIB-abs). Bug
  colateral x32 corrigido: o caminho absoluto tomava `.fo_abs32` antes de
  checar SIB e descartava o índice.

### Verificado

- `build.bat` limpo (1.2.371); `tests\run_tests.bat` **357/357 OK** (350 + 7
  novos: seção `[49]`); `tests\run_slow.bat` **7/7 OK**.
- Fixture `tests/sibabs.asm` (`lea [idx*scale]`): `-m bin -native`
  byte-idêntico + exit 42. Regressão do emissor: notepad `-m bin -native`
  `fc /b` 0 diffs.

## [Unreleased] — R-5.3 F4: hint/name + nomes de DLL simbólicos (`-m bin -native`) (2026-10-17)

### Adicionado

- **R-5.3 F4** (fecha R-5.3): a import table fica **100% regenerada** no
  `-m bin -native`. Cada `IMAGE_IMPORT_BY_NAME` sai `dw <hint>` +
  `db "<nome>", 0`; o `Name` do descritor sai `db "<dll>", 0`. Em
  `src/gen/rebuild.asm`: `.gb_db_slots` ganha os eventos 32 (hint/name) e 64
  (nome de DLL) + emissores `.gb_hint_emit`/`.gb_name_emit` + `.gb_cstr`
  (cstring bounded imprimível); `dex_emit_qstr` foi **promovido a
  file-scope** (os `.gb_*` estão em `dex_generate_bin` e não alcançavam o
  `.emit_qstr` local de `dex_generate_asm`). Fallback `db` byte-fiel quando o
  cstring não é imprimível/sem NUL/len > 255.

### Verificado

- `build.bat` limpo (1.2.367); `tests\run_tests.bat` **350/350 OK** (343 + 7
  novos: seção `[48]`); `tests\run_slow.bat` **7/7 OK**.
- `fc /b` 0 diffs em hello/var64/exc/gcc/notepad (`-m bin -native`);
  `tests/pe_impdesc.py` (hint/nomes): hello `hint=6 nomes=1 ruins=0`,
  notepad `hint=620 nomes=50 ruins=0`, todos `ruins=0`.

## [Unreleased] — R-5.3 F3: thunks ILT/IAT simbólicos (`-m bin -native`) (2026-10-17)

### Adicionado

- **R-5.3 F3**: em `-m bin -native` (x64) as arrays de thunks deixam de ser
  `db` — cada entrada não-nula de `OriginalFirstThunk` (ILT) e `FirstThunk`
  (IAT) sai `dq label_<hint/name VA> + C` (`C = vaddr − raw_ptr` da seção do
  alvo, a mesma constante da F2); o alvo `IMAGE_IMPORT_BY_NAME` ganha
  `label_` no ponto exato do stream. Ordinal (bit63), IAT *bound*
  (valor > 32 bits) ou alvo não-rotulável → `dq 0x<v>` cru (byte-fiel, sem
  label indefinido). Em `src/gen/rebuild.asm` (`.gb_db_slots`: varredura
  OFT/FT + flag de slot no `best`; emissor `.gb_slot_emit`; alvo descoberto
  independente do slot).

### Verificado

- `build.bat` limpo (1.2.364); `tests\run_tests.bat` **343/343 OK** (336 + 7
  novos: seção `[47]`); `tests\run_slow.bat` **7/7 OK**.
- `fc /b` 0 diffs em hello/var64/exc/gcc/notepad (`-m bin -native`); `hi` e
  `exc` (exit 42) rodam. `tests/pe_impdesc.py` estendido percorre OFT/FT
  (hello `thunks=6 sym=6 raw=0`; notepad `thunks=630 sym=620 raw=10` — prova
  do ramo *bound/ordinal → raw*).

## [Unreleased] — CTX (ctx.exe) na pipeline + higiene do repositório (2026-10-16)

### Adicionado

- **CTX integrado** (`ctx.exe`, no PATH — `C:\ctx\ctx\bin\ctx.exe`): `build.bat`
  registra proveniência (`ctx build record out\dexter.exe`) e atualiza o índice
  (`ctx scan --offline`) a cada build — best-effort (não falha o build se o ctx
  faltar). `skill.md` §10 documenta o uso obrigatório: descoberta
  (`ctx explain/decision/memory/grep/impact`), memórias/decisões, build,
  verificação/auditoria (`ctx smells/health/verify/audit/review/bench`).
- **`.ctx.yaml`** (índice + memórias/decisões) versionado; **`.ctx/`** (store
  local) ignorado.

### Corrigido (higiene)

- `tests/ld.lld.asm` (**734 MB gerados**, o `-m bin` do `ld.lld.exe`) estava
  versionado desde o baseline (`b3be7b8`) — fazia o `ctx scan` produzir um
  índice de **~3 GB**. `git rm --cached` + `.gitignore`; arquivo removido do
  disco (nada o referenciava). Pós-fix: `ctx scan` ~2 s, índice 1,24 MB.

### Verificado

- `build.bat` OK (com o passo CTX, +~2 s); `tests\run_tests.bat` **336/336 OK**.
- `ctx smells` (4 achados reais) + 2 memórias de lição registradas.

## [Unreleased] — R-5.4: UNWIND_INFO em qualquer seção (`.rdata`) + `notepad.exe` (2026-10-16)

### Adicionado

- **R-5.4 estendido**: o `UNWIND_INFO` é reemitido simbólico **onde ele
  estiver** (não só numa seção nomeada `.xdata`). Núcleo reutilizável em
  `src/gen/rebuild.asm` (escopo `dex_generate_asm`): `.uw_bitmap` (bitmap de
  inícios dentro da seção, da `.pdata` + `chained` propagado) e `.uw_emit`
  (`label_` + `db` do header/codes + `dd` simbólico dos campos RVA via
  `.pd_field`). O caminho bin (`.gb_db_slots`) ganhou a varredura de inícios
  de unwind e reemite cada um intercalado com imports/db, byte-exato. Motivo:
  o MS link funde o `.xdata` no `.rdata` em PE real (ex.: `notepad.exe`).
- **Corpus `tests/notepad.exe`** (MS x64 real, 8 seções, 315 imports; sem
  seção `.xdata`) + seção `[46]` na suíte.

### Verificado

- **`-m bin` E `-m bin -native` do notepad byte-idênticos** (`fc /b` 0).
  `-native` antes falhava no nasm (386 `symbol not defined` da `.pdata`).
- `tests\run_tests.bat` **336/336 OK**; `run_slow.bat` **7/7 OK**; corpus
  antigo (hello/var64/gcc/exc) byte-idêntico (bin e `-native`).

### Corrigido

- **D-20 FECHADA** (`src/disasm/emit_nasm.asm`): o `-m bin -native` do PE MS
  real já é **byte-idêntico**. Duas classes achadas com `fc`+listing:
  (1) **ALU/mov reg-reg na forma "load"** (`02/03..3A/3B`, `8A/8B`: reg=dst)
  o NASM monta na forma "store" (`89/31/…`) → agora cai p/ `db` (byte-exato);
  (2) **prefixo de segmento** (`gs:`/`fs:`) era **descartado** nos caminhos
  sem base (`[abs …]`, `[rel …]`) → agora emite `[<seg>:…]` (sub-rotina
  `.fo_segpre`). `fc /b` = 0 no notepad (360448 B).

## [Unreleased] — R-5.3 F2: descritores de import simbólicos (`-m bin -native`) (2026-10-16)

### Adicionado

- **R-5.3 F2**: em `-m bin -native` (x64), os `IMAGE_IMPORT_DESCRIPTOR`
  deixam de ser `db` opaco — cada descritor sai `label_<VA>:` + 5 `dd`, com
  `OriginalFirstThunk`/`Name`/`FirstThunk` como `dd label_<alvoVA> + C`
  (`C = vaddr − raw_ptr` da seção do alvo, idêntico ao do `.pdata` da F3) e os
  alvos (ILT/nome/IAT) rotulados. Só o alvo "rotulável" (seção de dados com
  bytes, não executável, não `.pdata`/`.xdata`) vira simbólico; senão
  `dd 0x<rva>` cru (byte-idêntico). Em `src/gen/rebuild.asm` (`.gb_db_slots`
  + `.gsa_upd`/`.gb_desc_emit`/`.gb_field_emit`/`.gb_dd_hex`/`.gb_tgt_c`).
  O limite do diretório é o **descritor terminador** (não `Size/20`, que
  abarca ILT/nomes).
- **`tests/pe_impdesc.py`** + seção `[45]`: verificação **estrutural** do
  import dir no `.asm` (oráculo = bytes do PE original): cada campo `dd` e
  cada label conferidos — pega regressão que o `fc` (bytes iguais) não pega,
  pois `db` e `dd` são byte-idênticos.

### Verificado

- `tests\run_tests.bat` **330/330 OK**; `run_slow.bat` **7/7 OK**.
- `fc /b` 0 diffs em hello/var64/gcc (`-m bin -native`).

### Limite honesto (pré-existente, não é regressão da F2)

- `tests/ld.lld.exe` (68 MB) `-m bin -native` já falhava no `nasm` **antes**
  da F2: 59160 `symbol not defined` (RVAs de `.xdata` da `.pdata` simbólica)
  + 5 `label-redef-late`, assinatura idêntica com e sem F2. Fora do escopo da
  R-5.3 (tabela de imports). `PE_NOTES §14`.

## [Unreleased] — Dívidas D-3/D-15/D-16 (2026-10-16)

### Corrigido

- **D-15** (`src/io/console.asm`): `dex_console_write` reservava 32 B e
  escrevia o 5º arg do `WriteFile` (`lpOverlapped=0`) em `[rsp+32]`, que
  caía no fundo do frame (funcionava por sorte). Agora reserva 48 B —
  o slot do 5º arg fica dentro do reservado.
- **D-16** (`src/gen/asm_buffer.asm`): auditoria — o "prólogo duplicado"
  descrito em 2026-10-11 **não existe**; nenhum caller passa `digits>16`.
  Comentário de alinhamento enganoso ("FALHA!") corrigido; buffer do hex
  movido de `[rbp-40]` (16 B) para `[rbp-72]` (32 B, acima da shadow),
  cobrindo `digits<=32` sem tocar registradores salvos.

### Adicionado

- **D-3 fechada**: `tests/strpool_check.asm` + seção `[44]` — driver
  dedicado do string pool (`strpool_new/add/get/free` + `asmbuf_len`):
  offsets estáveis 0/6/11, `len==17`, leitura por offset com `dex_streq`,
  borda `off>=len -> 0`. Golden `STRPOOL o=0 6 B len=11`.

### Verificado

- `tests\run_tests.bat` **327/327 OK** (`BAT_EXIT=0`); lenta **7/7**.

## [Unreleased] — R-5.3 F1: imports nativos no `-m bin -native` (2026-10-16)

### Adicionado

- R-5.3 F1: em `-m bin -native` (x64), o walker deixa de mandar `IMPORT`
  para `db` e emite `call|jmp [rel __imp_X + K]`. Os labels `__imp_X:`
  passam a ser injetados nos slots da IAT pelo caminho de dados do bin
  (novo `.gb_db_slots` em `src/gen/rebuild.asm`, fatias byte-exatas via
  `dex_emit_data` + `dex_emit_imp_label`).
- **Correção de delta K** (obrigatória em `-f bin`): como os labels valem
  file-offset, a ref RIP-relativa entre seções precisa de
  `K = iat_rva − off(slot) − (vaddr_code − raw_code)`; `K==0` (mesma seção)
  emite o nome puro. `extern dex_rva_to_offset` adicionado a `rebuild.asm`.
- `[36]`/`[37]`: gates que exigem `[rel __imp_` no `.asm` (o fallback `db`
  é byte-idêntico, então sem o gate a regressão passaria silenciosa).

### Verificado

- hello: 3× `jmp [rel __imp_... + 0xe00]` + 3 labels `__imp_`; `nasm -f bin`
  0 erros; `fc /b` 0 diffs; reconstruído imprime `hi` (exit 0).
- var64: 16 refs nativas (`+ 0x6600`); `fc /b` 0 diffs.
- `tests\run_tests.bat` **323/323 OK** (`BAT_EXIT=0`); lenta **7/7**
  (gcc 2 MB + ld.lld 68 MB `-m bin -native` seguem byte-idênticos).
- Pendente: R-5.3 F2–F4 (tabela simbólica: descritores/ILT/IAT/hint/nomes).

## [Unreleased] — R-5.4 SEH F4: exceção real + fuzz de unwind (2026-10-16)

### Adicionado

- Corpus de **exceção real** `tests/exc.exe` (fonte `tests/exc_cpp.cpp`,
  MinGW-w64 `g++ -O1`): C++ com `throw`/`catch` em recursão não-tail
  (6 frames com destrutor) → `.pdata` com 117 `RUNTIME_FUNCTION` e handlers
  `__CxxFrameHandler3` reais (flags `EHANDLER`/`UHANDLER`).
- Seção `[43]` (6 checks): `-m bin -native` byte-idêntico + **o
  reconstruído roda o throw/catch (exit 42)** — prova de que o unwind
  simbólico (F3) é funcional, não só fiel; `dd label_` presente no `.asm`;
  fuzz de `.pdata`/`.xdata` em dois modos.
- `tests/fuzz_pe.py`: operadores F4 que miram o encadeamento SEH
  (`--input tests/exc.exe`): EXCEPTION_DIRECTORY, flips em `.pdata`/`.xdata`
  e ponteiro `UnwindData` corrompido; flag `--bin-native` para exercitar o
  emissor simbólico (não só o loader).

### Verificado

- `tests\run_tests.bat` **320/320 OK** (base 314 + `[43]`).
- Fuzz `tests/exc.exe`: **300** casos (seed 42, win64) + **300** casos
  (seed 7, `-m bin -native`) → 0 crashes / 0 hangs (só saídas 0-3/5).
- `tests\exc.exe` win64 `-native -r` = **D-19** (link funde seções;
  Import Directory cego → `0xC000007B`); documentado em `PE_NOTES §11`.
  O caminho fiel é `-m bin` (byte-idêntico + comportamento).

## [Unreleased] — R-5.4 SEH F1: parser .pdata/.xdata (2026-10-15)

### Adicionado

- `src/pe/pe_unwind.asm` (R-5.4 SEH/unwind, fatia 1): decodifica as
  estruturas de exceção x64 — `.pdata` (`RUNTIME_FUNCTION`, 3×u32) e
  `.xdata` (`UNWIND_INFO` completo: versão/flags/prolog/frame/unwind codes
  + `CHAININFO`/`EHANDLER`/`UHANDLER`) com validação de limites contra o
  arquivo; `dex_unwind_count`/`dex_unwind_rf`/`dex_unwind_info`.
- `tests/unwind_check.asm` + seção `[40]`: driver com `PeImage`/seções/corpo
  craftados em memória (sem I/O), 2 `RUNTIME_FUNCTION` + 2 `UNWIND_INFO`
  (um simples, um com handler) + casos de borda (índice/rva fora).

### Verificado

- `tests\run_tests.bat` **303/303 OK** (base 299 + `[40]`).
- Sem tocar emissão ainda (F2/F3 pendentes): nenhum byte de saída mudou.

## [Unreleased] — R-5.4 SEH F2: emissão simbólica win64 (2026-10-15)

### Adicionado

- `rebuild.asm .emit_pdata_sec` / `.emit_xdata_sec` (F2): no caminho
  **win64**, `.pdata`/`.xdata` deixam de ser cópia crua e passam a ser
  reemitidas **simbolicamente**: cada `RUNTIME_FUNCTION` vira
  `dd label_<VA> wrt ..imagebase, ...` (reloc `ADDR32NB`) e cada
  `UNWIND_INFO` ganha `label_<VA>:` + bytes do header/unwind codes (`db`)
  + os campos RVA (handler/`chained`) como `dd label wrt ..imagebase`.
  O `link.exe` recalcula as RVAs e o EXCEPTION_DIRECTORY mesmo
  reordenando seções — ataca o D-19. Entradas de `.pdata` nulas (padding)
  são puladas (o link rejeita RUNTIME_FUNCTION zerada: LNK1223) e o
  linker dimensiona a seção pelo conteúdo.
- `tests/pe_exc_dir.py` (valida EXCEPTION_DIRECTORY: rva/size != 0 e
  `size % 12 == 0`) + seção `[41]` (7 checks).

### Verificado

- var64 win64 `-native -r`: link OK, `.pdata` 118 entradas, EXC dir
  válido (`rva=0xD000 size=0x588`) com RVAs recalculadas pelo linker.
- `tests\run_tests.bat` **310/310 OK** (base 303 + `[41]`). A emissão
  `-m bin` não foi tocada (F3 pendente) → byte-idêntico intacto.

## [Unreleased] — R-5.4 SEH F3: emissão simbólica e byte-idêntica em `-m bin` (2026-10-15)

### Adicionado

- F3: no caminho **`-m bin -native`**, `.pdata`/`.xdata` também saem
  **simbólicas**. Em `-f bin` os labels valem file-offset, então a RVA
  vira a **expressão constante** `dd label_<VA> + C`, com
  `C = vaddr − raw_ptr` da seção do alvo (`.pd_field` resolve a seção) —
  somando 0 byte de diferença. `.xdata` reusa o emissor de F2.
- `.emit_xdata_sec` reescrito com **bitmap** de inícios de `UNWIND_INFO`
  (`dex_malloc` zerado): os unwind RVAs da `.pdata` **não são monotônicos**
  (gcc), então o cursor antigo perdia entradas; agora marca todos os
  inícios da `.pdata`, **propaga alvos `chained`** (até 8 passadas) e emite
  em ordem de offset (gaps em `db` de uma vez). OOM/sem `.pdata` → `.xdata`
  crua (direção segura).
- `.emit_pdata_sec`: em bin, entradas nulas saem `dd 0, 0, 0` (byte-fiel)
  e a **cauda** (`raw_size` não múltiplo de 12, ex.: gcc) sai `db`.
- `[42]` (4 checks: `.pdata` bin simbólica + `nasm -f bin` +
  `fc /b` 0 diffs).

### Verificado

- gcc 15.2.0 `-m bin -native` → `nasm -f bin` → `fc /b` **0 diffs** com
  `.pdata`/`.xdata` simbólicas; idem ld.lld 68 MB e todo o corpus.
- `tests\run_tests.bat` **314/314 OK** (base 310 + `[42]`);
  `tests\run_slow.bat` **7/7 OK**. Bytes de saída inalterados.

## [Unreleased] — R-2.7: VEX/EVEX/x87/3DNow! rotulados (2026-10-15)

### Adicionado

- Decoder VEX (`C4`/`C5`) e EVEX (`62`) em x64 (`src/disasm/decoder.asm`):
  o prefixo entra em `npre`, o mapa (0F/0F38/0F3A) reaproveita as flags/imm
  das tabelas 2/38/3A e a instrução vira UMA linha `db` byte-exata com
  rótulo genérico `vex`/`evex` (`Insn.enc` = 1/2). Antes cada byte saía
  solto (uma instrução VEX virava vários `db` desalinhados).
- `src/disasm/x87.asm`: tabela real de mnemônicos x87 (`D8-DF`) resolvida
  por (opcode, ModRM) — 64 formas memória + 512 registro; strings + tables
  conferidas contra capstone 5.0.7 (576 codificações, 0 divergências).
- Strings `s_vex`/`s_evex`/`s_3dnow` + `tbl2_mne[0F] = s_3dnow` em
  `opcode_tbl.asm`.
- Corpus `tests/vex.asm` (VEX2/VEX3/EVEX/x87/3DNow!), driver
  `tests/x87_check.asm` (sweep 8×256 + FNV-1a) e seção `[39]` (29 checks).

### Corrigido

- 3DNow! (`0F 0F /r ib`) saía com comprimento errado: `tbl2_flag[0F]` era
  só `F_MODRM` (perdia o byte-sufixo). Agora `F_MODRM|F_I8`.
- `semantics` recusa VEX/EVEX no caminho nativo (`Insn.enc != 0` → `db`),
  evitando emissão nativa falsa (ex.: VEX `0F 77` cairia em `emms`).
- Debug vazado em `-m bin -native`: o ramo `.collect_syms`/`.cs_sec` de
  `rebuild.asm` imprimia `[cs] sec=N n=M` em stdout **mesmo com `-q`**
  (strings `s_csdbg`/`s_csdbg2` + 3 externs de console). Removido; `-q`
  volta a ser silencioso (0 bytes em stdout).

### Verificado

- x87: 576 codificações batem 1:1 com capstone; `run_tests.bat`
  **299/299 OK**; `run_slow.bat` **7/7 OK** (ld.lld 68 MB + gcc
  byte-idênticos). Corpus `vex` byte-idêntico + comportamento (`exit 42`).
- Limite honesto: VEX/EVEX seguem `db` (sem semântica de label/operando);
  EVEX 0F38 com imm8 pode ter comprimento off-by-one (raro; antes pior).

## [Unreleased] — R-8.2 f3: gcc `-native-bin` byte-idêntico + comportamento (2026-10-15)

### Adicionado

- Seção `[S2]` em `tests\run_slow.bat`: gcc 2 MB `-m bin -native`
  → `nasm -f bin` → `fc /b` byte-idêntico → swap do toolchain
  (backup+restore com hash) compila `tests/hello_f3.c` e confere `hi`.
- Corpus `tests/hello_f3.c` (fixture do teste de comportamento).

### Corrigido

- `semantics .l2_bt` forçava `s_bt` para A3/AB/B3/BB: BTS/BTR/BTC
  saíam como `bt` (diferença de 1 byte `AB→A3` no bin). Agora escolhe
  por `Insn.opcode`; tabela 2-byte alinhada (`B3→s_btr`, `BB→s_btc`).
- Shift/rotate por CL em memória (D2/D3) saía sem prefixo de tamanho:
  o nasm assumia byte e trocava Ev→Eb (`D3→D2`). `emit_nasm .fo_mem`
  agora força o prefixo por `op0.size` quando o único REG é CL.

### Verificado

- gcc 15.2.0 (2.064.976 B, 10 seções) `-m bin -native` → `fc /b` 0
  diffs + comportamento idêntico (`hi`); `tests\run_tests.bat` 270/270;
  `tests\run_slow.bat` 7/7 (`[S1]` ld.lld 68 MB + `[S2]` gcc).

## [Unreleased] — gcc-native: prefixo de tamanho em refs RIP (2026-10-14)

### Corrigido

- `.fo_mem` com prefixo de tamanho em TODAS as formas MEM (hoist:
  decisão antes de `.fo_memshape`; RIP/SIB-abs/abs32 ganham o que só
  `[base]` tinha): `movzx r32, [rel label]` → `byte`/`word`,
  `cmp [rel], imm` → `byte`. Era `nasm: invalid operand sizes`
  (29× movzx + 1× cmp no `gcc -native`).
- `aad` fantasma da sessão anterior: 0 ocorrências no output atual
  (classe extinta; sem ação).

### Adicionado

- Corpus `tests/memsz.asm` (movzx byte/word RIP + cmp RIP imm) +
  seção `[34]` (7 checks: build, generate, 3 greps, `nasm` exit 0).

### Verificado

- `gcc -native` fresco: 0 `movzx` sem tamanho, 0 `mem,imm` sem
  tamanho (estático); `nasm -f win64` final em andamento.

## [Unreleased] — x32 fase D2: IAT absoluta (2026-10-14)

### Adicionado

- Rewrite IAT em x32: `call|jmp [abs]` p/ slot de import vira
  `call|jmp [__imp_X]` absoluto (sem `rel`) + `__imp_X:` label-at-slot
  no chunk de dados; fallback `db` se sem entry/nome.
- `.collect_syms`: inserção R estreita em x32 (só `mod00+rm101+disp32`
  sem SIB/67 cujo alvo é `iat_rva` exato fora de código).
- Dados x32 com `-native` passam por `.wds_chunks` com `nodq`
  (`g_spanflags=1`: corpos `db` puros + labels R + `__imp_X:`);
  `dq` 8B continua desligado em x32.
- Seção `[33]` (6 checks: rewrite + label + sem forma `rel` +
  rebuild + exit 42 no tiny32).

### Verificado

- Calculator `-native`: 21 refs `[__imp_]` + 10 labels, `nasm -f win32`
  zero erros (D1b+ preservado); default `db` x32 sem `__imp_`;
  x64 intacto (3× `[rel __imp_]` no hello).

## [Unreleased] — x32 fase D1b+: allowlist ampla (2026-10-13)

### Adicionado

- Allowlist x32 ampliada: ALU/mov/test/xchg/lea (00-3D, 84-8D),
  `test` acc, `ret` imm, `loop/jcxz`, `movzx/movsx/cmov/setcc`
  (len2), `push/pop` reg; `jcxz` emite `jecxz` em x32; endereços
  sempre `r32` (nunca `rbp`).
- Calculator `-native`: 8.328 mnemônicos + monta + linka (PE32
  válido, 15 seções).

## [Unreleased] — x32 fase D1b: nativo em PE real (2026-10-13)

### Adicionado

- Emissor x32 com registradores de endereço 32 (`ebp`, nunca `rbp`);
  `x32+0x67` recusa (sem forma); `push/pop reg` 32 bits; spans/`dq`
  desligados em x32 (`db` fiel; 4B é trabalho futuro).
- `[30]` agora monta `calc32n.asm` (`nasm -f win32` exit 0, zero erros).

### Corrigido

- Gate `wds_plain` usava `rax` com `len` vivo (regra D-8 de novo);
  `rcx` (flags mortas) no lugar.

## [Unreleased] — x32 fase D1: nativo (2026-10-13)

### Adicionado

- Emissor nativo x32 por allowlist (`push/call/jmp/ret/indiretos`):
  `build_rm` absoluto (disp32 = VA), `call [abs]`/`[0xVA]` no emissor,
  IMPORT rebaixado p/ `db` (D2 fará `call [__imp_X]`); resto cai em
  `db` pelo fallback existente.
- Seção `[32]` (tiny32 `-native` exit 42); `[30]` agora exige `-native`
  x32 com `bits 32` (recusa 4 removida; path morto do main removido).

### Corrigido

- `lift_check`: `fake_img` com `dq` a mais lia `arch=1` (regra D-18).

## [Unreleased] — x32 fase C: rebuild (2026-10-13)

### Adicionado

- Rebuild x32 (`nasm -f win32`, machine inferida do obj, `patch_dirs`
  arch-aware validando `0x14C`/`0x10B` com dirs em 92/96); sanitize de
  seção `/NNN`→`_NNN` (COFF lê `/NNN` como offset de string-table).
- Corpus `tests/tiny32.asm` (exit 42, entry `start`, stdcall) + seção
  `[31]` (build X86 com `X86LIB` + round-trip exit 42).
- Calculator: linka (15 seções + 11 imports adotados; `.bss` fundida
  como no x64).

### Corrigido

- Regra D-8 estendida: `r13` não sobrevive a calls internos (rbx/r12
  sim) — `len` de seção é recomputado (`.sn_relen`); causa-raiz exata
  do clobber em aberto.

## [Unreleased] — x32 fases A+B: detectar + desmontar (2026-10-13)

### Adicionado

- Loader PE32 (`Machine 0x14C` + `Magic 0x10B`, `ImageBase` u32,
  `PeImage.arch`); diretórios arch-aware (imports stride 4/bit31,
  exports/relocs/resources); decoder 32-bit (`addr_mode` no `Insn`:
  sem REX, addr32 default, addr16, sem RIP, `moffs`, `arpl`,
  `inc/dec`); generate `bits 32` (sem `default rel`); `-native`
  recusado com 4, `-r` com 5 (Fases C/D futuras).
- Seção `[30]` (overview/base/generate/bits-32/sem-rel/recusa 4);
  `[6c]` virou aceite x32; `[19]` usa fixture `corrupt_mz` p/ saída 3.

### Corrigido (tabelas, valem p/ x64 e x32; achados via oráculo capstone)

- `0F AF` (imul) sem `F_MODRM`; `CMOVcc` 40-43 ausentes; x87
  (D8-DF) sem ModRM; acumulador-imm ignorava `66` (ex `66 25 iw`
  lido como imm32).

## [Unreleased] — var64 `-native` montável + D-7 bitmap (2026-10-13)

### Corrigido (saída 5 `nasm failed` no var64 `-native`, com teste-primeiro)

- Disp sem `0x` (`.fo_disp`): hex nu vira símbolo/decimal no nasm
  (`[rbp+FFFFFFE8]`, `[rax+5C]`); agora `+0x`/`-0x` sempre.
- `disp32`-curto escapava ao `db` (`.br_memret` comparava em 64 bits;
  `0xFFFFFFF8+128` não envolve): comparação em 32 bits.
- jcc32 (`0F 80-8F`) saía sem operando (`.l2_jcc32` confiava em
  `op0=REL` que só o len1 setava): set explícito via `target_va`.
- `movzx/movsx` sem tamanho (`movzx eax, [rax]`): prefixo `byte`/`word`
  da fonte (builder já guardava em `DexOp.size`).
- `strict dword 0xFFFFFFFF` (warning): forma `-0x1`.
- Refs sem label (`.bss` vazia, meio-de-instrução pós-x87): gate R
  (DATA) + bit-D (CODE) no walker → `db` byte-exato.

### Adicionado

- D-7 reativada como bitmap: 1 bit/RVA, 1 malloc, O(1); leitores:
  jump-table p/ código (`dq label_`, `[28]`) + gates acima.
- Seção `[29]`: var64 `-native` monta (`nasm -f win64` exit 0).

## [Unreleased] — jump table + `jmp/call r64` (2026-10-12)

### Adicionado

- Corpus `tests/jtable.asm` (switch com tabela absoluta `dq`,
  base via `lea [rel]`, `jmp rax`; imprime `2`, exit 0) + seção
  `[27]` (8 checks: build do corpus, round-trip `-native` e `db`,
  base rotulada).

### Corrigido (bug bloqueador achado pelo corpus novo)

- `jmp rax` (`FF E0`, sem REX) saía `jmp eax` — inválido em 64
  bits, rebuild falhava (5): `.l1_ffmem` (`src/disasm/semantics.asm`)
  assumia operando 32 por default; `call/jmp` não têm forma 32
  (como `push`, já tratado). Fix espelha o do `push`: força
  size 4→8 p/ `/2`/`/4` (16-bit já cai em `db`).

## [Unreleased] — lote D-2..D-6 + `-end` (2026-10-12)

### Corrigido (bug real achado em auditoria, com teste-primeiro)

- `-end` ignorado quando `-start` presente: `.wcs_oor_l`
  (`src/gen/rebuild.asm`) só estendia o lote `db` abaixo do `start`;
  acima do `end` fechava o lote vazio e reentrava como in-range
  (saída idêntica ao full). Fix 2 linhas (cair no check do `end`;
  sem `end` o comportamento é o de antes). Prova: `[25]` falhou
  (`combo igual ao full`) antes e passa depois + round-trip `hi`.

### Auditoria (sem mudar comportamento)

- D-2: `.bss` sai vazia no win64; var64 (0xB90 referenciados)
  rebuilda (exit 0) mas roda vazio — R-4.4 confirmada; fiel: `-m bin`.
- D-4: externs mortos `dex_file_read_at`/`write_at` removidos de
  `rebuild.asm` (declarados, nunca chamados).
- D-5: `-no-imports` × `-native` cai em `db` com segurança; `[26]`
  trava o combo (generate + rebuild `hi`).
- D-6: dados sempre inteiros com `-start`/`-end` (só código é
  fatiado); `[25]` trava o combo.

## [Unreleased] — R-6.5 `-emit` (2026-10-12)

### Adicionado

- Flag `-emit db|native` (`src/cli/parse_args.asm` + ajuda): forma
  explícita do emissor sobre o mesmo `DF_NATIVE` (`native` ≡ `-native`,
  `db` limpa o bit; `-native` segue como alias; last-wins; valor
  inválido/ausente → saída 1); seção `[23]` (8 checks: equivalência,
  erros, last-wins ambos os lados).

## [Unreleased] — 3c fuzz mínimo + hang em imports (2026-10-12)

### Adicionado

- `tests\fuzz_pe.py` (determinístico por seed; mutante nunca executado):
  flips aleatórios + miradas (MZ, `e_lfanew`, sig/Machine, seções,
  import-dir, truncamento, bloco zerado); passa = saída em {0,1,2,3,5};
  crash/timeout/saída desconhecida = falha (crasher salvo p/ repro);
  seção `[22]` (20 casos seed 7) na suíte. Requer Python 3.

### Corrigido (hang real achado pelo fuzz, com reproduzir→fix→suite)

- `dex_pe_parse_imports` travava (não crashava) com descritor fantasma
  (ex: 1 flip em terminador nulo → ILT lido como descritor → early-paths
  com `di/vi` em `r10d/r11d` clobberados por `dex_rva_to_offset`):
  `.fill` girava sem avançar (classe D-8). Fix: spill `[rbp-64]/[rbp-68]`
  no topo do `.fill` + reload no `.fill_next` (refresh no `.thunk_end`).
  Prova: 3 TIMEOUTs pré-fix (seed 42) → 200+300+50 casos limpos pós-fix.

## [Unreleased] — 3b dq-pointer (2026-10-12)

### Adicionado

- Pré-scan `.collect_strs` (`src/gen/rebuild.asm`, só `-native -strings`):
  starts de string-runs + alvos de ponteiros (qword com valor VA em
  seção de dados emitida) entram em g_symR (lookup unificado R U runs
  U ptrs; espelha o conjunto emitido na direção segura).
- Emissor `.wds_emit_span` (no caminho chunks `-native`, mesmos args de
  `dex_emit_data`): slots de 8B com alvo validado (`.ptr_tgt_ok`
  compartilhado: rejeita código, `.reloc` skipada, fora-do-eff) saem
  `dq label_<VA>`; sem hit é bit-idêntico ao `db` (default intocado).
- Efeito: `s_tab` do strings virou tabela simbólica (`dq label_s1`…;
  `s1/s2/s3` ganharam labels); round-trip `-native -strings` comporta-
  mentalmente idêntico; `[21]` (5 checks) na suíte; golden
  `tests/ref_native/ref_strings.asm` regenerado (só adições).

### Corrigido (bug real, pego pelo teste novo antes do fix)

- `.wds_emit_span` emitia a VA do slot (`spanva+o`, auto-ref) em vez da
  VA alvo (`base+rva`): `dq label_14000204D` apontava p/ si mesmo.
  Fix: alvo = `base+rva` preservado através da validação.

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
