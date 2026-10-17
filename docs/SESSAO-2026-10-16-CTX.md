# Sessão 2026-10-16 — CTX (ctx.exe) na pipeline + higiene do repositório

> Leitura: `skill.md` → `Projeto.md` → `marco.md` → `docs/ROADMAP.md` → este.
> **STATUS: verde, NÃO commitado.** Firmware: **1.2.361**.
> `tests\run_tests.bat` **336/336 OK**; `build.bat` OK (+~2 s de CTX).

## 0. Objetivo

Integrar a ferramenta `ctx.exe` (CTX — *source code diary*, no PATH em
`C:\ctx\ctx\bin\ctx.exe`) ao projeto: apoio em **auditoria, ajuste de erro,
performance e código errado**, presente na **pipeline de build** e registrada
no `skill.md`.

## 1. O que é o CTX (análise)

Diário de contexto versionável: **decisões (ADR), bugs, lições** (memória),
**proveniência de build**, **trilha de auditoria imutável**, além de
`smells` (diagnósticos `file:line:col`), `health`, `bench` (performance),
`verify`, `explain`, `impact`, `review`. É declarado a **fonte de verdade** do
projeto. Guia completo: `C:\ctx\ctx\usectx.md` (obrigatório).

Comandos usados/relevantes:
- Descoberta: `ctx explain . --detailed`, `ctx decision list`, `ctx memory
  list/search`, `ctx grep`, `ctx impact`.
- Build: `ctx scan`, `ctx build record <artefato>`, `ctx build --target
  build.bat`, `ctx build errors`, `ctx build suggest`.
- Qualidade: `ctx smells -s warning`, `ctx health`, `ctx verify`, `ctx bench`.
- Auditoria: `ctx audit list`, `ctx audit verify`, `ctx review --staged`.

## 2. Bloqueador achado e corrigido (higiene do git)

`tests/ld.lld.asm` — **734 MB** de asm gerado (o `-m bin` do `ld.lld.exe` de
68 MB) — estava **versionado desde o baseline** (`b3be7b8`). Consequência: o
`ctx scan` indexava esse arquivo (≈10 M linhas `label_…`) e criava um índice de
**~3 GB** (`symbols.json` 2,8 GB + `.ctx.yaml` 316 MB).

Correção: `git rm --cached tests/ld.lld.asm` + linha no `.gitignore` (o arquivo
foi removido do disco; nada o referenciava — o `run_slow.bat` gera em
`tests\out\`). Depois disso: `ctx scan` em **~2 s**, índice **1,24 MB**
(2.660 símbolos).

## 3. Integração na pipeline (`build.bat`)

No fim do build (sucesso), best-effort (não falha o build se o ctx faltar):

```bat
where ctx >nul 2>nul
if not errorlevel 1 (
    if not exist .ctx.yaml ctx init --offline >nul 2>nul
    ctx scan --offline >nul 2>nul
    ctx build record out\dexter.exe >nul 2>nul
    echo [ctx] proveniencia + indice atualizados
)
```

Alternativa orquestrada (o CTX roda o build e sugere correções históricas):
`ctx build --target build.bat`. Incremento de fase:
`ctx memory add --title "Implementado: <fase>"` e/ou
`ctx build --target build.bat --phase-tag "<fase>"`.

## 4. `skill.md` §10

Nova seção **"CTX — ferramenta de contexto (obrigatória)"**: descoberta
(antes), memória/decision (durante), build integrado, verificação/auditoria e a
**higiene específica do Dexter** (não versionar dumps `.asm` gigantes; `.ctx/`
ignorado, `.ctx.yaml` versionado; o `ctx scan` não respeita `.gitignore` para
arquivos avulsos — ignora `out/`/`obj/`/`bin/` por nome).

## 5. Uso (dogfooding)

- `ctx smells -s info`: 4 achados reais (complexidade de `tests/fuzz_pe.py` e
  1 `error-masking`).
- `ctx explain .`: 79 arquivos, language asm.
- `ctx build record out\dexter.exe` → `BUILD-00001`.
- 2 memórias (`ctx memory add --type lesson`): a de **D-20** (encoding
  load/store + prefixo de segmento) e a do **caveat do `ctx scan`**.

## 6. Estado do git (ao fechar)

- **Não commitado**: `.gitignore`, `build.bat`, `skill.md`, `marco.md`,
  `docs/*`, `src/disasm/emit_nasm.asm`, `src/gen/rebuild.asm`, `version.bin`,
  `tests/run_tests.bat`; novos `.ctx.yaml`, `tests/notepad.exe`,
  `tests/pe_impdesc.py`, docs de sessão.
- **Removido do versionamento**: `tests/ld.lld.asm` (staged `D`).
- **Ignorado**: `.ctx/`, `tests/ld.lld.asm`.

## 7. Caveats honestos

- `ctx build record` detecta o compilador como *"go"* (misdetecção do CTX para
  este repositório) — inofensivo.
- O `ctx scan` **não** respeita `.gitignore` para arquivos avulsos; ignora
  `out/`/`obj/`/`bin/`/`target`/… por nome. Manter dumps gerados em `tests/out/`.
