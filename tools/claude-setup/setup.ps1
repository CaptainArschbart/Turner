<#
  Claude-Code-Setup fuer das Godot-Projekt Turner - pro Person.
  Jede Person fuehrt das einmal mit ihrem eigenen Namen aus. Nichts davon
  ueberschreibt die Dateien einer anderen Person.

  Aufruf (im Projektordner D:\games\Turner):
    powershell -ExecutionPolicy Bypass -File tools\claude-setup\setup.ps1 -Name Arschi

  Was passiert:
    1. Eigene Agenten  -> %USERPROFILE%\.claude\agents\<name>-*.md   (nur fuer dich)
    2. Eigene Regeln   -> <Projekt>\<Name>_claude.md
    3. Laden der Regeln ueber CLAUDE.local.md (persoenlich, nicht im Git)
    4. Godot-MCP mit --scope local (nur fuer dich, in deinem Benutzerprofil)
  Bereits vorhandene Dateien werden nie ueberschrieben.
#>
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [switch]$SkipMcp
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Templates   = Join-Path $PSScriptRoot 'templates'
$UserAgents  = Join-Path (Join-Path $HOME '.claude') 'agents'
$Prefix      = ($Name.ToLower() -replace '[^a-z0-9]+', '-').Trim('-')
$Utf8NoBom   = New-Object System.Text.UTF8Encoding($false)
$PersonalFileName = "$($Name)_claude.md"

if (-not (Test-Path (Join-Path $ProjectRoot 'project.godot'))) {
    Write-Warning "Keine project.godot in $ProjectRoot gefunden - stimmt der Ordner?"
}

function Write-Template([string]$Source, [string]$Target) {
    if (Test-Path $Target) {
        Write-Host "  uebersprungen (existiert schon): $Target"
        return
    }
    $text = [IO.File]::ReadAllText($Source, $Utf8NoBom)
    $text = $text.Replace('{{NAME}}', $Name).Replace('{{PREFIX}}', $Prefix)
    [IO.File]::WriteAllText($Target, $text, $Utf8NoBom)
    Write-Host "  angelegt: $Target"
}

function Add-LineIfMissing([string]$File, [string]$Line) {
    if (Test-Path $File) {
        $existing = [IO.File]::ReadAllLines($File, $Utf8NoBom)
        if ($existing -contains $Line) { return $false }
        $content = [IO.File]::ReadAllText($File, $Utf8NoBom)
        $prefixNl = if ($content.Length -gt 0 -and -not $content.EndsWith("`n")) { "`r`n" } else { '' }
        [IO.File]::AppendAllText($File, "$prefixNl$Line`r`n", $Utf8NoBom)
    } else {
        [IO.File]::WriteAllText($File, "$Line`r`n", $Utf8NoBom)
    }
    return $true
}

Write-Host "`nClaude-Setup fuer '$Name' (Agenten-Praefix: $Prefix-)" -ForegroundColor Cyan
Write-Host "Projekt: $ProjectRoot`n"

# 1. Persoenliche Agenten im Benutzerordner
Write-Host "[1/4] Agenten"
New-Item -ItemType Directory -Force -Path $UserAgents | Out-Null
Get-ChildItem (Join-Path $Templates 'agents') -Filter *.md | ForEach-Object {
    Write-Template $_.FullName (Join-Path $UserAgents "$Prefix-$($_.Name)")
}

# 2. Persoenliche Regeldatei im Projekt
Write-Host "[2/4] Persoenliche Regeln"
Write-Template (Join-Path $Templates 'personal_claude.md') (Join-Path $ProjectRoot $PersonalFileName)

# 3. CLAUDE.local.md laedt die persoenliche Datei
Write-Host "[3/4] CLAUDE.local.md"
$localFile = Join-Path $ProjectRoot 'CLAUDE.local.md'
if (Test-Path $localFile) {
    $others = [IO.File]::ReadAllLines($localFile, $Utf8NoBom) |
        Where-Object { $_ -match '^@.+_claude\.md$' -and $_ -ne "@$PersonalFileName" }
    if ($others) {
        Write-Warning ("CLAUDE.local.md enthaelt schon Eintraege anderer Personen: $($others -join ', ')." +
            " Arbeitet ihr im selben Ordner statt mit eigenen Kopien? Dann laden beide alle Dateien.")
    }
}
if (Add-LineIfMissing $localFile "@$PersonalFileName") {
    Write-Host "  @$PersonalFileName eingetragen"
} else {
    Write-Host "  schon eingetragen"
}

if (Test-Path (Join-Path $ProjectRoot '.git')) {
    $gitignore = Join-Path $ProjectRoot '.gitignore'
    foreach ($entry in @('CLAUDE.local.md', '*_claude.md')) {
        if (Add-LineIfMissing $gitignore $entry) { Write-Host "  .gitignore: $entry ergaenzt" }
    }
}

# 4. Godot-MCP nur fuer diese Person
Write-Host "[4/4] Godot-MCP"
if ($SkipMcp) {
    Write-Host "  uebersprungen (-SkipMcp)"
} elseif (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Warning "Befehl 'claude' nicht gefunden - MCP spaeter manuell hinzufuegen (siehe README.md)."
} else {
    Push-Location $ProjectRoot
    # Windows PowerShell 5.1 wertet stderr von claude.exe sonst als Abbruchfehler.
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & cmd /c "claude mcp get godot >nul 2>&1"
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  'godot' ist schon eingerichtet"
        } else {
            & claude mcp add --scope local godot -- cmd /c npx -y '@coding-solo/godot-mcp'
            if ($LASTEXITCODE -eq 0) { Write-Host "  'godot' hinzugefuegt (nur fuer dich)" }
            else { Write-Warning "claude mcp add ist fehlgeschlagen (siehe Ausgabe oben)." }
        }
    } finally {
        $ErrorActionPreference = $previousEap
        Pop-Location
    }
    if (-not $env:GODOT_PATH) {
        Write-Host "  Tipp: Umgebungsvariable GODOT_PATH auf deine Godot-.exe setzen, falls Godot nicht gefunden wird."
    }
}

Write-Host "`nFertig. Claude Code im Projektordner neu starten." -ForegroundColor Green
Write-Host "Deine Agenten: $Prefix-gameplay, $Prefix-ui, $Prefix-tester, $Prefix-reviewer (pruefen: Claude fragen 'Welche Subagenten hast du?')"
