<p align="center">
  <img src="Dexter_logo_US.png" alt="Dexter" width="420">
</p>

<h1 align="center">Dexter</h1>

<p align="center">原生 PE 反汇编 / 重汇编工具 — x86-64 与 x86 — NASM / Windows</p>

<p align="center">
  <a href="README.md">Português</a> ·
  <a href="README.en.md">English</a> ·
  <a href="README.zh-CN.md"><strong>中文</strong></a>
</p>

<p align="center">
  <a href="https://github.com/Spoiledpay/Dexter/actions/workflows/ci.yml"><img src="https://github.com/Spoiledpay/Dexter/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT"></a>
  <a href="https://github.com/Spoiledpay/Dexter/releases/latest"><img src="https://img.shields.io/github/v/release/Spoiledpay/Dexter?display_name=tag" alt="Release"></a>
</p>

> **支持本项目。** Dexter 由独立开发者维护，永久免费且开源。如果它对你的
> 工作有帮助，欢迎通过
> [GitHub Sponsors](https://github.com/sponsors/Spoiledpay) 支持持续开发。
> 任何贡献都非常感谢，也能帮助项目保留测试、修复和新功能所需的时间。
> 感谢你的参与。

Dexter 是一个完全使用 NASM x86-64 编写、无 CRT 依赖的真实工具：读取 PE
（PE32/PE32+），生成可重汇编的 `.asm`，并重建 `.exe`。`-m bin` 可做到
**字节完全一致的往返重建**（hello 2560 B、var64 91872 B、gcc 2 MB、
ld.lld 68 MB），并验证运行行为一致。

项目：[github.com/Spoiledpay/Dexter](https://github.com/Spoiledpay/Dexter)
· 下载：[Releases](https://github.com/Spoiledpay/Dexter/releases/latest)

## 当前功能

### 反汇编与重汇编

- **PE32+（x64）与 PE32（x86）**：校验 DOS/NT 头、节表、导入表、导出表、
  重定位、资源和展开信息（`.pdata`/`.xdata`）。
- **真实 x86-64/x86 解码器**：legacy 前缀、REX、ModRM/SIB、RIP 相对寻址、
  1/2/`0F38`/`0F3A` 表、指令组、x87、VEX/EVEX 和 3DNow!（长度逐字节精确；
  VEX/EVEX/x87 在 `-native` 中仍回退为 `db`）。
- **`-m win64`**：生成 `.asm`，用 `nasm -f win64` 汇编，再用 `link.exe`
  链接；DataDirectory 按节/偏移重新映射。
- **`-m bin`**：生成自包含的 `.asm`，用 `nasm -f bin` 汇编；这是处理真实 PE
  （包括 gcc/ld.lld）的**字节级忠实**路径。
- **`-native`**：尽可能输出真实助记符/标签（`mov`、`lea`、`[rel label]`、
  `call|jmp [rel __imp_X]`），失败时回退为逐字节 `db`；支持符号化导入表、
  符号化 `UNWIND_INFO`、可重定位的 RIP 相对 `disp32`、精确 REX、`.bss`
  nobits，以及 `vsize > raw` 的 `.data` 尾部。
- **`-ast-dump`**：对生成的 `.asm` 做反向解析并输出
  `AST funcs=F blocks=B instrs=I succs=S db=D equ=E dir=R`。

### 分析（只读，不写 `.asm`）

- `-overview` / `-json`：镜像基址、入口点、节、导入/导出/重定位。
- `-func <VA>`：函数边界及调用/跳转。
- `-xrefs <VA>`：代码与数据引用（如实标记 `truncated`）。
- `-trace <VA>` / `-depth <N>`：调用链 DFS。
- `-rsrc`：三层资源清单（类型/名称/语言）。
- `-snapshot <json>` / `-compare <b.exe>`：FNV-1a 指纹与差异。
- `--doctor`：nasm/link/kernel32 + 版本。

### 健壮性

- 不支持的指令如实回退为 `db`，绝不返回假错误。
- 所有 PE 字段都对照文件大小做边界校验。
- `tests/fuzz_pe.py`：确定性变异（MZ、`e_lfanew`、节表、导入表、
  `.pdata`/`.xdata`、截断）；变异样本永不执行。

## 快速开始

```bat
build.bat

:: win64 往返（nasm + link）
out\dexter.exe tests\hello.exe -o tests\out\hello.asm -r -O tests\out\hello_rt.exe
tests\out\hello_rt.exe            &:: 输出 "hi"

:: 字节完全一致的往返（nasm -f bin）
out\dexter.exe tests\var64.exe -o tests\out\var64_bin.asm -m bin -r -O tests\out\var64_bin.exe
fc /b tests\var64.exe tests\out\var64_bin.exe

:: 完整测试套件
tests\run_tests.bat               &:: 426/426
```

### 分析示例

```bat
out\dexter.exe app.exe -overview
out\dexter.exe app.exe -overview -json
out\dexter.exe app.exe -func 0x140001000
out\dexter.exe app.exe -xrefs 0x140001000
out\dexter.exe app.exe -trace 0x140001000 -depth 8
out\dexter.exe app.exe -rsrc
out\dexter.exe app.exe -snapshot app.json
out\dexter.exe app.exe -compare other.exe
out\dexter.exe app.exe --doctor
```

### 输出与控制

| 参数 | 作用 |
|---|---|
| `-o <file.asm>` | 生成 NASM 源文件（默认 `<input>.asm`） |
| `-O <file.exe>` | 重汇编后的 `.exe`（隐含 `-r`） |
| `-m win64\|bin` | 重建路径（`win64` = nasm+link；`bin` = 字节忠实） |
| `-r` | 生成 `.asm` 后立即重汇编 |
| `-L <linker>` / `-N <nasm>` | 显式指定 linker/nasm 路径 |
| `-s <section>` | 只反汇编指定节，其余作为数据处理 |
| `-start <RVA>` / `-end <RVA>` | 代码范围（十六进制） |
| `-hex` | 输出 `; @0xVA` / `; mne` 注释 |
| `-nop-pad` | 将 `0x90`/`0xCC` 输出为真实 `nop`/`int3` |
| `-no-imports` / `-no-relocs` | 不处理导入/重定位（省略 `.reloc`） |
| `-strings` | ASCII 串输出为 `db "..."`, 0；配合 `-native` 输出 `dq label_` |
| `-native` / `-emit db\|native` | 启用原生发射器（`-native` 为别名） |
| `-ast-dump` | 输出生成 `.asm` 的 AST 摘要 |
| `-v` / `-vv` / `-q` | 详细 1、详细 2、静默 |
| `-ver` / `-h` / `--help` | 版本 / 帮助 |

返回码：`0` 成功，`1` 用法错误，`2` I/O，`3` PE 无效，
`4` 不支持的指令或 GCC C++ EH 的 `-native -r` 拒绝，`5` 重建失败。
完整说明：[docs/CLI.md](docs/CLI.md)（葡萄牙语）。

## 测试

- **快速套件**（`tests\run_tests.bat`）：1.2.435 下 **464/464 通过**。
- **慢速套件**（`tests\run_slow.bat`）：**7/7 通过** —— ld.lld 68 MB
  字节一致 + gcc 2 MB 字节一致，并能编译 `hello.c`。
- **模糊测试**（`tests/fuzz_pe.py`）：损坏的 PE 不得崩溃/挂起；
  允许返回 `{0,1,2,3,5}`。
- **CI**：[`.github/workflows/ci.yml`](.github/workflows/ci.yml) 在
  `windows-latest` 上使用 MSVC + NASM 执行构建和快速套件。大型夹具
  `tests/gcc.exe`、`tests/ld.lld.exe` 未纳入版本库，CI 中跳过
  （`DEXTER_SKIP_LARGE=1`）；完整套件在本地运行。

## 当前版本

**Dexter 1.2.435**（`-ver`）。每次运行 `build.bat` 都会通过
`version.bin` + `tools\bump_version.ps1` 递增补丁号。

## 已知限制（如实说明）

- 带 **GCC/MinGW C++ EH**（`__gxx_personality_*` /
  `__gcc_personality_*`）的 PE 使用 pcrel 表，`link.exe` 不会重定位它们；
  链接模式下的 `-native -r` 会**以返回码 4 拒绝**并建议使用 `-m bin`
  （ADR-0004）。可靠路径是 `-m bin -native -r`。
- x64 的 SIB-abs 符号索引仅在 `ImageBase < 2 GiB` 时可行
  （disp32 为符号扩展）；超出后保持数值形式且字节一致。
- VEX3/EVEX 已按字节精确解码，但原生发射器仍使用 `db`
  （VEX2 与 x87 已输出原生指令）。
- `-no-imports` 会关闭 GCC personality 检测（已记录的限制）。
- R-6.6（可优化 IR + 自有后端，不依赖 nasm）仍在未来计划中。

## 环境要求

- Windows x64。
- `nasm.exe`（`C:\Nasm\` 或 `PATH`）和 `link.exe`（MSVC）。
- Windows SDK 的 `kernel32.lib`（`build.bat` 会自动查找；可用
  `SDKLIBDIR` 覆盖）。

## 构建

```bat
build.bat
```

输出：`out\dexter.exe`。`clean.bat` 删除 `out\`/`obj\`。

## 目录结构

```text
build.bat  clean.bat  version.bin
include/         win64.inc dexter.inc pe.inc errors.inc macros.inc
src/cli io pe disasm gen util   每个 NASM 模块单一职责
src/front/       lexer + parser + AST
src/back/        lift (DexIR) + codegen
docs/            CLI ARQUITETURA ROADMAP REVISAO CHANGELOG PE_NOTES ADRs
tests/           corpus + fixtures + run_tests.bat + run_slow.bat + fuzz
out/ obj/        构建产物（已忽略）
```

## 贡献

欢迎贡献：请提交包含示例 PE（不含敏感数据）的 issue，描述预期行为，
并尽可能附上生成的 `.asm`/日志。修改代码前请运行 `build.bat` 和
`tests\run_tests.bat`。

## 许可证

基于 **MIT 许可证**发布。参见 [LICENSE](LICENSE)。

Copyright (c) 2026 Labsobjects.org | Developer.
