#!/usr/bin/env python3
# tests/qstr_check.py — valida a emissao de strings do Dexter (`-strings`):
# runs com CR/LF e aspas viram UMA linha NASM, com os escapes `, 13`/`, 10`/`, 34`
# e SEM aspas vazias (`""`). Oraculo = fixture tests/strings.asm (s1/s2/s3).
# Uso: python tests/qstr_check.py <asm>   -> imprime "QSTR ...".
# Exit: 0 tudo conferido; 1 divergencia/erro.
import sys

if len(sys.argv) != 2:
    print("uso: qstr_check.py <asm>")
    sys.exit(1)

try:
    text = open(sys.argv[1], "r", encoding="latin1").read()
except Exception as exc:  # noqa: BLE001
    print("erro:", exc)
    sys.exit(1)

want = [
    'db "alpha-one", 13, 10, 0',
    'db "say ", 34, "hi", 34, " ok", 13, 10, 0',
    'db "0123456789ABCDEF", 13, 10, 0',
]
bad = 0
for w in want:
    if w in text:
        print("  OK linha exata:", w)
    else:
        print("  FALTA linha exata:", w)
        bad += 1

empty = [ln for ln in text.split("\n") if 'db "' in ln and '""' in ln]
if empty:
    print("  FALHA aspa vazia:", empty[0].strip())
    bad += 1
else:
    print("  OK sem aspas vazias")

crlf = sum(1 for ln in text.split("\n") if ", 13, 10, 0" in ln)
print(f"QSTR linhas_crlf={crlf} ruins={bad}")
sys.exit(1 if bad else 0)
