# ADR-0007 — VEX2: tabela derivada (capstone + NASM) e flags de decode no descritor

- Data: 2026-10-22
- Status: aceito
- Requisito: item 2 da fila pós-2c, fatia **2b** (VEX2, mapa 0F)
- Ver: `docs/PE_NOTES.md §33`, `tools/gen_vex2.py`,
  `src/disasm/vex2_tbl.inc`, `tests/vex2nat.asm`, `[61]`

## Contexto

O decoder já reconhece VEX (C4/C5/62) e entrega limites byte-exatos (R-2.7),
mas `dex_build_operands` recusava `enc != 0`: todo VEX saía em `db`. Ao
contrário do x87 (conjunto fechado, 2048 codificações), o mapa `0F` sob VEX2
tem forma própria por `(pp, L, opcode)` — o mnemônico não é sempre "v" +
legado (`vmovups` vs `vaddps` vs `vzeroupper`), e vvvv é usado por algumas
instruções e proibido em outras. Escrever isso à mão seria adivinhação.

## Decisão

1. **Tabela derivada, não escrita à mão**: `tools/gen_vex2.py` monta alvos
   canônicos `C5` e usa o **NASM como juiz** (o texto só entra se reencodar
   os bytes exatos); o capstone identifica mnemônico/classes. O `.inc` é
   versionado e o build não depende de capstone.
2. **Descritor de 20 B** com `dq mnemônico`, `nops|flags` e até 4 pares
   `papel,classe`. Papéis R/V/M/I; classes V16/V32/G32/G64/K/M/M4/M8/I8.
3. **Flags de decode no descritor** (bit3 ModRM, bit4 imm8): a tabela
   legada `dex_tbl2_flag` tem lacunas (`0F F2 = 0`) e o decoder VEX2 precisa
   do tamanho correto para não desalinhar o sweep. A legada fica como
   fallback para opcodes fora da tabela.
4. **Gate de vvvv** (bit7): instruções que não usam vvvv exigem o campo
   `1111` (lógico 0); qualquer outro valor é encoding reservado → `db`.
5. **Entradas sem forma** (bit6) continuam `db`, mas com o mnemônico no
   comentário — 24 escalares com `L=1` (reservado; o NASM normaliza para
   `L=0`) e 10 combinações que não fecham byte a byte.
6. **Imm8 fora dos DexOps** (`Insn.vex_imm8`): o modelo cobre até 3
   registradores/memória; o imediato é o 4º operando das formas RVMI.

## Alternativas descartadas

- **Regra "v" + mnemônico legado**: falha em ~1/3 das entradas (`vmovmskps`,
  `vzeroupper`, `vucomiss`, `vmovd`…), e a ordem dos operandos muda
  (RVM/RM/MR/RVMI).
- **Copiar os bytes do prefixo e emitir só operandos**: inviável em texto —
  o NASM reencoda o prefixo a partir do mnemônico.
- **Usar a tabela legada para os flags de decode**: é a origem do bug do
  `0F F2` (sweep desalinhado); a tabela derivada é a fonte correta.
- **Derivar em tempo de build**: acopla o build ao capstone; rejeitado.

## Consequências

- `dexter.exe` cresce com ~7 KB de descritores + 4 KB de índice; custo de
  lookup O(1) por `(pp,L,op)`.
- Novos campos em `Insn` (carvados do `pad2`, sem mudar `SIZEOF_INSN`):
  pp/l/w/vvvv/mm/mask/r/b/x/imm8.
- A mesma metodologia escala para 2c (VEX3: mapas 0F/38/3A + W) e 2d
  (EVEX: mapa 5/6, máscara, broadcast, `disp8*N`) — muda só a chave e o
  gerador.
- Provas: fixture de 1442 instruções (1418 nativas + 24 db), `nasm -f bin`
  do `.asm` inteiro == `.exe`, `-m bin -native -r` byte-idêntico (exit 42),
  `-native -r` win64 linka e roda 42; suíte 464/464, lenta 7/7.
