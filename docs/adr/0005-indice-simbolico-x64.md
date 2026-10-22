# ADR-0005 — Índice simbólico em x64: gate por sinal-estensão e correção `+C` no bin

- Data: 2026-10-22
- Status: aceito
- Requisito: fila pós-2c, item 1 ("base simbólica do índice em x64")
- Ver: `docs/PE_NOTES.md §31`, `tests/absidx64.asm`, `[59]`

## Contexto

`[disp32 + idx*scale]` (ModRM mod=00, r/m=100, SIB base=101) é o endereço
absoluto com índice. Em x32 o disp32 é uma VA de 32 bits e desde a 1.2.379 o
emissor sai simbólico (`[nosplit label_<VA>+eax*4]`).

Em x64 o mesmo campo muda de regra: a CPU **sinal-estende** o disp32. Com a
`ImageBase` usual (`0x140000000`) nenhum disp32 pode endereçar o módulo — o
valor efetivo cai em `0x00000000_xxxxxxxx`. Só com base abaixo de 2 GiB
(`/BASE:0x400000`) a forma aponta para dados da imagem. Além disso, o
`-m bin` não usa `org`: os labels valem **file offsets**, enquanto o disp32
codifica uma VA.

## Decisão

1. **Escopo honesto:** só é simbólico quando o disp32 sinal-estendido é uma
   VA dentro da imagem (`sign_ext(disp32) >= ImageBase`). Fora disso o
   operando continua numérico (`[nosplit abs 0x..]`) — o símbolo seria uma
   mentira sobre o alvo efetivo.
2. **Coletor** (`.cs_abs64sib`): `movsxd` + gate `mod00/rm100/has_sib`,
   avaliado **antes** do teste `modrm&C7 == 05` (RIP). O gate invertido
   descartava todo SIB-abs em silêncio.
3. **Correção de layout** (`-m bin`): array `g_abs_corr`, paralelo ao array
   ordenado de RVAs (`g_abs_vas`/`g_abs_n`), com `C = VA - off`. O emissor
   consulta pelo índice do hit na busca binária e sai
   `label_<VA> + 0x<C>+<idx>*<scale>`. No win64 o array fica nulo (o linker
   resolve os labels como VAs).
4. **Semeadura de símbolos no bin** (`.gb_rchunks`): fatia a seção de dados
   em `[k0,k1)` nos alvos R, emitindo `label_<VA>:` antes dos bytes
   (verbatim). Aplicado à seção sem imports, aos gaps e ao resto de
   `.gb_db_slots`. Sem isso o `.asm` referenciaria símbolo inexistente.

## Alternativas descartadas

- **Emitir símbolo sempre que o RVA estiver no R** (sem checar a
  sinal-estensão): byte-idêntico, mas rotularia como "tabela da imagem" um
  acesso que a CPU faz a outro endereço. Rejeitado por fidelidade semântica.
- **`equ` global para cada alvo** em vez de fatiar os dados: criaria
  definições duplicadas com labels já emitidos pelos imports e não
  reproduziria o contrato de labels do win64.
- **Duplicar `rva_to_offset` no emissor**: preferiu-se o array pré-computado
  (sem dependência nova de link para os drivers que montam só `emit_nasm.obj`).

## Consequências

- `emit_nasm.asm` ganha o global `g_abs_corr` (0 = desligado); `rebuild.asm`
  preenche em `dex_generate_bin` e libera no fim (caminho de sucesso e OOM).
- Custo: 8 B por alvo R no `-m bin` (1238 no notepad) e uma chamada a
  `dex_rva_to_offset` por alvo na montagem do array.
- Limite declarado: com `ImageBase >= 2 GiB` a forma segue numérica; é o
  único comportamento correto, já que o disp32 não referencia o módulo.
- Provas: `[59]` (12 checks) — texto simbólico nos dois modos, `.asm` monta,
  rebuild win64 exit 42, `-m bin -native -r` byte-idêntico e exit 42; suíte
  438/438 e lenta 7/7.
