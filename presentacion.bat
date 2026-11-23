@echo off
chcp 65001 >nul
setlocal
set "PRESENTACION_BAT=%~f0"
set "PRESENTACION_DIR=%~dp0"

where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo [ERROR] No se encontro powershell.exe en el sistema.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$raw = [System.IO.File]::ReadAllText($env:PRESENTACION_BAT, [System.Text.Encoding]::UTF8); $marker = '#__PS_' + 'START__'; $parts = $raw -split ('(?m)^' + [regex]::Escape($marker) + '\r?$'), 2; if ($parts.Length -lt 2) { throw 'No se encontro el bloque de ejecucion.' }; & ([ScriptBlock]::Create($parts[1]))"
set "EXIT_CODE=%ERRORLEVEL%"
endlocal & exit /b %EXIT_CODE%
#__PS_START__
$ErrorActionPreference = "Continue"
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
[System.Net.ServicePointManager]::DefaultConnectionLimit = 32
try { $Host.UI.RawUI.WindowTitle = "Billetera Digital Distribuida · Presentacion" } catch { }

$RepoDir = $env:PRESENTACION_DIR.TrimEnd('\', '/')
Set-Location -LiteralPath $RepoDir

$Gateway = if ($env:GATEWAY) { $env:GATEWAY } else { "http://localhost:8080" }
$Eureka  = if ($env:EUREKA)  { $env:EUREKA }  else { "http://localhost:8761" }
$Origen  = "0991112233"
$Destino = "0984445566"

$script:Inv = [System.Globalization.CultureInfo]::InvariantCulture
$script:FirstFrame = $true
$script:ForceClear = $false
$script:FrameTop = 0
$script:LastScreenId = ""
$script:MaxDrawnRow = 0
$script:DockRow = 4
$script:WinW = 80
$script:WinH = 25
$script:UiW = 78
$script:InnerW = 74
$script:PadL = 1
$script:PadT = 0
$script:Margin = " "

$script:LastSnap = $null
$script:LastDockSig = ""
$script:DockProc = $null
$script:LastDockPoll = [DateTime]::MinValue

$script:CachePsLines = $null
$script:CacheEureka = $null
$script:CacheBalanceo = $null
$script:CacheTxOk = $null
$script:CacheTxErr = $null
$script:CacheLecturas07 = $null
$script:CacheCritico = $null
$script:CacheLecturas11 = $null
$script:CacheEstado12 = $null
$script:CacheEstado14 = $null
$script:LastTxNodo = "PRIMARY (recovery=false)"
$script:LastTxCodigo = "TX-2026-0001"
$script:LastBurstLines = @()
$script:StopRepAt = $null
$script:StartRepAt = $null

function Invoke-Cleanup {
    if ($script:DockProc) {
        try { if (-not $script:DockProc.HasExited) { $script:DockProc.Kill() }; $script:DockProc.Dispose() } catch { }
        $script:DockProc = $null
    }
    if (-not [Console]::IsOutputRedirected) {
        try { [Console]::CursorVisible = $true } catch { }
    }
}

function Update-UiMetrics {
    $w = if ($env:DEMO_COLS -match '^\d+$') { [int]$env:DEMO_COLS } else { 80 }
    $h = if ($env:DEMO_LINES -match '^\d+$') { [int]$env:DEMO_LINES } else { 25 }
    if (-not [Console]::IsOutputRedirected) {
        try {
            $w = [Console]::WindowWidth
            $h = [Console]::WindowHeight
        } catch { }
    }
    $newUiW = [Math]::Min(100, [Math]::Max(64, $w - 2))
    $newPadL = [Math]::Max(0, [int][Math]::Floor(($w - $newUiW) / 2))
    $newPadT = if (-not [Console]::IsOutputRedirected -and $h -ge 28) {
        [Math]::Min(3, [int][Math]::Floor(($h - 24) / 3))
    } else { 0 }

    if ($newUiW -ne $script:UiW -or $newPadL -ne $script:PadL -or $newPadT -ne $script:PadT) {
        $script:ForceClear = $true
    }
    $script:WinW   = $w
    $script:WinH   = $h
    $script:UiW    = $newUiW
    $script:InnerW = $newUiW - 4
    $script:PadL   = $newPadL
    $script:PadT   = $newPadT
    $script:Margin = " " * $newPadL
}

function Write-BlankLine {
    if ([Console]::IsOutputRedirected) { Write-Host ""; return }
    Write-Host (" " * [Math]::Max(1, $script:WinW - 1))
}

function Write-CleanLine([string]$Text = "", [string]$Color = "White") {
    $line = $script:Margin + $Text
    if ([Console]::IsOutputRedirected) { Write-Host $line -ForegroundColor $Color; return }
    $pad = [Math]::Max(0, ($script:WinW - 1) - $line.Length)
    Write-Host ($line + (" " * $pad)) -ForegroundColor $Color
}

function Complete-Row {
    if (-not [Console]::IsOutputRedirected) {
        try {
            $rem = ($script:WinW - 1) - [Console]::CursorLeft
            if ($rem -gt 0) { Write-Host (" " * $rem) -NoNewline }
        } catch { }
    }
    Write-Host ""
}

function Clear-TailFrom([int]$FromRow) {
    if ([Console]::IsOutputRedirected) { return }
    try {
        $bufH = [Console]::BufferHeight
        $limit = [Math]::Min($script:MaxDrawnRow, $bufH - 1)
        if ($FromRow -le $limit) {
            $blank = " " * [Math]::Max(1, $script:WinW - 1)
            for ($row = $FromRow; $row -le $limit; $row++) {
                [Console]::SetCursorPosition(0, $row)
                [Console]::Write($blank)
            }
            [Console]::SetCursorPosition(0, $FromRow)
        }
    } catch { }
}

function Begin-Frame([bool]$HardClear = $false) {
    Update-UiMetrics
    if ([Console]::IsOutputRedirected) { return }
    try {
        [Console]::CursorVisible = $false
        if ([Console]::WindowTop -ne $script:FrameTop) { $script:ForceClear = $true }
    } catch { }
    if ($script:FirstFrame -or $HardClear -or $script:ForceClear) {
        try {
            [Console]::Clear()
            $script:MaxDrawnRow = 0
            $script:FirstFrame = $false
            $script:ForceClear = $false
            $script:FrameTop = [Console]::WindowTop
        } catch { }
    } else {
        try { [Console]::SetCursorPosition(0, $script:FrameTop) } catch { }
    }
    for ($i = 0; $i -lt $script:PadT; $i++) {
        Write-BlankLine
    }
}

function End-Frame {
    if ([Console]::IsOutputRedirected) { return }
    try {
        $cur = [Console]::CursorTop
        Clear-TailFrom $cur
        $script:MaxDrawnRow = $cur
    } catch { }
}

function Format-Fixed([string]$Text, [int]$Width) {
    if ($null -eq $Text) { $Text = "" }
    if ($Width -le 0) { return "" }
    if ($Text.Length -gt $Width) {
        if ($Width -le 3) { return $Text.Substring(0, $Width) }
        return $Text.Substring(0, $Width - 3) + "..."
    }
    return $Text.PadRight($Width)
}

function Format-Center([string]$Text, [int]$Width) {
    if ($null -eq $Text) { $Text = "" }
    if ($Text.Length -ge $Width) { return (Format-Fixed $Text $Width) }
    $left = [int][Math]::Floor(($Width - $Text.Length) / 2)
    return ((" " * $left) + $Text).PadRight($Width)
}

function Format-Money($Val) {
    if ($null -eq $Val -or "$Val" -eq "") { return "-" }
    try { return [string]::Format($script:Inv, "{0:F2}", [decimal]$Val) } catch { return "$Val" }
}

function Get-ProgressBar([int]$SlideNum, [int]$TotalSlides = 15, [int]$Width = 10) {
    $filled = [int][Math]::Round(($SlideNum / $TotalSlides) * $Width)
    $filled = [Math]::Max(0, [Math]::Min($Width, $filled))
    return ("[" + ("█" * $filled) + ("░" * ($Width - $filled)) + "]")
}

function Write-BoxTop([string]$Title, [string]$Color = "DarkGray") {
    $t = " " + $Title + " "
    $maxT = [Math]::Max(4, $script:UiW - 6)
    if ($t.Length -gt $maxT) { $t = $t.Substring(0, $maxT) }
    $fill = [Math]::Max(2, ($script:UiW - 3) - $t.Length)
    Write-CleanLine ("┌─" + $t + ("─" * $fill) + "┐") $Color
}

function Write-BoxLine([string]$Text, [string]$TextColor = "White", [string]$BorderColor = "DarkGray") {
    Write-Host ($script:Margin + "│ ") -ForegroundColor $BorderColor -NoNewline
    Write-Host (Format-Fixed $Text $script:InnerW) -ForegroundColor $TextColor -NoNewline
    Write-Host " │" -ForegroundColor $BorderColor -NoNewline
    Complete-Row
}

function Write-BoxBottom([string]$Color = "DarkGray") {
    Write-CleanLine ("└" + ("─" * ($script:UiW - 2)) + "┘") $Color
}

function Write-Divider {
    Write-CleanLine ("─" * $script:UiW) "DarkGray"
}

function Parse-DockerPsLines([string[]]$Lines) {
    $map = @{}
    $names = @("api-gateway", "eureka-server", "ms-cuentas-1", "ms-cuentas-2", "ms-transacciones", "primary", "replica1", "replica2")
    foreach ($n in $names) {
        $map[$n] = @{ Sym = "?"; Color = "DarkGray"; State = "desconocido" }
    }
    $dockerOk = $false; $healthy = 0; $running = 0
    $sigParts = New-Object System.Collections.Generic.List[string]
    if ($Lines) {
        $dockerOk = $true
        foreach ($line in $Lines) {
            if (-not $line -or ($line -notmatch '\|')) { continue }
            $p = $line -split '\|', 3
            $svc = $p[0].Trim(); $st = $p[1].Trim(); $status = $p[2].Trim()
            if (-not $map.ContainsKey($svc)) { continue }
            $sigParts.Add("$svc=$st=$status")
            if ($st -eq "running") {
                $running++
                if ($status -match 'unhealthy') {
                    $map[$svc] = @{ Sym = "!"; Color = "Red"; State = "unhealthy" }
                } elseif ($status -match 'starting') {
                    $map[$svc] = @{ Sym = "~"; Color = "Yellow"; State = "starting" }
                } else {
                    $healthy++
                    $map[$svc] = @{ Sym = "●"; Color = "Green"; State = "healthy" }
                }
            } else {
                $map[$svc] = @{ Sym = "✗"; Color = "Red"; State = "detenido" }
            }
        }
    }
    $sig = "$dockerOk|$healthy|$running|" + (($sigParts | Sort-Object) -join ";")
    return @{ Map = $map; DockerOk = $dockerOk; Healthy = $healthy; Running = $running; Sig = $sig }
}

function Get-ContainerMapSync {
    try {
        $out = & docker compose ps -a --format "{{.Service}}|{{.State}}|{{.Status}}" 2>$null
        if ($LASTEXITCODE -eq 0) {
            $snap = Parse-DockerPsLines @($out)
            $script:LastSnap = $snap
            $script:LastDockPoll = [DateTime]::UtcNow
            return $snap
        }
    } catch { }
    $snap = Parse-DockerPsLines $null
    $script:LastSnap = $snap
    $script:LastDockPoll = [DateTime]::UtcNow
    return $snap
}

function Start-BackgroundDocker([string]$SubArgs) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "docker"
    $psi.Arguments = "compose $SubArgs"
    $psi.WorkingDirectory = $RepoDir
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()
    return $proc
}

function Poll-AsyncDock {
    if ($script:DockProc) {
        if ($script:DockProc.HasExited) {
            $stdout = ""
            try { $stdout = $script:DockProc.StandardOutput.ReadToEnd() } catch { }
            $rc = $script:DockProc.ExitCode
            try { $script:DockProc.Dispose() } catch { }
            $script:DockProc = $null
            $script:LastDockPoll = [DateTime]::UtcNow
            $snap = if ($rc -eq 0) { Parse-DockerPsLines ($stdout -split "`r?`n") } else { Parse-DockerPsLines $null }
            $changed = ($snap.Sig -ne $script:LastDockSig)
            $script:LastSnap = $snap
            if ($changed) { Update-DockInPlace $snap }
        }
        return
    }
    if (([DateTime]::UtcNow - $script:LastDockPoll).TotalMilliseconds -ge 2200) {
        $script:LastDockPoll = [DateTime]::UtcNow
        try { $script:DockProc = Start-BackgroundDocker 'ps -a --format "{{.Service}}|{{.State}}|{{.Status}}"' } catch { }
    }
}

function Write-Badge([string]$Label, $Info) {
    Write-Host ("[{0} {1}]" -f $Info.Sym, $Label) -ForegroundColor $Info.Color -NoNewline
}

function Render-ClusterDock([bool]$SaveRow = $true, $Snap = $null) {
    if ($SaveRow -and -not [Console]::IsOutputRedirected) {
        try { $script:DockRow = [Console]::CursorTop } catch { }
    }
    if (-not $Snap) {
        if ($script:LastSnap) { $Snap = $script:LastSnap }
        else { $Snap = Get-ContainerMapSync }
    }
    $script:LastDockSig = $Snap.Sig
    $m = $Snap.Map
    $bCol = "DarkCyan"
    if (-not $Snap.DockerOk) {
        $title = "MONITOR EN VIVO · DOCKER DESCONECTADO"; $tCol = "Red"
    } elseif ($Snap.Healthy -eq 8) {
        $title = "MONITOR EN VIVO · 8/8 EN LINEA"; $tCol = "Green"
    } else {
        $title = ("MONITOR EN VIVO · {0}/8 HEALTHY · {1}/8 ACTIVOS" -f $Snap.Healthy, $Snap.Running); $tCol = "Yellow"
    }
    $t = " " + $title + " "
    $fill = [Math]::Max(2, ($script:UiW - 3) - $t.Length)
    Write-Host ($script:Margin + "┌─") -ForegroundColor $bCol -NoNewline
    Write-Host $t -ForegroundColor $tCol -NoNewline
    Write-Host (("─" * $fill) + "┐") -ForegroundColor $bCol -NoNewline
    Complete-Row

    if ($script:InnerW -ge 74) {
        # Fila 1: 71 chars fijos + gap central + relleno = InnerW exacto
        $mid = [Math]::Max(2, [int][Math]::Floor(($script:InnerW - 71) / 2))
        $rem1 = [Math]::Max(0, $script:InnerW - (71 + $mid))
        Write-Host ($script:Margin + "│ ") -ForegroundColor $bCol -NoNewline
        Write-Host "RED  " -ForegroundColor DarkGray -NoNewline
        Write-Badge "gateway :8080" $m["api-gateway"]
        Write-Host " " -NoNewline
        Write-Badge "eureka :8761" $m["eureka-server"]
        Write-Host (" " * $mid) -NoNewline
        Write-Host "BD " -ForegroundColor DarkGray -NoNewline
        Write-Badge "primary" $m["primary"]
        Write-Host " " -NoNewline
        Write-Badge "rep1" $m["replica1"]
        Write-Host " " -NoNewline
        Write-Badge "rep2" $m["replica2"]
        Write-Host ((" " * $rem1) + " │") -ForegroundColor $bCol -NoNewline
        Complete-Row

        # Fila 2: 68 chars base
        $rem2 = [Math]::Max(0, $script:InnerW - 68)
        Write-Host ($script:Margin + "│ ") -ForegroundColor $bCol -NoNewline
        Write-Host "APPS " -ForegroundColor DarkGray -NoNewline
        Write-Badge "cuentas-1 :8081" $m["ms-cuentas-1"]
        Write-Host " " -NoNewline
        Write-Badge "cuentas-2 :8082" $m["ms-cuentas-2"]
        Write-Host " " -NoNewline
        Write-Badge "transacciones :8083" $m["ms-transacciones"]
        Write-Host ((" " * $rem2) + " │") -ForegroundColor $bCol -NoNewline
        Complete-Row
    } else {
        # Modo compacto para ventanas < 78 columnas
        $rem1 = [Math]::Max(0, $script:InnerW - 57)
        Write-Host ($script:Margin + "│ ") -ForegroundColor $bCol -NoNewline
        Write-Host "RED  " -ForegroundColor DarkGray -NoNewline
        Write-Badge "gw" $m["api-gateway"]
        Write-Host " " -NoNewline
        Write-Badge "eureka" $m["eureka-server"]
        Write-Host "   BD " -ForegroundColor DarkGray -NoNewline
        Write-Badge "primary" $m["primary"]
        Write-Host " " -NoNewline
        Write-Badge "rep1" $m["replica1"]
        Write-Host " " -NoNewline
        Write-Badge "rep2" $m["replica2"]
        Write-Host ((" " * $rem1) + " │") -ForegroundColor $bCol -NoNewline
        Complete-Row

        $rem2 = [Math]::Max(0, $script:InnerW - 50)
        Write-Host ($script:Margin + "│ ") -ForegroundColor $bCol -NoNewline
        Write-Host "APPS " -ForegroundColor DarkGray -NoNewline
        Write-Badge "cuentas-1" $m["ms-cuentas-1"]
        Write-Host " " -NoNewline
        Write-Badge "cuentas-2" $m["ms-cuentas-2"]
        Write-Host " " -NoNewline
        Write-Badge "transacciones" $m["ms-transacciones"]
        Write-Host ((" " * $rem2) + " │") -ForegroundColor $bCol -NoNewline
        Complete-Row
    }

    Write-CleanLine ("└" + ("─" * ($script:UiW - 2)) + "┘") $bCol
}

function Update-DockInPlace($Snap = $null) {
    if ([Console]::IsOutputRedirected) { return }
    try {
        $savedLeft = [Console]::CursorLeft
        $savedTop  = [Console]::CursorTop
        [Console]::SetCursorPosition(0, $script:DockRow)
        Render-ClusterDock $false $Snap
        [Console]::SetCursorPosition($savedLeft, $savedTop)
    } catch { }
}

function Write-SlideChrome([int]$SlideNum, [int]$ActiveSection, [string]$SlideTitle, [bool]$Cached = $false, [bool]$IsLive = $false) {
    Begin-Frame
    $compact = ($script:InnerW -lt 70)
    $tabs = if ($compact) {
        @(@{Id=1;L="[1]"},@{Id=2;L="[2]"},@{Id=3;L="[3]"},@{Id=4;L="[4]"},@{Id=5;L="[5]"},@{Id=6;L="[6]"})
    } else {
        @(@{Id=1;L="[1:Arq]"},@{Id=2;L="[2:Eur]"},@{Id=3;L="[3:P2P]"},@{Id=4;L="[4:Rep]"},@{Id=5;L="[5:Fal]"},@{Id=6;L="[6:Fin]"})
    }
    $barLen = if ($script:InnerW -ge 88) { 14 } else { 10 }
    $right = ("{0:00}/15 {1}" -f $SlideNum, (Get-ProgressBar $SlideNum 15 $barLen))
    $tabsLen = (($tabs | ForEach-Object { $_.L.Length }) | Measure-Object -Sum).Sum + ($tabs.Count - 1)
    $gap = [Math]::Max(1, $script:InnerW - $tabsLen - $right.Length)

    Write-CleanLine ("╔" + ("═" * ($script:UiW - 2)) + "╗") "DarkCyan"
    Write-Host ($script:Margin + "║ ") -ForegroundColor DarkCyan -NoNewline
    for ($i = 0; $i -lt $tabs.Count; $i++) {
        $tb = $tabs[$i]
        $col = if ($tb.Id -eq $ActiveSection) { "Yellow" } else { "DarkGray" }
        Write-Host $tb.L -ForegroundColor $col -NoNewline
        if ($i -lt $tabs.Count - 1) { Write-Host " " -NoNewline }
    }
    Write-Host (" " * $gap) -NoNewline
    Write-Host $right -ForegroundColor Cyan -NoNewline
    Write-Host " ║" -ForegroundColor DarkCyan -NoNewline
    Complete-Row

    $leftTitle = "► " + $SlideTitle
    $badge = ""
    $badgeCol = "DarkGray"
    if ($Cached) {
        $badge = if ($script:InnerW -ge 70) { "[CACHE · R]" } else { "[CACHE]" }
        $badgeCol = "Yellow"
    } elseif ($IsLive) {
        $badge = if ($script:InnerW -ge 70) { "[EN VIVO]" } else { "[VIVO]" }
        $badgeCol = "Green"
    }

    Write-Host ($script:Margin + "║ ") -ForegroundColor DarkCyan -NoNewline
    if ($badge -and ($leftTitle.Length + 1 + $badge.Length -le $script:InnerW)) {
        $gap2 = $script:InnerW - $leftTitle.Length - $badge.Length
        Write-Host $leftTitle -ForegroundColor White -NoNewline
        Write-Host (" " * $gap2) -NoNewline
        Write-Host $badge -ForegroundColor $badgeCol -NoNewline
    } else {
        Write-Host (Format-Fixed $leftTitle $script:InnerW) -ForegroundColor White -NoNewline
    }
    Write-Host " ║" -ForegroundColor DarkCyan -NoNewline
    Complete-Row
    Write-CleanLine ("╚" + ("═" * ($script:UiW - 2)) + "╝") "DarkCyan"

    Render-ClusterDock $true
    $sid = "S$SlideNum"
    if (-not [Console]::IsOutputRedirected -and $script:LastScreenId -ne $sid) {
        try { Clear-TailFrom ([Console]::CursorTop) } catch { }
    }
    $script:LastScreenId = $sid
}

function Show-LivePending([string]$Message) {
    if ([Console]::IsOutputRedirected) { return -1 }
    try {
        $row = [Console]::CursorTop
        Write-CleanLine ("  [~] " + $Message) "Yellow"
        Clear-TailFrom ([Console]::CursorTop)
        return $row
    } catch { return -1 }
}

function Restore-LivePending([int]$Row) {
    if ($Row -lt 0 -or [Console]::IsOutputRedirected) { return }
    try { [Console]::SetCursorPosition(0, $Row) } catch { }
}

function Open-EurekaBrowser {
    try { Start-Process "$Eureka" | Out-Null } catch { }
}

function Parse-ConsoleKey($k) {
    switch ($k.Key) {
        ([ConsoleKey]::LeftArrow)  { return "PREV" }
        ([ConsoleKey]::PageUp)     { return "PREV" }
        ([ConsoleKey]::Backspace)  { return "PREV" }
        ([ConsoleKey]::RightArrow) { return "NEXT" }
        ([ConsoleKey]::PageDown)   { return "NEXT" }
        ([ConsoleKey]::Spacebar)   { return "NEXT" }
        ([ConsoleKey]::Enter)      { return "NEXT" }
        ([ConsoleKey]::Escape)     { return "HOME" }
        ([ConsoleKey]::F1)         { return "HELP" }
    }
    $ch = "$($k.KeyChar)".ToUpperInvariant()
    switch ($ch) {
        "A" { return "PREV" }
        "N" { return "NEXT" }
        "R" { return "REPEAT" }
        "M" { return "HOME" }
        "Q" { return "QUIT" }
        "B" { return "EUREKA" }
        "U" { return "UTILS" }
        "P" { return "PREP" }
        "S" { return "STARTALL" }
        "T" { return "SUITE" }
        "C" { return "ENV" }
        "W" { return "DOCK_REFRESH" }
        "H" { return "HELP" }
        "?" { return "HELP" }
        default {
            if ($ch -match '^[1-6]$') { return "B$ch" }
            return "NEXT"
        }
    }
}

function Read-SlideKeyLive([bool]$LiveDock = $true) {
    if ([Console]::IsInputRedirected) { return "QUIT" }
    while ($true) {
        if ([Console]::KeyAvailable) {
            return (Parse-ConsoleKey ([Console]::ReadKey($true)))
        }
        try {
            if ([Console]::WindowWidth -ne $script:WinW -or [Console]::WindowHeight -ne $script:WinH) {
                return "RESIZE"
            }
        } catch { }
        if ($LiveDock) { Poll-AsyncDock }
        Start-Sleep -Milliseconds 30
    }
}

function Wait-SlideFooter([string]$NextLabel = "Siguiente", [bool]$AllowBack = $true, [string]$NextColor = "Green") {
    Write-Divider
    if ($AllowBack) {
        $navLine = "  [ESPACIO/→] {0}   [←/Backspace] Anterior" -f $NextLabel
        if ($navLine.Length -gt $script:UiW) {
            $navLine = "  [ESPACIO/→] {0}   [←] Anterior" -f $NextLabel
        }
        if ($navLine.Length -gt $script:UiW) {
            $navLine = "  [ESPACIO] {0}  [←] Atras" -f $NextLabel
        }
        Write-CleanLine $navLine $NextColor
    } else {
        Write-CleanLine ("  [ESPACIO/→] {0}" -f $NextLabel) $NextColor
    }
    $helpLine = if ($script:UiW -ge 90) {
        "  [1-6] Seccion  [R] Actualizar  [M] Inicio  [B] Eureka  [U] Utils  [?] Ayuda  [Q] Salir"
    } elseif ($script:UiW -ge 77) {
        "  [1-6] Sec  [R] Act  [M] Inicio  [B] Eureka  [U] Utils  [?] Ayuda  [Q] Salir"
    } else {
        "  [1-6] Ir [R] Act [M] Inicio [B] Eur [U] Util [?] Ayuda [Q] Sal"
    }
    Write-CleanLine $helpLine "DarkGray"
    End-Frame
    while ($true) {
        $act = Read-SlideKeyLive $true
        if ($act -eq "EUREKA") { Open-EurekaBrowser; continue }
        if ($act -eq "DOCK_REFRESH") { Update-DockInPlace (Get-ContainerMapSync); continue }
        return $act
    }
}

function Show-HelpModal {
    $script:FirstFrame = $true
    $script:LastScreenId = "HELP"
    while ($true) {
        Begin-Frame
        Write-CleanLine ("╔" + ("═" * ($script:UiW - 2)) + "╗") "DarkCyan"
        Write-Host ($script:Margin + "║ ") -ForegroundColor DarkCyan -NoNewline
        Write-Host (Format-Center "AYUDA RAPIDA Y ATAJOS DEL PRESENTADOR" $script:InnerW) -ForegroundColor Cyan -NoNewline
        Write-Host " ║" -ForegroundColor DarkCyan -NoNewline
        Complete-Row
        Write-CleanLine ("╚" + ("═" * ($script:UiW - 2)) + "╝") "DarkCyan"
        Write-BlankLine
        Write-BoxTop "NAVEGACION Y CONTROL" "Cyan"
        Write-BoxLine "Espacio/Enter/->/N : Siguiente diapositiva" "White" "Cyan"
        Write-BoxLine "<- / Backspace / A : Anterior (desde cache sin mutar)" "White" "Cyan"
        Write-BoxLine "1 .. 6             : Saltar directo a Seccion 1..6" "White" "Cyan"
        Write-BoxLine "R                  : Re-ejecutar en vivo el slide actual" "Yellow" "Cyan"
        Write-BoxLine "M / Esc            : Volver a la Portada principal" "White" "Cyan"
        Write-BoxLine "B / U / W          : Abrir Eureka / Utilidades / Dock" "White" "Cyan"
        Write-BoxLine "H / ? / F1   |   Q : Abrir esta ayuda   |   Salir" "DarkGray" "Cyan"
        Write-BoxBottom "Cyan"
        Write-BlankLine
        Write-BoxTop "SIGNIFICADO DE ESTADOS E INDICADORES" "DarkCyan"
        Write-BoxLine "● En linea (verde)   ~ Arranque (amarillo)   ! / ✗ Caido" "White" "DarkCyan"
        Write-BoxLine "[EN VIVO] Prueba actual   [CACHE · R] Vista guardada" "White" "DarkCyan"
        Write-BoxBottom "DarkCyan"
        Write-Divider
        Write-CleanLine "  [Cualquier tecla] Volver exactamente donde estabas" "Green"
        End-Frame
        if ([Console]::IsInputRedirected) { break }
        $act = Read-SlideKeyLive $false
        if ($act -eq "RESIZE") { continue }
        break
    }
    $script:FirstFrame = $true
}

function Invoke-ApiRequest([string]$Method, [string]$Url, [string]$JsonBody = "", [int]$TimeoutSec = 10) {
    $headers = @{}
    $rawBody = ""
    $bodyObj = $null
    $code = "000"
    try {
        $req = [System.Net.HttpWebRequest]::Create($Url)
        $req.Method = $Method
        $req.Timeout = $TimeoutSec * 1000
        $req.ReadWriteTimeout = $TimeoutSec * 1000
        $req.Accept = "application/json"
        if ($JsonBody) {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($JsonBody)
            $req.ContentType = "application/json; charset=utf-8"
            $req.ContentLength = $bytes.Length
            $rs = $req.GetRequestStream()
            $rs.Write($bytes, 0, $bytes.Length)
            $rs.Close()
        }
        $resp = $null
        try {
            $resp = [System.Net.HttpWebResponse]$req.GetResponse()
        } catch [System.Net.WebException] {
            if ($_.Exception.Response) {
                $resp = [System.Net.HttpWebResponse]$_.Exception.Response
            }
        }
        if ($resp) {
            $code = [string]([int]$resp.StatusCode)
            foreach ($hk in $resp.Headers.AllKeys) {
                $headers[$hk.ToLowerInvariant()] = $resp.Headers[$hk]
            }
            $stream = $resp.GetResponseStream()
            if ($stream) {
                $sr = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
                $rawBody = $sr.ReadToEnd()
                $sr.Close()
            }
            $resp.Close()
            if ($rawBody) {
                try { $bodyObj = $rawBody | ConvertFrom-Json } catch { }
            }
        }
    } catch { }
    return @{ Code = $code; Headers = $headers; Body = $bodyObj; Raw = $rawBody }
}

function Get-SaldoInfo {
    $r = Invoke-ApiRequest "GET" "$Gateway/api/cuentas/$Origen/saldo-critico" "" 2
    if ($r.Code -eq "200" -and $r.Body -and $r.Body.datos) { return $r.Body.datos }
    return $null
}

function Invoke-EnsureEnv {
    $envPath = Join-Path $RepoDir ".env"
    $exPath  = Join-Path $RepoDir ".env.example"
    if (-not (Test-Path $envPath)) {
        if (Test-Path $exPath) {
            Copy-Item -LiteralPath $exPath -Destination $envPath
            Write-Host ($script:Margin + "  [OK] Archivo .env creado desde .env.example.") -ForegroundColor Green
            return $true
        }
        Write-Host ($script:Margin + "  [ERROR] No existe .env ni .env.example.") -ForegroundColor Red
        return $false
    }
    return $true
}

function Write-ThreeColCards([string[]]$Titles, [string[]]$Colors, [object[]]$Rows) {
    $cwBase = [Math]::Floor(($script:UiW - 2) / 3)
    $rem = ($script:UiW - 2) - ($cwBase * 3)
    $cws = @(
        ($cwBase + $(if ($rem -ge 1) { 1 } else { 0 })),
        ($cwBase + $(if ($rem -ge 2) { 1 } else { 0 })),
        $cwBase
    )
    $gap = " "
    $lineTop = ""
    $lineBot = ""
    for ($i = 0; $i -lt 3; $i++) {
        $cw = $cws[$i]; $ci = $cw - 2
        $t = " " + $Titles[$i] + " "
        if ($t.Length -gt ($cw - 3)) { $t = $t.Substring(0, $cw - 3) }
        $fill = [Math]::Max(1, ($cw - 3) - $t.Length)
        $lineTop += "┌─" + $t + ("─" * $fill) + "┐"
        $lineBot += "└" + ("─" * $ci) + "┘"
        if ($i -lt 2) { $lineTop += $gap; $lineBot += $gap }
    }
    Write-CleanLine $lineTop "Cyan"
    foreach ($r in $Rows) {
        Write-Host $script:Margin -NoNewline
        for ($i = 0; $i -lt 3; $i++) {
            $bcol = $Colors[$i]; $ci = $cws[$i] - 2
            Write-Host "│" -ForegroundColor $bcol -NoNewline
            Write-Host (Format-Fixed $r[$i] $ci) -ForegroundColor White -NoNewline
            Write-Host "│" -ForegroundColor $bcol -NoNewline
            if ($i -lt 2) { Write-Host $gap -NoNewline }
        }
        Complete-Row
    }
    Write-CleanLine $lineBot "DarkGray"
}

# --- Panel de Utilidades ---

function Test-DockerReady {
    try {
        & docker info *> $null
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
}

function Show-CleanPrep {
    $script:LastScreenId = "PREP"
    Begin-Frame $true
    Write-CleanLine ("╔" + ("═" * ($script:UiW - 2)) + "╗") "DarkYellow"
    Write-Host ($script:Margin + "║ ") -ForegroundColor DarkYellow -NoNewline
    Write-Host (Format-Center "REINICIO LIMPIO DEL ENTORNO (down -v + up -d --build)" $script:InnerW) -ForegroundColor Yellow -NoNewline
    Write-Host " ║" -ForegroundColor DarkYellow -NoNewline
    Complete-Row
    Write-CleanLine ("╚" + ("═" * ($script:UiW - 2)) + "╝") "DarkYellow"
    Write-BlankLine
    if (-not (Test-DockerReady)) {
        Write-BoxTop "DOCKER NO DISPONIBLE" "Red"
        Write-BoxLine "[ERROR] Docker Desktop / daemon no esta ejecutandose." "Red" "Red"
        Write-BoxLine "Inicia Docker Desktop y vuelve a intentarlo." "White" "Red"
        Write-BoxBottom "Red"
        [void](Wait-SlideFooter "Volver" $false "Yellow")
        $script:FirstFrame = $true
        return
    }
    if (-not [Console]::IsInputRedirected) {
        Write-BoxTop "CONFIRMAR ACCION DESTRUCTIVA" "DarkYellow"
        Write-BoxLine "[!] Se ejecutara: docker compose down -v + up -d --build" "Yellow" "DarkYellow"
        Write-BoxLine "Se reiniciaran volumenes de BD y balances actuales." "White" "DarkYellow"
        Write-BoxBottom "DarkYellow"
        Write-BlankLine
        Write-CleanLine "  [S] Confirmar reinicio limpio   [Otra tecla] Cancelar" "Yellow"
        End-Frame
        $k = [Console]::ReadKey($true)
        if ("$($k.KeyChar)".ToUpperInvariant() -ne "S") {
            Write-CleanLine "  [Cancelado] No se realizaron cambios en los contenedores." "DarkGray"
            Start-Sleep -Milliseconds 700
            $script:FirstFrame = $true
            return
        }
        Write-BlankLine
    }
    if (-not (Invoke-EnsureEnv)) {
        [void](Wait-SlideFooter "Volver" $false)
        $script:FirstFrame = $true
        return
    }
    Write-CleanLine "  $ docker compose down -v && docker compose up -d --build" "Cyan"
    & docker compose down -v
    & docker compose up -d --build
    if ($LASTEXITCODE -ne 0) {
        Write-Host "`n  [ERROR] docker compose up fallo. Revisa Docker Desktop." -ForegroundColor Red
        [void](Wait-SlideFooter "Volver" $false "Yellow")
        $script:FirstFrame = $true
        return
    }
    Write-Host "`n  Esperando que los 8 contenedores esten healthy…" -ForegroundColor Yellow
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt 240) {
        $snap = Get-ContainerMapSync
        Write-Host ("`r  [{0,3}s] Healthy: {1}/8   " -f [int]$sw.Elapsed.TotalSeconds, $snap.Healthy) -NoNewline -ForegroundColor Cyan
        if ($snap.Healthy -ge 8) {
            Write-Host "`n  [OK] Los 8 contenedores estan healthy!" -ForegroundColor Green
            break
        }
        Start-Sleep -Seconds 2
    }
    Open-EurekaBrowser
    Write-Host "  [OK] Eureka abierto en $Eureka" -ForegroundColor Green
    $sal = Get-SaldoInfo
    if ($sal) {
        Write-Host ('  [OK] Cuenta {0}: saldo=${1} | consumidoHoy=${2} / ${3}' -f $Origen, (Format-Money $sal.saldo), (Format-Money $sal.consumidoHoy), (Format-Money $sal.limiteDiario)) -ForegroundColor Green
    }
    $script:CacheTxOk = $null
    $script:CacheTxErr = $null
    [void](Wait-SlideFooter "Volver al panel" $false)
    $script:FirstFrame = $true
}

function Show-UtilsPanel {
    $script:FirstFrame = $true
    $script:LastScreenId = "UTILS"
    while ($true) {
        Begin-Frame
        Write-CleanLine ("╔" + ("═" * ($script:UiW - 2)) + "╗") "DarkCyan"
        Write-Host ($script:Margin + "║ ") -ForegroundColor DarkCyan -NoNewline
        Write-Host (Format-Center "UTILIDADES DEL ENTORNO Y VERIFICACION" $script:InnerW) -ForegroundColor Cyan -NoNewline
        Write-Host " ║" -ForegroundColor DarkCyan -NoNewline
        Complete-Row
        Write-CleanLine ("╚" + ("═" * ($script:UiW - 2)) + "╝") "DarkCyan"
        Render-ClusterDock $true
        $sal = Get-SaldoInfo
        Write-BlankLine
        if (-not (Test-Path (Join-Path $RepoDir ".env"))) {
            Write-CleanLine "  [AVISO] Falta .env en el repositorio (pulsa [C] o [P])." "Yellow"
        } else {
            Write-CleanLine "  [OK] Archivo .env configurado." "DarkGray"
        }
        if ($sal) {
            $cons = [decimal]$sal.consumidoHoy
            $sc = if ($cons -eq 0) { "Green" } else { "Yellow" }
            Write-CleanLine ('  Cuenta {0}: saldo=${1} | consumidoHoy=${2} / ${3}' -f $Origen, (Format-Money $sal.saldo), (Format-Money $sal.consumidoHoy), (Format-Money $sal.limiteDiario)) $sc
        }
        Write-BlankLine
        Write-BoxTop "ACCIONES DISPONIBLES" "DarkCyan"
        Write-BoxLine "[P] Reinicio limpio (down -v + up -d --build + Eureka)" "Yellow" "DarkCyan"
        Write-BoxLine "[S] Arrancar contenedores detenidos (docker compose start)" "White" "DarkCyan"
        $eb = "[C] Verificar/crear .env   |   [B] Abrir Eureka ($Eureka)"
        if ($eb.Length -gt $script:InnerW) { $eb = "[C] Crear .env  |  [B] Abrir Eureka ($Eureka)" }
        if ($eb.Length -gt $script:InnerW) { $eb = "[C] Crear .env  |  [B] Abrir Eureka en navegador" }
        Write-BoxLine $eb "White" "DarkCyan"
        Write-BoxLine "[T] Ejecutar suite automatizada P01-P08" "White" "DarkCyan"
        Write-BoxLine "[1..6] Ir a Seccion 1..6   |   [W] Refrescar monitor" "Cyan" "DarkCyan"
        Write-BoxLine "[M / Esc] Volver a Portada |   [?] Ayuda  |  [Q] Salir" "Green" "DarkCyan"
        Write-BoxBottom "DarkCyan"
        End-Frame

        $act = Read-SlideKeyLive $true
        switch ($act) {
            "RESIZE"       { continue }
            "HELP"         { Show-HelpModal }
            "PREP"         { Show-CleanPrep }
            "STARTALL"     {
                Begin-Frame $true
                if (-not (Test-DockerReady)) {
                    Write-CleanLine "  [ERROR] Docker Desktop / daemon no responde." "Red"
                } else {
                    [void](Invoke-EnsureEnv); & docker compose start; [void](Get-ContainerMapSync)
                }
                [void](Wait-SlideFooter "Volver" $false); $script:FirstFrame = $true
            }
            "EUREKA"       { Open-EurekaBrowser }
            "DOCK_REFRESH" { Update-DockInPlace (Get-ContainerMapSync) }
            "ENV"          {
                if (Test-Path (Join-Path $RepoDir ".env")) {
                    Write-CleanLine "  [OK] El archivo .env ya existe." "Green"
                } else {
                    [void](Invoke-EnsureEnv)
                }
                Start-Sleep -Milliseconds 800
            }
            "SUITE" {
                Begin-Frame $true
                $ps1 = Join-Path $RepoDir "docs\api\curl-p01-p08.ps1"
                if (Test-Path $ps1) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ps1 }
                else { Write-CleanLine "  [AVISO] No se encontro docs/api/curl-p01-p08.ps1" "Yellow" }
                [void](Wait-SlideFooter "Volver" $false)
                $script:FirstFrame = $true
            }
            "QUIT" { return "QUIT" }
            default {
                if ($act -match '^B[1-6]$') { return $act }
                return "PORTADA"
            }
        }
    }
}

# --- Diapositivas 01 a 15 ---

function Slide-01([bool]$UseCache = $false) {
    Write-SlideChrome 1 1 "Arquitectura del Sistema · 8 Contenedores Docker" $false $false
    Write-BlankLine
    Write-BoxTop "FLUJO Y TOPOLOGIA DE RED (wallet-net)" "DarkCyan"
    if ($script:InnerW -ge 71) {
        $pad = if ($script:InnerW -ge 86) { "      " } else { "" }
        Write-BoxLine ($pad + "Cliente ─:8080─► [api-gateway] ◄──registro/latido 5s──► [eureka :8761]") "Cyan" "DarkCyan"
        Write-BoxLine ($pad + "                      │ lb:// Round-Robin") "DarkGray" "DarkCyan"
        Write-BoxLine ($pad + "        ┌─────────────┼─────────────┐") "DarkGray" "DarkCyan"
        Write-BoxLine ($pad + "        ▼             ▼             ▼") "DarkGray" "DarkCyan"
        Write-BoxLine ($pad + " [ms-cuentas-1] [ms-cuentas-2] [ms-transacciones]  (esquemas aislados:") "Green" "DarkCyan"
        Write-BoxLine ($pad + "     :8081          :8082            :8083          cuentas_db / tx_db)") "Green" "DarkCyan"
        Write-BoxLine ($pad + "        └─────────────┬─────────────┘  Enrutador JDBC (@UsarNodo)") "Magenta" "DarkCyan"
        Write-BoxLine ($pad + "     Escritura / RYOW │         Lecturas Ordinarias") "DarkGray" "DarkCyan"
        Write-BoxLine ($pad + "                      ▼") "DarkGray" "DarkCyan"
        Write-BoxLine ($pad + "       [primary :5432 R/W] ══WAL══► [replica1 :5433] + [replica2 :5434]") "Blue" "DarkCyan"
    } else {
        Write-BoxLine "Cliente :8080►[gateway]◄─5s─►[eureka :8761]" "Cyan" "DarkCyan"
        Write-BoxLine "                  │ lb:// Round-Robin" "DarkGray" "DarkCyan"
        Write-BoxLine "       ┌──────────┼──────────┐" "DarkGray" "DarkCyan"
        Write-BoxLine "       ▼          ▼          ▼" "DarkGray" "DarkCyan"
        Write-BoxLine " [cuentas-1] [cuentas-2] [ms-tx]  (cuentas_db / tx_db)" "Green" "DarkCyan"
        Write-BoxLine "     :8081      :8082     :8083" "Green" "DarkCyan"
        Write-BoxLine "       └──────────┬──────────┘  @UsarNodo JDBC" "Magenta" "DarkCyan"
        Write-BoxLine "   Write / RYOW   │    Lecturas" "DarkGray" "DarkCyan"
        Write-BoxLine "                  ▼" "DarkGray" "DarkCyan"
        Write-BoxLine " [primary:5432]═WAL═►[rep1:5433]+[rep2:5434]" "Blue" "DarkCyan"
    }
    Write-BoxBottom "DarkCyan"
    $takeaway = if ($script:InnerW -ge 70) { "  ● Gateway balancea HTTP; PostgreSQL separa escrituras y lecturas." } else { "  ● Gateway balancea HTTP; PostgreSQL separa write/read." }
    Write-CleanLine $takeaway "DarkGray"
    return (Wait-SlideFooter "Detalle del clúster")
}

function Slide-02([bool]$UseCache = $false) {
    Write-SlideChrome 2 1 "Clúster Docker Compose · Estado de Servicios" $UseCache $true
    Write-BlankLine
    if (-not $UseCache -or -not $script:CachePsLines) {
        $pRow = Show-LivePending "Consultando estado de contenedores (docker compose ps)…"
        $raw = & docker compose ps -a --format "{{.Name}}|{{.Service}}|{{.Status}}|{{.Ports}}" 2>$null
        if ($LASTEXITCODE -eq 0 -and $raw) {
            $script:CachePsLines = @($raw)
        } else {
            $script:CachePsLines = @()
        }
        Restore-LivePending $pRow
    }
    Write-BoxTop "TELEMETRIA DE CONTENEDORES (docker compose ps)" "Cyan"
    if ($script:CachePsLines.Count -gt 0) {
        $showPorts = ($script:InnerW -ge 72)
        if ($showPorts) {
            Write-BoxLine ("{0,-18} {1,-16} {2,-23} {3}" -f "CONTENEDOR", "SERVICIO", "ESTADO", "PUERTOS") "DarkGray" "Cyan"
        } else {
            Write-BoxLine ("{0,-18} {1,-16} {2}" -f "CONTENEDOR", "SERVICIO", "ESTADO") "DarkGray" "Cyan"
        }
        foreach ($line in $script:CachePsLines) {
            if (-not $line -or ($line -notmatch '\|')) { continue }
            $p = $line -split '\|', 4
            $st = ($p[2] -replace 'About an hour', '~1h' -replace '\(health: starting\)', '(starting)' -replace 'Less than a second', '<1s')
            $ports = ($p[3] -replace '0\.0\.0\.0:', '' -replace '\[::\]:\d+->\d+/tcp,?\s*', '' -replace '/tcp', '')
            $col = if ($st -match 'healthy') { "Green" } else { "Yellow" }
            $row = if ($showPorts) {
                "{0,-18} {1,-16} {2,-23} {3}" -f $p[0], $p[1], $st, $ports
            } else {
                "{0,-18} {1,-16} {2}" -f $p[0], $p[1], $st
            }
            Write-BoxLine $row $col "Cyan"
        }
    } else {
        Write-BoxLine "[ERROR] Sin respuesta de docker compose." "Red" "Cyan"
        Write-BoxLine "Accion: Verifica Docker activo o inicia con [U] -> [S]." "Yellow" "Cyan"
    }
    Write-BoxBottom "Cyan"
    return (Wait-SlideFooter "2. Descubrimiento en Eureka")
}

function Slide-03([bool]$UseCache = $false) {
    Write-SlideChrome 3 2 "Descubrimiento Dinámico con Netflix Eureka" $UseCache $true
    Write-BlankLine
    Write-BoxTop "ARQUITECTURA DE DESCUBRIMIENTO" "DarkCyan"
    Write-BoxLine "● Auto-registro al iniciar y latido (heartbeat) cada 5s." "White" "DarkCyan"
    Write-BoxLine "● Gateway resuelve vía lb://ms-cuentas, sin IPs fijas." "White" "DarkCyan"
    Write-BoxBottom "DarkCyan"
    Write-BlankLine
    if (-not $UseCache -or -not $script:CacheEureka) {
        $pRow = Show-LivePending "Consultando registro en Eureka (:8761/eureka/apps)…"
        $script:CacheEureka = Invoke-ApiRequest "GET" "$Eureka/eureka/apps" "" 5
        Restore-LivePending $pRow
    }
    $r = $script:CacheEureka
    Write-BoxTop "REGISTRO EUREKA EN VIVO (:8761/eureka/apps)" "Green"
    if ($r.Code -eq "200" -and $r.Body -and $r.Body.applications) {
        foreach ($app in $r.Body.applications.application) {
            $c = if ($app.name -eq "MS-CUENTAS") { "Green" } else { "Cyan" }
            $first = $true
            foreach ($inst in @($app.instance)) {
                $iid = "$($inst.instanceId)" -replace ':([0-9a-f]{6})[0-9a-f]{26}(?=:|$)', ':$1'
                $prefix = if ($first) { "{0,-16} -> " -f $app.name } else { "                    " }
                $first = $false
                Write-BoxLine ("{0}{1} [{2}]" -f $prefix, $iid, $inst.status) $c "Green"
            }
        }
    } elseif ($r.Code -eq "000") {
        Write-BoxLine ("Sin conexion con Eureka ({0})." -f $Eureka) "Red" "Green"
        Write-BoxLine "Accion: Revisa [U] Utilidades o pulsa [R] para reintentar." "Yellow" "Green"
    } else {
        Write-BoxLine ("Eureka no responde (HTTP {0}). Pulsa [R] para reintentar." -f $r.Code) "Red" "Green"
    }
    Write-BoxBottom "Green"
    return (Wait-SlideFooter "Balanceo HTTP Round Robin")
}

function Slide-04([bool]$UseCache = $false) {
    Write-SlideChrome 4 2 "Balanceo de Carga HTTP · Round Robin" $UseCache $true
    Write-BlankLine
    $sub = "  Objetivo: Verificar reparto 50/50 en GET {0}/api/cuentas/instancia" -f $Gateway
    if ($sub.Length -gt $script:InnerW) {
        $sub = "  Objetivo: Reparto 50/50 en GET /api/cuentas/instancia (20 peticiones)"
    }
    if ($sub.Length -gt $script:InnerW) {
        $sub = "  20x GET /api/cuentas/instancia (Round Robin)"
    }
    Write-CleanLine $sub "DarkCyan"
    Write-BlankLine
    if (-not $UseCache -or -not $script:CacheBalanceo) {
        $pRow = Show-LivePending "Ejecutando 20 peticiones HTTP GET contra Gateway :8080…"
        $res = @()
        for ($i = 1; $i -le 20; $i++) {
            $r = Invoke-ApiRequest "GET" "$Gateway/api/cuentas/instancia" "" 5
            $inst = if ($r.Headers["x-service-instance"]) { $r.Headers["x-service-instance"] } else { "sin-cabecera" }
            $res += [pscustomobject]@{ Code = $r.Code; Instance = $inst }
        }
        $script:CacheBalanceo = $res
        Restore-LivePending $pRow
    }
    $results = $script:CacheBalanceo
    $okCount = @($results | Where-Object Code -eq "200").Count
    $errCount = 20 - $okCount
    $barW = [Math]::Min(30, [Math]::Max(8, $script:InnerW - 42))

    Write-BoxTop "DISTRIBUCION POR INSTANCIA (20 PETICIONES)" "Green"
    Write-BoxLine ("{0,-20} {1,-5}  {2}  {3}" -f "INSTANCIA", "HTTP", "REPARTO".PadRight($barW), "CONTEO") "DarkGray" "Green"
    $grouped = $results | Group-Object Code, Instance | Sort-Object Name
    foreach ($g in $grouped) {
        $f = $g.Group[0]
        $pct = [int][Math]::Round(($g.Count / 20.0) * 100)
        $filled = [Math]::Min($barW, [int][Math]::Round(($g.Count / 20.0) * $barW))
        $bar = ("█" * $filled).PadRight($barW, "░")
        $c = if ($f.Code -eq "200") { if ($f.Instance -like "ms-cuentas-2*") { "Cyan" } else { "Green" } } else { "Red" }
        Write-BoxLine ("{0,-20} [{1}]  {2}  {3,2}/20 ({4,3}%)" -f $f.Instance, $f.Code, $bar, $g.Count, $pct) $c "Green"
    }
    if ($errCount -eq 20 -and ($results | Where-Object Code -eq "000").Count -eq 20) {
        Write-BoxLine "Gateway sin respuesta (HTTP 000). Revisa api-gateway en [U]." "Yellow" "Green"
    }
    Write-BoxBottom "Green"
    $pCol = if ($errCount -eq 0) { "Green" } else { "Red" }
    Write-CleanLine ("  [ RESULTADO: {0}/20 OK · ERRORES: {1} · REPARTO ROUND ROBIN ]" -f $okCount, $errCount) $pCol
    return (Wait-SlideFooter "3. Comunicación entre servicios")
}

function Slide-05([bool]$UseCache = $false) {
    Write-SlideChrome 5 3 "Orquestación P2P entre Microservicios · ACID" $UseCache $true
    Write-BlankLine
    $flow = if ($script:InnerW -ge 88) {
        "  Cliente ─POST :8080─► [ms-transacciones :8083] ─Eureka─► [ms-cuentas] ─ACID─► PRIMARY"
    } elseif ($script:InnerW -ge 66) {
        "  POST :8080 ─► ms-transacciones ─► ms-cuentas ─ACID─► PRIMARY"
    } else {
        "  POST :8080 ► ms-tx ► ms-cuentas ► PRIMARY"
    }
    Write-CleanLine $flow "Cyan"
    Write-BlankLine

    if (-not $UseCache -or -not $script:CacheTxOk) {
        $pRow = Show-LivePending 'Ejecutando transferencia P2P de prueba ($25.00)…'
        $payload = @{ celularOrigen = $Origen; celularDestino = $Destino; monto = 25; motivo = "Transferencia P2P" } | ConvertTo-Json -Compress
        $script:CacheTxOk = Invoke-ApiRequest "POST" "$Gateway/api/transacciones/transferir" $payload 10
        Restore-LivePending $pRow
    }
    $r = $script:CacheTxOk
    $ok = ($r.Code -eq "201" -or $r.Code -eq "200")
    $bCol = if ($ok) { "Green" } elseif ($r.Code -eq "000") { "Red" } else { "Yellow" }
    $msg = if ($r.Code -eq "000") { "Sin conexion con Gateway :8080 ([U]/[R])" } elseif ($r.Body) { $r.Body.mensaje } else { "Sin respuesta (HTTP $($r.Code))" }
    $cod = if ($r.Body -and $r.Body.datos) { $r.Body.datos.codigoComprobante } else { "-" }
    $sal = if ($r.Body -and $r.Body.datos) { Format-Money $r.Body.datos.nuevoSaldoOrigen } else { "-" }
    $ic  = if ($r.Body -and $r.Body.auditoriaTecnica) { $r.Body.auditoriaTecnica.instanciaCuentasConsultada } else { "-" }
    $nbd = if ($r.Body -and $r.Body.auditoriaTecnica) { $r.Body.auditoriaTecnica.nodoBaseDatos } else { "-" }
    $pol = if ($r.Body -and $r.Body.auditoriaTecnica) { $r.Body.auditoriaTecnica.politicaEnrutamiento } else { "-" }
    if ($nbd -and $nbd -ne "-") { $script:LastTxNodo = $nbd }
    if ($cod -and $cod -ne "-") { $script:LastTxCodigo = $cod }

    $nbdDisp = if ($script:InnerW -lt 66) { $nbd -replace 'recovery=', 'rec=' } else { $nbd }
    $nbdLbl  = if ($script:InnerW -lt 66) { "Nodo BD            : " } else { "Nodo Base de Datos : " }

    Write-BoxTop ("COMPROBANTE DE TRANSFERENCIA  [ HTTP " + $r.Code + " ]") $bCol
    Write-BoxLine ("Estado / Mensaje   : {0}" -f $msg) $bCol $bCol
    Write-BoxLine ('Comprobante        : {0}  (Monto: $25.00)' -f $cod) "White" $bCol
    Write-BoxLine ('Saldo Origen Post. : ${0}  ({1} -> {2})' -f $sal, $Origen, $Destino) "White" $bCol
    Write-BoxLine ("Instancia Cuentas  : {0}" -f $ic) "Cyan" $bCol
    Write-BoxLine ($nbdLbl + $nbdDisp) "Yellow" $bCol
    Write-BoxLine ("Política Enrutado  : {0}" -f $pol) "White" $bCol
    Write-BoxBottom $bCol
    $acidNote = if ($script:InnerW -ge 68) { "  ● Debito y credito en una sola transaccion ACID con bloqueo ordenado." } else { "  ● Debito/credito en 1 transaccion ACID con bloqueo ordenado." }
    Write-CleanLine $acidNote "DarkGray"
    return (Wait-SlideFooter "Validación saldo insuficiente")
}

function Slide-06([bool]$UseCache = $false) {
    Write-SlideChrome 6 3 "Validación de Reglas de Negocio · Error Controlado" $UseCache $true
    Write-BlankLine
    $prevNod = Format-NodeForWidth $script:LastTxNodo
    $prevTxt = if ($script:InnerW -ge 74) { "  Escritura previa ({0}) -> {1}" -f $script:LastTxCodigo, $prevNod } else { "  Escritura ({0}) -> {1}" -f $script:LastTxCodigo, $prevNod }
    Write-CleanLine $prevTxt "DarkCyan"
    Write-BlankLine

    if (-not $UseCache -or -not $script:CacheTxErr) {
        $pRow = Show-LivePending 'Validando rechazo controlado (monto $9999.00 > saldo)…'
        $payload = @{ celularOrigen = $Origen; celularDestino = $Destino; monto = 9999; motivo = "Prueba limite" } | ConvertTo-Json -Compress
        $script:CacheTxErr = Invoke-ApiRequest "POST" "$Gateway/api/transacciones/transferir" $payload 10
        Restore-LivePending $pRow
    }
    $r = $script:CacheTxErr
    $msg = if ($r.Code -eq "000") { "Sin conexion con Gateway :8080 ([U]/[R])" } elseif ($r.Body) { $r.Body.mensaje } else { "Sin respuesta (HTTP $($r.Code))" }
    $nbd = if ($r.Body -and $r.Body.auditoriaTecnica) { $r.Body.auditoriaTecnica.nodoBaseDatos } else { "-" }
    $col = if ($r.Code -eq "409") { "Yellow" } else { "Red" }
    $msgLbl = if ($msg.Length + 21 -gt $script:InnerW) { "Mensaje  : " } else { "Mensaje devuelto   : " }

    Write-BoxTop ("RECHAZO CONTROLADO  [ HTTP " + $r.Code + " ]") $col
    Write-BoxLine ($msgLbl + $msg) $col $col
    Write-BoxLine 'Monto solicitado   : $9999.00  (supera saldo disponible)' "White" $col
    Write-BoxLine "Integridad ACID    : Transaccion revertida; saldos intactos" "Green" $col
    Write-BoxLine ("Auditoría nodoBD   : {0}" -f (Format-NodeForWidth $nbd)) "Cyan" $col
    Write-BoxBottom $col
    return (Wait-SlideFooter "4. Persistencia replicada")
}

function Invoke-LecturasFetch {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $results = @()
    for ($i = 1; $i -le 10; $i++) {
        foreach ($path in @("cuentas/$Origen/contactos", "transacciones/historial/$Origen")) {
            $r = Invoke-ApiRequest "GET" "$Gateway/api/$path" "" 5
            $node = if ($r.Headers["x-db-node"]) { $r.Headers["x-db-node"] } else { "desconocido" }
            $fb   = if ($r.Headers["x-db-fallback"]) { $r.Headers["x-db-fallback"] } else { "false" }
            $results += [pscustomobject]@{ Code = $r.Code; Node = $node; Fallback = $fb }
        }
    }
    $sw.Stop()
    return @{ Results = $results; Sec = [string]::Format($script:Inv, "{0:F2}", $sw.Elapsed.TotalSeconds) }
}

function Format-NodeForWidth([string]$Node) {
    if ($script:InnerW -ge 72) { return $Node }
    return ($Node -replace '\([^)]*recovery=([^)]+)\)', '(rec=$1)' -replace ',\s*', ' ')
}

function Render-LecturasFromCache($Data, [string]$BorderCol = "Cyan") {
    $results = $Data.Results
    $okCount = @($results | Where-Object Code -eq "200").Count
    $errList = @($results | Where-Object Code -ne "200")
    $fbCount = @($results | Where-Object Fallback -eq "true").Count
    $errDetail = "0"
    if ($errList.Count -gt 0) {
        $errDetail = (@($errList | Group-Object Code | ForEach-Object { "HTTP $($_.Name) x$($_.Count)" }) -join ", ")
    }
    $maxNodeLen = 16
    foreach ($it in $results) {
        $dn = (Format-NodeForWidth $it.Node).Length
        if ($dn -gt $maxNodeLen) { $maxNodeLen = $dn }
    }
    $barW = [Math]::Min(18, [Math]::Max(4, $script:InnerW - 25 - $maxNodeLen))
    Write-BoxTop "20 LECTURAS ORDINARIAS (contactos + historial)" $BorderCol
    $barHdr = if ($barW -ge 7) { "REPARTO".PadRight($barW) } else { "BAR".PadRight($barW) }
    $hdrRow = ("CANT  HTTP  {0}  {1}  FALLBACK" -f $barHdr, "NODO BD".PadRight($maxNodeLen))
    if ($hdrRow.Length -le $script:InnerW) {
        Write-BoxLine $hdrRow "DarkGray" $BorderCol
    }
    $grouped = $results | Group-Object Code, Node, Fallback | Sort-Object Name
    foreach ($g in $grouped) {
        $f = $g.Group[0]
        $filled = [Math]::Min($barW, [int][Math]::Round(($g.Count / 20.0) * $barW))
        $bar = ("█" * $filled).PadRight($barW, "░")
        $c = if ($f.Code -ne "200") { "Red" } elseif ($f.Fallback -eq "true") { "Yellow" } else { "Green" }
        $dnVal = (Format-NodeForWidth $f.Node).PadRight($maxNodeLen)
        Write-BoxLine ("{0,2}/20 [{1}] {2}  {3}  fb={4}" -f $g.Count, $f.Code, $bar, $dnVal, $f.Fallback) $c $BorderCol
    }
    Write-BoxBottom $BorderCol
    return @{ Ok = $okCount; Err = $errList.Count; ErrDetail = $errDetail; Fallback = $fbCount; Sec = $Data.Sec }
}

function Slide-07([bool]$UseCache = $false) {
    Write-SlideChrome 7 4 "Enrutamiento BD · Primario vs Réplicas WAL" $UseCache $true
    Write-BlankLine
    $wNod = Format-NodeForWidth $script:LastTxNodo
    $hdr7 = if ($script:InnerW -ge 80) { "  Escrituras -> {0}  |  Lecturas -> REPLICA_1 / REPLICA_2" -f $wNod } else { "  Write -> {0} | Read -> REP1/REP2" -f $wNod }
    Write-CleanLine $hdr7 "DarkCyan"
    Write-BlankLine
    if (-not $UseCache -or -not $script:CacheLecturas07) {
        $pRow = Show-LivePending "Ejecutando 20 lecturas ordinarias (contactos + historial)…"
        $script:CacheLecturas07 = Invoke-LecturasFetch
        Restore-LivePending $pRow
    }
    $stats = Render-LecturasFromCache $script:CacheLecturas07 "Green"
    $col = if ($stats.Err -eq 0) { "Green" } else { "Red" }
    Write-CleanLine ("  [ {0}/20 OK · ERRORES: {1} · REPLICAS (recovery=true) · {2}s ]" -f $stats.Ok, $stats.ErrDetail, $stats.Sec) $col
    return (Wait-SlideFooter "Lectura crítica RYOW")
}

function Slide-08([bool]$UseCache = $false) {
    Write-SlideChrome 8 4 "Consistencia Inmediata · Read-Your-Own-Writes" $UseCache $true
    Write-BlankLine
    Write-BoxTop "ARQUITECTURA DE CONSISTENCIA" "DarkCyan"
    if ($script:InnerW -ge 68) {
        Write-BoxLine "● Las réplicas WAL pueden presentar retardo mínimo tras escribir." "White" "DarkCyan"
        Write-BoxLine "● /saldo-critico fuerza lectura al PRIMARIO (RYOW garantizado)." "White" "DarkCyan"
    } else {
        Write-BoxLine "● Réplicas WAL pueden tener retardo mínimo tras escribir." "White" "DarkCyan"
        Write-BoxLine "● /saldo-critico fuerza lectura en PRIMARIO (RYOW)." "White" "DarkCyan"
    }
    Write-BoxBottom "DarkCyan"
    Write-BlankLine
    if (-not $UseCache -or -not $script:CacheCritico) {
        $pRow = Show-LivePending "Consultando /saldo-critico directo al PRIMARIO…"
        $script:CacheCritico = Invoke-ApiRequest "GET" "$Gateway/api/cuentas/$Origen/saldo-critico" "" 5
        Restore-LivePending $pRow
    }
    $r = $script:CacheCritico
    $boxT8 = if ($script:InnerW -ge 68) { "LECTURA CRITICA  [ GET /api/cuentas/{0}/saldo-critico ]" -f $Origen } else { "LECTURA CRITICA (GET /saldo-critico)" }
    Write-BoxTop $boxT8 "Green"
    if ($r.Code -eq "200" -and $r.Body) {
        $sal = Format-Money $r.Body.datos.saldo
        $nbd = Format-NodeForWidth $r.Body.auditoriaTecnica.nodoBaseDatos
        $pol = $r.Body.auditoriaTecnica.politicaEnrutamiento
        Write-BoxLine ('Saldo inmediato    : ${0}' -f $sal) "Green" "Green"
        Write-BoxLine ("Nodo Base de Datos : {0}" -f $nbd) "Cyan" "Green"
        Write-BoxLine ("Política Enrutado  : {0}" -f $pol) "Yellow" "Green"
    } elseif ($r.Code -eq "000") {
        Write-BoxLine "Sin conexion con Gateway :8080 — Verifica cluster con [U]." "Red" "Green"
    } else {
        Write-BoxLine ("HTTP {0}: {1}" -f $r.Code, $r.Raw) "Red" "Green"
    }
    Write-BoxBottom "Green"
    return (Wait-SlideFooter "5. Simulación de fallos (en vivo)" $true "Yellow")
}

function Slide-09([bool]$UseCache = $false) {
    Write-SlideChrome 9 5 "Alta Disponibilidad HTTP · Caída ms-cuentas-2" $UseCache $true

    if ($UseCache -and $script:LastBurstLines.Count -gt 0) {
        Write-BlankLine
        $rCol = if ($script:LastBurstLines[0] -match 'Errores:\s*0\b') { "Green" } else { "Yellow" }
        Write-BoxTop "RESUMEN DE FALLO Y CONVERGENCIA" $rCol
        foreach ($ln in $script:LastBurstLines) {
            Write-BoxLine $ln "White" $rCol
        }
        Write-BoxBottom $rCol
        return (Wait-SlideFooter "5b. Caída de réplica PostgreSQL")
    }

    $phase = 1; $totalReq = 0; $errReq = 0; $c1 = 0; $c2 = 0
    $errByCode = @{}
    $ring = New-Object System.Collections.Generic.List[object]
    $eventMsg = "Tráfico continuo activo contra Gateway :8080"
    $stopProc = $null; $stopDone = $false
    $startProc = $null; $startDone = $false
    $stopTrigAt = $null; $detectMs = $null; $consecC1 = 0; $streakStart = $null
    $startTrigAt = $null; $rejoinMs = $null
    $abortAct = $null

    $renderBody = {
        if (-not [Console]::IsOutputRedirected) {
            try { [Console]::SetCursorPosition(0, $script:DockRow + 4) } catch { }
        }
        $statusTxt = if ($script:InnerW -ge 74) {
            switch ($phase) {
                1 { "Tráfico activo (ms-cuentas-1 + ms-cuentas-2)  |  [ESPACIO] Detener :8082" }
                2 { "ms-cuentas-2 DETENIDA · Midiendo detección  |  [ESPACIO] Reiniciar :8082" }
                3 { "Recuperando instancia (~25s JVM)              |  [ESPACIO] Ver resumen" }
            }
        } else {
            switch ($phase) {
                1 { "Activo (:8081 + :8082) | [ESPACIO] Detener :8082" }
                2 { ":8082 DETENIDA (detección) | [ESPACIO] Reiniciar" }
                3 { "Recuperando JVM (~25s) | [ESPACIO] Ver resumen" }
            }
        }
        $errCodes = if ($errByCode.Count -gt 0) {
            " [" + ((@($errByCode.Keys | Sort-Object | ForEach-Object { "$_ x$($errByCode[$_])" })) -join ", ") + "]"
        } else { "" }
        $totLine = "Total: {0,-4}  cta-1: {1,-4}  cta-2: {2,-4}  Errores: {3}{4}" -f $totalReq, $c1, $c2, $errReq, $errCodes
        if ($totLine.Length -gt $script:InnerW) {
            $totLine = "Tot:{0} c1:{1} c2:{2} Err:{3}{4}" -f $totalReq, $c1, $c2, $errReq, $errCodes
        }
        Write-BoxTop "TELEMETRIA EN VIVO (VENTANA FIJA)" "Yellow"
        Write-BoxLine $statusTxt "Yellow" "Yellow"
        Write-BoxLine $totLine $(if ($errReq -eq 0) { "Green" } else { "Red" }) "Yellow"
        Write-BoxBottom "Yellow"

        Write-BoxTop "ULTIMAS PETICIONES" "DarkGray"
        for ($idx = 0; $idx -lt 6; $idx++) {
            if ($idx -lt $ring.Count) {
                $item = $ring[$idx]
                Write-BoxLine $item.Line $item.Col "DarkGray"
            } else {
                Write-BoxLine "" "White" "DarkGray"
            }
        }
        Write-BoxBottom "DarkGray"
        Write-CleanLine ("  " + (Format-Fixed $eventMsg $script:InnerW)) "Cyan"
        $s9Hint = if ($script:UiW -ge 78) {
            "  [ESPACIO] Accion fase   [←] Atras   [B] Eureka   [M] Inicio   [?] Ayuda   [Q] Salir"
        } else {
            "  [ESPACIO] Fase  [←] Atras  [B] Eur  [M] Inicio  [?] Ayuda  [Q] Salir"
        }
        Write-CleanLine $s9Hint "DarkGray"
        End-Frame
    }

    try {
        while ($true) {
            try {
                if ([Console]::WindowWidth -ne $script:WinW -or [Console]::WindowHeight -ne $script:WinH) {
                    Write-SlideChrome 9 5 "Alta Disponibilidad HTTP · Caída ms-cuentas-2" $false $true
                }
            } catch { }
            if ($stopProc -and -not $stopDone -and $stopProc.HasExited) {
                $stopDone = $true
                $detTxt = if ($null -ne $detectMs) { (" ({0:F2}s)" -f ($detectMs / 1000.0)) } else { "" }
                $eventMsg = "[EVENTO] ms-cuentas-2 detenida · Convergencia a ms-cuentas-1$detTxt"
                Update-DockInPlace (Get-ContainerMapSync)
            }
            if ($startProc -and -not $startDone -and $startProc.HasExited) {
                $startDone = $true
                $eventMsg = "[EVENTO] ms-cuentas-2 reiniciada (arranque JVM ~25s en segundo plano)"
                Update-DockInPlace (Get-ContainerMapSync)
            }
            Poll-AsyncDock

            $r = Invoke-ApiRequest "GET" "$Gateway/api/cuentas/$Origen" "" 3
            $totalReq++
            $nowUtc = [DateTime]::UtcNow
            $ts = (Get-Date).ToString("HH:mm:ss")
            $inst = if ($r.Headers["x-service-instance"]) { $r.Headers["x-service-instance"] } else { "sin-instancia" }
            if ($r.Code -ne "200") {
                $errReq++; $col = "Red"
                $k = "HTTP $($r.Code)"
                $errByCode[$k] = if ($errByCode.ContainsKey($k)) { $errByCode[$k] + 1 } else { 1 }
                $consecC1 = 0; $streakStart = $null
            } elseif ($inst -like "ms-cuentas-2*") {
                $c2++; $col = "Cyan"
                $consecC1 = 0; $streakStart = $null
                if ($phase -eq 3 -and $null -eq $rejoinMs -and $startTrigAt) {
                    $rejoinMs = ($nowUtc - $startTrigAt).TotalMilliseconds
                    $eventMsg = ("[EVENTO] ms-cuentas-2 reincorporada al balanceo en {0}s!" -f [string]::Format($script:Inv, "{0:F2}", ($rejoinMs / 1000.0)))
                }
            } else {
                $c1++; $col = "Green"
                if ($phase -ge 2 -and $null -eq $detectMs -and $stopTrigAt) {
                    if ($consecC1 -eq 0) { $streakStart = $nowUtc }
                    $consecC1++
                    if ($consecC1 -ge 3) {
                        $detectMs = ($streakStart - $stopTrigAt).TotalMilliseconds
                    }
                }
            }
            $ring.Add(@{ Line = ("[{0}]  HTTP {1}  ->  {2}" -f $ts, $r.Code, $inst); Col = $col })
            if ($ring.Count -gt 6) { $ring.RemoveAt(0) }

            & $renderBody

            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            while ($sw.ElapsedMilliseconds -lt 260) {
                if (-not [Console]::IsInputRedirected -and [Console]::KeyAvailable) {
                    $act = Parse-ConsoleKey ([Console]::ReadKey($true))
                    if ($act -eq "QUIT" -or $act -eq "HOME" -or $act -eq "PREV" -or $act -match '^B[1-6]$') {
                        $abortAct = $act; break
                    }
                    if ($act -eq "EUREKA") { Open-EurekaBrowser; continue }
                    if ($act -eq "HELP") {
                        Show-HelpModal
                        Write-SlideChrome 9 5 "Alta Disponibilidad HTTP · Caída ms-cuentas-2" $false $true
                        & $renderBody
                        continue
                    }
                    if ($phase -eq 1) {
                        $phase = 2
                        $stopTrigAt = [DateTime]::UtcNow; $consecC1 = 0; $streakStart = $null
                        $eventMsg = "[ACCION] Deteniendo ms-cuentas-2 (docker compose stop)"
                        $stopProc = Start-BackgroundDocker "stop ms-cuentas-2"
                    } elseif ($phase -eq 2) {
                        $phase = 3
                        $startTrigAt = [DateTime]::UtcNow
                        $eventMsg = "[ACCION] Reiniciando ms-cuentas-2 (docker compose start)"
                        $startProc = Start-BackgroundDocker "start ms-cuentas-2"
                    } else {
                        $abortAct = "DONE"; break
                    }
                    & $renderBody
                }
                Start-Sleep -Milliseconds 30
            }
            if ($abortAct) { break }
        }
    } finally {
        if ($stopProc  -and -not $stopProc.HasExited)  { try { $stopProc.WaitForExit(3000)  | Out-Null } catch { } }
        if ($startProc -and -not $startProc.HasExited) { try { $startProc.WaitForExit(2000) | Out-Null } catch { } }
    }

    if ($abortAct -and $abortAct -ne "DONE") { return $abortAct }

    $errSummary = if ($errByCode.Count -gt 0) {
        (@($errByCode.Keys | Sort-Object | ForEach-Object { "$_ x$($errByCode[$_])" })) -join ", "
    } else { "ninguno (reintento GET en Gateway)" }
    $detStr = if ($null -ne $detectMs) { [string]::Format($script:Inv, "{0:F2}s", ($detectMs / 1000.0)) } else { "inmediata" }
    $rejStr = if ($null -ne $rejoinMs) { [string]::Format($script:Inv, "{0:F2}s", ($rejoinMs / 1000.0)) } else { "~25s JVM" }

    $script:LastBurstLines = @(
        ("Total: {0}  |  Exitosas (200): {1}  |  Errores: {2}" -f $totalReq, ($totalReq - $errReq), $errReq),
        ("Errores transitorios : {0}" -f $errSummary),
        ("Distribución : ms-cuentas-1={0}  |  ms-cuentas-2={1}" -f $c1, $c2),
        ("Detección    : {0}  |  Retorno: {1}" -f $detStr, $rejStr),
        ("Limitación   : Gateway reintenta GET (no POST /transferir)")
    )

    Write-SlideChrome 9 5 "Alta Disponibilidad HTTP · Errores y Tiempos" $false $true
    Write-BlankLine
    $rCol = if ($errReq -eq 0) { "Green" } else { "Yellow" }
    Write-BoxTop "RESUMEN DE FALLO Y CONVERGENCIA" $rCol
    Write-BoxLine $script:LastBurstLines[0] $rCol $rCol
    Write-BoxLine $script:LastBurstLines[1] $(if ($errReq -eq 0) { "Green" } else { "Red" }) $rCol
    Write-BoxLine $script:LastBurstLines[2] "White" $rCol
    Write-BoxLine $script:LastBurstLines[3] "Cyan" $rCol
    Write-BoxLine $script:LastBurstLines[4] "DarkGray" $rCol
    Write-BoxBottom $rCol
    return (Wait-SlideFooter "5b. Caída de réplica PostgreSQL")
}

function Slide-10([bool]$UseCache = $false) {
    Write-SlideChrome 10 5 "Alta Disponibilidad BD · Caída de Réplica PG" $false $false
    Write-BlankLine
    Write-BoxTop "OBJETIVO Y MECANISMO DE FAILOVER EN CALIENTE" "DarkCyan"
    if ($script:InnerW -ge 68) {
        Write-BoxLine "● Objetivo : Verificar continuidad de lecturas si cae replica1." "White" "DarkCyan"
        Write-BoxLine "● @UsarNodo: Captura el fallo SQL y reintenta en replica sana" "White" "DarkCyan"
        Write-BoxLine "             marcando cabecera X-Db-Fallback: true." "White" "DarkCyan"
        Write-BoxLine "● Sonda 3s : ReplicaHealthTracker retira replica1 tras fallar." "White" "DarkCyan"
    } else {
        Write-BoxLine "● Objetivo : Continuidad de lecturas ante caida de replica1." "White" "DarkCyan"
        Write-BoxLine "● @UsarNodo: Reintenta en replica sana (X-Db-Fallback: true)." "White" "DarkCyan"
        Write-BoxLine "● Sonda 3s : ReplicaHealthTracker retira replica1 al fallar." "White" "DarkCyan"
    }
    Write-BoxBottom "DarkCyan"
    Write-BlankLine
    Write-BoxTop "ACCION EN VIVO AL AVANZAR (PREVENCION)" "Yellow"
    Write-BoxLine "[!] Se ejecutara: docker compose stop replica1 + 20 lecturas." "Yellow" "Yellow"
    Write-BoxBottom "Yellow"
    return (Wait-SlideFooter "[!] Ejecutar: stop replica1 + 20 lecturas" $true "Yellow")
}

function Slide-11([bool]$UseCache = $false) {
    Write-SlideChrome 11 5 "Failover Transparente · Lecturas sobre REPLICA_2" $UseCache $true
    Write-BlankLine
    if (-not $UseCache -or -not $script:CacheLecturas11) {
        $pRow = Show-LivePending "Deteniendo replica1 y ejecutando 20 lecturas con failover…"
        & docker compose stop replica1 2>&1 | Out-Null
        $script:StopRepAt = [DateTime]::UtcNow
        [void](Get-ContainerMapSync)
        Update-DockInPlace $script:LastSnap
        $script:CacheLecturas11 = Invoke-LecturasFetch
        Restore-LivePending $pRow
    }
    Write-CleanLine "  $ docker compose stop replica1  [OK]" "DarkCyan"
    Write-BlankLine
    $stats = Render-LecturasFromCache $script:CacheLecturas11 "Yellow"
    $col = if ($stats.Err -eq 0) { "Green" } else { "Yellow" }
    Write-CleanLine ("  [ {0}/20 OK · ERRORES: {1} · FALLBACK={2} · TIEMPO={3}s ]" -f $stats.Ok, $stats.ErrDetail, $stats.Fallback, $stats.Sec) $col
    return (Wait-SlideFooter "Estado de salud de réplicas")
}

function Render-DbEstadoBox([string]$Title, $Resp) {
    Write-BoxTop $Title "Cyan"
    if ($Resp.Code -eq "200" -and $Resp.Body) {
        if ($Resp.Body.servicio -or $Resp.Body.consultasTotales) {
            $ct = $Resp.Body.consultasTotales
            $ctTxt = if ($ct) { " · Consultas: PRI=$($ct.PRIMARY) R1=$($ct.REPLICA_1) R2=$($ct.REPLICA_2)" } else { "" }
            Write-BoxLine ("Instancia: {0}{1}" -f $Resp.Body.servicio, $ctTxt) "DarkGray" "Cyan"
        }
        foreach ($rep in $Resp.Body.replicas) {
            $avail = [bool]$rep.available
            $badge = if ($avail) { "[● ACTIVA · available=true ]" } else { "[✗ CAIDA  · available=false]" }
            $c = if ($avail) { "Green" } else { "Red" }
            $row = if ($script:InnerW -ge 66) {
                "{0,-10} {1}  exitos={2,-3} LSN={3}" -f $rep.nodo, $badge, $rep.consecutiveSuccesses, $rep.lastReplayLsn
            } else {
                $shortB = if ($avail) { "[● ACTIVA]" } else { "[✗ CAIDA ]" }
                "{0,-10} {1} ok={2,-4} LSN={3}" -f $rep.nodo, $shortB, $rep.consecutiveSuccesses, $rep.lastReplayLsn
            }
            Write-BoxLine $row $c "Cyan"
        }
    } elseif ($Resp.Code -eq "000") {
        Write-BoxLine "Sin conexion con Gateway :8080 — Verifica cluster con [U]." "Red" "Cyan"
    } else {
        Write-BoxLine ("HTTP {0}: {1}" -f $Resp.Code, $Resp.Raw) "Red" "Cyan"
    }
    Write-BoxBottom "Cyan"
}

function Slide-12([bool]$UseCache = $false) {
    Write-SlideChrome 12 5 "Detección Automática · Sondeo cada 3s" $UseCache $true
    Write-BlankLine
    if (-not $UseCache -or -not $script:CacheEstado12) {
        $pRow = Show-LivePending "Consultando estado de salud (/api/cuentas/db/estado)…"
        $script:CacheEstado12 = Invoke-ApiRequest "GET" "$Gateway/api/cuentas/db/estado" "" 5
        Restore-LivePending $pRow
    }
    Render-DbEstadoBox "SALUD DE REPLICAS (/api/cuentas/db/estado)" $script:CacheEstado12
    Write-BlankLine
    $elapsedStop = if ($script:StopRepAt) { [string]::Format($script:Inv, "{0:F1}s tras stop", ([DateTime]::UtcNow - $script:StopRepAt).TotalSeconds) } else { "sondeo cada 3.0s" }
    Write-BoxTop "DETECCIÓN Y LIMITACIONES" "DarkGray"
    Write-BoxLine ("● Detección : {0} (ReplicaHealthTracker, c/3s)." -f $elapsedStop) "White" "DarkGray"
    Write-BoxLine "● Limitación: failover solo lectura (no promueve PRIMARY)." "Yellow" "DarkGray"
    Write-BoxBottom "DarkGray"
    return (Wait-SlideFooter "Reiniciar replica1 (recuperación WAL)" $true "Cyan")
}

function Slide-13([bool]$UseCache = $false) {
    Write-SlideChrome 13 5 "Recuperación WAL · Reinicio de replica1" $UseCache $true
    Write-BlankLine
    if (-not $UseCache) {
        $pRow = Show-LivePending "Reiniciando replica1 y actualizando monitor…"
        & docker compose start replica1 2>&1 | Out-Null
        $script:StartRepAt = [DateTime]::UtcNow
        [void](Get-ContainerMapSync)
        Update-DockInPlace $script:LastSnap
        Restore-LivePending $pRow
    }
    Write-CleanLine "  $ docker compose start replica1  [OK]" "DarkCyan"
    Write-BlankLine
    Write-BoxTop "SINCRONIZACION AUTOMATICA EN CURSO" "Green"
    Write-BoxLine "[✓] Contenedor replica1 reiniciado y conectado al PRIMARY." "Green" "Green"
    Write-BoxLine "[~] Replicando registros WAL atrasados de forma continua." "Yellow" "Green"
    Write-BoxLine "[~] Umbral de retorno: 2 chequeos sanos seguidos (2 x 3s)." "Cyan" "Green"
    Write-BoxBottom "Green"
    return (Wait-SlideFooter "Verificar retorno al Round-Robin")
}

function Slide-14([bool]$UseCache = $false) {
    Write-SlideChrome 14 5 "Reincorporación Automática · Umbral 2/2" $UseCache $true
    Write-BlankLine
    if (-not $UseCache -or -not $script:CacheEstado14) {
        $pRow = Show-LivePending "Consultando reincorporacion (/api/cuentas/db/estado)…"
        $script:CacheEstado14 = Invoke-ApiRequest "GET" "$Gateway/api/cuentas/db/estado" "" 5
        Restore-LivePending $pRow
    }
    Render-DbEstadoBox "SALUD DE REPLICAS TRAS RECUPERACION (/api/cuentas/db/estado)" $script:CacheEstado14
    Write-BlankLine
    $elapsedStart = if ($script:StartRepAt) { [string]::Format($script:Inv, "{0:F1}s tras start", ([DateTime]::UtcNow - $script:StartRepAt).TotalSeconds) } else { "~6-8s habituales" }
    Write-BoxTop "RETORNO AUTOMATICO Y LIMITACION" "DarkGray"
    Write-BoxLine ("● Retorno   : {0} (2x pg_is_in_recovery=true)." -f $elapsedStart) "White" "DarkGray"
    Write-BoxLine "● Limitación: depende de wal_keep_size (usar slots en prod)." "Yellow" "DarkGray"
    Write-BoxLine "● Tip       : si replica1 sigue iniciando, pulsa [R]." "Cyan" "DarkGray"
    Write-BoxBottom "DarkGray"
    return (Wait-SlideFooter "6. Conclusiones técnicas")
}

function Slide-15([bool]$UseCache = $false) {
    Write-SlideChrome 15 6 "Conclusiones · Decisiones, Limitaciones, Mejoras" $false $false
    Write-BlankLine
    if ($script:InnerW -ge 72) {
        $rows = @(
            @("· BD por @UsarNodo",      "· Sin failover primario", "· Failover (Patroni)"),
            @("  write->PRI read->REP",  "· Eureka único (SPOF)",   "· Claves idempotencia"),
            @("· Round Robin + salud",   "· /movimiento-interno",   "· Retry conexión en"),
            @("  chequeo 2 de 2",        "  expuesto en Gateway",   "  ms-transacciones"),
            @("· Eureka sin cache +",    "· Límite diario no se",   "· Health Eureka real"),
            @("  retry GET (0 err P03)", "  reinicia solo",         "· Bloquear ruta interna"),
            @("· Flyway advisory lock",  "· Sin idempotencia P2P",  "  y Sagas / Outbox")
        )
        Write-ThreeColCards @("DECISIONES", "LIMITACIONES", "MEJORAS FUTURAS") @("Green", "Yellow", "Cyan") $rows
    } else {
        $rows = @(
            @("· @UsarNodo JDBC",   "· Sin failover PRI", "· Failover Patroni"),
            @("  W:PRI R:REPLICA",  "· Eureka único",     "· Idempotencia P2P"),
            @("· Round-Robin 2/2",  "· /mov-interno en",  "· Retry conexión"),
            @("  salud verificada", "  ruta del Gateway", "  ms-transacciones"),
            @("· Eureka sin cache", "· Límite diario",    "· Health Eureka"),
            @("  + retry GET GW",   "  sin auto-reset",   "· Cerrar /mov-int"),
            @("· Flyway adv. lock", "· Sin idempotencia", "  + Sagas / Outbox")
        )
        Write-ThreeColCards @("DECISIONES", "LIMITACIONES", "MEJORAS") @("Green", "Yellow", "Cyan") $rows
    }
    Write-BoxTop "SÍNTESIS FINAL" "Cyan"
    $quote = if ($script:InnerW -ge 74) {
        '"Más de uno de todo, y saber esquivar al que falla. Sistema distribuido."'
    } else {
        '"Replicar cada capa y esquivar al nodo que falla."'
    }
    Write-BoxLine (Format-Center $quote $script:InnerW) "Cyan" "Cyan"
    Write-BoxBottom "Cyan"
    return (Wait-SlideFooter "Volver a Portada")
}

# --- Motor PowerPoint ---

function Run-Deck([int]$StartSlide) {
    $slides = @(
        "Slide-01", "Slide-02", "Slide-03", "Slide-04", "Slide-05",
        "Slide-06", "Slide-07", "Slide-08", "Slide-09", "Slide-10",
        "Slide-11", "Slide-12", "Slide-13", "Slide-14", "Slide-15"
    )
    $map = @{ "1" = 0; "2" = 2; "3" = 4; "4" = 6; "5" = 8; "6" = 14 }
    $idx = $StartSlide
    $useCache = $false
    while ($idx -ge 0 -and $idx -lt $slides.Count) {
        $act = & $slides[$idx] $useCache
        $useCache = $false
        switch ($act) {
            "RESIZE" { $useCache = $true; continue }
            "HELP"   { Show-HelpModal; $useCache = $true; continue }
            "PREV" {
                if ($idx -eq 0) { return "PORTADA" }
                $idx--
                $useCache = $true
            }
            "REPEAT" { continue }
            "HOME"   { return "PORTADA" }
            "QUIT"   { return "QUIT" }
            "UTILS" {
                $u = Show-UtilsPanel
                $script:FirstFrame = $true
                if ($u -eq "QUIT") { return "QUIT" }
                if ($u -match '^B([1-6])$') { $idx = $map[$Matches[1]] }
            }
            default {
                if ($act -match '^B([1-6])$') {
                    $idx = $map[$Matches[1]]
                } else {
                    $idx++
                }
            }
        }
    }
    return "PORTADA"
}

function Show-Portada {
    $blockMap = @{ "B1" = 0; "B2" = 2; "B3" = 4; "B4" = 6; "B5" = 8; "B6" = 14 }
    $salCached = $null
    $lastSalPoll = [DateTime]::MinValue
    while ($true) {
        Begin-Frame
        $pTitle = if ($script:InnerW -ge 66) { "BILLETERA DIGITAL DISTRIBUIDA · DEMO EN VIVO" } else { "BILLETERA DIGITAL · DEMO EN VIVO" }
        $pSub   = if ($script:InnerW -ge 70) { "Replicación PostgreSQL WAL, descubrimiento Eureka y failover" } else { "Replicación Postgres WAL, Eureka y tolerancia a fallos" }
        Write-CleanLine ("╔" + ("═" * ($script:UiW - 2)) + "╗") "DarkCyan"
        Write-Host ($script:Margin + "║ ") -ForegroundColor DarkCyan -NoNewline
        Write-Host (Format-Center $pTitle $script:InnerW) -ForegroundColor Cyan -NoNewline
        Write-Host " ║" -ForegroundColor DarkCyan -NoNewline
        Complete-Row
        Write-Host ($script:Margin + "║ ") -ForegroundColor DarkCyan -NoNewline
        Write-Host (Format-Center $pSub $script:InnerW) -ForegroundColor DarkGray -NoNewline
        Write-Host " ║" -ForegroundColor DarkCyan -NoNewline
        Complete-Row
        Write-CleanLine ("╚" + ("═" * ($script:UiW - 2)) + "╝") "DarkCyan"

        Render-ClusterDock $true
        if (-not [Console]::IsOutputRedirected -and $script:LastScreenId -ne "PORTADA") {
            try { Clear-TailFrom ([Console]::CursorTop) } catch { }
        }
        $script:LastScreenId = "PORTADA"

        $leg = if ($script:InnerW -ge 72) {
            "  ● En línea   ~ Iniciando   ✗ Caído     (actualizado en segundo plano)"
        } else {
            "  ● En línea   ~ Iniciando   ✗ Caído"
        }
        Write-CleanLine $leg "DarkGray"

        Write-BlankLine
        $agTitle = if ($script:InnerW -ge 70) { "RECORRIDO (15 DIAPOSITIVAS) · ELIGE SECCIÓN [1-6]" } else { "RECORRIDO (15 SLIDES) · PULSA [1-6]" }
        Write-BoxTop $agTitle "DarkCyan"
        $colL = [int][Math]::Floor(($script:InnerW - 3) / 2)
        $colR = $script:InnerW - 3 - $colL
        $agItems = if ($script:InnerW -ge 74) {
            @(
                @("[1]", "Arquitectura y Docker",  "(01-02)", "[4]", "Lecturas Réplica/RYOW", "(07-08)"),
                @("[2]", "Eureka y Balanceo HTTP", "(03-04)", "[5]", "Caídas: App y Postgres","(09-14)"),
                @("[3]", "Transferencia P2P ACID", "(05-06)", "[6]", "Conclusiones Técnicas", "   (15)")
            )
        } else {
            @(
                @("[1]", "Arquitectura",    "(01-02)", "[4]", "Lecturas y RYOW", "(07-08)"),
                @("[2]", "Eureka/Balanceo", "(03-04)", "[5]", "Fallos App/BD",   "(09-14)"),
                @("[3]", "P2P Transf ACID", "(05-06)", "[6]", "Conclusiones",    "   (15)")
            )
        }
        $tW1 = [Math]::Max(8, $colL - 11)
        $tW2 = [Math]::Max(8, $colR - 11)
        foreach ($ar in $agItems) {
            Write-Host ($script:Margin + "│ ") -ForegroundColor DarkCyan -NoNewline
            Write-Host ($ar[0] + " ") -ForegroundColor Yellow -NoNewline
            Write-Host (Format-Fixed $ar[1] $tW1) -ForegroundColor White -NoNewline
            Write-Host $ar[2] -ForegroundColor DarkGray -NoNewline
            Write-Host " │ " -ForegroundColor DarkGray -NoNewline
            Write-Host ($ar[3] + " ") -ForegroundColor Yellow -NoNewline
            Write-Host (Format-Fixed $ar[4] $tW2) -ForegroundColor White -NoNewline
            Write-Host $ar[5] -ForegroundColor DarkGray -NoNewline
            Write-Host " │" -ForegroundColor DarkCyan -NoNewline
            Complete-Row
        }
        Write-BoxBottom "DarkCyan"

        if (([DateTime]::UtcNow - $lastSalPoll).TotalSeconds -ge 4) {
            $salCached = Get-SaldoInfo
            $lastSalPoll = [DateTime]::UtcNow
        }
        Write-BlankLine
        if ($salCached) {
            $cons = [decimal]$salCached.consumidoHoy
            $sc = if ($cons -eq 0) { "Green" } else { "Yellow" }
            $sTxt = Format-Money $salCached.saldo
            $cTxt = Format-Money $salCached.consumidoHoy
            $lTxt = Format-Money $salCached.limiteDiario
            $acctLine = if ($script:UiW -ge 86) {
                $b = if ($cons -gt 0) { " [REINICIAR CON U->P]" } else { " [LISTO]" }
                ('  Cuenta demo {0} : saldo=${1} | hoy=${2}/${3}{4}' -f $Origen, $sTxt, $cTxt, $lTxt, $b)
            } elseif ($script:UiW -ge 74) {
                $b = if ($cons -gt 0) { " [REINICIAR U->P]" } else { " [LISTO]" }
                ('  Cuenta {0}: saldo=${1} | hoy=${2}/${3}{4}' -f $Origen, $sTxt, $cTxt, $lTxt, $b)
            } else {
                $b = if ($cons -gt 0) { " [U->P]" } else { " [LISTO]" }
                ('  {0}: saldo=${1} | hoy=${2}/${3}{4}' -f $Origen, $sTxt, $cTxt, $lTxt, $b)
            }
            Write-CleanLine $acctLine $sc
        } elseif (-not (Test-Path (Join-Path $RepoDir ".env"))) {
            Write-CleanLine "  [AVISO] Gateway sin respuesta y falta .env -> [U] -> [C] / [P]" "Yellow"
        } else {
            Write-CleanLine "  Gateway :8080 sin conexión -> Pulsa [U] para iniciar servicios" "DarkGray"
        }

        Write-Divider
        $startPrompt = if ($script:UiW -ge 68) { "  ► [ESPACIO / ENTER] Iniciar Presentación (Diapositiva 1/15)" } else { "  ► [ESPACIO/→] Iniciar Presentación (1/15)" }
        $navPrompt   = if ($script:UiW -ge 84) {
            "    Atajos: [1-6] Sección  [B] Eureka  [U] Utilidades  [?] Ayuda  [Q] Salir"
        } elseif ($script:UiW -ge 72) {
            "    [1-6] Sec  [B] Eureka  [U] Utils  [?] Ayuda  [Q] Salir"
        } else {
            "    [1-6] Sec  [B] Eur  [U] Util  [?] Ayuda  [Q] Salir"
        }
        Write-CleanLine $startPrompt "Green"
        Write-CleanLine $navPrompt "DarkGray"
        End-Frame

        $act = Read-SlideKeyLive $true
        $res = "PORTADA"
        switch ($act) {
            "RESIZE"       { continue }
            "HELP"         { Show-HelpModal; $lastSalPoll = [DateTime]::MinValue }
            "QUIT"         { return }
            "EUREKA"       { Open-EurekaBrowser }
            "DOCK_REFRESH" { Update-DockInPlace (Get-ContainerMapSync) }
            "PREP"         { Show-CleanPrep; $lastSalPoll = [DateTime]::MinValue }
            "UTILS" {
                $u = Show-UtilsPanel
                $script:FirstFrame = $true
                $lastSalPoll = [DateTime]::MinValue
                if ($u -eq "QUIT") { return }
                if ($u -match '^B[1-6]$') { $res = Run-Deck $blockMap[$u] }
            }
            default {
                if ($act -match '^B[1-6]$') {
                    $res = Run-Deck $blockMap[$act]
                } elseif ($act -eq "NEXT" -or $act -eq "REPEAT") {
                    $res = Run-Deck 0
                }
                $lastSalPoll = [DateTime]::MinValue
            }
        }
        if ($res -eq "QUIT") { return }
    }
}

try {
    Show-Portada
} finally {
    Invoke-Cleanup
}
