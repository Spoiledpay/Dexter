# marco.md — Marco de controle do Dexter

> Arquivo de acompanhamento. Leitura: `skill.md` → `Projeto.md` → este arquivo → `docs/ROADMAP.md`.
> Marcar `[x]` somente com teste verde (`tests\run_tests.bat`). Nada é "pronto" sem prova.

## 0. Onde estamos (2026-10-14, Dexter 1.2.315)

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
- Placar honesto: 270 passam, 0 falham (`tests\run_tests.bat → 270/270 OK` em 1.2.325: base 252/252 + `[37]`/`[38]` com 18 checks). Lenta `run_slow.bat`: `[S1]` ld.lld + `[S2]` gcc

## 1. Build / Testes / Uso (resumo)

- [x] Build: `build.bat` (`[0/3]` versão → `[1/3]` nasm → `[2/3]` link). Requer `nasm.exe` + `link.exe` + `kernel32.lib`
- [x] Versão: `version.bin` (magic `DXVB`) + `tools/bump_version.ps1` + `-ver`/banner dinâmicos
- [x] Suite rápida: `tests\run_tests.bat` (seções `[0]`–`[38]`, 270 checks em 1.2.315)
- [x] Suite lenta: `tests\run_slow.bat` (round-trip `ld.lld.exe` 68 MB)
- [x] Corpus: `hello/tiny/loop/strings/no_relocs` (round-trip) + `var64/gcc/ld.lld` (bin) + `var64/gcc` (`-native` monta 0 erros; comportamento em PE grande = R-8.2) + negativos `var32/link` (saída 3)
- [x] Regra D-12: checar dexter com `if !errorlevel! NEQ 0` (crash é negativo; `if errorlevel 1` ignora AV)

## 2. Fase 0 — Retomada limpa (sem código novo)

- [x] `git status` limpo + `build.bat` OK (v1.2.179, 2026-10-11; só `marco.md` untracked)
- [x] `tests\run_tests.bat` confirma base 67/13
- [x] AV reproduzido isolado: `dexter tests\tiny.exe -native` → `-1073741819` (0xC0000005), sem `.asm`
- [ ] Matriz de isolação repetida (walker neutro / imp neutro / R neutro — um por vez)

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
  comportamental provado; loads indexados/jump-to-code = futuro)
- [x] `-rsrc` (inspect_pe_resources: type/name/language + payload validado)
- [x] `-snapshot` / `-compare a.exe b.exe` (hash FNV-1a + size + layout)
- [x] `dexter --doctor` (nasm/link/kernel32/versão)
- [x] Goldens na suíte + geração byte-idêntica com/sem flag (1.2.254: `[24]` prova `-q`/`-v`/`-vv` byte-idênticos; `-ast-dump` já em `[10]`; flags inspect-only nunca geram `.asm` por construção)

## 6. Fase 4 — Robustez (sem regressão)

- [x] `tests\fuzz_pe.py` mínimo (muta bytes, nunca executa input; 20 casos seed 7 na suíte `[22]` + baterias manuais 200/300/50; meta: só saídas 0-3/5, nunca crash/hang — 1 hang real achado e corrigido em 1.2.253)
- [x] Jump tables: base rotulada via R + corpus `jtable.asm` + round-trip (1.2.257, `[27]`); entradas `dq label_` p/ código via D-7 (1.2.266, `[28]` com guarda `-s`), `jmp [idx]` opaco (futuro: índice simbólico)
- [ ] SEH/unwind reemitido (hoje: cópia/trim)
- [ ] R-2.7 VEX/EVEX/x87 rotulado (hoje: `db` correto)
- [ ] R-5.3 bin com import table regenerada (hoje: copiada, suficiente)
- [x] R-6.5 `-emit=db|native` (1.2.254, `[23]`) + var64 `-native` montável (1.2.266, `[29]`: disp com `0x`, disp32-curto→`db` em 32 bits, jcc32 com `op0=REL`, `movzx/movsx` com `byte/word`, imm32 negativo como `-0x`, gates R/D) + R-6.6 IR otimizável/backend próprio (→ Fase 5 R-8.2)

## 7. Dívida técnica (D-1–D-19, ver ROADMAP)

- [x] D2 IAT absoluta x32 (2026-10-14, backlog `SESSAO-2026-10-13-D1B.md` §4.1): `call|jmp [__imp_X]` + labels, `[33]` verde, suíte 231/231 (1.2.300). `mov`-from-IAT segue `db` (kinds 3/4 não existem); `dq` 8B segue off em x32 (`nodq`); próxima fila: `gcc -native` 62 erros.
- [x] gcc-native prefixo RIP (2026-10-14, backlog §4.2): hoist `.fo_mem`→`.fo_memshape` (movzx/cmp com tamanho em `[rel]`/SIB-abs/abs32); 30 erros estáticos zerados; corpus `memsz.asm` + `[34]` verde; `nasm -f win64` do gcc FECHADO com 0 erros (obj 10,5 MB) + link só com LNK4078; suíte 238/238 (1.2.301). `aad` fantasma extinto (0 ocorrências). Comportamento em PE grande → Fase 5 (D-19).

- [x] D-3 parcial: `sym_check` (`[15]`, golden `SYM n=5`) — falta `strpool`/`labels-imp` dedicado
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
- [ ] Resto ordenado (após R-8.2): SEH/unwind reemitido → R-2.7 VEX/EVEX/x87 rotulado → R-5.3 (`-f bin` com import table regenerada) → loads indexados/jump-to-code → `-s` + RIP.

## 9. Como marcar

- Só marque `[x]` com comando exato verde (ex: `tests\run_tests.bat → 80/80 OK`).
- Cada `[x]` pede: commit Conventional (`Refs:` + `Testes:`) + linha em `docs/REVISAO.md`.
