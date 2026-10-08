# Dexter — CLI

`dexter <input.exe> [opções]` — desassemblador/reassemblador x64 nativo (NASM/Win64).

Sem argumentos, imprime o banner + ajuda e retorna 0:

```text
Dexter disassembler Tool Version 1.2.3
LabsObjects All rights reserved
...
```

Versão atual sempre via `-ver` (lida de `version.bin` no build;
`tools\bump_version.ps1` incrementa o patch a cada `build.bat`).

## Saída

| Flag | Efeito real |
|---|---|
| `-o <arquivo.asm>` | Fonte NASM gerada (padrão: `<input>.asm` ao lado do input) |
| `-O <arquivo.exe>` | .exe reassemblado (implica `-r`) |
| `-m <modo>` | `win64` (padrão, via `link.exe`) ou `bin` (via `nasm -f bin`, byte-fiel) |
| `-r` | Reassembla após gerar o .asm |
| `-L <linker>` | Caminho do linker (padrão: `C:\Nasm\link.exe`) |
| `-N <nasm>` | Caminho do nasm (padrão: `C:\Nasm\nasm.exe`) |

## Controle de desassemblagem (modo `win64`)

| Flag | Efeito real |
|---|---|
| `-s <secao>` | Só esta seção é desassemblada; demais viram `db` |
| `-start <RVA>` / `-end <RVA>` | Intervalo de RVAs desassemblado (hex `0x...`); fora vira `db`. Seções de dados sempre saem por inteiro |
| `-hex` | Acrescenta comentário `; @0xVA` (e `; mne`) em cada linha |
| `-nop-pad` | Bytes `0x90`/`0xCC` em código saem como `nop`/`int3` reais (mesmos bytes) em vez de `db` |
| `-no-imports` | Não processa imports (afeta `-v`; rebuild por cópia não precisa deles) |
| `-no-relocs` | Não processa relocs e **omite a seção `.reloc`** do `.asm` |
| `-strings` | Runs ASCII ≥8 + NUL em dados viram `db "...", 0` |
| `-native` | (R-6.1, opt-in) emite mnemônicos reais (`mov rax, rbx`, `[rel label]`) via `dex_emit_native` quando possível, com tamanho byte-exato garantido (`strict`, regras de forma); fallback `db` byte-exato quando não (inclui refs RIP/REL p/ dados, sem labels); default desligado (= `db` atual). Round-trip provado no corpus simples |
| `-ast-dump` | (R-6.5, opt-in) após gerar o `.asm`, faz parse-back em memória e imprime em stdout o resumo `AST funcs=F blocks=B instrs=I succs=S db=D equ=E dir=R` (mesmo formato do golden de `tests/ast_check.asm`); a geração do `.asm` é inalterada (byte-idêntica com/sem a flag); falha de parse (`.asm` >16 MB ou OOM) = aviso em stderr, nunca erro (respeita `-q`) |

Em modo `-m bin` as flags de desassemblagem são ignoradas (aviso em stderr,
exceto com `-q`); `-hex` continua valendo para os comentários de VA.

## Diagnóstico

| Flag | Efeito |
|---|---|
| `-v` | Verbose 1: base, entry, seções, imports/exports/relocs |
| `-vv` | Verbose 2: tudo do `-v` + hexdump de 64 bytes por seção |
| `-q` | Silencioso (só erros em stderr) |
| `-ver` | Versão |
| `-h`, `--help` | Ajuda |

## Retorno

| Código | Significado |
|---|---|
| 0 | sucesso |
| 1 | uso incorreto (inclui opção desconhecida, sem input, `-m` inválido) |
| 2 | erro de I/O (abrir/ler/escrever/spawn) |
| 3 | PE inválido ou não-x64 |
| 4 | (reservado) opcode sem suporte — atual: fallback `db`, não usado |
| 5 | falha no reassembly (nasm/link retornou ≠ 0, patch de diretórios) |

## Exemplos

```bat
dexter.exe app.exe -o app.asm -hex -v
dexter.exe app.exe -o app.asm -r -O app_rebuild.exe
dexter.exe app.exe -o app.asm -m bin -r -O app_bin.exe
dexter.exe app.exe -s .text -start 0x1000 -end 0x2000
```
