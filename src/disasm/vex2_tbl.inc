;=============================================================================
; Dexter/src/disasm/vex2_tbl.inc
; Tabela VEX2 (C5, mapa 0F): mnemônico + forma de operando.
;
; GERADO por tools/gen_vex2.py (capstone 5.0.7 + NASM como juiz).
; NAO EDITAR A MAO. Regenerar: python tools\gen_vex2.py
;
; Descritor (20 B, alinhado a 4):
;   dq mnemônico
;   db nops | 0x80 (vvvv precisa ser 0/não usado)
;   db role0, class0, role1, class1
;   db role2, class2, role3, class3
;   db 0,0,0
; Índice: vex2_idx[(pp*2+L)*256+op] = id do descritor (0xFFFF = db).
;=============================================================================

%define VEX2_DESC_NONE 0xFFFF
%define VEX2_DESC_SIZE 20

section .rodata

s_v2_000: db "vmovups", 0
s_v2_001: db "vmovups", 0
s_v2_002: db "vmovhlps", 0
s_v2_003: db "vmovlps", 0
s_v2_004: db "vunpcklps", 0
s_v2_005: db "vunpckhps", 0
s_v2_006: db "vmovlhps", 0
s_v2_007: db "vmovhps", 0
s_v2_008: db "vmovaps", 0
s_v2_009: db "vmovaps", 0
s_v2_010: db "vmovntps", 0
s_v2_011: db "vucomiss", 0
s_v2_012: db "vcomiss", 0
s_v2_013: db "knotw", 0
s_v2_014: db "vmovmskps", 0
s_v2_015: db "vsqrtps", 0
s_v2_016: db "vrsqrtps", 0
s_v2_017: db "vrcpps", 0
s_v2_018: db "vandps", 0
s_v2_019: db "vandnps", 0
s_v2_020: db "vorps", 0
s_v2_021: db "vxorps", 0
s_v2_022: db "vaddps", 0
s_v2_023: db "vmulps", 0
s_v2_024: db "vcvtps2pd", 0
s_v2_025: db "vcvtdq2ps", 0
s_v2_026: db "vsubps", 0
s_v2_027: db "vminps", 0
s_v2_028: db "vdivps", 0
s_v2_029: db "vmaxps", 0
s_v2_030: db "vzeroupper", 0
s_v2_031: db "kmovw", 0
s_v2_032: db "kmovw", 0
s_v2_033: db "kmovw", 0
s_v2_034: db "kmovw", 0
s_v2_035: db "kortestw", 0
s_v2_036: db "ktestw", 0
s_v2_037: db "vcmpfalse_osps", 0
s_v2_038: db "vshufps", 0
s_v2_039: db "vmovups", 0
s_v2_040: db "vmovups", 0
s_v2_041: db "vunpcklps", 0
s_v2_042: db "vunpckhps", 0
s_v2_043: db "vmovaps", 0
s_v2_044: db "vmovaps", 0
s_v2_045: db "vmovntps", 0
s_v2_046: db "vucomiss", 0
s_v2_047: db "vcomiss", 0
s_v2_048: db "kandw", 0
s_v2_049: db "kandnw", 0
s_v2_050: db "korw", 0
s_v2_051: db "kxnorw", 0
s_v2_052: db "kxorw", 0
s_v2_053: db "kaddw", 0
s_v2_054: db "kunpckwd", 0
s_v2_055: db "vmovmskps", 0
s_v2_056: db "vsqrtps", 0
s_v2_057: db "vrsqrtps", 0
s_v2_058: db "vrcpps", 0
s_v2_059: db "vandps", 0
s_v2_060: db "vandnps", 0
s_v2_061: db "vorps", 0
s_v2_062: db "vxorps", 0
s_v2_063: db "vaddps", 0
s_v2_064: db "vmulps", 0
s_v2_065: db "vcvtps2pd", 0
s_v2_066: db "vcvtdq2ps", 0
s_v2_067: db "vsubps", 0
s_v2_068: db "vminps", 0
s_v2_069: db "vdivps", 0
s_v2_070: db "vmaxps", 0
s_v2_071: db "vzeroall", 0
s_v2_072: db "vcmpfalse_osps", 0
s_v2_073: db "vshufps", 0
s_v2_074: db "vmovupd", 0
s_v2_075: db "vmovupd", 0
s_v2_076: db "vmovlpd", 0
s_v2_077: db "vmovlpd", 0
s_v2_078: db "vunpcklpd", 0
s_v2_079: db "vunpckhpd", 0
s_v2_080: db "vmovhpd", 0
s_v2_081: db "vmovhpd", 0
s_v2_082: db "vmovapd", 0
s_v2_083: db "vmovapd", 0
s_v2_084: db "vmovntpd", 0
s_v2_085: db "vucomisd", 0
s_v2_086: db "vcomisd", 0
s_v2_087: db "knotb", 0
s_v2_088: db "vmovmskpd", 0
s_v2_089: db "vsqrtpd", 0
s_v2_090: db "vandpd", 0
s_v2_091: db "vandnpd", 0
s_v2_092: db "vorpd", 0
s_v2_093: db "vxorpd", 0
s_v2_094: db "vaddpd", 0
s_v2_095: db "vmulpd", 0
s_v2_096: db "vcvtpd2ps", 0
s_v2_097: db "vcvtps2dq", 0
s_v2_098: db "vsubpd", 0
s_v2_099: db "vminpd", 0
s_v2_100: db "vdivpd", 0
s_v2_101: db "vmaxpd", 0
s_v2_102: db "vpunpcklbw", 0
s_v2_103: db "vpunpcklwd", 0
s_v2_104: db "vpunpckldq", 0
s_v2_105: db "vpacksswb", 0
s_v2_106: db "vpcmpgtb", 0
s_v2_107: db "vpcmpgtw", 0
s_v2_108: db "vpcmpgtd", 0
s_v2_109: db "vpackuswb", 0
s_v2_110: db "vpunpckhbw", 0
s_v2_111: db "vpunpckhwd", 0
s_v2_112: db "vpunpckhdq", 0
s_v2_113: db "vpackssdw", 0
s_v2_114: db "vpunpcklqdq", 0
s_v2_115: db "vpunpckhqdq", 0
s_v2_116: db "vmovd", 0
s_v2_117: db "vmovdqa", 0
s_v2_118: db "vpshufd", 0
s_v2_119: db "vpcmpeqb", 0
s_v2_120: db "vpcmpeqw", 0
s_v2_121: db "vpcmpeqd", 0
s_v2_122: db "vhaddpd", 0
s_v2_123: db "vhsubpd", 0
s_v2_124: db "vmovd", 0
s_v2_125: db "vmovdqa", 0
s_v2_126: db "kmovb", 0
s_v2_127: db "kmovb", 0
s_v2_128: db "kmovb", 0
s_v2_129: db "kmovb", 0
s_v2_130: db "kortestb", 0
s_v2_131: db "ktestb", 0
s_v2_132: db "vcmpfalse_ospd", 0
s_v2_133: db "vpinsrw", 0
s_v2_134: db "vpextrw", 0
s_v2_135: db "vshufpd", 0
s_v2_136: db "vaddsubpd", 0
s_v2_137: db "vpsrlw", 0
s_v2_138: db "vpsrld", 0
s_v2_139: db "vpsrlq", 0
s_v2_140: db "vpaddq", 0
s_v2_141: db "vpmullw", 0
s_v2_142: db "vmovq", 0
s_v2_143: db "vpmovmskb", 0
s_v2_144: db "vpsubusb", 0
s_v2_145: db "vpsubusw", 0
s_v2_146: db "vpminub", 0
s_v2_147: db "vpand", 0
s_v2_148: db "vpaddusb", 0
s_v2_149: db "vpaddusw", 0
s_v2_150: db "vpmaxub", 0
s_v2_151: db "vpandn", 0
s_v2_152: db "vpavgb", 0
s_v2_153: db "vpsraw", 0
s_v2_154: db "vpsrad", 0
s_v2_155: db "vpavgw", 0
s_v2_156: db "vpmulhuw", 0
s_v2_157: db "vpmulhw", 0
s_v2_158: db "vcvttpd2dq", 0
s_v2_159: db "vmovntdq", 0
s_v2_160: db "vpsubsb", 0
s_v2_161: db "vpsubsw", 0
s_v2_162: db "vpminsw", 0
s_v2_163: db "vpor", 0
s_v2_164: db "vpaddsb", 0
s_v2_165: db "vpaddsw", 0
s_v2_166: db "vpmaxsw", 0
s_v2_167: db "vpxor", 0
s_v2_168: db "vpsllw", 0
s_v2_169: db "vpslld", 0
s_v2_170: db "vpsllq", 0
s_v2_171: db "vpmuludq", 0
s_v2_172: db "vpmaddwd", 0
s_v2_173: db "vpsadbw", 0
s_v2_174: db "vmaskmovdqu", 0
s_v2_175: db "vpsubb", 0
s_v2_176: db "vpsubw", 0
s_v2_177: db "vpsubd", 0
s_v2_178: db "vpsubq", 0
s_v2_179: db "vpaddb", 0
s_v2_180: db "vpaddw", 0
s_v2_181: db "vpaddd", 0
s_v2_182: db "vmovupd", 0
s_v2_183: db "vmovupd", 0
s_v2_184: db "vunpcklpd", 0
s_v2_185: db "vunpckhpd", 0
s_v2_186: db "vmovapd", 0
s_v2_187: db "vmovapd", 0
s_v2_188: db "vmovntpd", 0
s_v2_189: db "vucomisd", 0
s_v2_190: db "vcomisd", 0
s_v2_191: db "kandb", 0
s_v2_192: db "kandnb", 0
s_v2_193: db "korb", 0
s_v2_194: db "kxnorb", 0
s_v2_195: db "kxorb", 0
s_v2_196: db "kaddb", 0
s_v2_197: db "kunpckbw", 0
s_v2_198: db "vmovmskpd", 0
s_v2_199: db "vsqrtpd", 0
s_v2_200: db "vandpd", 0
s_v2_201: db "vandnpd", 0
s_v2_202: db "vorpd", 0
s_v2_203: db "vxorpd", 0
s_v2_204: db "vaddpd", 0
s_v2_205: db "vmulpd", 0
s_v2_206: db "vcvtpd2ps", 0
s_v2_207: db "vcvtps2dq", 0
s_v2_208: db "vsubpd", 0
s_v2_209: db "vminpd", 0
s_v2_210: db "vdivpd", 0
s_v2_211: db "vmaxpd", 0
s_v2_212: db "vpunpcklbw", 0
s_v2_213: db "vpunpcklwd", 0
s_v2_214: db "vpunpckldq", 0
s_v2_215: db "vpacksswb", 0
s_v2_216: db "vpcmpgtb", 0
s_v2_217: db "vpcmpgtw", 0
s_v2_218: db "vpcmpgtd", 0
s_v2_219: db "vpackuswb", 0
s_v2_220: db "vpunpckhbw", 0
s_v2_221: db "vpunpckhwd", 0
s_v2_222: db "vpunpckhdq", 0
s_v2_223: db "vpackssdw", 0
s_v2_224: db "vpunpcklqdq", 0
s_v2_225: db "vpunpckhqdq", 0
s_v2_226: db "vmovdqa", 0
s_v2_227: db "vpshufd", 0
s_v2_228: db "vpcmpeqb", 0
s_v2_229: db "vpcmpeqw", 0
s_v2_230: db "vpcmpeqd", 0
s_v2_231: db "vhaddpd", 0
s_v2_232: db "vhsubpd", 0
s_v2_233: db "vmovdqa", 0
s_v2_234: db "vcmpfalse_ospd", 0
s_v2_235: db "vshufpd", 0
s_v2_236: db "vaddsubpd", 0
s_v2_237: db "vpsrlw", 0
s_v2_238: db "vpsrld", 0
s_v2_239: db "vpsrlq", 0
s_v2_240: db "vpaddq", 0
s_v2_241: db "vpmullw", 0
s_v2_242: db "vpmovmskb", 0
s_v2_243: db "vpsubusb", 0
s_v2_244: db "vpsubusw", 0
s_v2_245: db "vpminub", 0
s_v2_246: db "vpand", 0
s_v2_247: db "vpaddusb", 0
s_v2_248: db "vpaddusw", 0
s_v2_249: db "vpmaxub", 0
s_v2_250: db "vpandn", 0
s_v2_251: db "vpavgb", 0
s_v2_252: db "vpsraw", 0
s_v2_253: db "vpsrad", 0
s_v2_254: db "vpavgw", 0
s_v2_255: db "vpmulhuw", 0
s_v2_256: db "vpmulhw", 0
s_v2_257: db "vcvttpd2dq", 0
s_v2_258: db "vmovntdq", 0
s_v2_259: db "vpsubsb", 0
s_v2_260: db "vpsubsw", 0
s_v2_261: db "vpminsw", 0
s_v2_262: db "vpor", 0
s_v2_263: db "vpaddsb", 0
s_v2_264: db "vpaddsw", 0
s_v2_265: db "vpmaxsw", 0
s_v2_266: db "vpxor", 0
s_v2_267: db "vpsllw", 0
s_v2_268: db "vpslld", 0
s_v2_269: db "vpsllq", 0
s_v2_270: db "vpmuludq", 0
s_v2_271: db "vpmaddwd", 0
s_v2_272: db "vpsadbw", 0
s_v2_273: db "vpsubb", 0
s_v2_274: db "vpsubw", 0
s_v2_275: db "vpsubd", 0
s_v2_276: db "vpsubq", 0
s_v2_277: db "vpaddb", 0
s_v2_278: db "vpaddw", 0
s_v2_279: db "vpaddd", 0
s_v2_280: db "vmovss", 0
s_v2_281: db "vmovss", 0
s_v2_282: db "vmovsldup", 0
s_v2_283: db "vmovshdup", 0
s_v2_284: db "vcvtsi2ss", 0
s_v2_285: db "vcvttss2si", 0
s_v2_286: db "vcvtss2si", 0
s_v2_287: db "vsqrtss", 0
s_v2_288: db "vrsqrtss", 0
s_v2_289: db "vrcpss", 0
s_v2_290: db "vaddss", 0
s_v2_291: db "vmulss", 0
s_v2_292: db "vcvtss2sd", 0
s_v2_293: db "vcvttps2dq", 0
s_v2_294: db "vsubss", 0
s_v2_295: db "vminss", 0
s_v2_296: db "vdivss", 0
s_v2_297: db "vmaxss", 0
s_v2_298: db "vmovdqu", 0
s_v2_299: db "vpshufhw", 0
s_v2_300: db "vmovq", 0
s_v2_301: db "vmovdqu", 0
s_v2_302: db "vcmpfalse_osss", 0
s_v2_303: db "vcvtdq2pd", 0
s_v2_304: db "vmovss", 0
s_v2_305: db "vmovss", 0
s_v2_306: db "vmovsldup", 0
s_v2_307: db "vmovshdup", 0
s_v2_308: db "vcvtsi2ss", 0
s_v2_309: db "vcvttss2si", 0
s_v2_310: db "vcvtss2si", 0
s_v2_311: db "vsqrtss", 0
s_v2_312: db "vrsqrtss", 0
s_v2_313: db "vrcpss", 0
s_v2_314: db "vaddss", 0
s_v2_315: db "vmulss", 0
s_v2_316: db "vcvtss2sd", 0
s_v2_317: db "vcvttps2dq", 0
s_v2_318: db "vsubss", 0
s_v2_319: db "vminss", 0
s_v2_320: db "vdivss", 0
s_v2_321: db "vmaxss", 0
s_v2_322: db "vmovdqu", 0
s_v2_323: db "vpshufhw", 0
s_v2_324: db "vmovdqu", 0
s_v2_325: db "vcmpfalse_osss", 0
s_v2_326: db "vcvtdq2pd", 0
s_v2_327: db "vmovsd", 0
s_v2_328: db "vmovsd", 0
s_v2_329: db "vmovddup", 0
s_v2_330: db "vcvtsi2sd", 0
s_v2_331: db "vcvttsd2si", 0
s_v2_332: db "vcvtsd2si", 0
s_v2_333: db "vsqrtsd", 0
s_v2_334: db "vaddsd", 0
s_v2_335: db "vmulsd", 0
s_v2_336: db "vcvtsd2ss", 0
s_v2_337: db "vsubsd", 0
s_v2_338: db "vminsd", 0
s_v2_339: db "vdivsd", 0
s_v2_340: db "vmaxsd", 0
s_v2_341: db "vpshuflw", 0
s_v2_342: db "vhaddps", 0
s_v2_343: db "vhsubps", 0
s_v2_344: db "kmovd", 0
s_v2_345: db "kmovd", 0
s_v2_346: db "vcmpfalse_ossd", 0
s_v2_347: db "vaddsubps", 0
s_v2_348: db "vcvtpd2dq", 0
s_v2_349: db "vlddqu", 0
s_v2_350: db "vmovsd", 0
s_v2_351: db "vmovsd", 0
s_v2_352: db "vmovddup", 0
s_v2_353: db "vcvtsi2sd", 0
s_v2_354: db "vcvttsd2si", 0
s_v2_355: db "vcvtsd2si", 0
s_v2_356: db "vsqrtsd", 0
s_v2_357: db "vaddsd", 0
s_v2_358: db "vmulsd", 0
s_v2_359: db "vcvtsd2ss", 0
s_v2_360: db "vsubsd", 0
s_v2_361: db "vminsd", 0
s_v2_362: db "vdivsd", 0
s_v2_363: db "vmaxsd", 0
s_v2_364: db "vpshuflw", 0
s_v2_365: db "vhaddps", 0
s_v2_366: db "vhsubps", 0
s_v2_367: db "vcmpfalse_ossd", 0
s_v2_368: db "vaddsubps", 0
s_v2_369: db "vcvtpd2dq", 0
s_v2_370: db "vlddqu", 0

align 8
vex2_desc:
    dq s_v2_000
    db 138, 1, 1, 3, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_001
    db 138, 3, 5, 1, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_002
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_003
    db 138, 3, 5, 1, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_004
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_005
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_006
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_007
    db 138, 3, 5, 1, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_008
    db 138, 1, 1, 3, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_009
    db 138, 3, 5, 1, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_010
    db 138, 3, 5, 1, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_011
    db 138, 1, 1, 3, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_012
    db 138, 1, 1, 3, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_013
    db 138, 1, 4, 3, 4
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_014
    db 138, 1, 3, 3, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_015
    db 138, 1, 1, 3, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_016
    db 138, 1, 1, 3, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_017
    db 138, 1, 1, 3, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_018
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_019
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_020
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_021
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_022
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_023
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_024
    db 138, 1, 1, 3, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_025
    db 138, 1, 1, 3, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_026
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_027
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_028
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_029
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_030
    db 128, 0, 0, 0, 0
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_031
    db 138, 1, 4, 3, 4
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_032
    db 138, 3, 5, 1, 4
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_033
    db 138, 1, 4, 3, 3
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_034
    db 138, 1, 3, 3, 4
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_035
    db 138, 1, 4, 3, 4
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_036
    db 138, 1, 4, 3, 4
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_037
    db 27, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_038
    db 28, 1, 1, 2, 1
    db 3, 1, 4, 8
    db 0, 0, 0
    dq s_v2_039
    db 138, 1, 2, 3, 2
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_040
    db 138, 3, 5, 1, 2
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_041
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_042
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_043
    db 138, 1, 2, 3, 2
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_044
    db 138, 3, 5, 1, 2
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_045
    db 138, 3, 5, 1, 2
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_046
    db 72, 0, 0, 0, 0
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_047
    db 72, 0, 0, 0, 0
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_048
    db 11, 1, 4, 2, 4
    db 3, 4, 0, 0
    db 0, 0, 0
    dq s_v2_049
    db 11, 1, 4, 2, 4
    db 3, 4, 0, 0
    db 0, 0, 0
    dq s_v2_050
    db 11, 1, 4, 2, 4
    db 3, 4, 0, 0
    db 0, 0, 0
    dq s_v2_051
    db 11, 1, 4, 2, 4
    db 3, 4, 0, 0
    db 0, 0, 0
    dq s_v2_052
    db 11, 1, 4, 2, 4
    db 3, 4, 0, 0
    db 0, 0, 0
    dq s_v2_053
    db 11, 1, 4, 2, 4
    db 3, 4, 0, 0
    db 0, 0, 0
    dq s_v2_054
    db 11, 1, 4, 2, 4
    db 3, 4, 0, 0
    db 0, 0, 0
    dq s_v2_055
    db 138, 1, 3, 3, 2
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_056
    db 138, 1, 2, 3, 2
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_057
    db 138, 1, 2, 3, 2
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_058
    db 138, 1, 2, 3, 2
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_059
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_060
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_061
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_062
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_063
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_064
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_065
    db 138, 1, 2, 3, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_066
    db 138, 1, 2, 3, 2
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_067
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_068
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_069
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_070
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_071
    db 128, 0, 0, 0, 0
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_072
    db 27, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_073
    db 28, 1, 2, 2, 2
    db 3, 2, 4, 8
    db 0, 0, 0
    dq s_v2_074
    db 138, 1, 1, 3, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_075
    db 138, 3, 5, 1, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_076
    db 11, 1, 1, 2, 1
    db 3, 5, 0, 0
    db 0, 0, 0
    dq s_v2_077
    db 138, 3, 5, 1, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_078
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_079
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_080
    db 11, 1, 1, 2, 1
    db 3, 5, 0, 0
    db 0, 0, 0
    dq s_v2_081
    db 138, 3, 5, 1, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_082
    db 138, 1, 1, 3, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_083
    db 138, 3, 5, 1, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_084
    db 138, 3, 5, 1, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_085
    db 138, 1, 1, 3, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_086
    db 138, 1, 1, 3, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_087
    db 138, 1, 4, 3, 4
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_088
    db 138, 1, 3, 3, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_089
    db 138, 1, 1, 3, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_090
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_091
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_092
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_093
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_094
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_095
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_096
    db 138, 1, 1, 3, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_097
    db 138, 1, 1, 3, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_098
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_099
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_100
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_101
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_102
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_103
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_104
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_105
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_106
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_107
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_108
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_109
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_110
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_111
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_112
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_113
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_114
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_115
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_116
    db 138, 1, 1, 3, 3
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_117
    db 138, 1, 1, 3, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_118
    db 155, 1, 1, 3, 1
    db 4, 8, 0, 0
    db 0, 0, 0
    dq s_v2_119
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_120
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_121
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_122
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_123
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_124
    db 138, 3, 3, 1, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_125
    db 138, 3, 5, 1, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_126
    db 138, 1, 4, 3, 4
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_127
    db 138, 3, 5, 1, 4
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_128
    db 138, 1, 4, 3, 3
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_129
    db 138, 1, 3, 3, 4
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_130
    db 138, 1, 4, 3, 4
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_131
    db 138, 1, 4, 3, 4
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_132
    db 27, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_133
    db 28, 1, 1, 2, 1
    db 3, 3, 4, 8
    db 0, 0, 0
    dq s_v2_134
    db 155, 1, 3, 3, 1
    db 4, 8, 0, 0
    db 0, 0, 0
    dq s_v2_135
    db 28, 1, 1, 2, 1
    db 3, 1, 4, 8
    db 0, 0, 0
    dq s_v2_136
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_137
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_138
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_139
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_140
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_141
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_142
    db 138, 3, 5, 1, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_143
    db 138, 1, 3, 3, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_144
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_145
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_146
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_147
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_148
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_149
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_150
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_151
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_152
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_153
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_154
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_155
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_156
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_157
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_158
    db 138, 1, 1, 3, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_159
    db 138, 3, 5, 1, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_160
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_161
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_162
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_163
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_164
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_165
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_166
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_167
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_168
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_169
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_170
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_171
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_172
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_173
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_174
    db 138, 1, 1, 3, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_175
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_176
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_177
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_178
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_179
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_180
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_181
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_182
    db 138, 1, 2, 3, 2
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_183
    db 138, 3, 5, 1, 2
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_184
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_185
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_186
    db 138, 1, 2, 3, 2
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_187
    db 138, 3, 5, 1, 2
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_188
    db 138, 3, 5, 1, 2
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_189
    db 72, 0, 0, 0, 0
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_190
    db 72, 0, 0, 0, 0
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_191
    db 11, 1, 4, 2, 4
    db 3, 4, 0, 0
    db 0, 0, 0
    dq s_v2_192
    db 11, 1, 4, 2, 4
    db 3, 4, 0, 0
    db 0, 0, 0
    dq s_v2_193
    db 11, 1, 4, 2, 4
    db 3, 4, 0, 0
    db 0, 0, 0
    dq s_v2_194
    db 11, 1, 4, 2, 4
    db 3, 4, 0, 0
    db 0, 0, 0
    dq s_v2_195
    db 11, 1, 4, 2, 4
    db 3, 4, 0, 0
    db 0, 0, 0
    dq s_v2_196
    db 11, 1, 4, 2, 4
    db 3, 4, 0, 0
    db 0, 0, 0
    dq s_v2_197
    db 11, 1, 4, 2, 4
    db 3, 4, 0, 0
    db 0, 0, 0
    dq s_v2_198
    db 138, 1, 3, 3, 2
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_199
    db 138, 1, 2, 3, 2
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_200
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_201
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_202
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_203
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_204
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_205
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_206
    db 138, 1, 1, 3, 2
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_207
    db 138, 1, 2, 3, 2
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_208
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_209
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_210
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_211
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_212
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_213
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_214
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_215
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_216
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_217
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_218
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_219
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_220
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_221
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_222
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_223
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_224
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_225
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_226
    db 138, 1, 2, 3, 2
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_227
    db 155, 1, 2, 3, 2
    db 4, 8, 0, 0
    db 0, 0, 0
    dq s_v2_228
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_229
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_230
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_231
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_232
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_233
    db 138, 3, 5, 1, 2
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_234
    db 27, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_235
    db 28, 1, 2, 2, 2
    db 3, 2, 4, 8
    db 0, 0, 0
    dq s_v2_236
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_237
    db 11, 1, 2, 2, 2
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_238
    db 11, 1, 2, 2, 2
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_239
    db 11, 1, 2, 2, 2
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_240
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_241
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_242
    db 138, 1, 3, 3, 2
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_243
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_244
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_245
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_246
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_247
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_248
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_249
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_250
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_251
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_252
    db 11, 1, 2, 2, 2
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_253
    db 11, 1, 2, 2, 2
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_254
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_255
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_256
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_257
    db 138, 1, 1, 3, 2
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_258
    db 138, 3, 5, 1, 2
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_259
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_260
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_261
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_262
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_263
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_264
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_265
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_266
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_267
    db 11, 1, 2, 2, 2
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_268
    db 11, 1, 2, 2, 2
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_269
    db 11, 1, 2, 2, 2
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_270
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_271
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_272
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_273
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_274
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_275
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_276
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_277
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_278
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_279
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_280
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_281
    db 138, 3, 5, 1, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_282
    db 138, 1, 1, 3, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_283
    db 138, 1, 1, 3, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_284
    db 11, 1, 1, 2, 1
    db 3, 3, 0, 0
    db 0, 0, 0
    dq s_v2_285
    db 138, 1, 3, 3, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_286
    db 138, 1, 3, 3, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_287
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_288
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_289
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_290
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_291
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_292
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_293
    db 138, 1, 1, 3, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_294
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_295
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_296
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_297
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_298
    db 138, 1, 1, 3, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_299
    db 155, 1, 1, 3, 1
    db 4, 8, 0, 0
    db 0, 0, 0
    dq s_v2_300
    db 138, 1, 1, 3, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_301
    db 138, 3, 5, 1, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_302
    db 27, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_303
    db 138, 1, 1, 3, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_304
    db 72, 0, 0, 0, 0
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_305
    db 72, 0, 0, 0, 0
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_306
    db 138, 1, 2, 3, 2
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_307
    db 138, 1, 2, 3, 2
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_308
    db 72, 0, 0, 0, 0
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_309
    db 72, 0, 0, 0, 0
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_310
    db 72, 0, 0, 0, 0
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_311
    db 72, 0, 0, 0, 0
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_312
    db 72, 0, 0, 0, 0
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_313
    db 72, 0, 0, 0, 0
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_314
    db 72, 0, 0, 0, 0
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_315
    db 72, 0, 0, 0, 0
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_316
    db 72, 0, 0, 0, 0
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_317
    db 138, 1, 2, 3, 2
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_318
    db 72, 0, 0, 0, 0
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_319
    db 72, 0, 0, 0, 0
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_320
    db 72, 0, 0, 0, 0
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_321
    db 72, 0, 0, 0, 0
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_322
    db 138, 1, 2, 3, 2
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_323
    db 155, 1, 2, 3, 2
    db 4, 8, 0, 0
    db 0, 0, 0
    dq s_v2_324
    db 138, 3, 5, 1, 2
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_325
    db 88, 0, 0, 0, 0
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_326
    db 138, 1, 2, 3, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_327
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_328
    db 138, 3, 5, 1, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_329
    db 138, 1, 1, 3, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_330
    db 11, 1, 1, 2, 1
    db 3, 3, 0, 0
    db 0, 0, 0
    dq s_v2_331
    db 138, 1, 3, 3, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_332
    db 138, 1, 3, 3, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_333
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_334
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_335
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_336
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_337
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_338
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_339
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_340
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_341
    db 155, 1, 1, 3, 1
    db 4, 8, 0, 0
    db 0, 0, 0
    dq s_v2_342
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_343
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_344
    db 138, 1, 4, 3, 3
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_345
    db 138, 1, 3, 3, 4
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_346
    db 27, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_347
    db 11, 1, 1, 2, 1
    db 3, 1, 0, 0
    db 0, 0, 0
    dq s_v2_348
    db 138, 1, 1, 3, 1
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_349
    db 138, 1, 1, 3, 5
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_350
    db 72, 0, 0, 0, 0
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_351
    db 72, 0, 0, 0, 0
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_352
    db 138, 1, 2, 3, 2
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_353
    db 72, 0, 0, 0, 0
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_354
    db 72, 0, 0, 0, 0
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_355
    db 72, 0, 0, 0, 0
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_356
    db 72, 0, 0, 0, 0
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_357
    db 72, 0, 0, 0, 0
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_358
    db 72, 0, 0, 0, 0
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_359
    db 72, 0, 0, 0, 0
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_360
    db 72, 0, 0, 0, 0
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_361
    db 72, 0, 0, 0, 0
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_362
    db 72, 0, 0, 0, 0
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_363
    db 72, 0, 0, 0, 0
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_364
    db 155, 1, 2, 3, 2
    db 4, 8, 0, 0
    db 0, 0, 0
    dq s_v2_365
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_366
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_367
    db 88, 0, 0, 0, 0
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_368
    db 11, 1, 2, 2, 2
    db 3, 2, 0, 0
    db 0, 0, 0
    dq s_v2_369
    db 138, 1, 1, 3, 2
    db 0, 0, 0, 0
    db 0, 0, 0
    dq s_v2_370
    db 138, 1, 2, 3, 5
    db 0, 0, 0, 0
    db 0, 0, 0

align 8
vex2_idx:
    ; pp=0 L=0
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0x0000, 0x0001, 0x0002, 0x0003, 0x0004, 0x0005, 0x0006, 0x0007, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0x0008, 0x0009, 0xFFFF, 0x000A, 0xFFFF, 0xFFFF, 0x000B, 0x000C
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0x000D, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0x000E, 0x000F, 0x0010, 0x0011, 0x0012, 0x0013, 0x0014, 0x0015, 0x0016, 0x0017, 0x0018, 0x0019, 0x001A, 0x001B, 0x001C, 0x001D
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0x001E, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0x001F, 0x0020, 0x0021, 0x0022, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0x0023, 0x0024, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0x0025, 0xFFFF, 0xFFFF, 0xFFFF, 0x0026, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    ; pp=0 L=1
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0x0027, 0x0028, 0xFFFF, 0xFFFF, 0x0029, 0x002A, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0x002B, 0x002C, 0xFFFF, 0x002D, 0xFFFF, 0xFFFF, 0x002E, 0x002F
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0x0030, 0x0031, 0xFFFF, 0xFFFF, 0x0032, 0x0033, 0x0034, 0xFFFF, 0xFFFF, 0x0035, 0x0036, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0x0037, 0x0038, 0x0039, 0x003A, 0x003B, 0x003C, 0x003D, 0x003E, 0x003F, 0x0040, 0x0041, 0x0042, 0x0043, 0x0044, 0x0045, 0x0046
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0x0047, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0x0048, 0xFFFF, 0xFFFF, 0xFFFF, 0x0049, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    ; pp=1 L=0
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0x004A, 0x004B, 0x004C, 0x004D, 0x004E, 0x004F, 0x0050, 0x0051, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0x0052, 0x0053, 0xFFFF, 0x0054, 0xFFFF, 0xFFFF, 0x0055, 0x0056
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0x0057, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0x0058, 0x0059, 0xFFFF, 0xFFFF, 0x005A, 0x005B, 0x005C, 0x005D, 0x005E, 0x005F, 0x0060, 0x0061, 0x0062, 0x0063, 0x0064, 0x0065
    dw 0x0066, 0x0067, 0x0068, 0x0069, 0x006A, 0x006B, 0x006C, 0x006D, 0x006E, 0x006F, 0x0070, 0x0071, 0x0072, 0x0073, 0x0074, 0x0075
    dw 0x0076, 0xFFFF, 0xFFFF, 0xFFFF, 0x0077, 0x0078, 0x0079, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0x007A, 0x007B, 0x007C, 0x007D
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0x007E, 0x007F, 0x0080, 0x0081, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0x0082, 0x0083, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0x0084, 0xFFFF, 0x0085, 0x0086, 0x0087, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0x0088, 0x0089, 0x008A, 0x008B, 0x008C, 0x008D, 0x008E, 0x008F, 0x0090, 0x0091, 0x0092, 0x0093, 0x0094, 0x0095, 0x0096, 0x0097
    dw 0x0098, 0x0099, 0x009A, 0x009B, 0x009C, 0x009D, 0x009E, 0x009F, 0x00A0, 0x00A1, 0x00A2, 0x00A3, 0x00A4, 0x00A5, 0x00A6, 0x00A7
    dw 0xFFFF, 0x00A8, 0x00A9, 0x00AA, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x00AF, 0x00B0, 0x00B1, 0x00B2, 0x00B3, 0x00B4, 0x00B5, 0xFFFF
    ; pp=1 L=1
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0x00B6, 0x00B7, 0xFFFF, 0xFFFF, 0x00B8, 0x00B9, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0x00BA, 0x00BB, 0xFFFF, 0x00BC, 0xFFFF, 0xFFFF, 0x00BD, 0x00BE
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0x00BF, 0x00C0, 0xFFFF, 0xFFFF, 0x00C1, 0x00C2, 0x00C3, 0xFFFF, 0xFFFF, 0x00C4, 0x00C5, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0x00C6, 0x00C7, 0xFFFF, 0xFFFF, 0x00C8, 0x00C9, 0x00CA, 0x00CB, 0x00CC, 0x00CD, 0x00CE, 0x00CF, 0x00D0, 0x00D1, 0x00D2, 0x00D3
    dw 0x00D4, 0x00D5, 0x00D6, 0x00D7, 0x00D8, 0x00D9, 0x00DA, 0x00DB, 0x00DC, 0x00DD, 0x00DE, 0x00DF, 0x00E0, 0x00E1, 0xFFFF, 0x00E2
    dw 0x00E3, 0xFFFF, 0xFFFF, 0xFFFF, 0x00E4, 0x00E5, 0x00E6, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0x00E7, 0x00E8, 0xFFFF, 0x00E9
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0x00EA, 0xFFFF, 0xFFFF, 0xFFFF, 0x00EB, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0x00EC, 0x00ED, 0x00EE, 0x00EF, 0x00F0, 0x00F1, 0xFFFF, 0x00F2, 0x00F3, 0x00F4, 0x00F5, 0x00F6, 0x00F7, 0x00F8, 0x00F9, 0x00FA
    dw 0x00FB, 0x00FC, 0x00FD, 0x00FE, 0x00FF, 0x0100, 0x0101, 0x0102, 0x0103, 0x0104, 0x0105, 0x0106, 0x0107, 0x0108, 0x0109, 0x010A
    dw 0xFFFF, 0x010B, 0x010C, 0x010D, 0x010E, 0x010F, 0x0110, 0xFFFF, 0x0111, 0x0112, 0x0113, 0x0114, 0x0115, 0x0116, 0x0117, 0xFFFF
    ; pp=2 L=0
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0x0118, 0x0119, 0x011A, 0xFFFF, 0xFFFF, 0xFFFF, 0x011B, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0x011C, 0xFFFF, 0x011D, 0x011E, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0x011F, 0x0120, 0x0121, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0x0122, 0x0123, 0x0124, 0x0125, 0x0126, 0x0127, 0x0128, 0x0129
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0x012A
    dw 0x012B, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0x012C, 0x012D
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0x012E, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0x012F, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    ; pp=2 L=1
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0x0130, 0x0131, 0x0132, 0xFFFF, 0xFFFF, 0xFFFF, 0x0133, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0x0134, 0xFFFF, 0x0135, 0x0136, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0x0137, 0x0138, 0x0139, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0x013A, 0x013B, 0x013C, 0x013D, 0x013E, 0x013F, 0x0140, 0x0141
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0x0142
    dw 0x0143, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0x0144
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0x0145, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0x0146, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    ; pp=3 L=0
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0x0147, 0x0148, 0x0149, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0x014A, 0xFFFF, 0x014B, 0x014C, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0x014D, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0x014E, 0x014F, 0x0150, 0xFFFF, 0x0151, 0x0152, 0x0153, 0x0154
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0x0155, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0x0156, 0x0157, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0x0158, 0x0159, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0x015A, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0x015B, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0x015C, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0x015D, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    ; pp=3 L=1
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0x015E, 0x015F, 0x0160, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0x0161, 0xFFFF, 0x0162, 0x0163, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0x0164, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0x0165, 0x0166, 0x0167, 0xFFFF, 0x0168, 0x0169, 0x016A, 0x016B
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0x016C, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0x016D, 0x016E, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0x016F, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0x0170, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0x0171, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
    dw 0x0172, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF
