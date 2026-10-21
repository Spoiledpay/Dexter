# ADR-0002 — Entry label via `equ` no `-s` + `-r`

Data: 2026-10-19 · Status: aceito (D-22, 1.2.389) · Autor: Dexter Engineer

## Contexto

No modo `win64`/`win32`, `dex_rebuild` passa
`/ENTRY:label_<entryVA>` ao `link.exe`. O cabeçalho do `.asm` gerado declarava
apenas `global label_<entryVA>`; a **definição** `label_<entryVA>:` só era
emitida pelo walker de código da seção do entrypoint.

Com `-s <seção>` apontando para outra seção, o contrato do filtro manda emitir
a seção do entry como dados (`db`/chunks). Sem a definição do label, o link
falhava com:

```text
LINK : error LNK2001: unresolved external symbol label_<entryVA>
```

Reproduzido em `tests/exc.exe -s .rdata -native -r` (exit 5) e
`-s .rdata -r` (exit 5). `-s .text` funcionava porque a seção do entry era
justamente a seção desassemblada.

## Decisão

Fechar o `.asm` com uma expressão constante, emitida por
`.emit_entry_alias` (`src/gen/rebuild.asm`) **depois** de todas as seções:

```text
label_<entryVA> equ label_<secVA> + 0x<delta>
```

Onde `label_<secVA>` é o `lab0` que toda seção emitida já produz
(`db`/chunks/`resb`) e `delta = entry_rva - sec_vaddr`.

Guardas:

* `delta == 0`: não emite (o label da seção já é o entry; evita
  `label_X equ label_X + 0`);
* `-s` na própria seção do entry: não emite (o walker de código define o
  label; evita duplicata);
* `-m bin`: não emite (`-f bin` não usa `/ENTRY`);
* sem `-r`: não emite.

A emissão no fim do arquivo elimina forward reference: o label da seção já
foi definido quando o `equ` é avaliado.

## Alternativas consideradas

1. **Forçar a seção do entry a ser code-walked quando `-r`.** Rejeitada:
   muda o escopo de `-s` (o usuário pediu só uma seção), aumenta o `.asm` e
   pode reintroduzir símbolos/referências que o filtro existia para evitar.
2. **Recusar `-s` + `-r` com exit 1.** Rejeitada: quebra um uso legítimo
   (analisar uma seção e reconstruir a imagem com o entry opaco).
3. **Emitir o label no stream `db` em duas partes.** Rejeitada por
   duplicação de lógica nos caminhos `plain`/`chunks`/`uw`/`bss`; a expressão
   `equ` é única e independente do caminho.

## Consequências

* Positivas: `-s` + `-r` passa a linkar em x64 e x32; `-s` preserva o
  contrato (demais seções continuam `db`); `-m bin` fica intocado
  (byte-idêntico).
* Negativas: o entrypoint reconstruído aponta para bytes `db` — a imagem
  linka e carrega, mas o comportamento em PE real segue limitado pela
  **D-19 fatia 2** (`exc` ainda dá `0xC0000005`); a D-22 fecha apenas o
  `LNK2001`.
* Riscos: nomes de label dependem de `entry_va`/`sec_va` estáveis (já são a
  convenção `label_<hexVA>`); `equ` é absoluto e não gera relocação, o que é
  correto para o `/ENTRY`.

## Verificação

* `[55]` (6 checks): `exc -s .rdata -native -r` e `-s .rdata -r` linkam;
  `-s .text -native -r` sem `equ` redundante; `tiny32 -s .rdata -r`
  (x32, delta 0) linka.
* `build.bat` limpo; `tests\run_tests.bat` **391/391**;
  `tests\run_slow.bat` **7/7**.
* `[0]` valida `FONTE SAGRADA DO CORPUS` em todos os `.asm` do corpus
  (lição registrada no CTX: `dexter x.exe -v` usa `<input>.asm` por default).
