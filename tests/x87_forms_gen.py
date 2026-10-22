#!/usr/bin/env python3
"""x87_forms_gen.py — gera tests/x87nat.asm + tests/expected/x87nat.tsv.

Fixture 2a (x87 nativo): as 8 opcodes x87 (D8-DF) x 256 ModRM = 2048
codificações, uma instrução por linha `db` (para o sweep linear do Dexter
decodificar exatamente uma por linha). As formas de memória percorrem as
classes de endereçamento:
  mod=00 rm=0..3/6/7 -> [reg]
  mod=00 rm=4        -> SIB [rbx+rcx*4]
  mod=00 rm=5        -> RIP+disp32 (0 = próxima instrução, em código)
  mod=01             -> disp8 0x10 (rm=5 -> [rbp+0x10])
  mod=10             -> disp32 0x1000
O payload fica APÓS `call ExitProcess` (inalcançável); o comportamento do
fixture é exit 42.

O TSV registra, por codificação: idx, opcode, modrm, native (1 = a tabela
x87 tem forma; 0 = db esperado), mnemônico. É o oráculo de contagem do
tests/x87_native_check.py — o teste independente de bytes é o nasm.

Uso: python tests\\x87_forms_gen.py
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
X87 = ROOT / "src" / "disasm" / "x87.asm"
OUT_ASM = ROOT / "tests" / "x87nat.asm"
OUT_ASM32 = ROOT / "tests" / "x87nat32.asm"
OUT_TSV = ROOT / "tests" / "expected" / "x87nat.tsv"

HEADER = """; x87nat.asm — CORPUS 2a: as 2048 codificações x87 (D8-DF).
; FONTE SAGRADA DO CORPUS: nunca gerar .asm em cima deste arquivo!
; GERADO por tests/x87_forms_gen.py — não editar à mão (regenere o script).
; Uma instrução por linha `db`, na ordem (opcode, modrm), para o sweep
; linear do Dexter. O payload é inalcançável (após ExitProcess); sai 42.
bits 64
default rel

global main
extern ExitProcess

section .text
main:
    sub rsp, 40
    mov ecx, 42
    call ExitProcess

; ---- payload: 2048 codificações (opcode D8-DF x ModRM 00-FF) ----
"""

HEADER32 = """; x87nat32.asm — CORPUS 2a (x32): as 2048 codificações x87 (D8-DF).
; FONTE SAGRADA DO CORPUS: nunca gerar .asm em cima deste arquivo!
; GERADO por tests/x87_forms_gen.py — não editar à mão (regenere o script).
; Mesmo payload do x87nat.asm (bytes idênticos), em PE32 (stdcall). Em x32 o
; rm=101/mod=00 é ABSOLUTO (disp32), não RIP — o emissor sai `[0xVA]`.
bits 32

global main
extern _ExitProcess@4

section .text
main:
    push ebp
    mov ebp, esp
    sub esp, 0x28
    push dword 42
    call _ExitProcess@4

; ---- payload: 2048 codificações (opcode D8-DF x ModRM 00-FF) ----
"""

FOOTER = """
section .rdata
align 8
x87data: dq 0x3FF0000000000000
"""

def parse_tables():
    text = X87.read_text(encoding="utf-8", errors="replace")
    strings = dict(re.findall(r'^(s_x87_[A-Za-z0-9_]+):\s*db\s+"([^"]*)"', text, re.M))

    def table(name, count):
        m = re.search(r'^' + name + r':\n(.*?)\n\n', text, re.M | re.S)
        if not m:
            raise SystemExit("tabela %s nao encontrada" % name)
        out = []
        for line in m.group(1).splitlines():
            line = line.strip()
            if line.startswith("dq "):
                for item in line[3:].split(","):
                    item = item.strip()
                    out.append(None if item == "0" else strings[item])
        if len(out) != count:
            raise SystemExit("%s: %d entradas (esperado %d)" % (name, len(out), count))
        return out

    return table("x87_mem", 64), table("x87_reg", 512)

def bytes_for(op, modrm):
    mod = modrm >> 6
    rm = modrm & 7
    b = [op, modrm]
    if mod == 3:
        return b
    if rm == 4:
        b.append(0x8B)                    # SIB: scale=4, index=rcx, base=rbx
    if mod == 0:
        if rm == 5:
            b += [0x00, 0x00, 0x00, 0x00]  # RIP+0 (alvo = próxima instrução)
        return b
    if mod == 1:
        b.append(0x10)                    # disp8
        return b
    b += [0x00, 0x10, 0x00, 0x00]         # disp32 = 0x1000
    return b

def main():
    mem, reg = parse_tables()
    body = []
    tsv = ["# idx\topcode\tmodrm\tnative\tnative32\tmnemonic"]
    idx = 0
    for op in range(0xD8, 0xE0):
        for modrm in range(256):
            mod = modrm >> 6
            grp = (modrm >> 3) & 7
            if mod == 3:
                mne = reg[(op - 0xD8) * 64 + (modrm & 0x3F)]
                # D9 D8-DF: fstpnce não tem mnemônico no NASM -> db
                native = 0 if (op == 0xD9 and grp == 3) else 1
            else:
                mne = mem[(op - 0xD8) * 8 + grp]
                native = 1
            if not mne:
                mne_name = "-"
                native = 0
            else:
                mne_name = mne
            # x32: rm=101/mod=00 é ABSOLUTO; alvo fora da imagem cai em db
            native32 = native and not (mod == 0 and (modrm & 7) == 5)
            raw = bytes_for(op, modrm)
            body.append("    db %s   ; %02X/%02X %s\n" % (
                ", ".join("0x%02X" % x for x in raw), op, modrm, mne_name))
            tsv.append("%d\t%02X\t%02X\t%d\t%d\t%s" % (idx, op, modrm, native, native32, mne_name))
            idx += 1
    payload = "".join(body)
    OUT_ASM.write_text(HEADER + payload + FOOTER, encoding="utf-8", newline="\n")
    OUT_ASM32.write_text(HEADER32 + payload + FOOTER, encoding="utf-8", newline="\n")
    OUT_TSV.parent.mkdir(parents=True, exist_ok=True)
    OUT_TSV.write_text("\n".join(tsv) + "\n", encoding="utf-8", newline="\n")
    print("gerado %s + %s (%d instrucoes) e %s" % (
        OUT_ASM.name, OUT_ASM32.name, idx, OUT_TSV.name))

if __name__ == "__main__":
    main()
