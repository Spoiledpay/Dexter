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
| `-strings` | Runs ASCII ≥8 + NUL em dados viram `db "...", 0`; com `-native`, slots de 8 bytes com valor VA rotulada (R/runs/ponteiros) viram `dq label_` |
| `-overview` | (inspect-only) resumo do PE em stdout (base, entry, seções, imports/exports/relocs); não escreve `.asm`, ignora `-r`; `-q` não suprime |
| `-json` | Com `-overview`/`-func`/`-xrefs`/`-trace`: mesma informação em JSON compacto (1 linha, chaves estáveis, hex como string, counts decimais); sozinho é ignorado |
| `-func <VA>` | (inspect-only) dossiê da função em VA: bounds (linear-sweep até ret/jmp/inválido/fim, sem CFG), calls e jmps com alvos (+`__imp_` se IAT) |
| `-xrefs <VA>` | (inspect-only) quem referencia VA: `call`/`jmp`/`branch` (via `target_va`) + `data` (RIP-rel); cap 256 com `truncated` honesto |
| `-trace <VA>` | (inspect-only) cadeia de calls (first-call DFS até `-depth`); `end` ∈ `leaf/import/cycle/depth/outside` + `truncated`; jmp-out p/ import registra aresta |
| `-depth <N>` | Profundidade do `-trace` (1..64 em hex `0x..`, padrão 8) |
| `-rsrc` | (inspect-only) inventário de recursos PE em 3 níveis (tipo/nome/idioma); vazio honesto se ausente; corrompido → saída 3 |
| `-snapshot <arq.json>` | (inspect-only) fingerprint do PE em arquivo JSON (FNV-1a, size, base, entry, seções, imports, exports, relocs); não escreve `.asm`, ignora `-r` |
| `-compare <b.exe>` | (inspect-only) diff A (input) vs B em stdout: texto (`same`/`DIFF`, `+`/`-`/`~` por seção e `dll!func`) ou `-json` (`identical`); B ilegível/inválido → saída 2/3 |
| `--doctor` / `-doctor` | (inspect-only) toolchain + versão em stdout (`Doctor:`, `nasm: <path> ok\|missing`, `link: …`, `kernel32: ok`, `input: valid PE x64`); exit 0 sempre; `-q` não suprime |
| `-native` | (R-6.1, opt-in) emite mnemônicos reais (`mov rax, rbx`, `[rel label]`) via `dex_emit_native` quando possível, com tamanho byte-exato garantido (`strict`, regras de forma); fallback `db` byte-exato quando não (inclui refs RIP/REL p/ dados, sem labels); default desligado (= `db` atual). No modo `win64`, a import table sai **simbólica** (`dd label_<VA> wrt ..imagebase`; IAT como `dd label, 0`), para o `link.exe` recalcular as RVAs depois de reordenar seções (D-19 2b); `-m bin` segue a R-5.3 (`label + C`). Nomes `__imp_` repetidos em 2 slots recebem sufixo `_<iat_rva>` a partir da 2ª ocorrência. Round-trip provado no corpus simples |
| `-emit <db\|native>` | (R-6.5) forma explícita do emissor: `native` ≡ `-native`, `db` ≡ default; `-native` segue como alias; last-wins entre ambos; outro valor → saída 1 |
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
dexter.exe app.exe -overview -json -q
```

Chaves do JSON (`-overview -json`): `tool`, `version`, `image_base`,
`entry_rva`, `num_sections`, `sections[]` (`name`, `vaddr`, `vsize`,
`raw_size`), `imports_count`, `imports[]` (`dll`, `func` — vazio se
ordinal — `ordinal`, `is_ordinal`, `iat_rva`), `exports_count`,
`relocs_count`. Nomes com escape `"`/`\` (controle vira `?`, cap 255).
Limitação honesta: imports por ordinal não têm cobertura no corpus
atual (nenhum binário de teste usa).

Chaves do `-func -json`: `tool`, `version`, `entry`, `found`,
`size`, `instrs`, `calls[]` (`va`, `imp`), `jmps[]` (`va`, `kind`),
`has_ret`, `truncated`. `found:false` sai sem o resto.

Chaves do `-xrefs -json`: `tool`, `version`, `query`, `total`,
`truncated`, `refs[]` (`va`, `kind` ∈ `call/jmp/branch/data`,
`detail` com `__imp_` ou vazio).

Chaves do `-trace -json`: `tool`, `version`, `from`, `depth`,
`truncated`, `end` ∈ `leaf/import/cycle/depth/outside`,
`chain[]` (`from`, `to`, `kind` ∈ `call/jmp`, `imp`).

Endereços sempre em hex `0x...` (absolutos, VAs). Todas as queries
são inspect-only (nunca escrevem `.asm`, ignoram `-r`; `-q` não
suprime o pedido explícito) e nunca retornam erro por conteúdo
(lista vazia / `found:false` / `leaf` em vez de crash).

Chaves do `-rsrc -json`: `tool`, `version`, `count`,
`resources[]` (`type` número ou `-1` se nomeado, `type_str`,
`name` número ou `-1`, `name_str`, `lang` número ou `-1`,
`lang_str`, `size`/`rva`/`offset` como strings `0x..`,
`codepage`). Texto: `  /tipo/nome/idioma size=0x.. rva=0x..
off=0x..` (nomes entre `"..."` com escape). Diretório ausente =
inventário vazio (saída 0); malformado (fora de limites, forma
inválida, payload não-mapeado, dir > 4MB) = saída 3 com motivo em
stderr. Duplicatas de irmãos são listadas (anomalia visível).

Chaves do `-snapshot` (arquivo): `tool`, `version`, `size`,
`fnv1a`, `image_base`, `entry_rva` (strings `0x..`), `num_sections`,
`sections[]` (`name`, `vaddr`, `vsize`, `raw_size`),
`imports_count`, `imports[]` (`dll`, `func` — vazio se ordinal —
`ordinal`, `is_ordinal`, `iat_rva`), `exports_count`,
`relocs_count`. JSON validado por parse (`ConvertFrom-Json`).

Chaves do `-compare -json`: `tool`, `version`, `a`, `b`,
`size`/`fnv1a`/`base`/`entry` (`a`, `b`, `same` 0/1; hex como
string `0x..`), `sections` (`a`, `b`, `added[]`, `removed[]`,
`changed[]` com nomes), `imports` (`a`, `b`, `added[]`,
`removed[]` como `dll!func` ou `dll!ordN`), `exports`/`relocs`
(`a`, `b`, `same`), `identical` (true/false). Texto espelha o
mesmo conteúdo (`same`/`DIFF`, `+`/`-`/`~`).
