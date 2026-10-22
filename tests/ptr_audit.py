#!/usr/bin/env python3
"""ptr_audit.py ORIG.exe REBUILT.exe [--limit N]

Auditoria da D-19 (dados): procura VA de 8 bytes (qword) que ficou
CONGELADA do original quando o `link.exe` moveu seções.

Método (independente do texto do `.asm`):
  1. varre o ORIGINAL, alinhado a 8, nas seções não-executáveis;
  2. cada qword dentro de [imagebase, imagebase+SizeOfImage) é candidato a
     VA/slot de ponteiro: descobre (seção, offset) do alvo e calcula a VA
     equivalente no REBUILT (mesma seção homônima + offset);
  3. se a VA mudou, o slot correspondente do REBUILT (mesma seção/offset)
     tem de conter a VA nova; se contém a antiga (ou outra coisa), é
     ponteiro congelado -> o consumidor (unwinder, EH, TLS, tabela do CRT)
     salta para o lugar errado.

Saída: contagem por seção-alvo + primeiros casos (slot -> antigo/novo).
Sai 0 quando não há ponteiro congelado; 1 caso contrário.
Nunca executa binário.
"""
import struct
import sys

import secdump


def main():
    args = sys.argv[1:]
    if len(args) < 2:
        print(__doc__)
        return 2
    orig_p, reb_p = args[0], args[1]
    limit = 20
    if '--limit' in args:
        limit = int(args[args.index('--limit') + 1])
    o = secdump.load(orig_p)
    r = secdump.load(reb_p)
    od = open(orig_p, 'rb').read()
    rd = open(reb_p, 'rb').read()
    obase, rbase = o['imagebase'], r['imagebase']
    rmap = {secdump.norm(s['name']): s for s in r['secs']}
    stale = []
    seen = 0
    for s in o['secs']:
        ch = s['ch']
        if ch & 0x20000000 or ch & 0x20:      # executável/código
            continue
        raw = od[s['rp']:s['rp'] + s['rsz']]
        tsec = rmap.get(secdump.norm(s['name']))
        if tsec is None:
            continue
        traw = rd[tsec['rp']:tsec['rp'] + tsec['rsz']]
        for off in range(0, len(raw) - 7, 8):
            v = struct.unpack_from('<Q', raw, off)[0]
            if not (obase <= v < obase + o['sizeimage']):
                continue
            seen += 1
            oname, ooff = secdump.locate(o['secs'], v - obase)
            if oname is None:
                continue
            t = rmap.get(secdump.norm(oname))
            if t is None:
                continue
            new = rbase + t['va'] + ooff
            if new == v:
                continue
            if off + 8 > len(traw):
                stale.append((secdump.norm(s['name']), off, v, new, None))
                continue
            got = struct.unpack_from('<Q', traw, off)[0]
            if got != new:
                stale.append((secdump.norm(s['name']), off, v, new, got))
    print(f"candidatos (qword em faixa de imagem): {seen} | "
          f"congelados: {len(stale)}")
    if not stale:
        print("OK: nenhum ponteiro de dados congelado")
        return 0
    bysec = {}
    for (name, off, v, new, got) in stale:
        bysec[name] = bysec.get(name, 0) + 1
    for k in sorted(bysec):
        print(f"  secao {k:10} {bysec[k]:4}x")
    for (name, off, v, new, got) in stale[:limit]:
        g = f"0x{got:X}" if got is not None else "fora"
        print(f"  {name}+0x{off:X}: orig 0x{v:X} deveria ser 0x{new:X} "
              f"(rebuild tem {g})")
    if len(stale) > limit:
        print(f"  ... +{len(stale) - limit}")
    print(f"\nFALHA: {len(stale)} ponteiro(s) de dados congelado(s)")
    return 1


if __name__ == '__main__':
    sys.exit(main())
