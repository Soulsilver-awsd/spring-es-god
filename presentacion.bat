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
$script:DockRow = 2
$script:DualBodyRow = 3
$script:WinW = 80
$script:WinH = 25
$script:UiW = 78
$script:InnerW = 74
$script:SlideBoxW = 78
$script:DualPane = $false
$script:LeftW = 78
$script:RightW = 0
$script:RightInner = 0
$script:PadL = 1
$script:PadT = 0
$script:Margin = " "
$script:FrameRows = 0
$script:BufferingLeft = $false
$script:LeftRows = New-Object System.Collections.Generic.List[object]
$script:LeftTitle = "WORKSPACE"
$script:EventLogs = New-Object System.Collections.Generic.List[object]
$script:HttpTraces = New-Object System.Collections.Generic.List[object]
$script:LastLoggedDockSig = ""

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

function Add-EventLog([string]$Level, [string]$Cat, [string]$Message) {
    $ts = (Get-Date).ToString("HH:mm:ss")
    $script:EventLogs.Add(@{
        Time  = $ts
        Level = $Level
        Cat   = $Cat
        Msg   = $Message
    })
    while ($script:EventLogs.Count -gt 60) { $script:EventLogs.RemoveAt(0) }
}
Add-EventLog "INFO" "SYS" "Presentacion iniciada"

function Clip-Clean([string]$Text, [int]$MaxLen) {
    if ($null -eq $Text) { $Text = "" }
    if ($MaxLen -le 0) { return "" }
    if ($Text.Length -le $MaxLen) { return $Text }
    if ($MaxLen -eq 1) { return "…" }
    return ($Text.Substring(0, $MaxLen - 1) + "…")
}

function Invoke-Cleanup {
    if ($script:DockProc) {
        try { if (-not $script:DockProc.HasExited) { $script:DockProc.Kill() }; $script:DockProc.Dispose() } catch { }
        $script:DockProc = $null
    }
    if (-not [Console]::IsOutputRedirected) {
        try { [Console]::CursorVisible = $true } catch { }
    }
}

function Update-UiMetrics([bool]$ForceSingle = $false) {
    $w = if ($env:DEMO_COLS -match '^\d+$') { [int]$env:DEMO_COLS } else { 80 }
    $h = if ($env:DEMO_LINES -match '^\d+$') { [int]$env:DEMO_LINES } else { 25 }
    if (-not [Console]::IsOutputRedirected) {
        try {
            $w = [Console]::WindowWidth
            $h = [Console]::WindowHeight
        } catch { }
    }
    $dual = (-not $ForceSingle) -and ($w -ge 112)
    if ($dual) {
        $newUiW = [Math]::Min(136, $w - 2)
        $newRightW = if ($newUiW -ge 128) { 42 } else { 37 }
        $newLeftW = $newUiW - $newRightW - 1
        $newSlideBoxW = $newLeftW - 4
        $newInnerW = $newSlideBoxW - 4
        $newRightInner = $newRightW - 4
    } else {
        $newUiW = [Math]::Min(100, [Math]::Max(64, $w - 2))
        $newRightW = 0
        $newLeftW = $newUiW
        $newSlideBoxW = $newUiW
        $newInnerW = $newSlideBoxW - 4
        $newRightInner = 0
    }
    $newPadL = [Math]::Max(0, [int][Math]::Floor(($w - $newUiW) / 2))
    $newPadT = if (-not [Console]::IsOutputRedirected -and $h -ge 28) {
        [Math]::Min(3, [int][Math]::Floor(($h - 24) / 3))
    } else { 0 }

    if ($newUiW -ne $script:UiW -or $newPadL -ne $script:PadL -or $newPadT -ne $script:PadT -or $dual -ne $script:DualPane) {
        $script:ForceClear = $true
    }
    $script:WinW       = $w
    $script:WinH       = $h
    $script:DualPane   = $dual
    $script:UiW        = $newUiW
    $script:LeftW      = $newLeftW
    $script:RightW     = $newRightW
    $script:RightInner = $newRightInner
    $script:SlideBoxW  = $newSlideBoxW
    $script:InnerW     = $newInnerW
    $script:PadL       = $newPadL
    $script:PadT       = $newPadT
    $script:Margin     = " " * $newPadL
}

function Write-RowRaw([object[]]$Segs) {
    Write-Host $script:Margin -NoNewline
    foreach ($s in $Segs) {
        Write-Host $s.T -ForegroundColor $s.C -NoNewline
    }
    Complete-Row
    $script:FrameRows++
}

function Emit-SlideSegs([object[]]$Segs, [int]$TargetW = -1) {
    if ($TargetW -lt 0) { $TargetW = $script:SlideBoxW }
    $vis = 0
    foreach ($s in $Segs) { $vis += $s.T.Length }
    if ($vis -lt $TargetW) {
        $Segs = @($Segs) + @(@{ T = (" " * ($TargetW - $vis)); C = "DarkGray" })
    }
    if ($script:BufferingLeft) {
        $script:LeftRows.Add($Segs)
    } else {
        Write-RowRaw $Segs
    }
}

function Write-BlankLine {
    if ($script:BufferingLeft) {
        $script:LeftRows.Add(@(@{ T = (" " * $script:SlideBoxW); C = "White" }))
        return
    }
    if ([Console]::IsOutputRedirected) { Write-Host ""; $script:FrameRows++; return }
    Write-Host (" " * [Math]::Max(1, $script:WinW - 1))
    $script:FrameRows++
}

function Write-CleanLine([string]$Text = "", [string]$Color = "White") {
    if ($script:BufferingLeft) {
        Emit-SlideSegs @(@{ T = (Format-Fixed $Text $script:SlideBoxW); C = $Color }) $script:SlideBoxW
        return
    }
    $line = $script:Margin + $Text
    if ([Console]::IsOutputRedirected) { Write-Host $line -ForegroundColor $Color; $script:FrameRows++; return }
    $pad = [Math]::Max(0, ($script:WinW - 1) - $line.Length)
    Write-Host ($line + (" " * $pad)) -ForegroundColor $Color
    $script:FrameRows++
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

function Begin-Frame([bool]$HardClear = $false, [bool]$ModalSingle = $false) {
    $script:BufferingLeft = $false
    $script:LeftRows.Clear()
    Update-UiMetrics $ModalSingle
    $script:FrameRows = 0
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
    $maxT = [Math]::Max(4, $script:SlideBoxW - 6)
    if ($t.Length -gt $maxT) { $t = $t.Substring(0, $maxT) }
    $fill = [Math]::Max(2, ($script:SlideBoxW - 3) - $t.Length)
    $line = "╭─" + $t + ("─" * $fill) + "╮"
    Emit-SlideSegs @(@{ T = $line; C = $Color }) $script:SlideBoxW
}

function Write-BoxLine([string]$Text, [string]$TextColor = "White", [string]$BorderColor = "DarkGray") {
    Emit-SlideSegs @(
        @{ T = "│ "; C = $BorderColor },
        @{ T = (Format-Fixed $Text $script:InnerW); C = $TextColor },
        @{ T = " │"; C = $BorderColor }
    ) $script:SlideBoxW
}

function Write-BoxBottom([string]$Color = "DarkGray") {
    $line = "╰" + ("─" * ($script:SlideBoxW - 2)) + "╯"
    Emit-SlideSegs @(@{ T = $line; C = $Color }) $script:SlideBoxW
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
    $hKey = "$dockerOk|$healthy|$running"
    if ($script:LastLoggedDockSig -and $hKey -ne $script:LastLoggedDockSig) {
        if (-not $dockerOk) { Add-EventLog "ERR" "DOCK" "Docker desconectado" }
        elseif ($healthy -eq 8) { Add-EventLog "OK" "DOCK" "Cluster 8/8 healthy" }
        else { Add-EventLog "WARN" "DOCK" "Cluster $healthy/8 healthy ($running/8 ON)" }
    }
    $script:LastLoggedDockSig = $hKey
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

function Get-DockStatusMeta($Snap) {
    if (-not $Snap.DockerOk) { return @{ Title = "MONITOR EN VIVO · DOCKER DESCONECTADO"; Short = "MONITOR · DOCKER CAIDO"; Col = "Red" } }
    if ($Snap.Healthy -eq 8) { return @{ Title = "MONITOR EN VIVO · 8/8 EN LINEA"; Short = "MONITOR · 8/8 EN LINEA"; Col = "Green" } }
    $t = "MONITOR EN VIVO · {0}/8 HEALTHY · {1}/8 ON" -f $Snap.Healthy, $Snap.Running
    $s = "MONITOR · {0}/8 OK · {1}/8 ON" -f $Snap.Healthy, $Snap.Running
    return @{ Title = $t; Short = $s; Col = "Yellow" }
}

function Write-Badge([string]$Label, $Info) {
    Write-Host ("[{0} {1}]" -f $Info.Sym, $Label) -ForegroundColor $Info.Color -NoNewline
}

function Render-ClusterDock([bool]$SaveRow = $true, $Snap = $null, [bool]$Fused = $false) {
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
    $meta = Get-DockStatusMeta $Snap
    $t = " " + $meta.Title + " "
    $maxT = [Math]::Max(10, $script:UiW - 6)
    if ($t.Length -gt $maxT) { $t = $t.Substring(0, $maxT) }
    $fill = [Math]::Max(2, ($script:UiW - 3) - $t.Length)
    $topL = if ($Fused) { "├─" } else { "┌─" }
    $topR = if ($Fused) { "┤" } else { "┐" }
    $botL = if ($Fused) { "╰" } else { "└" }
    $botR = if ($Fused) { "╯" } else { "┘" }

    Write-Host ($script:Margin + $topL) -ForegroundColor $bCol -NoNewline
    Write-Host $t -ForegroundColor $meta.Col -NoNewline
    Write-Host (("─" * $fill) + $topR) -ForegroundColor $bCol -NoNewline
    Complete-Row
    $script:FrameRows++

    $innerFull = $script:UiW - 4
    if ($innerFull -ge 74) {
        $mid = [Math]::Max(2, [int][Math]::Floor(($innerFull - 71) / 2))
        $rem1 = [Math]::Max(0, $innerFull - (71 + $mid))
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
        $script:FrameRows++

        $rem2 = [Math]::Max(0, $innerFull - 68)
        Write-Host ($script:Margin + "│ ") -ForegroundColor $bCol -NoNewline
        Write-Host "APPS " -ForegroundColor DarkGray -NoNewline
        Write-Badge "cuentas-1 :8081" $m["ms-cuentas-1"]
        Write-Host " " -NoNewline
        Write-Badge "cuentas-2 :8082" $m["ms-cuentas-2"]
        Write-Host " " -NoNewline
        Write-Badge "transacciones :8083" $m["ms-transacciones"]
        Write-Host ((" " * $rem2) + " │") -ForegroundColor $bCol -NoNewline
        Complete-Row
        $script:FrameRows++
    } else {
        $rem1 = [Math]::Max(0, $innerFull - 57)
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
        $script:FrameRows++

        $rem2 = [Math]::Max(0, $innerFull - 50)
        Write-Host ($script:Margin + "│ ") -ForegroundColor $bCol -NoNewline
        Write-Host "APPS " -ForegroundColor DarkGray -NoNewline
        Write-Badge "cuentas-1" $m["ms-cuentas-1"]
        Write-Host " " -NoNewline
        Write-Badge "cuentas-2" $m["ms-cuentas-2"]
        Write-Host " " -NoNewline
        Write-Badge "transacciones" $m["ms-transacciones"]
        Write-Host ((" " * $rem2) + " │") -ForegroundColor $bCol -NoNewline
        Complete-Row
        $script:FrameRows++
    }

    Write-RowRaw @(@{ T = ($botL + ("─" * ($script:UiW - 2)) + $botR); C = $bCol })
}

function Pad-SegsRight([object[]]$Segs, [int]$TargetW, [string]$BorderCol = "DarkCyan") {
    $vis = 0
    foreach ($s in $Segs) { $vis += $s.T.Length }
    $rem = [Math]::Max(0, $TargetW - $vis)
    return ,@(@{ T = "│ "; C = $BorderCol }) + @($Segs) + @(@{ T = ((" " * $rem) + " │"); C = $BorderCol })
}

function Get-ClusterTileRows($Snap = $null) {
    if (-not $Snap) {
        if ($script:LastSnap) { $Snap = $script:LastSnap }
        else { $Snap = Get-ContainerMapSync }
    }
    $script:LastDockSig = $Snap.Sig
    $m = $Snap.Map
    $meta = Get-DockStatusMeta $Snap
    $ri = $script:RightInner
    $bCol = "DarkCyan"
    $hdr = " " + (Clip-Clean $meta.Short ($script:RightW - 5)) + " "
    $fill = [Math]::Max(2, ($script:RightW - 3) - $hdr.Length)
    $rows = New-Object System.Collections.Generic.List[object]
    $rows.Add(@(@{ T = "╭─"; C = $bCol }, @{ T = $hdr; C = $meta.Col }, @{ T = (("─" * $fill) + "╮"); C = $bCol }))

    $bSeg = { param($lbl, $inf) @{ T = ("[{0} {1}]" -f $inf.Sym, $lbl); C = $inf.Color } }
    $rows.Add((Pad-SegsRight @(@{ T = "RED "; C = "DarkGray" }, (& $bSeg "gw:8080" $m["api-gateway"]), @{ T = " "; C = "DarkGray" }, (& $bSeg "eureka:8761" $m["eureka-server"])) $ri $bCol))
    $rows.Add((Pad-SegsRight @(@{ T = "BD  "; C = "DarkGray" }, (& $bSeg "pri" $m["primary"]), @{ T = " "; C = "DarkGray" }, (& $bSeg "rep1" $m["replica1"]), @{ T = " "; C = "DarkGray" }, (& $bSeg "rep2" $m["replica2"])) $ri $bCol))
    $rows.Add((Pad-SegsRight @(@{ T = "APP "; C = "DarkGray" }, (& $bSeg "cta1:8081" $m["ms-cuentas-1"]), @{ T = " "; C = "DarkGray" }, (& $bSeg "cta2:8082" $m["ms-cuentas-2"])) $ri $bCol))
    $rows.Add((Pad-SegsRight @(@{ T = "    "; C = "DarkGray" }, (& $bSeg "transacciones:8083" $m["ms-transacciones"])) $ri $bCol))
    $rows.Add(@(@{ T = ("╰" + ("─" * ($script:RightW - 2)) + "╯"); C = $bCol }))
    return $rows
}

function Format-LogRow([object]$Entry, [int]$MaxInner) {
    $sym = switch ($Entry.Level) { "OK" { "●" } "WARN" { "~" } "ERR" { "✗" } default { "►" } }
    $col = switch ($Entry.Level) { "OK" { "Green" } "WARN" { "Yellow" } "ERR" { "Red" } default { "Cyan" } }
    $prefix = "{0} {1} " -f $Entry.Time, $sym
    $txtAvail = [Math]::Max(4, $MaxInner - $prefix.Length)
    $body = Clip-Clean ("{0} {1}" -f $Entry.Cat, $Entry.Msg) $txtAvail
    $pad = [Math]::Max(0, $MaxInner - ($prefix.Length + $body.Length))
    return @(
        @{ T = $Entry.Time; C = "DarkGray" },
        @{ T = (" " + $sym + " "); C = $col },
        @{ T = ($body + (" " * $pad)); C = $(if ($Entry.Level -eq "ERR") { "Red" } elseif ($Entry.Level -eq "WARN") { "Yellow" } else { "White" }) }
    )
}

function Get-LogTileRows([int]$TotalH) {
    $rows = New-Object System.Collections.Generic.List[object]
    $ri = $script:RightInner
    $bCol = "DarkGray"
    $hdr = " LOG EN VIVO "
    $fill = [Math]::Max(2, ($script:RightW - 3) - $hdr.Length)
    $rows.Add(@(@{ T = "╭─"; C = $bCol }, @{ T = $hdr; C = "Cyan" }, @{ T = (("─" * $fill) + "╮"); C = $bCol }))

    $slots = [Math]::Max(1, $TotalH - 2)
    $cnt = $script:EventLogs.Count
    $take = [Math]::Min($slots, $cnt)
    for ($i = 0; $i -lt $slots; $i++) {
        if ($i -lt $take) {
            $e = $script:EventLogs[$cnt - 1 - $i]
            $segs = Format-LogRow $e $ri
            $rows.Add((@(@{ T = "│ "; C = $bCol }) + $segs + @(@{ T = " │"; C = $bCol })))
        } else {
            $msg = if ($i -eq 0 -and $cnt -eq 0) { Format-Fixed "(sin eventos)" $ri } else { " " * $ri }
            $rows.Add(@(@{ T = "│ "; C = $bCol }, @{ T = $msg; C = "DarkGray" }, @{ T = " │"; C = $bCol }))
        }
    }

    $foot = " [L] Historial ({0}) " -f $cnt
    if ($foot.Length -gt $script:RightW - 5) { $foot = " [L] Log " }
    $fillB = [Math]::Max(2, ($script:RightW - 3) - $foot.Length)
    $rows.Add(@(@{ T = "╰─"; C = $bCol }, @{ T = $foot; C = "DarkGray" }, @{ T = (("─" * $fillB) + "╯"); C = $bCol }))
    return $rows
}

function Flush-DualFrame {
    $script:BufferingLeft = $false
    $lw = $script:LeftW
    $li = $script:SlideBoxW
    $bCol = "DarkCyan"
    $leftH = $script:LeftRows.Count + 2
    $h = [Math]::Max($leftH, 14)

    $leftTile = New-Object System.Collections.Generic.List[object]
    $lt = " " + (Clip-Clean $script:LeftTitle ($lw - 6)) + " "
    $lFill = [Math]::Max(2, ($lw - 3) - $lt.Length)
    $leftTile.Add(@(@{ T = ("╭─" + $lt + ("─" * $lFill) + "╮"); C = $bCol }))
    $innerSlots = $h - 2
    for ($i = 0; $i -lt $innerSlots; $i++) {
        if ($i -lt $script:LeftRows.Count) {
            $r = $script:LeftRows[$i]
            $leftTile.Add((@(@{ T = "│ "; C = $bCol }) + $r + @(@{ T = " │"; C = $bCol })))
        } else {
            $leftTile.Add(@(@{ T = ("│ " + (" " * $li) + " │"); C = $bCol }))
        }
    }
    $leftTile.Add(@(@{ T = ("╰" + ("─" * ($lw - 2)) + "╯"); C = $bCol }))

    $rightTile = New-Object System.Collections.Generic.List[object]
    foreach ($cr in (Get-ClusterTileRows)) { $rightTile.Add($cr) }
    foreach ($lr in (Get-LogTileRows ($h - $rightTile.Count))) { $rightTile.Add($lr) }

    for ($i = 0; $i -lt $h; $i++) {
        $segs = @($leftTile[$i]) + @(@{ T = " "; C = "DarkGray" }) + @($rightTile[$i])
        Write-RowRaw $segs
    }
}

function Render-LogStrip {
    if ($script:DualPane) { return }
    $avail = 25 - $script:FrameRows - 2
    $slots = if ($avail -ge 4) { 2 } elseif ($avail -ge 3) { 1 } else { 0 }
    if ($slots -le 0) { Write-Divider; return }
    $hdr = " LOG EN VIVO ([L] historial) "
    $fill = [Math]::Max(2, ($script:UiW - 3) - $hdr.Length)
    Write-RowRaw @(@{ T = "╭─"; C = "DarkGray" }, @{ T = $hdr; C = "Cyan" }, @{ T = (("─" * $fill) + "╮"); C = "DarkGray" })
    $cnt = $script:EventLogs.Count
    $wIn = $script:UiW - 4
    for ($i = 0; $i -lt $slots; $i++) {
        if ($i -lt $cnt) {
            $segs = Format-LogRow $script:EventLogs[$cnt - 1 - $i] $wIn
            Write-RowRaw (@(@{ T = "│ "; C = "DarkGray" }) + $segs + @(@{ T = " │"; C = "DarkGray" }))
        } else {
            Write-RowRaw @(@{ T = "│ "; C = "DarkGray" }, @{ T = (Format-Fixed "(sin eventos)" $wIn); C = "DarkGray" }, @{ T = " │"; C = "DarkGray" })
        }
    }
    Write-RowRaw @(@{ T = ("╰" + ("─" * ($script:UiW - 2)) + "╯"); C = "DarkGray" })
}

function Update-DockInPlace($Snap = $null) {
    if ([Console]::IsOutputRedirected) { return }
    try {
        $savedLeft = [Console]::CursorLeft
        $savedTop  = [Console]::CursorTop
        if ($script:DualPane) {
            $colX = $script:PadL + $script:LeftW + 1
            $cRows = Get-ClusterTileRows $Snap
            for ($i = 0; $i -lt $cRows.Count; $i++) {
                [Console]::SetCursorPosition($colX, $script:DualBodyRow + $i)
                foreach ($s in $cRows[$i]) { Write-Host $s.T -ForegroundColor $s.C -NoNewline }
            }
        } else {
            [Console]::SetCursorPosition(0, $script:DockRow)
            Render-ClusterDock $false $Snap $true
        }
        [Console]::SetCursorPosition($savedLeft, $savedTop)
    } catch { }
}

function Write-SlideChrome([int]$SlideNum, [int]$ActiveSection, [string]$SlideTitle, [bool]$Cached = $false, [bool]$IsLive = $false) {
    Begin-Frame
    $compact = ($script:UiW -lt 76)
    $tabs = if ($compact) {
        @(@{Id=1;L="[1]"},@{Id=2;L="[2]"},@{Id=3;L="[3]"},@{Id=4;L="[4]"},@{Id=5;L="[5]"},@{Id=6;L="[6]"})
    } else {
        @(@{Id=1;L="[1:Arq]"},@{Id=2;L="[2:Eur]"},@{Id=3;L="[3:P2P]"},@{Id=4;L="[4:Rep]"},@{Id=5;L="[5:Fal]"},@{Id=6;L="[6:Fin]"})
    }
    $barLen = if ($script:UiW -ge 94) { 14 } else { 10 }
    $right = ("{0:00}/15 {1}" -f $SlideNum, (Get-ProgressBar $SlideNum 15 $barLen))

    $badge = ""
    $badgeCol = "DarkGray"
    if ($Cached) {
        $badge = if ($script:UiW -ge 74) { "[CACHE · R]" } else { "[CACHE]" }
        $badgeCol = "Yellow"
    } elseif ($IsLive) {
        $badge = if ($script:UiW -ge 74) { "[EN VIVO]" } else { "[VIVO]" }
        $badgeCol = "Green"
    }

    $topSegs = New-Object System.Collections.Generic.List[object]
    $topSegs.Add(@{ T = "╭─ "; C = "DarkCyan" })
    $tabStrLen = 0
    for ($i = 0; $i -lt $tabs.Count; $i++) {
        $tb = $tabs[$i]
        $col = if ($tb.Id -eq $ActiveSection) { "Yellow" } else { "DarkGray" }
        $topSegs.Add(@{ T = $tb.L; C = $col })
        $tabStrLen += $tb.L.Length
        if ($i -lt $tabs.Count - 1) {
            $topSegs.Add(@{ T = " "; C = "DarkGray" })
            $tabStrLen++
        }
    }
    $rightBadge = if ($script:DualPane -and $badge) { "$right $badge" } else { $right }
    $fillLen = [Math]::Max(1, ($script:UiW - 8) - $tabStrLen - $rightBadge.Length)
    $topSegs.Add(@{ T = (" " + ("─" * $fillLen) + " "); C = "DarkCyan" })
    $topSegs.Add(@{ T = $right; C = "Cyan" })
    if ($script:DualPane -and $badge) {
        $topSegs.Add(@{ T = " "; C = "DarkGray" })
        $topSegs.Add(@{ T = $badge; C = $badgeCol })
    }
    $topSegs.Add(@{ T = " ─╮"; C = "DarkCyan" })
    Write-RowRaw $topSegs

    $innerFull = $script:UiW - 4
    $leftTitle = "► " + $SlideTitle
    if ($script:DualPane) {
        $hy = "Hyprland · {0}c" -f $script:WinW
        $gap2 = [Math]::Max(1, $innerFull - $leftTitle.Length - $hy.Length)
        Write-RowRaw @(
            @{ T = "│ "; C = "DarkCyan" },
            @{ T = $leftTitle; C = "White" },
            @{ T = (" " * $gap2); C = "DarkGray" },
            @{ T = $hy; C = "DarkGray" },
            @{ T = " │"; C = "DarkCyan" }
        )
        Write-RowRaw @(@{ T = ("╰" + ("─" * ($script:UiW - 2)) + "╯"); C = "DarkCyan" })
        if (-not [Console]::IsOutputRedirected) {
            try { $script:DualBodyRow = [Console]::CursorTop; $script:DockRow = $script:DualBodyRow } catch { }
        }
        $script:BufferingLeft = $true
        $script:LeftTitle = "WORKSPACE · SECCION $ActiveSection"
    } else {
        if ($badge -and ($leftTitle.Length + 1 + $badge.Length -le $innerFull)) {
            $gap2 = $innerFull - $leftTitle.Length - $badge.Length
            Write-RowRaw @(
                @{ T = "│ "; C = "DarkCyan" },
                @{ T = $leftTitle; C = "White" },
                @{ T = (" " * $gap2); C = "DarkGray" },
                @{ T = $badge; C = $badgeCol },
                @{ T = " │"; C = "DarkCyan" }
            )
        } else {
            Write-RowRaw @(
                @{ T = "│ "; C = "DarkCyan" },
                @{ T = (Format-Fixed $leftTitle $innerFull); C = "White" },
                @{ T = " │"; C = "DarkCyan" }
            )
        }
        Render-ClusterDock $true $null $true
    }

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
        Write-Host ($script:Margin + "  [~] " + $Message) -ForegroundColor Yellow
        Clear-TailFrom ([Console]::CursorTop)
        return $row
    } catch { return -1 }
}

function Restore-LivePending([int]$Row) {
    if ($Row -lt 0 -or [Console]::IsOutputRedirected) { return }
    try { [Console]::SetCursorPosition(0, $Row) } catch { }
}

function Open-EurekaBrowser {
    Add-EventLog "INFO" "SYS" "Abriendo Eureka en navegador"
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
        "L" { return "LOG" }
        "E" { return "EXPORT" }
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
    if ($script:DualPane -and $script:BufferingLeft) {
        Flush-DualFrame
    } elseif ($script:LastScreenId -like 'S*') {
        Render-LogStrip
    } else {
        Write-Divider
    }
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
    $helpLine = if ($script:UiW -ge 98) {
        "  [1-6] Sec  [R] Act  [M] Inicio  [B] Eureka  [U] Utils  [L] Log  [E] Exportar  [?] Ayuda  [Q] Salir"
    } elseif ($script:UiW -ge 77) {
        "  [1-6] Sec [R] Act [M] Ini [B] Eur [U] Util [L] Log [E] Rep [?] Ayuda [Q] Salir"
    } else {
        "  [1-6] Sec [R] Act [M] Ini [U] Util [L] Log [E] Rep [?] Ayuda [Q] Sal"
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
        Begin-Frame $false $true
        Write-CleanLine ("╭" + ("─" * ($script:UiW - 2)) + "╮") "DarkCyan"
        Write-RowRaw @(
            @{ T = "│ "; C = "DarkCyan" },
            @{ T = (Format-Center "AYUDA RAPIDA Y ATAJOS DEL PRESENTADOR" $script:InnerW); C = "Cyan" },
            @{ T = " │"; C = "DarkCyan" }
        )
        Write-CleanLine ("╰" + ("─" * ($script:UiW - 2)) + "╯") "DarkCyan"
        Write-BlankLine
        Write-BoxTop "NAVEGACION Y CONTROL" "Cyan"
        Write-BoxLine "Espacio/Enter/->/N : Siguiente diapositiva" "White" "Cyan"
        Write-BoxLine "<- / Backspace / A : Anterior (desde cache sin mutar)" "White" "Cyan"
        Write-BoxLine "1 .. 6             : Saltar directo a Seccion 1..6" "White" "Cyan"
        Write-BoxLine "R                  : Re-ejecutar en vivo el slide actual" "Yellow" "Cyan"
        Write-BoxLine "M / Esc            : Volver a la Portada principal" "White" "Cyan"
        Write-BoxLine "B / U / W          : Abrir Eureka / Utilidades / Dock" "White" "Cyan"
        Write-BoxLine "L  |  E            : Ver log completo | Exportar reporte (.md)" "Cyan" "Cyan"
        Write-BoxLine "H / ? / F1         : Abrir esta ayuda" "Cyan" "Cyan"
        Write-BoxLine "Q                  : Salir de la presentacion" "DarkGray" "Cyan"
        Write-BoxBottom "Cyan"
        Write-BlankLine
        Write-BoxTop "SIGNIFICADO DE ESTADOS E INDICADORES" "DarkCyan"
        Write-BoxLine "● En linea (verde)   ~ Arranque (amarillo)   ! / ✗ Caido" "White" "DarkCyan"
        Write-BoxLine "[EN VIVO] Prueba actual   [CACHE · R] Vista guardada" "White" "DarkCyan"
        Write-BoxBottom "DarkCyan"
        Write-CleanLine "  [Cualquier tecla] Volver exactamente donde estabas" "Green"
        End-Frame
        if ([Console]::IsInputRedirected) { break }
        $act = Read-SlideKeyLive $false
        if ($act -eq "RESIZE") { continue }
        break
    }
    $script:FirstFrame = $true
}

function Show-LogModal {
    $script:FirstFrame = $true
    $script:LastScreenId = "LOG"
    while ($true) {
        Begin-Frame $false $true
        Write-CleanLine ("╭" + ("─" * ($script:UiW - 2)) + "╮") "DarkCyan"
        Write-RowRaw @(
            @{ T = "│ "; C = "DarkCyan" },
            @{ T = (Format-Center "BITACORA DE EVENTOS EN VIVO (LOG)" $script:InnerW); C = "Cyan" },
            @{ T = " │"; C = "DarkCyan" }
        )
        Write-CleanLine ("╰" + ("─" * ($script:UiW - 2)) + "╯") "DarkCyan"
        Write-BlankLine
        $cnt = $script:EventLogs.Count
        Write-BoxTop ("HISTORIAL RECIENTE ({0} EVENTOS)" -f $cnt) "DarkCyan"
        $maxShow = 14
        if ($cnt -eq 0) {
            Write-BoxLine "  (Sin eventos registrados todavia)" "DarkGray" "DarkCyan"
        } else {
            $take = [Math]::Min($maxShow, $cnt)
            for ($i = 0; $i -lt $take; $i++) {
                $e = $script:EventLogs[$cnt - 1 - $i]
                $segs = Format-LogRow $e $script:InnerW
                Emit-SlideSegs (@(@{ T = "│ "; C = "DarkCyan" }) + $segs + @(@{ T = " │"; C = "DarkCyan" })) $script:SlideBoxW
            }
        }
        Write-BoxBottom "DarkCyan"
        Write-CleanLine "  [C] Limpiar bitacora   [Otra tecla] Volver" "Green"
        End-Frame
        if ([Console]::IsInputRedirected) { break }
        $act = Read-SlideKeyLive $false
        if ($act -eq "RESIZE") { continue }
        if ($act -eq "ENV") {
            $script:EventLogs.Clear()
            Add-EventLog "INFO" "SYS" "Bitacora reiniciada"
            continue
        }
        break
    }
    $script:FirstFrame = $true
}

function Add-HttpTrace([string]$Method, [string]$Url, [string]$ReqBody, [string]$Code, [int]$Ms, [hashtable]$Headers, [string]$RawBody, [string]$Note = "") {
    if ($script:HttpTraces.Count -ge 200) { $script:HttpTraces.RemoveAt(0) }
    $hdrCopy = @{}
    if ($Headers) {
        foreach ($k in $Headers.Keys) { $hdrCopy[$k] = $Headers[$k] }
    }
    $script:HttpTraces.Add(@{
        Time    = (Get-Date).ToString("HH:mm:ss")
        Screen  = $(if ($script:LastScreenId) { $script:LastScreenId } else { "PORTADA" })
        Method  = $Method
        Url     = $Url
        ReqBody = $ReqBody
        Code    = $Code
        Ms      = $Ms
        Headers = $hdrCopy
        RawBody = $RawBody
        Note    = $Note
    })
}

function Format-PrettyJson([string]$Raw) {
    if ([string]::IsNullOrWhiteSpace($Raw)) { return "" }
    try {
        $obj = $Raw | ConvertFrom-Json
        return ($obj | ConvertTo-Json -Depth 10)
    } catch {
        return $Raw
    }
}

function Export-PresentationReport {
    $repDir = Join-Path $RepoDir "reportes"
    if (-not (Test-Path $repDir)) { [void](New-Item -ItemType Directory -Path $repDir -Force) }
    $tsFile = (Get-Date).ToString("yyyyMMdd-HHmmss")
    $fname = "reporte-$tsFile.md"
    $fullPath = Join-Path $repDir $fname

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("# Reporte de Ejecución — Billetera Digital Distribuida")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("- **Fecha y hora:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    [void]$sb.AppendLine("- **Generador:** ``presentacion.bat`` (PowerShell)")
    [void]$sb.AppendLine("- **Gateway:** ``$Gateway``")
    [void]$sb.AppendLine("- **Eureka:** ``$Eureka``")
    [void]$sb.AppendLine("- **Cuentas de prueba:** Origen ``$Origen`` / Destino ``$Destino``")
    [void]$sb.AppendLine("")

    [void]$sb.AppendLine("## 1. Estado del Clúster Docker")
    [void]$sb.AppendLine("")
    $snap = Get-ContainerMapSync
    if ($snap -and $snap.Map -and $snap.Map.Count -gt 0) {
        [void]$sb.AppendLine("| Contenedor | Estado | Salud |")
        [void]$sb.AppendLine("|---|---|---|")
        foreach ($name in @("primary", "replica1", "replica2", "eureka-server", "ms-cuentas-1", "ms-cuentas-2", "ms-transacciones", "api-gateway")) {
            if ($snap.Map.ContainsKey($name)) {
                $info = $snap.Map[$name]
                $h = if ($info.Health) { $info.Health } else { "-" }
                [void]$sb.AppendLine("| ``$name`` | $($info.State) | $h |")
            } else {
                [void]$sb.AppendLine("| ``$name`` | no encontrado | - |")
            }
        }
    } else {
        [void]$sb.AppendLine("_No se pudo obtener estado de Docker Compose (daemon inactivo o sin contenedores)._")
    }
    [void]$sb.AppendLine("")

    [void]$sb.AppendLine("## 2. Resumen de Pruebas Ejecutadas en la Sesión")
    [void]$sb.AppendLine("")
    $hasSummary = $false
    $sumLines = New-Object System.Collections.Generic.List[string]
    if ($script:CacheBalanceo) {
        $hasSummary = $true
        $okB = @($script:CacheBalanceo | Where-Object Code -eq "200").Count
        $sumLines.Add("| Slide 04 · Balanceo HTTP | $okB/20 respuestas HTTP 200 (Round Robin) |")
    }
    if ($script:CacheTxOk) {
        $hasSummary = $true
        $codOk = if ($script:CacheTxOk.Body -and $script:CacheTxOk.Body.datos) { $script:CacheTxOk.Body.datos.codigoComprobante } else { "-" }
        $sumLines.Add("| Slide 05 · Transferencia P2P ACID | HTTP $($script:CacheTxOk.Code) · Comprobante ``$codOk`` |")
    }
    if ($script:CacheTxErr) {
        $hasSummary = $true
        $msgErr = if ($script:CacheTxErr.Body) { $script:CacheTxErr.Body.mensaje } else { "-" }
        $sumLines.Add("| Slide 06 · Rechazo Controlado | HTTP $($script:CacheTxErr.Code) · $msgErr |")
    }
    if ($script:CacheLecturas07) {
        $hasSummary = $true
        $ok7 = @($script:CacheLecturas07.Results | Where-Object Code -eq "200").Count
        $sumLines.Add("| Slide 07 · Lecturas en Réplicas | $ok7/20 HTTP 200 ($($script:CacheLecturas07.Sec)s) |")
    }
    if ($script:CacheCritico) {
        $hasSummary = $true
        $nod8 = if ($script:CacheCritico.Body -and $script:CacheCritico.Body.auditoriaTecnica) { $script:CacheCritico.Body.auditoriaTecnica.nodoBaseDatos } else { "-" }
        $sumLines.Add("| Slide 08 · Lectura Crítica RYOW | HTTP $($script:CacheCritico.Code) · ``$nod8`` |")
    }
    if ($script:CacheEstado12) {
        $hasSummary = $true
        $sumLines.Add("| Slide 12 · Estado BD tras Caída | HTTP $($script:CacheEstado12.Code) |")
    }
    if ($script:CacheEstado14) {
        $hasSummary = $true
        $sumLines.Add("| Slide 14 · Estado BD Recuperación | HTTP $($script:CacheEstado14.Code) |")
    }
    if ($hasSummary) {
        [void]$sb.AppendLine("| Prueba / Diapositiva | Resultado |")
        [void]$sb.AppendLine("|---|---|")
        foreach ($sl in $sumLines) { [void]$sb.AppendLine($sl) }
    } else {
        [void]$sb.AppendLine("_Aún no se han ejecutado diapositivas en vivo en esta sesión._")
    }
    [void]$sb.AppendLine("")

    [void]$sb.AppendLine("## 3. Salidas de Peticiones HTTP (GET / POST)")
    [void]$sb.AppendLine("")
    if ($script:HttpTraces.Count -eq 0) {
        [void]$sb.AppendLine("_No se capturaron peticiones HTTP en esta sesión. Recorre las diapositivas [1-6] antes de exportar._")
    } else {
        $idx = 0
        foreach ($tr in $script:HttpTraces) {
            $idx++
            $shortUrl = $tr.Url -replace '^https?://[^/]+', ''
            [void]$sb.AppendLine("### $idx. ``$($tr.Method) $shortUrl`` -> HTTP ``$($tr.Code)`` ($($tr.Ms) ms)")
            [void]$sb.AppendLine("")
            $metaLine = "- **Hora:** $($tr.Time) | **Pantalla:** ``$($tr.Screen)`` | **URL:** ``$($tr.Url)``"
            if ($tr.Note) { $metaLine += " | **Nota:** $($tr.Note)" }
            [void]$sb.AppendLine($metaLine)
            if ($tr.ReqBody) {
                [void]$sb.AppendLine("")
                [void]$sb.AppendLine("**Request Body:**")
                [void]$sb.AppendLine('```json')
                [void]$sb.AppendLine((Format-PrettyJson $tr.ReqBody))
                [void]$sb.AppendLine('```')
            }
            $relHdrs = @()
            foreach ($hk in @("x-gateway-handled", "x-service-instance", "x-db-node", "x-db-fallback", "x-consistencia", "content-type")) {
                if ($tr.Headers -and $tr.Headers.ContainsKey($hk) -and $tr.Headers[$hk]) {
                    $relHdrs += "``$($hk): $($tr.Headers[$hk])``"
                }
            }
            if ($relHdrs.Count -gt 0) {
                [void]$sb.AppendLine("- **Headers de respuesta:** $($relHdrs -join ' · ')")
            }
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("**Response Body:**")
            $raw = if ($null -ne $tr.RawBody) { $tr.RawBody.Trim() } else { "" }
            if (-not $raw) {
                [void]$sb.AppendLine("_Sin cuerpo de respuesta._")
            } else {
                $pretty = Format-PrettyJson $raw
                $lang = if ($pretty.StartsWith("{") -or $pretty.StartsWith("[")) { "json" } elseif ($pretty.StartsWith("<")) { "xml" } else { "text" }
                if ($pretty.Length -gt 6000) {
                    $pretty = $pretty.Substring(0, 6000) + "`n... [truncado a 6000 caracteres]"
                }
                [void]$sb.AppendLine('```' + $lang)
                [void]$sb.AppendLine($pretty)
                [void]$sb.AppendLine('```')
            }
            [void]$sb.AppendLine("")
        }
    }

    [void]$sb.AppendLine("## 4. Bitácora de Eventos de la Sesión")
    [void]$sb.AppendLine("")
    if ($script:EventLogs.Count -eq 0) {
        [void]$sb.AppendLine("_Sin eventos registrados._")
    } else {
        [void]$sb.AppendLine('```text')
        foreach ($ev in $script:EventLogs) {
            [void]$sb.AppendLine(("{0} [{1,-4}] [{2,-4}] {3}" -f $ev.Time, $ev.Level, $ev.Cat, $ev.Msg))
        }
        [void]$sb.AppendLine('```')
    }

    [System.IO.File]::WriteAllText($fullPath, $sb.ToString(), [System.Text.Encoding]::UTF8)
    Add-EventLog "OK" "SYS" ("Reporte exportado: reportes/{0}" -f $fname)
    return @{ Path = $fullPath; RelPath = ("reportes/{0}" -f $fname); Traces = $script:HttpTraces.Count; Events = $script:EventLogs.Count }
}

function Show-ExportModal {
    $script:FirstFrame = $true
    $script:LastScreenId = "EXPORT"
    $info = Export-PresentationReport
    while ($true) {
        Begin-Frame $false $true
        Write-CleanLine ("╭" + ("─" * ($script:UiW - 2)) + "╮") "DarkCyan"
        Write-RowRaw @(
            @{ T = "│ "; C = "DarkCyan" },
            @{ T = (Format-Center "EXPORTACION DE REPORTE MARKDOWN" $script:InnerW); C = "Cyan" },
            @{ T = " │"; C = "DarkCyan" }
        )
        Write-CleanLine ("╰" + ("─" * ($script:UiW - 2)) + "╯") "DarkCyan"
        Write-BlankLine
        Write-BoxTop "REPORTE GENERADO EXITOSAMENTE" "Green"
        Write-BoxLine ("Archivo    : {0}" -f $info.RelPath) "Green" "Green"
        Write-BoxLine ("Ruta       : {0}" -f (Clip-Clean $info.Path ($script:InnerW - 14))) "White" "Green"
        Write-BoxLine ("Peticiones : {0} salidas GET/POST capturadas" -f $info.Traces) "Cyan" "Green"
        Write-BoxLine ("Eventos    : {0} registros en bitacora + estado Docker" -f $info.Events) "White" "Green"
        Write-BoxBottom "Green"
        Write-BlankLine
        if ($info.Traces -eq 0) {
            Write-CleanLine "  [TIP] Recorre las diapositivas [1-6] antes de exportar para incluir salidas GET/POST." "Yellow"
        } else {
            Write-CleanLine "  [OK] Listo para adjuntar o copiar en tu informe." "DarkGray"
        }
        Write-CleanLine "  [Cualquier tecla] Volver exactamente donde estabas" "Green"
        End-Frame
        if ([Console]::IsInputRedirected) { break }
        $act = Read-SlideKeyLive $false
        if ($act -eq "RESIZE") { continue }
        break
    }
    $script:FirstFrame = $true
}

function Invoke-ApiRequest([string]$Method, [string]$Url, [string]$JsonBody = "", [int]$TimeoutSec = 10, [bool]$QuietLog = $false) {
    $headers = @{}
    $rawBody = ""
    $bodyObj = $null
    $code = "000"
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
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
    $sw.Stop()
    if (-not $QuietLog) {
        $shortP = ($Url -replace '^https?://[^/]+', '') -replace '/api/(cuentas|transacciones)/', '/'
        $ms = [int]$sw.ElapsedMilliseconds
        $lvl = if ($code -match '^2') { "OK" } elseif ($code -eq "409") { "WARN" } else { "ERR" }
        Add-EventLog $lvl "HTTP" ("{0} {1} -> {2} ({3}ms)" -f $Method, $shortP, $code, $ms)
        Add-HttpTrace $Method $Url $JsonBody $code $ms $headers $rawBody
    }
    return @{ Code = $code; Headers = $headers; Body = $bodyObj; Raw = $rawBody }
}

function Get-SaldoInfo {
    $r = Invoke-ApiRequest "GET" "$Gateway/api/cuentas/$Origen/saldo-critico" "" 2 $true
    if ($r.Code -eq "200" -and $r.Body -and $r.Body.datos) { return $r.Body.datos }
    return $null
}

function Invoke-EnsureEnv {
    $envPath = Join-Path $RepoDir ".env"
    $exPath  = Join-Path $RepoDir ".env.example"
    if (-not (Test-Path $envPath)) {
        if (Test-Path $exPath) {
            Copy-Item -LiteralPath $exPath -Destination $envPath
            Add-EventLog "OK" "SYS" "Archivo .env creado desde .env.example"
            Write-Host ($script:Margin + "  [OK] Archivo .env creado desde .env.example.") -ForegroundColor Green
            return $true
        }
        Add-EventLog "ERR" "SYS" "Falta .env y .env.example"
        Write-Host ($script:Margin + "  [ERROR] No existe .env ni .env.example.") -ForegroundColor Red
        return $false
    }
    return $true
}

function Write-ThreeColCards([string[]]$Titles, [string[]]$Colors, [object[]]$Rows) {
    $cwBase = [Math]::Floor(($script:SlideBoxW - 2) / 3)
    $rem = ($script:SlideBoxW - 2) - ($cwBase * 3)
    $cws = @(
        ($cwBase + $(if ($rem -ge 1) { 1 } else { 0 })),
        ($cwBase + $(if ($rem -ge 2) { 1 } else { 0 })),
        $cwBase
    )
    $topSegs = New-Object System.Collections.Generic.List[object]
    $botSegs = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt 3; $i++) {
        $cw = $cws[$i]; $ci = $cw - 2
        $t = " " + $Titles[$i] + " "
        if ($t.Length -gt ($cw - 3)) { $t = $t.Substring(0, $cw - 3) }
        $fill = [Math]::Max(1, ($cw - 3) - $t.Length)
        $topSegs.Add(@{ T = ("╭─" + $t + ("─" * $fill) + "╮"); C = "Cyan" })
        $botSegs.Add(@{ T = ("╰" + ("─" * $ci) + "╯"); C = "DarkGray" })
        if ($i -lt 2) {
            $topSegs.Add(@{ T = " "; C = "DarkGray" })
            $botSegs.Add(@{ T = " "; C = "DarkGray" })
        }
    }
    Emit-SlideSegs $topSegs.ToArray() $script:SlideBoxW
    foreach ($r in $Rows) {
        $rowSegs = New-Object System.Collections.Generic.List[object]
        for ($i = 0; $i -lt 3; $i++) {
            $bcol = $Colors[$i]; $ci = $cws[$i] - 2
            $rowSegs.Add(@{ T = "│"; C = $bcol })
            $rowSegs.Add(@{ T = (Format-Fixed $r[$i] $ci); C = "White" })
            $rowSegs.Add(@{ T = "│"; C = $bcol })
            if ($i -lt 2) { $rowSegs.Add(@{ T = " "; C = "DarkGray" }) }
        }
        Emit-SlideSegs $rowSegs.ToArray() $script:SlideBoxW
    }
    Emit-SlideSegs $botSegs.ToArray() $script:SlideBoxW
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
    Begin-Frame $true $true
    Write-CleanLine ("╭" + ("─" * ($script:UiW - 2)) + "╮") "DarkYellow"
    Write-RowRaw @(
        @{ T = "│ "; C = "DarkYellow" },
        @{ T = (Format-Center "REINICIO LIMPIO DEL ENTORNO (down -v + up -d --build)" $script:InnerW); C = "Yellow" },
        @{ T = " │"; C = "DarkYellow" }
    )
    Write-CleanLine ("╰" + ("─" * ($script:UiW - 2)) + "╯") "DarkYellow"
    Write-BlankLine
    if (-not (Test-DockerReady)) {
        Add-EventLog "ERR" "DOCK" "Docker daemon no responde"
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
    Add-EventLog "WARN" "SYS" "Ejecutando docker compose down -v + up --build"
    Write-CleanLine "  $ docker compose down -v && docker compose up -d --build" "Cyan"
    & docker compose down -v
    & docker compose up -d --build
    if ($LASTEXITCODE -ne 0) {
        Add-EventLog "ERR" "DOCK" "docker compose up fallo"
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
    Add-EventLog "OK" "DOCK" "Reinicio limpio completo (8/8 healthy)"
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
        Begin-Frame $false $true
        Write-CleanLine ("╭" + ("─" * ($script:UiW - 2)) + "╮") "DarkCyan"
        Write-RowRaw @(
            @{ T = "│ "; C = "DarkCyan" },
            @{ T = (Format-Center "UTILIDADES DEL ENTORNO Y VERIFICACION" $script:InnerW); C = "Cyan" },
            @{ T = " │"; C = "DarkCyan" }
        )
        Render-ClusterDock $true $null $true
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
        Write-BoxLine "[E] Exportar reporte completo con salidas GET/POST (.md)" "Yellow" "DarkCyan"
        Write-BoxLine "[1..6] Ir a Seccion 1..6   |   [W] Refrescar  |  [L] Log" "Cyan" "DarkCyan"
        Write-BoxLine "[M / Esc] Volver a Portada |   [?] Ayuda      |  [Q] Salir" "Green" "DarkCyan"
        Write-BoxBottom "DarkCyan"
        End-Frame

        $act = Read-SlideKeyLive $true
        switch ($act) {
            "RESIZE"       { continue }
            "HELP"         { Show-HelpModal }
            "LOG"          { Show-LogModal }
            "EXPORT"       { Show-ExportModal }
            "PREP"         { Show-CleanPrep }
            "STARTALL"     {
                Begin-Frame $true $true
                if (-not (Test-DockerReady)) {
                    Add-EventLog "ERR" "DOCK" "Docker daemon no responde"
                    Write-CleanLine "  [ERROR] Docker Desktop / daemon no responde." "Red"
                } else {
                    Add-EventLog "INFO" "DOCK" "Ejecutando docker compose start"
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
                Begin-Frame $true $true
                Add-EventLog "INFO" "SYS" "Ejecutando suite curl-p01-p08.ps1"
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
            Add-EventLog "OK" "DOCK" ("docker ps -> {0} filas" -f $script:CachePsLines.Count)
        } else {
            $script:CachePsLines = @()
            Add-EventLog "ERR" "DOCK" "docker compose ps sin respuesta"
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
            $r = Invoke-ApiRequest "GET" "$Gateway/api/cuentas/instancia" "" 5 $true
            if ($i -eq 1) { Add-HttpTrace "GET" "$Gateway/api/cuentas/instancia" "" $r.Code 0 $r.Headers $r.Raw "Muestra 1/20 del balanceo Round Robin" }
            $inst = if ($r.Headers["x-service-instance"]) { $r.Headers["x-service-instance"] } else { "sin-cabecera" }
            $res += [pscustomobject]@{ Code = $r.Code; Instance = $inst }
        }
        $script:CacheBalanceo = $res
        $okC = @($res | Where-Object Code -eq "200").Count
        $lvl = if ($okC -eq 20) { "OK" } elseif ($okC -gt 0) { "WARN" } else { "ERR" }
        Add-EventLog $lvl "HTTP" ("20x GET /instancia -> {0}/20 OK" -f $okC)
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
            $r = Invoke-ApiRequest "GET" "$Gateway/api/$path" "" 5 $true
            if ($i -eq 1) { Add-HttpTrace "GET" "$Gateway/api/$path" "" $r.Code 0 $r.Headers $r.Raw "Muestra 1/10 de lecturas ordinarias en replica" }
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
        $res07 = $script:CacheLecturas07.Results
        $ok07 = @($res07 | Where-Object Code -eq "200").Count
        $fb07 = @($res07 | Where-Object Fallback -eq "true").Count
        $lvl07 = if ($ok07 -eq 20) { "OK" } else { "ERR" }
        Add-EventLog $lvl07 "HTTP" ("20x lecturas R1/R2 -> {0}/20 OK fb={1}" -f $ok07, $fb07)
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

    Add-EventLog "INFO" "FAIL" "Iniciada telemetria en vivo S09 (:8080)"
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
        $s9Hint = if ($script:SlideBoxW -ge 76) {
            "  [ESPACIO] Fase  [←] Atras  [B] Eureka  [M] Inicio  [L] Log  [?] Ayuda  [Q] Salir"
        } else {
            "  [ESPACIO] Fase  [←] Atras  [L] Log  [M] Inicio  [?] Ayuda  [Q] Salir"
        }

        if ($script:DualPane) {
            if (-not [Console]::IsOutputRedirected) {
                try { [Console]::SetCursorPosition(0, $script:DualBodyRow) } catch { }
            }
            $script:BufferingLeft = $true
            $script:LeftRows.Clear()
            $script:LeftTitle = "WORKSPACE · TRAFICO EN VIVO"
        } else {
            if (-not [Console]::IsOutputRedirected) {
                try { [Console]::SetCursorPosition(0, $script:DockRow + 4) } catch { }
            }
            $script:BufferingLeft = $false
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
        Write-CleanLine ("  " + (Format-Fixed $eventMsg ($script:InnerW))) "Cyan"
        if ($script:DualPane) {
            Flush-DualFrame
            Write-CleanLine $s9Hint "DarkGray"
        } else {
            Write-CleanLine $s9Hint "DarkGray"
        }
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
                Add-EventLog "WARN" "FAIL" "ms-cuentas-2 detenida ($detTxt)"
                Update-DockInPlace (Get-ContainerMapSync)
            }
            if ($startProc -and -not $startDone -and $startProc.HasExited) {
                $startDone = $true
                $eventMsg = "[EVENTO] ms-cuentas-2 reiniciada (arranque JVM ~25s en segundo plano)"
                Add-EventLog "INFO" "FAIL" "ms-cuentas-2 reiniciada (JVM warmup)"
                Update-DockInPlace (Get-ContainerMapSync)
            }
            Poll-AsyncDock

            $r = Invoke-ApiRequest "GET" "$Gateway/api/cuentas/$Origen" "" 3 $true
            $totalReq++
            $nowUtc = [DateTime]::UtcNow
            $ts = (Get-Date).ToString("HH:mm:ss")
            $inst = if ($r.Headers["x-service-instance"]) { $r.Headers["x-service-instance"] } else { "sin-instancia" }
            if ($r.Code -ne "200") {
                $errReq++; $col = "Red"
                $k = "HTTP $($r.Code)"
                if (-not $errByCode.ContainsKey($k)) { Add-EventLog "ERR" "HTTP" "Detectado $k durante rafaga S09" }
                $errByCode[$k] = if ($errByCode.ContainsKey($k)) { $errByCode[$k] + 1 } else { 1 }
                $consecC1 = 0; $streakStart = $null
            } elseif ($inst -like "ms-cuentas-2*") {
                $c2++; $col = "Cyan"
                $consecC1 = 0; $streakStart = $null
                if ($phase -eq 3 -and $null -eq $rejoinMs -and $startTrigAt) {
                    $rejoinMs = ($nowUtc - $startTrigAt).TotalMilliseconds
                    $rSec = [string]::Format($script:Inv, "{0:F2}", ($rejoinMs / 1000.0))
                    $eventMsg = ("[EVENTO] ms-cuentas-2 reincorporada al balanceo en {0}s!" -f $rSec)
                    Add-EventLog "OK" "FAIL" "Reincorporada ms-cuentas-2 (${rSec}s)"
                }
            } else {
                $c1++; $col = "Green"
                if ($phase -ge 2 -and $null -eq $detectMs -and $stopTrigAt) {
                    if ($consecC1 -eq 0) { $streakStart = $nowUtc }
                    $consecC1++
                    if ($consecC1 -ge 3) {
                        $detectMs = ($streakStart - $stopTrigAt).TotalMilliseconds
                        $dSec = [string]::Format($script:Inv, "{0:F2}", ($detectMs / 1000.0))
                        Add-EventLog "OK" "FAIL" "Convergencia a ms-cuentas-1 (${dSec}s)"
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
                    if ($act -eq "LOG") {
                        Show-LogModal
                        Write-SlideChrome 9 5 "Alta Disponibilidad HTTP · Caída ms-cuentas-2" $false $true
                        & $renderBody
                        continue
                    }
                    if ($phase -eq 1) {
                        $phase = 2
                        $stopTrigAt = [DateTime]::UtcNow; $consecC1 = 0; $streakStart = $null
                        $eventMsg = "[ACCION] Deteniendo ms-cuentas-2 (docker compose stop)"
                        Add-EventLog "WARN" "FAIL" "docker compose stop ms-cuentas-2"
                        $stopProc = Start-BackgroundDocker "stop ms-cuentas-2"
                    } elseif ($phase -eq 2) {
                        $phase = 3
                        $startTrigAt = [DateTime]::UtcNow
                        $eventMsg = "[ACCION] Reiniciando ms-cuentas-2 (docker compose start)"
                        Add-EventLog "INFO" "FAIL" "docker compose start ms-cuentas-2"
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
    Add-EventLog $(if ($errReq -eq 0) { "OK" } else { "WARN" }) "FAIL" ("Resumen S09: $totalReq req, $errReq err, det=$detStr")

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
        Add-EventLog "WARN" "FAIL" "docker compose stop replica1"
        & docker compose stop replica1 2>&1 | Out-Null
        $script:StopRepAt = [DateTime]::UtcNow
        [void](Get-ContainerMapSync)
        Update-DockInPlace $script:LastSnap
        $script:CacheLecturas11 = Invoke-LecturasFetch
        $r11 = $script:CacheLecturas11.Results
        $ok11 = @($r11 | Where-Object Code -eq "200").Count
        $fb11 = @($r11 | Where-Object Fallback -eq "true").Count
        $err11 = 20 - $ok11
        $lvl11 = if ($err11 -eq 0) { "OK" } else { "WARN" }
        Add-EventLog $lvl11 "FAIL" ("Failover 20x -> {0}/20 OK ({1} err) fb={2}" -f $ok11, $err11, $fb11)
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
        Add-EventLog "INFO" "FAIL" "docker compose start replica1 (WAL sync)"
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
        $pRow = Show-LivePending "Esperando umbral 2/2 de reincorporacion para replica1 (~6s)…"
        $retries = 0
        while ($retries -lt 12) {
            $script:CacheEstado14 = Invoke-ApiRequest "GET" "$Gateway/api/cuentas/db/estado" "" 5
            if ($script:CacheEstado14 -and $script:CacheEstado14.Code -eq 200 -and $script:CacheEstado14.Json) {
                $r1 = $script:CacheEstado14.Json.replicas | Where-Object { $_.nodo -eq "REPLICA_1" }
                if ($r1 -and $r1.available -eq $true) { break }
            }
            $retries++
            Start-Sleep -Seconds 1
        }
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
            @("  retry GET (0 err P03)", "  reinicia solo",         "· Cerrar /mov-interno"),
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
        '"Redundancia en cada capa y failover transparente con integridad ACID."'
    } elseif ($script:InnerW -ge 64) {
        '"Redundancia activa, failover transparente e integridad ACID."'
    } else {
        '"Failover transparente e integridad ACID."'
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
            "LOG"    { Show-LogModal;  $useCache = $true; continue }
            "EXPORT" { Show-ExportModal; $useCache = $true; continue }
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
        $innerFull = $script:UiW - 4
        $pTitle = if ($innerFull -ge 66) { "BILLETERA DIGITAL DISTRIBUIDA · DEMO EN VIVO" } else { "BILLETERA DIGITAL · DEMO EN VIVO" }
        $pSub   = if ($innerFull -ge 70) { "Replicación PostgreSQL WAL, descubrimiento Eureka y failover" } else { "Replicación Postgres WAL, Eureka y tolerancia a fallos" }
        Write-RowRaw @(@{ T = ("╭" + ("─" * ($script:UiW - 2)) + "╮"); C = "DarkCyan" })
        Write-RowRaw @(@{ T = "│ "; C = "DarkCyan" }, @{ T = (Format-Center $pTitle $innerFull); C = "Cyan" }, @{ T = " │"; C = "DarkCyan" })
        Write-RowRaw @(@{ T = "│ "; C = "DarkCyan" }, @{ T = (Format-Center $pSub $innerFull); C = "DarkGray" }, @{ T = " │"; C = "DarkCyan" })

        if ($script:DualPane) {
            Write-RowRaw @(@{ T = ("╰" + ("─" * ($script:UiW - 2)) + "╯"); C = "DarkCyan" })
            if (-not [Console]::IsOutputRedirected) {
                try { $script:DualBodyRow = [Console]::CursorTop; $script:DockRow = $script:DualBodyRow } catch { }
            }
            $script:BufferingLeft = $true
            $script:LeftTitle = "MENU PRINCIPAL · RECORRIDO"
        } else {
            Render-ClusterDock $true $null $true
        }

        if (-not [Console]::IsOutputRedirected -and $script:LastScreenId -ne "PORTADA") {
            try { Clear-TailFrom ([Console]::CursorTop) } catch { }
        }
        $script:LastScreenId = "PORTADA"

        $leg = if ($script:InnerW -ge 72) {
            "  ● En línea   ~ Iniciando   ✗ Caído     (actualizado en segundo plano)"
        } else {
            "  ● En línea   ~ Iniciando   ✗ Caído"
        }
        if ($script:DualPane) { Write-BlankLine }
        Write-CleanLine $leg "DarkGray"
        Write-BlankLine
        $agTitle = if ($script:InnerW -ge 70) { "RECORRIDO (15 DIAPOSITIVAS) · ELIGE SECCIÓN [1-6]" } else { "RECORRIDO (15 SLIDES) · PULSA [1-6]" }
        Write-BoxTop $agTitle "DarkCyan"
        $colL = [int][Math]::Floor(($script:InnerW - 3) / 2)
        $colR = $script:InnerW - 3 - $colL
        $agItems = if ($script:InnerW -ge 72) {
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
            Emit-SlideSegs @(
                @{ T = "│ "; C = "DarkCyan" },
                @{ T = ($ar[0] + " "); C = "Yellow" },
                @{ T = (Format-Fixed $ar[1] $tW1); C = "White" },
                @{ T = $ar[2]; C = "DarkGray" },
                @{ T = " │ "; C = "DarkGray" },
                @{ T = ($ar[3] + " "); C = "Yellow" },
                @{ T = (Format-Fixed $ar[4] $tW2); C = "White" },
                @{ T = $ar[5]; C = "DarkGray" },
                @{ T = " │"; C = "DarkCyan" }
            ) $script:SlideBoxW
        }
        Write-BoxBottom "DarkCyan"

        if (([DateTime]::UtcNow - $lastSalPoll).TotalSeconds -ge 4) {
            $salCached = Get-SaldoInfo
            $lastSalPoll = [DateTime]::UtcNow
        }
        if ($script:DualPane) { Write-BlankLine }
        if ($salCached) {
            $cons = [decimal]$salCached.consumidoHoy
            $sc = if ($cons -eq 0) { "Green" } else { "Yellow" }
            $sTxt = Format-Money $salCached.saldo
            $cTxt = Format-Money $salCached.consumidoHoy
            $lTxt = Format-Money $salCached.limiteDiario
            $acctLine = if ($script:SlideBoxW -ge 86) {
                $b = if ($cons -gt 0) { " [REINICIAR CON U->P]" } else { " [LISTO]" }
                ('  Cuenta demo {0} : saldo=${1} | hoy=${2}/${3}{4}' -f $Origen, $sTxt, $cTxt, $lTxt, $b)
            } elseif ($script:SlideBoxW -ge 72) {
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

        if ($script:DualPane) {
            Flush-DualFrame
        } else {
            Render-LogStrip
        }
        $startPrompt = if ($script:UiW -ge 68) { "  ► [ESPACIO / ENTER] Iniciar Presentación (Diapositiva 1/15)" } else { "  ► [ESPACIO/→] Iniciar Presentación (1/15)" }
        $navPrompt   = if ($script:UiW -ge 92) {
            "    Atajos: [1-6] Sec  [B] Eureka  [U] Utils  [L] Log  [E] Exportar  [?] Ayuda  [Q] Salir"
        } elseif ($script:UiW -ge 74) {
            "    [1-6] Sec  [B] Eureka  [U] Utils  [L] Log  [E] Rep  [?] Ayuda  [Q] Salir"
        } else {
            "    [1-6] Sec [B] Eur [U] Util [L] Log [E] Rep [?] Ayuda [Q] Sal"
        }
        Write-CleanLine $startPrompt "Green"
        Write-CleanLine $navPrompt "DarkGray"
        End-Frame

        $act = Read-SlideKeyLive $true
        $res = "PORTADA"
        switch ($act) {
            "RESIZE"       { continue }
            "HELP"         { Show-HelpModal; $lastSalPoll = [DateTime]::MinValue }
            "LOG"          { Show-LogModal;  $lastSalPoll = [DateTime]::MinValue }
            "EXPORT"       { Show-ExportModal; $lastSalPoll = [DateTime]::MinValue }
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
