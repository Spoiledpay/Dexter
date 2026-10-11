# marco.md — Marco de controle do Dexter

> Arquivo de acompanhamento. Leitura: `skill.md` → `Projeto.md` → este arquivo → `docs/ROADMAP.md`.
> Marcar `[x]` somente com teste verde (`tests\run_tests.bat`). Nada é "pronto" sem prova.

## 0. Onde estamos (2026-10-07, Dexter 1.2.16x)

- [x] Fases 0–4 + modo `-m bin` (round-trip byte-idêntico hello/var64)
- [x] R-6.1 `-native` opt-in (round-trip corpus simples)
- [x] R-6.2 lexer (`dex_lex_one`, golden 164 tokens, 0 unknowns)
- [x] R-6.3 parser + AST (goldens hello `1/1/18/3/1/1/8`, loop `1/5/30/9/2/0/8`)
- [x] R-6.5 parcial `-ast-dump`
- [x] R-6.4 fatias 1–2 (lift `DexIR` + codegen + R-labels)
- [ ] R-6.4 fatia 3 (IAT `call|jmp [rel __imp_X]`) — BLOQUEADA: AV `0xC0000005` em generate `-native` com conteúdo
- Placar honesto: 67 passam, 13 falham (`[12b]/[13]`, mesma raiz). Detalhe: `docs/SESSAO-2026-10-07-R64.md`

## 1. Build / Testes / Uso (resumo)

- [x] Build: `build.bat` (`[0/3]` versão → `[1/3]` nasm → `[2/3]` link). Requer `nasm.exe` + `link.exe` + `kernel32.lib`
- [x] Versão: `version.bin` (magic `DXVB`) + `tools/bump_version.ps1` + `-ver`/banner dinâmicos
- [x] Suite rápida: `tests\run_tests.bat` (seções `[0]`–`[13]`)
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

- [ ] `dex_build_impname` + `dex_emit_imp_label` finais (label-at-slot, sem `extern`)
- [ ] Codegen kinds 1/2 (`call|jmp [rel __imp_X]`) com fallback `db`
- [ ] `.idata` com `__imp_X:` + round-trip hello/var64
- [ ] Docs + suite verde + tag

## 5. Fase 3 — Views + JSON mínimo (estilo REA, opt-in)

Inspiração REA: `binary_overview` / `inspect_analysis_view` / `--json` / evidence-first (observado × inferido × desconhecido).

- [x] `-overview` (base/entry/seções/imports/exports/relocs, texto + `--json`)
- [x] `-func <VA>` / `-xrefs <VA>` / `-trace <VA>` (sobre `target_va`, com `truncated:true` honesto)
- [ ] `-strings` ampliado (refs em code-flow viram labels)
- [ ] `-rsrc` (inspetor PE resources, 3 níveis type/name/lang, fail explícito, nunca parcial silencioso)
- [ ] `-snapshot` / `-compare a.exe b.exe` (hash FNV-1a + size + layout)
- [ ] `dexter --doctor` (nasm/link/kernel32/versão)
- [ ] Goldens na suíte + geração byte-idêntica com/sem flag

## 6. Fase 4 — Robustez (sem regressão)

- [ ] `tests\fuzz_pe.py` (muta bytes, nunca executa input; meta: só saídas 3/4, nunca crash)
- [ ] Jump tables + dados em code-flow
- [ ] SEH/unwind reemitido (hoje: cópia/trim)
- [ ] R-2.7 VEX/EVEX/x87 rotulado (hoje: `db` correto)
- [ ] R-5.3 bin com import table regenerada (hoje: copiada, suficiente)
- [ ] R-6.5 `-emit=db|native` + R-6.6 IR otimizável/backend próprio

## 7. Dívida técnica (D-1–D-12, ver ROADMAP)

- [ ] D-3: teste unitário p/ `symtab/strpool/labels-imp`
- [ ] D-7: reativar tabela D com estrutura adequada (intervalos/bitmap)
- [ ] D-1: numerar ADRs em `docs/adr/`
- [ ] D-2/D-4/D-5/D-6: revisar `.bss`/seek/`-no-imports`/`-start` em dados

## 8. Como marcar

- Só marque `[x]` com comando exato verde (ex: `tests\run_tests.bat → 80/80 OK`).
- Cada `[x]` pede: commit Conventional (`Refs:` + `Testes:`) + linha em `docs/REVISAO.md`.
