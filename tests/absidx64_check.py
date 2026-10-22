#!/usr/bin/env python3
"""absidx64_check.py — oráculo do índice simbólico x64 (SIB-abs com índice).

Uso: python tests\\absidx64_check.py <asm_win64> <asm_bin>

Contrato verificado (R: base simbólica do índice em x64):
  1. `jmp qword [nosplit abs label_<VA>+rcx*8]`  (dispatch)
  2. `mov eax, [nosplit abs label_<VA>+rdx*4]`   (load indexado)
  3. o label referenciado está DEFINIDO no próprio .asm (semeadura de símbolo)
  4. no modo `-m bin` a expressão leva a correção `+ 0x<C>` (VA != file offset)

Sai 0 se tudo confere; 1 caso contrário (com motivo em stdout).
"""
import re
import sys

def die(msg):
    print("FALHA: " + msg)
    return 1

def labels_defined(text):
    # label_<HEX>: no início de linha (definição), não referência
    return set(m.group(1).upper() for m in re.finditer(r"(?m)^label_([0-9A-Fa-f]+):", text))

def check_operand(path, insn_re, want_corr, what):
    try:
        text = open(path, "r", encoding="utf-8", errors="replace").read()
    except OSError as exc:
        return 1, "nao foi possivel ler %s (%s)" % (path, exc)
    m = re.search(insn_re, text)
    if not m:
        return 1, "%s: operando simbolico ausente (%s)" % (path, what)
    lab = m.group(1).upper()
    defined = labels_defined(text)
    if lab not in defined:
        return 1, "%s: label_%s referenciado mas NAO definido" % (path, lab)
    corr = m.group(2) if (m.lastindex or 0) >= 2 else None
    if want_corr and not corr:
        return 1, "%s: label_%s sem correcao '+ 0x<C>' no -m bin" % (path, lab)
    if not want_corr and corr:
        return 1, "%s: label_%s com correcao inesperada no win64" % (path, lab)
    return 0, "OK %s: label_%s%s" % (what, lab, corr or "")

def main(argv):
    if len(argv) != 3:
        return die("uso: absidx64_check.py <asm_win64> <asm_bin>")
    win, binf = argv[1], argv[2]
    rc = 0
    # win64: sem correção (o linker resolve labels na mesma imagem)
    for pat, what in (
        (r"nosplit abs label_([0-9A-Fa-f]+)\+rcx\*8\]", "jmp [label+rcx*8]"),
        (r"nosplit abs label_([0-9A-Fa-f]+)\+rdx\*4\]", "mov [label+rdx*4]"),
    ):
        r, msg = check_operand(win, pat, False, what)
        print(msg)
        rc |= r
    # bin: mesma forma + correção VA->file offset
    for pat, what in (
        (r"nosplit abs label_([0-9A-Fa-f]+)( \+ 0x[0-9A-Fa-f]+)?\+rcx\*8\]", "jmp [label+C+rcx*8]"),
        (r"nosplit abs label_([0-9A-Fa-f]+)( \+ 0x[0-9A-Fa-f]+)?\+rdx\*4\]", "mov [label+C+rdx*4]"),
    ):
        r, msg = check_operand(binf, pat, True, what)
        print(msg)
        rc |= r
    return 1 if rc else 0

if __name__ == "__main__":
    sys.exit(main(sys.argv))
