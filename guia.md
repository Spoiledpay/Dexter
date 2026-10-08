# Guia do Dexter — manual do usuário

O Dexter lê um executável Windows x64 (PE), gera um fonte `.asm` (NASM)
legível e reassemblável, e pode reconstruir o `.exe` — incluindo
**round-trip byte-idêntico** no modo `-m bin`.

## 1. Requisitos

- Windows 64-bit.
- `nasm.exe` em `C:\Nasm\` ou no `PATH` (testado: NASM 3.01).
- `link.exe` + `kernel32.lib` (o `build.bat` localiza sozinhos; informe
  `SDKLIBDIR` se o SDK estiver fora do padrão).
- Sem nada a instalar: é um único `out\dexter.exe`, sem CRT.

```bat
build.bat
out\dexter.exe -ver
```

Saída esperada:

```text
Dexter disassembler Tool Version 1.2.x
LabsObjects All rights reserved
```

> Sem argumentos, o Dexter mostra o banner acima + a ajuda completa e
> retorna 0. A cada `build.bat`, o terceiro número da versão incrementa
> (`version.bin` na raiz; detalhe em `docs/ROADMAP.md` R-0.6).

## 2. Uso em 30 segundos

```bat
:: 1) gerar o .asm
out\dexter.exe tests\hello.exe -o tests\out\hello.asm

:: 2) gerar E reconstruir o .exe de uma vez (modo win64, via link)
out\dexter.exe tests\hello.exe -o tests\out\hello.asm -r -O tests\out\hello_rt.exe

:: 3) rodar o rebuild e comparar comportamento
tests\out\hello_rt.exe
```

## 3. Os dois modos: `win64` × `bin`

| | `-m win64` (padrão) | `-m bin` |
|---|---|---|
| `.asm` gerado | labels + `db` + comentários (legível, desassembla de verdade) | headers + seções + overlay em `db` (cópia fiel, sem decode) |
| Rebuild | `nasm -f win64` + `link.exe` | só `nasm -f bin` |
| Fidelidade | Perfeita em PEs simples; o linker pode reordenar seções em PEs complexos | **Byte-idêntica** (`fc /b` igual) em qualquer PE x64 válido |
| Quando usar | Estudar/analisar código, flags `-s -start -hex -strings` | Clonar um `.exe` com garantia total |

Regra prática: quer **analisar**, use `win64`. Quer **clonar com garantia**,
use `bin`:

```bat
out\dexter.exe tests\var64.exe -o tests\out\var64_bin.asm -m bin -r -O tests\out\var64_bin.exe
fc /b tests\var64.exe tests\out\var64_bin.exe
```

## 4. Referência rápida de flags

```bat
:: Inspecionar um binário (nada é escrito além do .asm)
out\dexter.exe app.exe -o app.asm -v        &:: base, entry, seções, imports
out\dexter.exe app.exe -o app.asm -vv       &:: + hexdump de 64 B por seção

:: Focar em uma região
out\dexter.exe app.exe -o app.asm -s .text -start 0x1000 -end 0x2000

:: Legibilidade
out\dexter.exe app.exe -o app.asm -hex      &:: comentários "; @0xVA"
out\dexter.exe app.exe -o app.asm -strings  &:: strings como db "...", 0
out\dexter.exe app.exe -o app.asm -nop-pad  &:: 0x90/0xCC como nop/int3

:: Rebuild
out\dexter.exe app.exe -o app.asm -r -O novo.exe
out\dexter.exe app.exe -o app.asm -r -O novo.exe -N C:\outro\nasm.exe -L C:\outro\link.exe

:: Casos especiais
out\dexter.exe app.exe -o app.asm -no-relocs   &:: omite a seção .reloc
out\dexter.exe app.exe -o app.asm -no-imports  &:: pula parse de imports
out\dexter.exe app.exe -o app.asm -q            &:: silencioso (só erros)
```

Códigos de retorno: `0` ok · `1` uso incorreto · `2` erro de I/O ·
`3` PE inválido ou 32-bit · `5` falha no reassembly. Mensagens de erro
vão para stderr; com `-q`, só erros aparecem.

## 5. Lendo o `.asm` gerado (modo win64)

```nasm
bits 64
default rel

global label_140001000

section .text code
label_140001000:
    db 0x55  ; push @0x140001000
label_140001001:
    db 0x48, 0x89, 0xE5  ; mov @0x140001001
```

- `label_<VA>:` marca cada instrução (VA original em hexadecimal).
- `db` preserva os bytes exatos — o rebuild tem comportamento idêntico.
- `; mne` é o mnemônico detectado (comentário); `; @0xVA` aparece com `-hex`.
- Seções de dados saem em blocos de 16 bytes; com `-strings`, textos
  legíveis viram `db "texto", 0`.
- O arquivo monta com `nasm -f win64` sem edição.

## 6. Fluxos prontos (copie e cole)

**Auditar imports de um suspeito (sem executar nada — o Dexter nunca
executa o input):**

```bat
out\dexter.exe suspeito.exe -o NUL -v -q
```

> Dica: `-o NUL` dispensa o `.asm` quando só interessa o dump. O Dexter
> nunca executa o binário analisado; para amostras não confiáveis, rode
> em VM mesmo assim.

**Clonar qualquer x64 com prova de fidelidade:**

```bat
out\dexter.exe original.exe -o clone.asm -m bin -r -O clone.exe -q
fc /b original.exe clone.exe
```

**Testar tudo de uma vez:**

```bat
tests\run_tests.bat         &:: rápido: 42 checagens (saída 0 = tudo OK)
tests\run_slow.bat          &:: lento: round-trip do ld.lld de 68 MB
```

## 7. Corpus em `tests/`

| Arquivo | O que é | Uso |
|---|---|---|
| `hello.asm` | Fonte golden (NASM) — a suíte monta `hello.exe` dele | round-trip win64 |
| `tiny.exe` | Mínimo, 2 seções, exit 42 | round-trip |
| `loop.exe` | Loops/branches, imprime `55` | round-trip |
| `strings.exe` | `.rdata` rico | round-trip + `-strings` |
| `no_relocs.exe` | Sem tabela de relocs (`/FIXED`) | round-trip |
| `var64.exe` | Real (mingw, 11 seções, TLS, 14 imports) | round-trip bin |
| `gcc.exe` | GCC 15.2.0 real (2 MB) | round-trip bin + `--version` |
| `ld.lld.exe` | LLD 21.1.3 real (68 MB) | dump rápido; round-trip em `run_slow.bat` |
| `var32.exe`, `link.exe`, `Calculator.exe`, `Case.exe`, `Char.exe`, `color.exe`, `Color2.exe`, `Contador.exe` | 32-bit | teste de rejeição (saída 3) |
| `for.exe` | `Magic=0` (nem o Windows executa — erro 193) | teste de rejeição (saída 3) |

> Atenção: `for.exe` trava se executado (loop infinito aparente) — a suíte
> nunca o executa, só verifica a rejeição. Programas que imprimem o próprio
> nome (`gcc --version`) são comparados com o mesmo nome de arquivo (via
> cópia em `%TEMP%`), pois o output depende de `argv[0]`.

## 8. Erros comuns

| Sintoma | Causa provável |
|---|---|
| `dexter: invalid or unsupported PE file` (3) | Arquivo 32-bit, corrompido ou `Magic != 0x20B` — use `-v` para inspecionar |
| `dexter: cannot open/read input file` (2) | Caminho errado ou sem permissão de leitura |
| `dexter: nasm failed` (5) | `nasm.exe` não achado (use `-N`) ou `.asm` inválido |
| `dexter: link failed` (5) | `link.exe` não achado (use `-L`); ver saída do link acima |
| `LNK4078 ... different attributes` | Aviso benigno (merge de `.rdata`/`.bss`); o link conclui |
| Rebuild win64 de PE complexo não roda | Limitação conhecida: o linker reordena seções — use `-m bin` |

## 9. Limitações honestas (ver `docs/ROADMAP.md`)

- Só PE **x64** (32-bit retorna 3; não há plano de decoder 32-bit).
- VEX/EVEX/x87 saem como `db` byte-exato (correto em bytes).
- Modo win64 garante round-trip comportamental em PEs simples; para PEs
  reais complexos, `-m bin` é o caminho fiel (byte-idêntico).
- Rewrite `call [rel __imp_X]` desativado por decisão (db-copy preserva);
  reativação futura (R-3.3/R-4.5) com emissor nativo de mnemônicos.

## 10. Para desenvolvedores

- Leia nesta ordem: `skill.md` → `Projeto.md` → `docs/ROADMAP.md` →
  `docs/ARQUITETURA.md`. A `skill.md` é normativa.
- `build.bat` (etapas `[0/3]` versão, `[1/3]` nasm, `[2/3]` link),
  `clean.bat`, `tests\run_tests.bat` (rápido), `tests\run_slow.bat` (68 MB).
- Convenção de commits: Conventional Commits + `Refs:` + `Testes:`.

## 11. Fase 6 — AST / Lexer / Código nativo (R-6.1 pronto)

Onde estamos (2026-10-07): `-native` emite mnemônicos reais com
round-trip provado no corpus simples (`hello`, `tiny`, `loop`,
`strings`, `no_relocs`); `db` continua o default fiel.

Plano (incremental, `db` continua default):

* **A — `-native` (R-6.1, FECHADO):** `out\dexter.exe tests\hello.exe -o h.asm -native`
  emite `mov/lea/call/jmp` reais com tamanho byte-exato, com fallback
  `db` byte-exato (inclui refs RIP/REL p/ dados, sem labels ainda).
* **B — lexer+AST (R-6.2/R-6.3 FECHADOS, `-ast-dump` pronto):**
  `src/front/lexer.asm` (`dex_lex_one`) + `parser.asm` + `ast.asm` →
  `Func → Blocos (CFG) → Instr → Op`; `out\dexter.exe app.exe -o
  app.asm -ast-dump` imprime o resumo da AST do `.asm` gerado.
* **C — lift+codegen (R-6.4+, futura):** `src/back/lift.asm` + `codegen.asm`;
  só aqui o rewrite `call [rel __imp_X]` volta (R-3.3/R-4.5).

Ver `docs/adr/0001-ast-lexer-codegen.md` e `docs/ROADMAP.md` R-6.x.
