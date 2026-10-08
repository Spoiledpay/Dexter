#Requires -Version 5.1
<#
.SYNOPSIS
  Incrementa o contador de versão do Dexter (version.bin) e gera obj/version.inc
  para o NASM. Chamado pelo build.bat (etapa [0/3]); uso manual permitido:
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\bump_version.ps1 [-NoBump]

  Formato version.bin (16 bytes, little-endian):
    off 0: magic "DXVB" (44 58 56 42)
    off 4: major u16 | off 6: minor u16
    off 8: patch/build u32 (auto-incremento a cada build)
    off 12: reservado u32 (0)

  Robustez: arquivo ausente ou corrompido (tamanho/magic inválidos) =>
  faz backup para version.bin.corrupt.<timestamp> e reinicializa em 1.2.3.
  Escrita atômica via .tmp + Move-Item. Saída: "Dexter version M.m.p".
#>
[CmdletBinding()]
param([switch]$NoBump)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$vbin = Join-Path $repo 'version.bin'
$tmp  = "$vbin.tmp"
$inc  = Join-Path $repo 'obj\version.inc'

$MAGIC = [byte[]](0x44, 0x58, 0x56, 0x42)  # "DXVB"
$major = 1; $minor = 2; $patch = 3

function Read-Version {
    if (-not (Test-Path -LiteralPath $vbin)) { return $null }
    try {
        $b = [IO.File]::ReadAllBytes($vbin)
    } catch { return $null }
    if ($b.Length -ne 16) { return $null }
    for ($i = 0; $i -lt 4; $i++) { if ($b[$i] -ne $MAGIC[$i]) { return $null } }
    return @{
        major = [BitConverter]::ToUInt16($b, 4)
        minor = [BitConverter]::ToUInt16($b, 6)
        patch = [BitConverter]::ToUInt32($b, 8)
    }
}

$cur = Read-Version
if ($null -eq $cur) {
    if (Test-Path -LiteralPath $vbin) {
        $bk = "$vbin.corrupt.$(Get-Date -Format 'yyyyMMddHHmmss')"
        try { Move-Item -LiteralPath $vbin -Destination $bk -Force } catch {}
        Write-Warning "version.bin ausente/corrompido; backup em $bk; reinicializando 1.2.3."
    }
} else {
    $major = $cur.major; $minor = $cur.minor; $patch = $cur.patch
}

if (-not $NoBump) {
    if ($patch -eq [uint32]::MaxValue) {
        # rollover seguro: minor+1, patch=0 (major preservado)
        $minor = ($minor + 1) -band 0xFFFF
        $patch = [uint32]0
    } else {
        $patch = $patch + [uint32]1
    }
}

$out = New-Object byte[] 16
[Array]::Copy($MAGIC, $out, 4)
[Array]::Copy([BitConverter]::GetBytes([uint16]$major), 0, $out, 4, 2)
[Array]::Copy([BitConverter]::GetBytes([uint16]$minor), 0, $out, 6, 2)
[Array]::Copy([BitConverter]::GetBytes([uint32]$patch), 0, $out, 8, 4)
# bytes 12..15 já zerados (reservado)
[IO.File]::WriteAllBytes($tmp, $out)
Move-Item -LiteralPath $tmp -Destination $vbin -Force

$objdir = Split-Path -Parent $inc
if (-not (Test-Path -LiteralPath $objdir)) {
    New-Item -ItemType Directory -Path $objdir -Force | Out-Null
}
$incText = @"
; AUTO-GERADO por tools\bump_version.ps1 - NAO EDITAR (build sobrescreve).
; Fonte da verdade: version.bin (magic DXVB + major/minor/patch).
%ifndef DEX_VERSION_INC
%define DEX_VERSION_INC
%define DEX_VER_MAJOR $major
%define DEX_VER_MINOR $minor
%define DEX_VER_PATCH $patch
%endif
"@
[IO.File]::WriteAllText($inc, $incText, [Text.Encoding]::ASCII)

Write-Output "Dexter version $major.$minor.$patch"
