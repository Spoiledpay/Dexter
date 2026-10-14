# marco.md — Marco de controle do Dexter

> Arquivo de acompanhamento. Leitura: `skill.md` → `Projeto.md` → este arquivo → `docs/ROADMAP.md`.
> Marcar `[x]` somente com teste verde (`tests\run_tests.bat`). Nada é "pronto" sem prova.

## 0. Onde estamos (2026-10-12, Dexter 1.2.257)

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
- Placar honesto: 199 passam, 0 falham (`tests\run_tests.bat → 199/199 OK` em 1.2.257). Detalhe do dia: `docs/SESSAO-2026-10-12-DIA.md` (base R-7.4 em `docs/SESSAO-2026-10-11-R74.md`)

## 1. Build / Testes / Uso (resumo)

- [x] Build: `build.bat` (`[0/3]` versão → `[1/3]` nasm → `[2/3]` link). Requer `nasm.exe` + `link.exe` + `kernel32.lib`
- [x] Versão: `version.bin` (magic `DXVB`) + `tools/bump_version.ps1` + `-ver`/banner dinâmicos
- [x] Suite rápida: `tests\run_tests.bat` (seções `[0]`–`[27]`, 199 checks em 1.2.257)
- [x] Suite lenta: `tests\run_slow.bat` (round-trip `ld.lld.exe` 68 MB)
- [x] Corpus: `hello/tiny/loop/strings/no_relocs` (round-trip) + `var64/gcc/ld.lld` (bin) + negativos `var32/link/for` (saída 3)
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
- [x] R-6.5 `-emit=db|native` (1.2.254, `[23]`) + var64 `-native` montável (1.2.266, `[29]`: disp com `0x`, disp32-curto→`db` em 32 bits, jcc32 com `op0=REL`, `movzx/movsx` com `byte/word`, imm32 negativo como `-0x`, gates R/D) + R-6.6 IR otimizável/backend próprio (futuro)

## 7. Dívida técnica (D-1–D-17, ver ROADMAP)

- [x] D-3 parcial: `sym_check` (`[15]`, golden `SYM n=5`) — falta `strpool`/`labels-imp` dedicado
- [x] D-7: tabela D reativada como bitmap (1.2.266: 1 bit/RVA, 1 malloc; leitores: jump-table p/ código `[28]`, gates R/D no walker que convertem refs sem label em `db` — sem eles o var64 `-native` não montava)
- [x] R-6.1/x64 nativo em PE real (1.2.266, `[29]`: disp com `0x`, disp32-curto em 32 bits, jcc32 `op0=REL`, `movzx/movsx` com `byte/word`, imm32 negativo, gates R/D)
- [x] x32 fases A+B (1.2.271, `[30]`+`[6c]`: loader PE32 + decoder 32-bit + `bits 32` db fiel; tabelas endireitadas p/ ambos os modos: imul AF, cmov 40-43, x87 ModRM, acumulador-imm 66)
- [x] x32 fase C (1.2.293, `[31]`: rebuild `nasm -f win32` + link X86 com `patch_dirs` arch-aware; sanitize `/NNN`→`_NNN` (COFF strtab); corpus `tiny32.asm` exit 42 round-trip; Calculator linka com 15 seções + 11 imports; `-native` x32 segue recusado com 4 — Fase D)
- [x] D-1: convenção ADR estabelecida (`docs/adr/0001-ast-lexer-codegen.md` numerado; novas decisões seguem `NNNN-<título>.md`)
- [x] D-2: `.bss` sai vazia no win64 (link dimensiona sem o vsize: var64 tem 0xB90 referenciados; rebuild win64 roda mas imprime vazio × original — limitação R-4.4 confirmada; caminho fiel: `-m bin`; contramedida futura: `resb vsize` nobits)
- [x] D-4: I/O posicional removido de vez (externs mortos `dex_file_read_at/write_at` extirpados de `rebuild.asm`; `mmap_rw` é o desenho; falha 87 histórica não reincide)
- [x] D-5: `-no-imports` × `-native` seguro (sem parse → fallback `db`, 0 `__imp_`, rebuild `hi`; `[26]` trava o combo)
- [x] D-6: `-start`/`-end` valem p/ código E dados saem inteiros — MAIS bug real achado e corrigido: `-end` ignorado com `-start` presente (scanner oor só conhecia `< start`; fix 2 linhas; `[25]` + round-trip `hi`)

## 8. Como marcar

- Só marque `[x]` com comando exato verde (ex: `tests\run_tests.bat → 80/80 OK`).
- Cada `[x]` pede: commit Conventional (`Refs:` + `Testes:`) + linha em `docs/REVISAO.md`.
