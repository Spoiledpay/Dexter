# marco.md — Marco de controle do Dexter

> Arquivo de acompanhamento. Leitura: `skill.md` → `Projeto.md` → este arquivo → `docs/ROADMAP.md`.
> Marcar `[x]` somente com teste verde (`tests\run_tests.bat`). Nada é "pronto" sem prova.

## 0. Onde estamos (2026-10-22, Dexter 1.2.435)

- [x] Fases 0–4 + modo `-m bin` (round-trip byte-idêntico hello/var64)
- [x] R-6.1 `-native` opt-in (round-trip corpus simples)
- [x] R-6.2 lexer (`dex_lex_one`, golden 164 tokens, 0 unknowns)
- [x] R-6.3 parser + AST (goldens hello `1/1/18/3/1/1/8`, loop `1/5/30/9/2/0/8`)
- [x] R-6.5 parcial `-ast-dump`
- [x] R-6.4 fatias 1–3 (lift `DexIR` + codegen + R-labels + IAT `call|jmp [rel __imp_X]` — FECHADA 1.2.181, fix colisão `[rbp-100]`x`[rbp-96]` → `img` em `[rbp-104]`)
- [x] R-7.1 `-overview`/`-json` + R-7.2 `-func`/`-xrefs`/`-trace` + R-7.3 `-rsrc` + R-7.4 `-snapshot`/`-compare` (texto+JSON válido, inspect-only)
- [x] R-7.5 `--doctor` (1.2.248, `[20]`)
- [x] 3b dq-pointer (1.2.250, `s_tab` simbólica, `[21]`)
- [x] 3c fuzz mínimo (1.2.253, `tests\fuzz_pe.py`, hang em imports achado e corrigido, `[22]`)
- [x] R-6.5 `-emit` (1.2.254, `[23]`) + lote rápido (1.2.254: `[24]`, D-1, tag `v1.2.254`) + lote D-2..D-6 (1.2.256: `[25]`, `[26]`) + jtable 1ª fatia (1.2.257: `[27]`, tag `v1.2.257`)
- [x] R-8.1 `.bss` com `resb` + labels (1.2.303, `[35]`: soma `resb`==vsize, 100+ refs simbólicas, monta 0 erros; limite honesto D-19)
- [x] R-8.2 f1 bin com `.text` nativa (1.2.308, `[36]`: hello byte-idêntico + `hi` + AST 217 instrs, tiny 42)
- [x] R-8.2 f2 exatidão + matriz (1.2.315, `[37]` var64 + `[38]` 15 checks: loop/strings/no_relocs/jtable/t32)
- [x] R-8.2 f3 PE grande: gcc `-native-bin` byte-idêntico (1.2.325, `[S2]`: 2.064.976 B `fc` limpo + swap compila `hello_f3.c` → `hi`; fixes `l2_bt` por opcode + prefixo CL-shift D2/D3; critério da Fase 5 fechado)
- [x] R-2.7 VEX/EVEX/x87/3DNow! rotulados (1.2.327, `[39]` 29 checks): VEX2/VEX3/EVEX com limite exato + `vex`/`evex`; x87 real (576 codificações vs capstone 5.0.7 = 0 div.); 3DNow! com byte-sufixo; gate `Insn.enc` no nativo. Corpus `vex.asm` byte-idêntico + `exit 42` (COMMIT `5d1daaf`)
- [x] R-5.4 SEH/unwind reemitido — **F1** parser `.pdata`/`.xdata` (1.2.329, `[40]`), **F2** emissão win64 simbólica `wrt ..imagebase` + EXC dir regenerado (1.2.332, `[41]` var64 `rva=0xD000 size=0x588`; ataca D-19), **F3** emissão bin simbólica **byte-idêntica** `dd label_<VA> + C` + bitmap p/ unwind RVAs não-monotônicos (1.2.338, `[42]`; gcc/ld.lld `fc /b` 0 diffs). **F4** FECHADA (1.2.338, `[43]`, 6 checks): corpus de exceção real `tests/exc.exe` (C++ `throw`/`catch`, 117 `RUNTIME_FUNCTION` com `__CxxFrameHandler3`) `-m bin -native` byte-idêntico **e** reconstruído roda o throw/catch (exit 42); win64 do fixture = D-19 (`0xC000007B`)
- [x] Removido debug vazado `[cs] sec=` no `-m bin -native` (`-q` agora 0 bytes em stdout)
- [x] Round-trip `-m bin` byte-idêntico verificado nos apps do usuário: `link/Contador/Color2/Case/Char/color/Calculator` (x32) + `gcc` (x64) — todos `fc /b` 0 diffs (bin e bin-native)
- [x] R-5.3 F3 thunks ILT/IAT simbólicos no `-m bin -native` (1.2.364, `[47]` 7 checks: `dq label_<hint/name> + C`; ordinal/bound→`dq 0x<v>` cru; notepad `thunks=630 sym=620 raw=10`)
- [x] R-5.3 F4 hint/name + nomes de DLL simbólicos (1.2.367, `[48]` 7 checks: `dw <hint>` + `db "<nome>", 0`; `db "<dll>", 0`; **FECHA R-5.3** — import table 100% regenerada; notepad `hint=620 nomes=50`)
- [x] SIB-abs com índice — "loads indexados" (1.2.371, `[49]` 7 checks: `[nosplit abs 0x<disp>+<idx>*<scale>]`, byte-exato; fixture `tests/sibabs.asm` exit 42)
- [x] `-strings` com CR/LF (1.2.375, `[50]` 4 checks: `.str_run` aceita CR/LF dentro do run + qstr fecha/reabre aspas → uma linha sem `""`; `tests/qstr_check.py`)
- [x] Índice simbólico x32 (1.2.379, `[51]` 7 checks: `jmp [jtab+eax*4]` sai `[nosplit label_<VA>+eax*4]`; fixture `tests/absidx.asm` round-trip exit 42; x64 segue numérico)
- [x] jump-to-code x32 — spans de 4 bytes (`dd label_`) (1.2.381, `[51]` +1 check: tabela de switch aponta p/ código via D-7; `.collect_strs`/`.wds_emit_span` com stride do arch)
- [x] **D-19 fatia 2b FECHADA** (1.2.407, `[56]` 9 checks): import table
  simbólica no `win64 -native` — descritores `dd label wrt ..imagebase`,
  thunks `dd label, 0` (RVA zero-estendida de 8B), hint/name + nomes de DLL;
  gaps via `.wds_chunks`/`.wds_gap_win` (preserva `-strings`). Provado:
  `pe_impdesc.py win64` no `exc` = 42 campos/138 thunks/138 hints/14 nomes,
  `ruins=0`; rebuildado `imports_count=69` (14 DLLs) + `pe_dirs.py` 5/5;
  `hello -native -r` = `hi`. **Bug real junto:** parser de imports com `di`
  volátil no `.fill` (`exc` 1→69, `var64` 14→62; `[16]` atualizado).
  `PE_NOTES §26`, ADR-0003. Comportamento do `.exe` segue na fatia 2.
- Placar honesto: **413 passam, 0 falham** (`tests\run_tests.bat → 413/413 OK` em 1.2.415: base 402 + `[57]` 11). Lenta `run_slow.bat`: **7/7**. Build: `build.bat` OK (+~2 s do CTX).

## 1. Build / Testes / Uso (resumo)

- [x] Build: `build.bat` (`[0/3]` versão → `[1/3]` nasm → `[2/3]` link). Requer `nasm.exe` + `link.exe` + `kernel32.lib`
- [x] CTX (`ctx.exe`, no PATH): `build.bat` registra proveniência (`ctx build record out\dexter.exe`) + atualiza índice (`ctx scan`) a cada build (best-effort). Uso obrigatório em `skill.md` §10 (descoberta/memórias/decisões/build/auditoria). `.ctx/` ignorado; `.ctx.yaml` versionado. Higiene: `tests/ld.lld.asm` (734 MB gerado) destrackeado (estourava o índice do CTX a ~3 GB).
- [x] Versão: `version.bin` (magic `DXVB`) + `tools/bump_version.ps1` + `-ver`/banner dinâmicos
- [x] Suite rápida: `tests\run_tests.bat` (seções `[0]`–`[58]`, 426 checks em 1.2.419; 403 com `DEXTER_SKIP_LARGE=1`)
- [x] Suite lenta: `tests\run_slow.bat` (`[S1]` round-trip `ld.lld.exe` 68 MB + `[S2]` gcc byte-idêntico+comportamento)
- [x] Corpus: `hello/tiny/loop/strings/no_relocs/jtable/t32` (round-trip bin-native) + `var64/gcc/ld.lld` (bin) + `gcc` (`-native-bin` byte-idêntico + comportamento = R-8.2 FECHADA) + negativos `var32/link` (saída 3)
- [x] Regra D-12: checar dexter com `if !errorlevel! NEQ 0` (crash é negativo; `if errorlevel 1` ignora AV)

## 2. Fase 0 — Retomada limpa (sem código novo)

- [x] `git status` limpo + `build.bat` OK (v1.2.179, 2026-10-11; só `marco.md` untracked)
- [x] `tests\run_tests.bat` confirma base 67/13
- [x] AV reproduzido isolado: `dexter tests\tiny.exe -native` → `-1073741819` (0xC0000005), sem `.asm`
- [~] Matriz de isolação (walker/imp/R neutros): **obsoleta** — a causa raiz
  do AV (`[rbp-100]`×`[rbp-96]` em `.wds_chunks`) foi fechada na Fase 1
  (2026-10-11); a matriz deixou de ser necessária.

## 3. Fase 1 — Fechar bloqueador R-6.4.3 (AV `-native`)

FECHADA em 2026-10-11 (Dexter 1.2.181, suíte **95/95**). Causa raiz:
colisão de slots em `.wds_chunks`: `img` em `[rbp-100]` + `va` em
`[rbp-96]` (2 qwords a 4 bytes!) corrompiam-se mutuamente; o `img`
selvagem chegava a `dex_emit_imp_label` (`r8=-1`, fault em
`mov rax,[r13+0x10]`, RIP=imp_label+24, provado via VEH temporário
já removido + `.lst`). Fix: `img` → `[rbp-104]` (3 linhas).
De quebra, os labels `__imp_` "faltantes" (D-A aparente) e os goldens
2a defasados se explicaram (splits errados pela mesma corrupção).

- [x] 1.1 OOB heap: auditar `to_sorted` (fill==count), appends com `len` selvagem, `g_impname` 500B
- [x] 1.2 Smash pilha: varrer writes indexados (`rep`, `[rsp+]`, `[rbp-]` em `asm_buffer/emit_data/emit_qstr/u16_dec/str_run`)
- [x] 1.3 Prova R-split real (`label_140002008:` + round-trip hello)
- [x] 1.4 Revalidar 2a (`fc /b` vs `tests/ref_native/` — goldens REGENERADOS p/ saída fatia 3)
- [x] 1.5 `[13]` IAT verde (hello/var64/no_relocs)
- [x] 1.6 `[14]` (imp_check) + `[15]` (sym_check) criados na suíte
- [x] 1.7 Suite 100% OK + docs (ROADMAP/CHANGELOG/REVISAO/marco.md)
- [x] 1.8 Commit + tag (aguardando ordem explícita)

## 4. Fase 2 — IAT nativo R-3.3/R-4.5

FECHADA em 2026-10-12 (Dexter 1.2.247, sem código novo — auditoria + docs).
Evidência: `tests\out\audit_hello.asm` (3×`jmp [rel __imp_]` + labels,
0 `extern`) + `audit_var64.asm` (2×`call [rel __imp_]`/14 labels, 0
`extern`) + round-trip `-native` hello (`hi`); suíte **155/155 OK**.

- [x] `dex_build_impname` + `dex_emit_imp_label` finais (label-at-slot, sem `extern`)
- [x] Codegen kinds 1/2 (`call|jmp [rel __imp_X]`) com fallback `db`
- [x] `.idata` com `__imp_X:` + round-trip hello/var64
- [x] Docs + suite verde (ROADMAP R-3.3/R-4.5 → `[x]`; tag pendente de ordem explícita)

## 5. Fase 3 — Views + JSON mínimo (estilo REA, opt-in)

Inspiração REA: `binary_overview` / `inspect_analysis_view` / `--json` / evidence-first (observado × inferido × desconhecido).

- [x] `-overview` (base/entry/seções/imports/exports/relocs, texto + `--json`)
- [x] `-func <VA>` / `-xrefs <VA>` / `-trace <VA>` (sobre `target_va`, com `truncated:true` honesto)
- [x] `-strings` ampliado (refs em code-flow viram labels: 1.2.250 — slots
  de 8B com valor VA rotulada (R U runs U ptrs) saem `dq label_` em
  `-native`; `s_tab` do strings virou tabela simbólica; round-trip
  comportamental provado; SIB-abs com índice = FECHADO 1.2.370 (`[49]`);
  runs com CR/LF = FECHADO 1.2.375 (`[50]`); base simbólica do índice = futuro)
- [x] `-rsrc` (inspect_pe_resources: type/name/language + payload validado)
- [x] `-snapshot` / `-compare a.exe b.exe` (hash FNV-1a + size + layout)
- [x] `dexter --doctor` (nasm/link/kernel32/versão)
- [x] Goldens na suíte + geração byte-idêntica com/sem flag (1.2.254: `[24]` prova `-q`/`-v`/`-vv` byte-idênticos; `-ast-dump` já em `[10]`; flags inspect-only nunca geram `.asm` por construção)

## 6. Fase 4 — Robustez (sem regressão)

- [x] `tests\fuzz_pe.py` mínimo (muta bytes, nunca executa input; 20 casos seed 7 na suíte `[22]` + baterias manuais 200/300/50; meta: só saídas 0-3/5, nunca crash/hang — 1 hang real achado e corrigido em 1.2.253)
- [x] Jump tables: base rotulada via R + corpus `jtable.asm` + round-trip (1.2.257, `[27]`); entradas `dq label_` p/ código via D-7 (1.2.266, `[28]` com guarda `-s`), `jmp [idx]` opaco (futuro: índice simbólico)
- Itens abertos de fidelidade (SEH/unwind reemitido, R-5.3) vivem na fila ordenada do §8 (fonte única — não duplicar aqui).
- [x] R-6.5 `-emit=db|native` (1.2.254, `[23]`) + var64 `-native` montável (1.2.266, `[29]`: disp com `0x`, disp32-curto→`db` em 32 bits, jcc32 com `op0=REL`, `movzx/movsx` com `byte/word`, imm32 negativo como `-0x`, gates R/D) + R-6.6 IR otimizável/backend próprio (→ Fase 5 R-8.2)

## 7. Dívida técnica (D-1–D-19, ver ROADMAP)

- [x] D2 IAT absoluta x32 (2026-10-14, backlog `SESSAO-2026-10-13-D1B.md` §4.1): `call|jmp [__imp_X]` + labels, `[33]` verde, suíte 231/231 (1.2.300). `mov`-from-IAT segue `db` (kinds 3/4 não existem); `dq` 8B segue off em x32 (`nodq`); próxima fila: `gcc -native` 62 erros.
- [x] gcc-native prefixo RIP (2026-10-14, backlog §4.2): hoist `.fo_mem`→`.fo_memshape` (movzx/cmp com tamanho em `[rel]`/SIB-abs/abs32); 30 erros estáticos zerados; corpus `memsz.asm` + `[34]` verde; `nasm -f win64` do gcc FECHADO com 0 erros (obj 10,5 MB) + link só com LNK4078; suíte 238/238 (1.2.301). `aad` fantasma extinto (0 ocorrências). Comportamento em PE grande → Fase 5 (D-19).

- [x] D-3 FECHADA (2026-10-16): `symtab` (`[15]`, golden `SYM n=5`) +
  **`strpool`/`asm_buffer`** (`tests/strpool_check.asm` + `[44]`, golden
  `STRPOOL o=0 6 B len=11`). `labels-imp` coberto indiretamente por
  `[13]`/`[14]` (imp_check).
- [x] D-15 FECHADA (2026-10-16): `dex_console_write` reserva 48 B p/ o 5º
  arg do `WriteFile` (antes `[rsp+32]` caía no fundo do frame).
- [x] D-16 FECHADA (2026-10-16, auditoria): "prólogo duplicado" descrito
  **não existe**; comentário de alinhamento corrigido + buffer do hex
  movido p/ `[rbp-72]` (32 B, acima da shadow).
- [x] D-7: tabela D reativada como bitmap (1.2.266: 1 bit/RVA, 1 malloc; leitores: jump-table p/ código `[28]`, gates R/D no walker que convertem refs sem label em `db` — sem eles o var64 `-native` não montava)
- [x] R-6.1/x64 nativo em PE real (1.2.266, `[29]`: disp com `0x`, disp32-curto em 32 bits, jcc32 `op0=REL`, `movzx/movsx` com `byte/word`, imm32 negativo, gates R/D)
- [x] x32 fases A+B (1.2.271, `[30]`+`[6c]`: loader PE32 + decoder 32-bit + `bits 32` db fiel; tabelas endireitadas p/ ambos os modos: imul AF, cmov 40-43, x87 ModRM, acumulador-imm 66)
- [x] x32 fase C (1.2.293, `[31]`: rebuild `nasm -f win32` + link X86 com `patch_dirs` arch-aware; sanitize `/NNN`→`_NNN` (COFF strtab); corpus `tiny32.asm` exit 42 round-trip; Calculator linka com 15 seções + 11 imports; `-native` x32 segue recusado com 4 — Fase D)
- [x] x32 fase D1 (1.2.295, `[32]`: nativo x32 por allowlist com round-trip tiny32 exit 42; IMPORT→db até D2; D-18 fakes manuais)
- [x] x32 fase D1b (1.2.297, `[30]`: Calculator `-native` monta zero erros; regs de endereço 32, `push/pop` 32, spans/`dq` off em x32)
- [x] x32 fase D1b+ (1.2.298: allowlist ampla — ALU/mov/lea/test/xchg/`test`-acc/`ret`-imm/`loop`/`movzx`/`cmov`/`setcc`; `jecxz`; Calculator `-native` com 8.328 mnemônicos, link PE32 válido)
- [x] D-1: convenção ADR estabelecida (`docs/adr/0001-ast-lexer-codegen.md` numerado; novas decisões seguem `NNNN-<título>.md`)
- [x] D-2: `.bss` com `resb` + labels (R-8.1 FECHADA 1.2.303: `.wds_bss` + `.ptr_tgt_ok` aceita `off<vsize`; soma `resb`==vsize, 100+ refs simbólicas no var64, monta 0 erros; `[35]` trava). Comportamento em PE grande pendente de layout (D-19 → R-8.2); caminho fiel segue `-m bin`.
- [x] D-4: I/O posicional removido de vez (externs mortos `dex_file_read_at/write_at` extirpados de `rebuild.asm`; `mmap_rw` é o desenho; falha 87 histórica não reincide)
- [x] D-5: `-no-imports` × `-native` seguro (sem parse → fallback `db`, 0 `__imp_`, rebuild `hi`; `[26]` trava o combo)
- [x] D-6: `-start`/`-end` valem p/ código E dados saem inteiros — MAIS bug real achado e corrigido: `-end` ignorado com `-start` presente (scanner oor só conhecia `< start`; fix 2 linhas; `[25]` + round-trip `hi`)
- [x] D-19: `link.exe` funde seções (R-8.1, 2026-10-14: 3 sondas + `secdump` — `.bss`/`.tls`/`.xdata` do `.obj` somem no `.exe`; `resb` vira zeros, nunca nobits; `dex_patch_dirs` copia RVAs cegamente e `imp`/`iat` caíram na `.reloc` nova). Rebuild `-native` via link só vale p/ PEs simples; PEs reais → R-8.2.

## 8. Fase 5 — Layout robusto (R-8.x, ORDEM DE EXECUÇÃO)

> Meta: `-native` com funcionamento completo em PEs reais (o que falta
> para o gcc/link/ld.lld recompilados funcionarem). Ordem fixa; só
> avance com a fatia anterior verde (`tests\run_tests.bat`).

- [x] R-8.1 `.bss` com `resb` + labels (1.2.303, `[35]` 7 checks, commit `dddeac4`). Nível asm exato; comportamento em PE grande pendente de layout.
- [x] R-8.2 f1 bin com `.text` nativa (1.2.308, `[36]` 7 checks). Prova: hello byte-idêntico + `hi` + AST 217 instrs; tiny exit 42 = original.
- [x] R-8.2 f2 exatidão + matriz (1.2.315, `[37]` + `[38]`). Prova: var64 byte-idêntico + comportamento; loop/strings/no_relocs/jtable/t32 idem; 5 classes fechadas (disp-zero/nop/branch/imm8/grp2).
- [x] R-8.2 fatia 3 — PE grande: gcc `-native-bin` byte-idêntico + comportamento (1.2.325, `[S2]`). Critério de aceite da Fase 5 FECHADO.
- [x] R-2.7 VEX/EVEX/x87/3DNow! rotulado (1.2.327, `[39]` 29 checks). Próximo da ordem: SEH/unwind reemitido.
- [x] Resto ordenado (após R-2.7): SEH/unwind reemitido **F1–F4 FECHADAS** (F4 = corpus de exceção real `tests/exc.exe` + fuzz `.pdata`/`.xdata`, 1.2.338 `[43]`). **R-5.3 F1 FECHADA** (1.2.341): imports nativos no `-m bin -native` (`call|jmp [rel __imp_X + K]`, K = correção de delta offset↔RVA; `[36]`/`[37]`). **R-5.3 F2 FECHADA** (1.2.347, `[45]`, 3 checks: descritores de import simbólicos — `dd label_<alvoVA> + C` + alvos rotulados; `fc /b` 0 diffs hello/var64/gcc; `tests/pe_impdesc.py`; limite honesto: ld.lld native-bin já falhava no nasm pré-F2, `PE_NOTES §14`). **R-5.3 F3 FECHADA** (1.2.364, `[47]`, 7 checks: thunks ILT/IAT — `dq label_<hint/name VA> + C`; ordinal/bound→`dq 0x<v>` cru; `PE_NOTES §16`). **R-5.3 F4 FECHADA** (1.2.367, `[48]`, 7 checks: `dw <hint>` + `db "<nome>", 0`; `db "<dll>", 0`; `PE_NOTES §17`) → **R-5.3 completa**. Próximo da ordem: → SIB-abs com índice (1.2.371) → base simbólica do índice / jump-to-code → `-s` + RIP.
- [x] **R-5.3 F3 FECHADA** (1.2.364, `[47]`, 7 checks): arrays de thunks (OFT/ILT + FT/IAT) no `-m bin -native` saem `dq label_<hint/name VA> + C` (alvo rotulado; descoberto **independente** do slot — o scanner resolve 1 VA/iteração); ordinal/bound (>32 bits)/alvo não-rotulável → `dq 0x<v>` cru. `tests/pe_impdesc.py` estendido (OFT/FT) + `[47]`; hello/var64/exc/gcc/notepad `fc /b` 0 diffs. Próximo da ordem: → **R-5.3 F4** (hint/name + nomes simbólicos) → loads indexados/jump-to-code → `-s` + RIP.
- [x] **R-5.3 F4 FECHADA** (1.2.367, `[48]`, 7 checks): cada `IMAGE_IMPORT_BY_NAME` sai `dw <hint>` + `db "<nome>", 0` e o `Name` do descritor sai `db "<dll>", 0` (via `dex_emit_qstr` **file-scope** — os `.gb_*` estão em `dex_generate_bin` e não alcançam labels locais de `dex_generate_asm`); fallback `db` p/ cstring não-imprimível/sem NUL. `tests/pe_impdesc.py` (hint/nomes) + `[48]`; **FECHA R-5.3** (import table 100% regenerada). Próximo da ordem: → loads indexados/jump-to-code → `-s` + RIP.
- [x] **SIB-abs com índice — "loads indexados"** (1.2.371, `[49]`, 6 checks): operandos `[disp32+idx*scale]` (base ausente) saem `[nosplit abs 0x<disp>+<idx>*<scale>]` (x64) / `[nosplit 0x<disp>+<idx>*<scale>]` (x32), byte-exatos (`nosplit` obrigatório: o nasm re-encoda `[abs 0x2+rax*2]`→`[rax+rax+0x2]`); fixture `tests/sibabs.asm` + `[49]`; `PE_NOTES §18`. Próximo da ordem: → base simbólica do índice / jump-to-code → `-s` + RIP.
- [x] **`-strings` com CR/LF** (1.2.375, `[50]`, 4 checks): `.str_run` aceita CR/LF dentro do run (1º byte imprimível) e `dex_emit_qstr` fecha/reabre as aspas em volta de cada escape (`open`) → `db "alpha-one", 13, 10, 0` numa linha, sem `""`; oráculo `tests/qstr_check.py`. `PE_NOTES §19`. Próximo da ordem: → base simbólica do índice / jump-to-code → `-s` + RIP.
- [x] **Índice simbólico x32** (1.2.379, `[51]`, 7 checks): `jmp dword [jtab+eax*4]` (VA x32 cabe em 32 bits) sai `[nosplit label_<VA>+eax*4]`; `.cs_abs32sib` registra a RVA no R; canal emissor↔rebuild por dados (`g_abs_vas`/`g_abs_n`/`g_abs_base` em emit_nasm) p/ não quebrar o link dos drivers; fixture `tests/absidx.asm` + round-trip exit 42. `PE_NOTES §20`. Próximo da ordem: → jump-to-code restante → `-s` + RIP.
- [x] **jump-to-code x32** (1.2.381, `[51]` +1): spans de ponteiro com stride do arch (4=`dd`, 8=`dq`) — tabela de switch x32 aponta p/ código via D-7 → `dd label_<VA>`; `.collect_strs`/`.wds_emit_span` arch-aware; removidos o gate `arch==X64` e o `g_spanflags=1` do x32. `PE_NOTES §21`. Próximo da ordem: → `-s` + RIP.
- [x] **`-s` + SEH simbólico — fecha a fila "`-s` + RIP"** (1.2.382, `D-21`, `[52]` 7 checks): o gap **não era o RIP** (19 probes em `-m bin`, `fc /b` 0: exc/notepad/var64/tiny/loop/strings/jtable/no_relocs); era o `-s` cruzando com a reemissão simbólica da `.pdata`/`.xdata` (R-5.4) no `win64 -native` → 234 erros de nasm (`symbol not defined`) em `tests/exc.exe -s .rdata`. Fix: `section_filter != 0` pula a exceção SEH no `.walk_data` (cai no `db` comum, D-17). Limite honesto: `-s` filtrando a seção do entry + `-r` → LNK2001/exit 5. `PE_NOTES §22`.
- [x] **D-19 fatia 1** — `UNWIND_INFO` em qualquer seção também no win64 (1.2.385, `[53]` 5 checks): `.walk_data_sec` + `.uw_bitmap` + novo `.wds_plain_uw` (fatia em início de unwind; gaps via `.wds_chunks` p/ preservar R-labels/spans; unwind simbólico via `.uw_emit`) + `.uw_next_bit`; desligado sob `-s` (D-17/D-21). Prova: `notepad.exe -native` win64 **0 erros** (antes 386) + 8 alvos win64 0 erros; `-m bin` intacto; `-native -r` já linka (exit 0). **Fatia 2 pendente** (`dex_patch_dirs` cego + fusão de seções pelo link: comportamento do exe). `PE_NOTES §23`.
- [x] **D-19 fatia 2a** — `dex_patch_dirs` remapeia DataDirectories por (seção, offset) (1.2.386, `[54]` 4 checks + `tests/pe_dirs.py`): novo `.pd_remap` (seção original → offset → homônima rebuildada, `/NNN`→`_NNN`; sem homônima não copia). Prova: `exc -native -r` de `0xC000007B` (imagem inválida) para `0xC0000005` (imagem carrega); exc 5/5 e hello 3/3 dirs. **Fatia 2b FECHADA em 1.2.407** (import table simbólica; ver abaixo). `PE_NOTES §24`.
- [x] **R-5.4 estendido** — `UNWIND_INFO` em QUALQUER seção (1.2.359, `[46]` 6 checks): o MS link funde o `.xdata` no `.rdata` (ex.: `notepad.exe`), então o unwind reemitido simbólico **onde estiver** (`.uw_bitmap`/`.uw_emit` no bin, byte-exato). `-m bin` E `-m bin -native` do notepad **byte-idênticos**. **D-20 FECHADA** (`src/disasm/emit_nasm.asm`: ALU/mov reg-reg "load" → `db`; prefixo de segmento `gs:`/`fs:` reemitido). win64 de PE MS real segue **D-19**. `PE_NOTES §15`.
- [x] **D-22 FECHADA** (1.2.390, `[55]` 6 checks): `-s <seção>` + `-r` no
  win64/win32 falhava no link (`LNK2001`, `label_<entry>` indefinido) quando o
  filtro não era a seção do entrypoint. `.emit_entry_alias` fecha o `.asm` com
  `label_<entryVA> equ label_<secVA> + 0x<delta>` (delta 0/`-s` na seção do
  entry não emitem; sem duplicata nem auto-referência). Prova: x64 native/db,
  `-s .text` sem equ e x32 delta 0; suite 391/391. `PE_NOTES §25`.
  Detalhe/handoff: `docs/SESSAO-2026-10-19-D22.md`.
- [x] **D-19 fatia 2b FECHADA** (1.2.407, `[56]` 9 checks): import table
  simbólica no `win64 -native` (descritores `dd label wrt ..imagebase`,
  thunks `dd label, 0`, hint/name + nomes de DLL; gaps
  `.wds_chunks`/`.wds_gap_win`). Prova: `pe_impdesc.py win64` no `exc` =
  42/138/138/14, `ruins=0`; rebuildado `imports_count=69` (14 DLLs) +
  `pe_dirs.py` 5/5; `hello -native -r` = `hi`. **Bug real junto:** parser de
  imports (spill de `di` volátil no `.fill`): `exc` 1→69, `var64` 14→62
  (`[16]` agora exige 62). `PE_NOTES §26`, ADR-0003.
- [x] **D-19 fatia 2c — diagnóstico fechado** (2026-10-21, sem mudança em
  `src/`, suíte segue 402/402): a causa do `0xC0000005` **não** é
  `.tls`/`.CRT`; é `db` com **disp32 RIP-relative congelado** quando o link
  move a seção alvo. Prova: `exc -native -r` → AV de execução em `0x0`,
  `mov rax,[rip+0xdb69]` (IAT `0x140010440`) → `.bss` nova → `call rax`.
  Classe medida por `tests/rip_audit.py`: `exc` **42** (`.idata` 23 +
  `.rdata` 19), `var64` **47**, `notepad` **1252** (`.data` 1229+),
  `hello` **0** (por isso nunca falhou). Mecanismo do fix provado em sonda
  (`dd label - $ - 4` = REL32 no COFF x64, linker recalcula). Defeito
  independente: `.bss` sai `data` (progbits) → `LNK4078` + `resb` zerado;
  TLS Directory já está simbólica e correta. `dbg_probe.py`/`secdump.py`/
  `rip_audit.py` em `tests/`. `PE_NOTES §27`,
  `docs/SESSAO-2026-10-21-D19-2C.md`.
- [x] **D-19 fatia 2c — fix** (1.2.415, `[57]`): instrução que cai em `db`
  com disp32 RIP-relative sai `db <prefixo>` + `dd label_<alvo> - $ - 4
  [- 0x<imm>]` + `db <imm>` (REL32; o link recalcula) — `exc` 42→**0**,
  `var64` 47→**0**, `notepad` 14 corrigíveis→0 (1238 limite). Junto:
  `call|jmp [mem]` com REX cai em `db` (encoding encolhia 7→6 B e
  deslocava labels; `.CRT` byte-idêntico agora) e seção uninit sai classe
  `bss` (nobits; fim do `-w+zeroing` e do `LNK4078 .bss`).
  **Prova de comportamento: `var64.exe -native -r` roda exit 0.**
  Limite: tabelas de EH do GCC são pcrel e o link não as relocaliza
  (`exc` segue AV, agora dentro de `libstdc++`); `.data` com
  `vsize>raw` (tail) ainda não é emitido (notepad 1238 refs).
  `PE_NOTES §28`.
- [x] **D-19 fatia 2c-3** (1.2.417, `[57]`/`[58]`): `.data` com
  `vsize > raw` emite o tail zerado (`times N db 0`) com `label_` nos alvos
  R; `.ptr_tgt_ok` aceita `off < vsize` no modo link. `notepad`: 1238 refs
  com label (`rip_audit` 0 falsos) e `ptr_audit` 0; `.data` mantém
  `vsize=0x2740`. Fixture `tests/taildata.asm` + patch/check (original e
  rebuild exit 42). `-m bin` byte-idêntico. `PE_NOTES §29`.
- [x] **D-19 fatia 2c-2** (1.2.417, ADR-0004): recusa honesta do EH C++ do
  GCC. Com `-native -r` no modo link e
  `__gxx_personality_*`/`__gcc_personality_*` na import table, sai **4**
  com mensagem `pcrel` + `-m bin`; geração pura segue e o caminho fiel do
  `exc` é `-m bin -native -r` (exit 42). Gates de rebuild migraram de `exc`
  para `var64` (5 dirs/62 imports) e `notepad`. `PE_NOTES §30`.
- Placar honesto: **464 passam, 0 falham** (`tests\run_tests.bat → 464/464 OK`
  em 1.2.435; 441/441 em `DEXTER_SKIP_LARGE=1`). Lenta `run_slow.bat`:
  **7/7**. Build: `build.bat` OK. CI GitHub Actions: verde no commit
  publicado da 1.2.435.
- [x] **Publicação 1.2.419** (2026-10-22): README PT/EN/CN, GitHub Sponsors,
  CI em `windows-latest`, tag `v1.2.419` e release com `dexter.exe` + zip
  + SHA256. Detalhe e processo em §9.
- [x] **Fila após a 2c (1.2.419, ordem fixa):** (1) **D-19 fatia 2** —
  comportamento do `.exe` reconstruído pelo `win64` em PE real: `var64`
  roda exit 0; `notepad` linka com 1238 refs de `.data` agora rotuladas
  (2c-3). `exc` (EH C++ do GCC, pcrel) fica **recusado por decisão**
  (2c-2/ADR-0004); o comportamento dele é provado em `-m bin -native -r`
  (exit 42). Fecha o escopo medido da D-19;
- [x] **Base simbólica do índice em x64** (1.2.422, `[59]` 12 checks): o
  disp32 do SIB-abs (base=101) é **sinal-estendido** — só endereça a imagem
  com base < 2 GiB (`/BASE:0x400000`); coletor `.cs_abs64sib` (`movsxd` +
  gate `mod00/rm100/has_sib` antes do teste RIP) e emissor
  `[nosplit abs label_<VA>+idx*scale]` nos dois modos. No `-m bin` o label
  vale file offset → `+ 0x<C>` (`C = VA - off`, array `g_abs_corr`) e novo
  `.gb_rchunks` semeia `label_<VA>:` nos dados. Fixture `tests/absidx64.asm`
  + `absidx64_check.py`: win64 e bin simbólicos, `.asm` monta, rebuild win64
  exit 42, bin `fc /b` 0 + exit 42. `PE_NOTES §31`.
- [x] **2a — x87 nativo** (1.2.427, `[60]` 15 checks): tabela de forma
  (`x87_shape`/`x87_memsz`, `dex_x87_form`), `DEX_OP_ST`, `tword`,
  `DEX_MEM_NOSZ` e grafia NASM. Exaustivo: 1796 nativas x64 / 1736 x32 /
  244 inválidas / 8 `fstpnce` db. `PE_NOTES §32`, ADR-0006.
- [x] **2b — VEX2 nativo** (1.2.434, `[61]` 11 checks): tabela derivada
  (`vex2_tbl.inc`: 371 entradas do mapa 0F; 337 com forma) por capstone+NASM,
  descritor com papel/classe e flags de decode; `DEX_OP_VEC`/`DEX_OP_MASK` e
  `Insn.vex_imm8`. Bugs reais: `dex_tbl2_flag[0xF2]=0`, `r8` clobrado no
  caller de `dex_vex2_flags` (AV), `.vex_set` lendo `eax` e vvvv=0 nas
  entradas sem vvvv (cobertura). Fixture 1442 instruções: 1418 nativas + 24
  db; bin byte-idêntico, exit 42. `PE_NOTES §33`, ADR-0007.
- [x] **Publicação 1.2.435** (2026-10-22): tag `v1.2.435` no commit
  publicado e release com `dexter.exe` + zip + `SHA256SUMS.txt`; assets
  conferidos de volta (`-ver` = 1.2.435). Detalhe em §9.5.
- [ ] **Próxima fila (1.2.435, ordem fixa):** (1) **2c/2d — VEX3/EVEX**
  (mesma metodologia por mapa/pp/W/L; EVEX com máscara/broadcast/`disp8*N`);
  (2) **R-6.6 opção C** — IR otimizável + backend próprio; (3) evolução
  2c-2(b): pós-patch dos campos pcrel do LSDA (parser DWARF EH) + reverter
  a recusa para esses PEs. Espelho em `docs/ROADMAP.md` ("Fila de execução").

## 9. Publicação 1.2.419 — CI, README trilíngue e release (2026-10-22)

Fechamento de distribuição do projeto. Tudo abaixo está publicado no
repositório real `Spoiledpay/Dexter` e provado por execução, não por inspeção.

### 9.1 CI (GitHub Actions)

- Workflow `.github/workflows/ci.yml`: `windows-latest`, MSVC x64
  (`ilammy/msvc-dev-cmd`), NASM via Chocolatey, `build.bat` e suíte rápida.
- `DEXTER_SKIP_LARGE=1` pula os fixtures grandes não versionados
  (`tests/gcc.exe` e `tests/ld.lld.exe`); a suíte completa é local.
- Última execução: run **#5**, conclusão **success**
  (`https://github.com/Spoiledpay/Dexter/actions/runs/39779917551`).
- Correções de portabilidade que a CI exigiu:
  - `build.bat`: `exit /b 0` no fim (sem `ctx` no PATH o `where ctx`
    deixava `errorlevel=1` e o step falhava apesar do `.exe` pronto).
  - `src/cli/parse_args.asm`: default `C:\Nasm\nasm.exe`/`link.exe` cai
    para `nasm.exe`/`link.exe` do PATH quando `C:\Nasm` não existe.
  - `.gitattributes`: `*.asm`/`*.inc` em LF (golden do lexer 164 tokens;
    CRLF virava 199) e binários marcados `binary`.
  - `tests/run_tests.bat`: `LINKER`/`KLIB`/`X86LIB` portáveis (PATH/SDK) e
    `DEXTER_SKIP_LARGE`.
  - `tests/label_drift.py`: usa `shutil.which("nasm")`; não fixa `C:\Nasm`.
  - Fixtures pequenos versionados: `loop/tiny/strings/no_relocs`, `t32`,
    `Calculator/Case/Char/color/Color2/Contador`.
  - CI instala `capstone` (usado por `tests/rip_audit.py`).

### 9.2 README, licença e financiamento

- `README.md` (pt-BR), `README.en.md` (US English) e `README.zh-CN.md`
  (简体中文), com seletor de idioma e o mesmo conteúdo: recursos atuais,
  uso, flags, testes, versão, limites e licença.
- Logo oficial `Dexter_logo_US.png`; badges de CI, MIT e release.
- Apoio via **GitHub Sponsors** (`https://github.com/sponsors/Spoiledpay`)
  + `.github/FUNDING.yml` (`github: Spoiledpay`).
- `LICENSE` MIT (`Labsobjects.org | Developer`), idêntico ao holder do
  repositório remoto.

### 9.3 Release

- Tag anotada `v1.2.419` no commit da publicação; `version.bin` = 1.2.419.
- Release: `https://github.com/Spoiledpay/Dexter/releases/tag/v1.2.419`.
- Assets publicados:
  - `dexter.exe` (114.688 B) — binário standalone (kernel32 apenas);
  - `dexter-v1.2.419-win64.zip` (65.737 B) — exe + READMEs + LICENSE +
    `docs/CLI.md`;
  - `SHA256SUMS.txt`.
- Hashes:
  - `b9109771caeb09fb3c244d70b1ed47ee80055b28817d6953b2d945717e86bbde` (`dexter.exe`)
  - `d786bf515c51039d9b979062025bcf50db648eb2ec8ecfbe0bfdf88a3de10a47` (zip)
- Verificação pós-publicação: asset baixado de volta, hash confere e
  `dexter.exe -ver` imprime **1.2.419** (exit 0).

### 9.4 Higiene de histórico

- O histórico local ainda continha `tests/ld.lld.asm` (blob de **712 MB**
  em commits antigos), que o GitHub rejeitaria (>100 MB).
- Histórico de `main` reescrito com `git filter-branch --index-filter`
  removendo o path; tags antigas reapontadas para os commits equivalentes;
  `git gc` aplicado. Repositório local: **4,31 MiB**, nenhum blob >100 MB.
- O commit inicial do GitHub (`LICENSE`) foi integrado por merge; `main`
  ficou fast-forward em relação ao remoto e foi enviada.
- Regra: antes do primeiro push, conferir o maior blob de
  `git rev-list --objects <branch>`; nunca enviar binário >100 MB.

### 9.5 Publicação 1.2.435

- Escopo publicado: 2b (VEX2 nativo), 2a (x87 nativo) e o índice simbólico
  de SIB-abs em x64 (1.2.422/1.2.427/1.2.434) — os três commits que estavam
  locais desde a 1.2.419.
- `tests\run_tests.bat` **464/464 OK** (441/441 em `DEXTER_SKIP_LARGE=1`) e
  `tests\run_slow.bat` **7/7 OK** antes do push.
- Tag anotada `v1.2.435` no commit publicado; CI do `main` **success**
  (run `39885426216`,
  `https://github.com/Spoiledpay/Dexter/actions/runs/39885426216`).
- Release: `https://github.com/Spoiledpay/Dexter/releases/tag/v1.2.435`.
- Assets: `dexter.exe` (133.120 B), `dexter-v1.2.435-win64.zip` (70.961 B) e
  `SHA256SUMS.txt`.
- Hashes: `1b1bc9818244a882ec75d57c755ca0efe499c9d3cbd6c9f16dd1f0426bf770c1`
  (`dexter.exe`) e `6654adcd6710875bd8189863c7745b89b38c8880cb267bdac3ac2cba47911f00`
  (zip).
- Verificação pós-publicação: assets baixados de volta, SHA-256 confere e
  `dexter.exe -ver` imprime **1.2.435** (exit 0).

## 10. Como marcar

- Só marque `[x]` com comando exato verde (ex: `tests\run_tests.bat → 80/80 OK`).
- Cada `[x]` pede: commit Conventional (`Refs:` + `Testes:`) + linha em `docs/REVISAO.md`.
