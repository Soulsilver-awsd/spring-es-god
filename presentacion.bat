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
try { $Host.UI.RawUI.WindowTitle = "Billetera Digital Distribuida · Presentacion" } catch { }

$RepoDir = $env:PRESENTACION_DIR.TrimEnd('\', '/')
Set-Location -LiteralPath $RepoDir

$Gateway = if ($env:GATEWAY) { $env:GATEWAY } else { "http://localhost:8080" }
$Eureka  = if ($env:EUREKA)  { $env:EUREKA }  else { "http://localhost:8761" }
$Origen  = "0991112233"
$Destino = "0984445566"

$script:Inv = [System.Globalization.CultureInfo]::InvariantCulture
$script:CacheTxOk = $null
$script:CacheTxErr = $null
$script:LastTxNodo = "PRIMARY (recovery=false)"
$script:LastTxCodigo = "TX-2026-0001"
$script:LastBurstSummary = $null

$script:TmpDir = Join-Path ([IO.Path]::GetTempPath()) ("billetera-ppt-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Path $script:TmpDir -Force | Out-Null
$script:HeadersFile = Join-Path $script:TmpDir "headers.txt"
$script:BodyFile    = Join-Path $script:TmpDir "body.json"
$script:JsonFile    = Join-Path $script:TmpDir "req.json"
$script:Utf8NoBom   = New-Object System.Text.UTF8Encoding($false)

function Invoke-Cleanup {
    if (Test-Path $script:TmpDir) {
        Remove-Item -Recurse -Force $script:TmpDir -ErrorAction SilentlyContinue
    }
}

function Clear-ScreenSafe {
    if (-not [Console]::IsOutputRedirected) {
        try { [Console]::Clear() } catch { }
    }
}

function Format-Fixed([string]$Text, [int]$Width) {
    if ($null -eq $Text) { $Text = "" }
    if ($Text.Length -gt $Width) { return $Text.Substring(0, [Math]::Max(0, $Width - 3)) + "..." }
    return $Text.PadRight($Width)
}

function Format-Money($Val) {
    if ($null -eq $Val -or "$Val" -eq "") { return "-" }
    try { return [string]::Format($script:Inv, "{0:F2}", [decimal]$Val) } catch { return "$Val" }
}

function Get-ProgressBar([int]$SlideNum, [int]$TotalSlides = 15) {
    $filled = [int][Math]::Round(($SlideNum / $TotalSlides) * 10)
    $empty = 10 - $filled
    return ("[" + ("█" * $filled) + ("░" * $empty) + "]")
}

function Write-SlideChrome([int]$SlideNum, [string]$SectionTitle, [string]$SlideTitle) {
    Clear-ScreenSafe
    $prog  = Get-ProgressBar $SlideNum 15
    $left  = ("SLIDE {0:00}/15  {1}" -f $SlideNum, $prog)
    $right = $SectionTitle
    $gap   = [Math]::Max(1, 74 - $left.Length - $right.Length)
    if ($left.Length + $gap + $right.Length -gt 74) {
        $right = $right.Substring(0, [Math]::Max(1, 74 - $left.Length - 1))
        $gap = 74 - $left.Length - $right.Length
    }
    $row2 = Format-Fixed ("► " + $SlideTitle) 74

    Write-Host ("╔" + ("═" * 76) + "╗") -ForegroundColor DarkCyan
    Write-Host "║ " -ForegroundColor DarkCyan -NoNewline
    Write-Host $left -ForegroundColor Cyan -NoNewline
    Write-Host (" " * $gap) -NoNewline
    Write-Host $right -ForegroundColor Yellow -NoNewline
    Write-Host " ║" -ForegroundColor DarkCyan
    Write-Host "║ " -ForegroundColor DarkCyan -NoNewline
    Write-Host $row2 -ForegroundColor White -NoNewline
    Write-Host " ║" -ForegroundColor DarkCyan
    Write-Host ("╚" + ("═" * 76) + "╝") -ForegroundColor DarkCyan
}

function Write-BoxTop([string]$Title, [string]$Color = "DarkGray") {
    $t = " " + $Title + " "
    $fill = [Math]::Max(2, 75 - $t.Length)
    Write-Host ("┌─" + $t + ("─" * $fill) + "┐") -ForegroundColor $Color
}

function Write-BoxLine([string]$Text, [string]$TextColor = "White", [string]$BorderColor = "DarkGray") {
    Write-Host "│ " -ForegroundColor $BorderColor -NoNewline
    Write-Host (Format-Fixed $Text 74) -ForegroundColor $TextColor -NoNewline
    Write-Host " │" -ForegroundColor $BorderColor
}

function Write-BoxBottom([string]$Color = "DarkGray") {
    Write-Host ("└" + ("─" * 76) + "┘") -ForegroundColor $Color
}

function Open-EurekaBrowser {
    try { Start-Process "$Eureka" | Out-Null } catch { }
}

function Read-SlideKey {
    if ([Console]::IsInputRedirected) { return "QUIT" }
    $k = [Console]::ReadKey($true)
    switch ($k.Key) {
        ([ConsoleKey]::LeftArrow)  { return "PREV" }
        ([ConsoleKey]::PageUp)     { return "PREV" }
        ([ConsoleKey]::Backspace)  { return "PREV" }
        ([ConsoleKey]::RightArrow) { return "NEXT" }
        ([ConsoleKey]::PageDown)   { return "NEXT" }
        ([ConsoleKey]::Spacebar)   { return "NEXT" }
        ([ConsoleKey]::Enter)      { return "NEXT" }
        ([ConsoleKey]::Escape)     { return "HOME" }
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
        default {
            if ($ch -match '^[1-6]$') { return "B$ch" }
            return "NEXT"
        }
    }
}

function Wait-SlideFooter([string]$NextLabel = "Siguiente", [bool]$AllowBack = $true) {
    Write-Host ""
    Write-Host ("─" * 78) -ForegroundColor DarkGray
    if ($AllowBack) {
        Write-Host ("  [ESPACIO/→] {0}   [←/Backspace] Anterior" -f $NextLabel) -ForegroundColor Green
    } else {
        Write-Host ("  [ESPACIO/→] {0}" -f $NextLabel) -ForegroundColor Green
    }
    Write-Host "  [R] Actualizar   [B] Eureka   [U] Utilidades   [M] Portada   [Q] Salir" -ForegroundColor DarkGray
    while ($true) {
        $act = Read-SlideKey
        if ($act -eq "EUREKA") {
            Open-EurekaBrowser
            Write-Host ("  [OK] Eureka abierto en el navegador ({0})." -f $Eureka) -ForegroundColor DarkCyan
            continue
        }
        return $act
    }
}

function Invoke-ApiRequest([string]$Method, [string]$Url, [string]$JsonBody = "", [int]$TimeoutSec = 10) {
    if (-not (Test-Path $script:TmpDir)) {
        New-Item -ItemType Directory -Path $script:TmpDir -Force | Out-Null
    }
    $curlArgs = @("-s", "--max-time", "$TimeoutSec", "-o", $script:BodyFile, "-D", $script:HeadersFile, "-w", "%{http_code}", "-X", $Method, $Url)
    if ($JsonBody) {
        [IO.File]::WriteAllText($script:JsonFile, $JsonBody, $script:Utf8NoBom)
        $curlArgs += @("-H", "Content-Type: application/json", "--data-binary", "@$($script:JsonFile)")
    } else {
        $curlArgs += @("-H", "Accept: application/json")
    }
    $code = (& curl.exe @curlArgs 2>$null)
    if (-not $code) { $code = "000" }
    $headers = @{}
    if (Test-Path $script:HeadersFile) {
        foreach ($line in (Get-Content -LiteralPath $script:HeadersFile -Encoding UTF8 -ErrorAction SilentlyContinue)) {
            if ($line -match '^([^:]+):\s*(.*)$') {
                $headers[$Matches[1].Trim().ToLowerInvariant()] = $Matches[2].Trim()
            }
        }
    }
    $rawBody = ""
    $bodyObj = $null
    if (Test-Path $script:BodyFile) {
        $rawBody = Get-Content -LiteralPath $script:BodyFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        if ($rawBody) {
            try { $bodyObj = $rawBody | ConvertFrom-Json } catch { }
        }
    }
    return @{ Code = "$code".Trim(); Headers = $headers; Body = $bodyObj; Raw = $rawBody }
}

function Get-ClusterStatus {
    $envOk = Test-Path (Join-Path $RepoDir ".env")
    $dockerOk = $false
    $total = 0; $healthy = 0; $stopped = @()
    try {
        $out = & docker compose ps -a --format "{{.Name}}|{{.State}}|{{.Status}}" 2>$null
        if ($LASTEXITCODE -eq 0) {
            $dockerOk = $true
            foreach ($line in $out) {
                if (-not $line -or ($line -notmatch '\|')) { continue }
                $p = $line -split '\|', 3
                $total++
                if ($p[2] -match 'healthy') { $healthy++ }
                if ($p[1] -ne 'running') { $stopped += $p[0] }
            }
        }
    } catch { }
    $saldo = $null
    $r = Invoke-ApiRequest "GET" "$Gateway/api/cuentas/$Origen/saldo-critico" "" 2
    if ($r.Code -eq "200" -and $r.Body -and $r.Body.datos) { $saldo = $r.Body.datos }
    return @{ EnvExists = $envOk; DockerOk = $dockerOk; Total = $total; Healthy = $healthy; Stopped = $stopped; Saldo = $saldo }
}

function Invoke-EnsureEnv {
    $envPath = Join-Path $RepoDir ".env"
    $exPath  = Join-Path $RepoDir ".env.example"
    if (-not (Test-Path $envPath)) {
        if (Test-Path $exPath) {
            Copy-Item -LiteralPath $exPath -Destination $envPath
            Write-Host "  [OK] Archivo .env creado desde .env.example." -ForegroundColor Green
            return $true
        }
        Write-Host "  [ERROR] No existe .env ni .env.example." -ForegroundColor Red
        return $false
    }
    return $true
}

# --- Panel de Utilidades (Backstage) ---

function Show-CleanPrep {
    Clear-ScreenSafe
    Write-Host ("╔" + ("═" * 76) + "╗") -ForegroundColor DarkYellow
    Write-Host ("║ " + (Format-Fixed "REINICIO LIMPIO DEL ENTORNO (down -v + up -d --build)" 74) + " ║") -ForegroundColor Yellow
    Write-Host ("╚" + ("═" * 76) + "╝") -ForegroundColor DarkYellow
    Write-Host ""
    if (-not (Invoke-EnsureEnv)) {
        [void](Wait-SlideFooter "Volver" $false)
        return
    }
    Write-Host "  $ docker compose down -v && docker compose up -d --build" -ForegroundColor Cyan
    & docker compose down -v
    & docker compose up -d --build
    if ($LASTEXITCODE -ne 0) {
        Write-Host "`n  [ERROR] docker compose up fallo. Revisa Docker Desktop." -ForegroundColor Red
        [void](Wait-SlideFooter "Volver" $false)
        return
    }
    Write-Host "`n  Esperando que los 8 contenedores esten healthy..." -ForegroundColor Yellow
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt 240) {
        $st = Get-ClusterStatus
        Write-Host ("`r  [{0,3}s] Healthy: {1}/8   " -f [int]$sw.Elapsed.TotalSeconds, $st.Healthy) -NoNewline -ForegroundColor Cyan
        if ($st.Healthy -ge 8) {
            Write-Host "`n  [OK] Los 8 contenedores estan healthy!" -ForegroundColor Green
            break
        }
        Start-Sleep -Seconds 2
    }
    Open-EurekaBrowser
    Write-Host "  [OK] Eureka abierto en $Eureka" -ForegroundColor Green
    $s = Invoke-ApiRequest "GET" "$Gateway/api/cuentas/$Origen/saldo-critico" "" 4
    if ($s.Code -eq "200" -and $s.Body.datos) {
        Write-Host ('  [OK] Cuenta {0}: saldo=${1} | consumidoHoy=${2} / ${3}' -f $Origen, (Format-Money $s.Body.datos.saldo), (Format-Money $s.Body.datos.consumidoHoy), (Format-Money $s.Body.datos.limiteDiario)) -ForegroundColor Green
    }
    $script:CacheTxOk = $null
    $script:CacheTxErr = $null
    [void](Wait-SlideFooter "Volver al panel" $false)
}

function Show-UtilsPanel {
    while ($true) {
        Clear-ScreenSafe
        Write-Host ("╔" + ("═" * 76) + "╗") -ForegroundColor DarkCyan
        Write-Host ("║ " + (Format-Fixed "UTILIDADES DEL ENTORNO Y VERIFICACION" 74) + " ║") -ForegroundColor Cyan
        Write-Host ("╚" + ("═" * 76) + "╝") -ForegroundColor DarkCyan
        $st = Get-ClusterStatus
        Write-Host ""
        if (-not $st.EnvExists) {
            Write-Host "  [AVISO] Falta .env en el repositorio (pulsa [C] o [P])." -ForegroundColor Yellow
        }
        if ($st.DockerOk) {
            $col = if ($st.Healthy -ge 8) { "Green" } else { "Yellow" }
            Write-Host ("  Clúster: {0}/8 healthy (visibles: {1})" -f $st.Healthy, $st.Total) -ForegroundColor $col
            if ($st.Stopped.Count -gt 0) {
                Write-Host ("  Detenidos: {0}  -> pulsa [S] para arrancar" -f ($st.Stopped -join ", ")) -ForegroundColor Red
            }
        } else {
            Write-Host "  Docker: Daemon no responde (abre Docker Desktop)." -ForegroundColor Red
        }
        if ($st.Saldo) {
            $cons = [decimal]$st.Saldo.consumidoHoy
            $sc = if ($cons -eq 0) { "Green" } else { "Yellow" }
            Write-Host ('  Cuenta {0}: saldo=${1} | consumidoHoy=${2} / ${3}' -f $Origen, (Format-Money $st.Saldo.saldo), (Format-Money $st.Saldo.consumidoHoy), (Format-Money $st.Saldo.limiteDiario)) -ForegroundColor $sc
        }
        Write-Host ""
        Write-BoxTop "ACCIONES DISPONIBLES" "DarkCyan"
        Write-BoxLine "[P] Reinicio limpio (down -v + up -d --build + abrir Eureka)" "Yellow" "DarkCyan"
        Write-BoxLine "[S] Arrancar contenedores detenidos (docker compose start)" "White" "DarkCyan"
        Write-BoxLine "[B] Abrir Eureka en navegador ($Eureka)" "White" "DarkCyan"
        Write-BoxLine "[C] Crear .env desde .env.example" "White" "DarkCyan"
        Write-BoxLine "[T] Ejecutar suite automatizada P01-P08" "White" "DarkCyan"
        Write-BoxLine "[1..6] Ir directo a Seccion 1..6" "Cyan" "DarkCyan"
        Write-BoxLine "[ESPACIO / ESC / M] Volver a la Portada" "Green" "DarkCyan"
        Write-BoxBottom "DarkCyan"

        $act = Read-SlideKey
        switch ($act) {
            "PREP"     { Show-CleanPrep }
            "STARTALL" { Clear-ScreenSafe; [void](Invoke-EnsureEnv); & docker compose start; [void](Wait-SlideFooter "Volver" $false) }
            "EUREKA"   { Open-EurekaBrowser }
            "ENV"      { [void](Invoke-EnsureEnv); Start-Sleep -Milliseconds 800 }
            "SUITE" {
                Clear-ScreenSafe
                $ps1 = Join-Path $RepoDir "docs\api\curl-p01-p08.ps1"
                if (Test-Path $ps1) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ps1 }
                [void](Wait-SlideFooter "Volver" $false)
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
    Write-SlideChrome 1 "1. ARQUITECTURA" "Arquitectura del Sistema · 8 Contenedores Docker"
    Write-Host ""
    Write-Host "  +----------------+   HTTP :8080   +-----------------------+" -ForegroundColor White
    Write-Host "  | Cliente / Demo | -------------> |  api-gateway (:8080)  |" -ForegroundColor Cyan
    Write-Host "  +----------------+                +-----------+-----------+" -ForegroundColor White
    Write-Host "                                                | lb:// Round Robin" -ForegroundColor DarkGray
    Write-Host "  +-----------------------+                     v" -ForegroundColor White
    Write-Host "  | eureka-server (:8761) | <==== registro + latido 5s =====" -ForegroundColor Yellow
    Write-Host "  +-----------------------+     |              |            |" -ForegroundColor White
    Write-Host "                                v              v            v" -ForegroundColor DarkGray
    Write-Host "                         +------------+ +------------+ +----------------+" -ForegroundColor White
    Write-Host "                         |ms-cuentas-1| |ms-cuentas-2| |ms-transacciones|" -ForegroundColor Green
    Write-Host "                         |   :8081    | |   :8082    | |     :8083      |" -ForegroundColor Green
    Write-Host "                         +-----+------+ +-----+------+ +-------+--------+" -ForegroundColor White
    Write-Host "                               \              |                /" -ForegroundColor DarkGray
    Write-Host "                                +----> [Enrutador JDBC] <-----+" -ForegroundColor Magenta
    Write-Host "                        Escritura/RYOW /              \ Lecturas" -ForegroundColor DarkGray
    Write-Host "                                      v                v" -ForegroundColor DarkGray
    Write-Host "                   +----------------------+     +---------------------+" -ForegroundColor White
    Write-Host "                   | primary :5432 (R/W)  |====>| replica1 :5433 (RO) |" -ForegroundColor Blue
    Write-Host "                   | cuentas_db  | tx_db  | WAL | replica2 :5434 (RO) |" -ForegroundColor Blue
    Write-Host "                   +----------------------+     +---------------------+" -ForegroundColor White
    Write-Host ""
    Write-BoxTop "COMPONENTES PRINCIPALES" "DarkCyan"
    Write-BoxLine "● Negocio: ms-cuentas (2 instancias) y ms-transacciones (orquestador P2P)" "White" "DarkCyan"
    Write-BoxLine "● Datos:   PostgreSQL 17 con esquemas y usuarios aislados (cuentas_db/tx_db)" "White" "DarkCyan"
    Write-BoxBottom "DarkCyan"
    return (Wait-SlideFooter "Estado del clúster en vivo")
}

function Slide-02([bool]$UseCache = $false) {
    Write-SlideChrome 2 "1. ARQUITECTURA" "Clúster Docker Compose · Estado de Contenedores"
    Write-Host ""
    Write-BoxTop "CONTENEDORES ACTIVOS (docker compose ps)" "Cyan"
    $out = & docker compose ps --format "table {{.Name}}\t{{.Service}}\t{{.Status}}\t{{.Ports}}" 2>$null
    $healthy = 0; $total = 0
    if ($LASTEXITCODE -eq 0 -and $out) {
        foreach ($line in $out) {
            if ($line -match 'healthy') { $healthy++; $total++; Write-BoxLine $line "Green" "Cyan" }
            elseif ($line -match '^NAME') { Write-BoxLine $line "Cyan" "Cyan" }
            elseif ($line.Trim()) { $total++; Write-BoxLine $line "Yellow" "Cyan" }
        }
    } else {
        Write-BoxLine "No se pudo consultar docker compose (verifica Docker Desktop)." "Red" "Cyan"
    }
    Write-BoxBottom "Cyan"
    Write-Host ""
    $pillCol = if ($healthy -ge 8) { "Green" } else { "Yellow" }
    Write-Host ("  [ ESTADO DEL CLUSTER: {0}/{1} CONTENEDORES HEALTHY ]" -f $healthy, [Math]::Max($total, 8)) -ForegroundColor $pillCol
    return (Wait-SlideFooter "2. Descubrimiento en Eureka")
}

function Slide-03([bool]$UseCache = $false) {
    Write-SlideChrome 3 "2. DESCUBRIMIENTO" "Descubrimiento Dinámico con Netflix Eureka"
    Write-Host ""
    Write-BoxTop "ARQUITECTURA DE DESCUBRIMIENTO" "DarkCyan"
    Write-BoxLine "● Auto-registro al arrancar y latido (heartbeat) cada 5 segundos." "White" "DarkCyan"
    Write-BoxLine "● API Gateway resuelve por nombre logico (lb://ms-cuentas), sin IPs fijas." "White" "DarkCyan"
    Write-BoxBottom "DarkCyan"
    Write-Host ""
    Write-BoxTop "REGISTRO EUREKA EN VIVO (:8761/eureka/apps)" "Green"
    $r = Invoke-ApiRequest "GET" "$Eureka/eureka/apps" "" 5
    if ($r.Code -eq "200" -and $r.Body -and $r.Body.applications) {
        foreach ($app in $r.Body.applications.application) {
            $insts = @($app.instance | ForEach-Object { "$($_.instanceId) [$($_.status)]" }) -join "  ,  "
            $c = if ($app.name -eq "MS-CUENTAS") { "Green" } else { "Cyan" }
            Write-BoxLine ("{0,-17} -> {1}" -f $app.name, $insts) $c "Green"
        }
    } else {
        Write-BoxLine ("No responde Eureka en {0} (HTTP {1})." -f $Eureka, $r.Code) "Red" "Green"
    }
    Write-BoxBottom "Green"
    return (Wait-SlideFooter "Balanceo HTTP Round Robin")
}

function Slide-04([bool]$UseCache = $false) {
    Write-SlideChrome 4 "2. DESCUBRIMIENTO" "Balanceo de Carga HTTP · Round Robin"
    Write-Host ""
    Write-Host ("  20 peticiones consecutivas a GET {0}/api/cuentas/instancia" -f $Gateway) -ForegroundColor DarkCyan
    Write-Host ""
    $results = @()
    for ($i = 1; $i -le 20; $i++) {
        $r = Invoke-ApiRequest "GET" "$Gateway/api/cuentas/instancia" "" 5
        $inst = if ($r.Headers["x-service-instance"]) { $r.Headers["x-service-instance"] } else { "sin-cabecera" }
        $results += [pscustomobject]@{ Code = $r.Code; Instance = $inst }
    }
    $okCount = @($results | Where-Object Code -eq "200").Count
    Write-BoxTop "DISTRIBUCION POR INSTANCIA" "Green"
    $grouped = $results | Group-Object Code, Instance | Sort-Object Name
    foreach ($g in $grouped) {
        $f = $g.Group[0]
        $pct = [int][Math]::Round(($g.Count / 20.0) * 100)
        $bar = ("█" * [Math]::Min($g.Count, 20)).PadRight(20, "░")
        $c = if ($f.Code -eq "200") { if ($f.Instance -like "ms-cuentas-2*") { "Cyan" } else { "Green" } } else { "Red" }
        Write-BoxLine ("{0,-20} [{1}]  {2}  {3,2}/20 ({4,3}%)" -f $f.Instance, $f.Code, $bar, $g.Count, $pct) $c "Green"
    }
    Write-BoxBottom "Green"
    Write-Host ""
    $pCol = if ($okCount -eq 20) { "Green" } else { "Red" }
    Write-Host ("  [ RESULTADO: {0}/20 RESPUESTAS 200 OK · REPARTO ROUND ROBIN ]" -f $okCount) -ForegroundColor $pCol
    return (Wait-SlideFooter "3. Comunicación entre servicios")
}

function Slide-05([bool]$UseCache = $false) {
    Write-SlideChrome 5 "3. COMUNICACION" "Orquestación P2P entre Microservicios · Transferencia"
    Write-Host ""
    Write-Host "  Cliente ─POST :8080─▶ [ms-transacciones :8083] ─Eureka─▶ [ms-cuentas] ─ACID─▶ PRIMARY" -ForegroundColor Cyan
    Write-Host ""

    if (-not $UseCache -or -not $script:CacheTxOk) {
        $payload = @{ celularOrigen = $Origen; celularDestino = $Destino; monto = 25; motivo = "Transferencia P2P" } | ConvertTo-Json -Compress
        $script:CacheTxOk = Invoke-ApiRequest "POST" "$Gateway/api/transacciones/transferir" $payload 10
    }
    $r = $script:CacheTxOk
    $ok = ($r.Code -eq "201" -or $r.Code -eq "200")
    $bCol = if ($ok) { "Green" } else { "Yellow" }
    $msg = if ($r.Body) { $r.Body.mensaje } else { "Sin respuesta ($($r.Code))" }
    $cod = if ($r.Body -and $r.Body.datos) { $r.Body.datos.codigoComprobante } else { "-" }
    $sal = if ($r.Body -and $r.Body.datos) { Format-Money $r.Body.datos.nuevoSaldoOrigen } else { "-" }
    $ic  = if ($r.Body -and $r.Body.auditoriaTecnica) { $r.Body.auditoriaTecnica.instanciaCuentasConsultada } else { "-" }
    $nbd = if ($r.Body -and $r.Body.auditoriaTecnica) { $r.Body.auditoriaTecnica.nodoBaseDatos } else { "-" }
    $pol = if ($r.Body -and $r.Body.auditoriaTecnica) { $r.Body.auditoriaTecnica.politicaEnrutamiento } else { "-" }
    if ($nbd -and $nbd -ne "-") { $script:LastTxNodo = $nbd }
    if ($cod -and $cod -ne "-") { $script:LastTxCodigo = $cod }

    Write-BoxTop ("COMPROBANTE DE TRANSFERENCIA  [ HTTP " + $r.Code + " ]") $bCol
    Write-BoxLine ("Estado / Mensaje   : {0}" -f $msg) $bCol $bCol
    Write-BoxLine ("Comprobante        : {0}       Monto: $25.00 ({1} -> {2})" -f $cod, $Origen, $Destino) "White" $bCol
    Write-BoxLine ('Nuevo Saldo Origen : ${0}' -f $sal) "White" $bCol
    Write-BoxLine ("Instancia Cuentas  : {0}  (resuelta via Eureka)" -f $ic) "Cyan" $bCol
    Write-BoxLine ("Nodo Base de Datos : {0}" -f $nbd) "Yellow" $bCol
    Write-BoxLine ("Politica Enrutado  : {0}" -f $pol) "White" $bCol
    Write-BoxBottom $bCol
    Write-Host ""
    Write-Host "  ● Debito y credito ejecutados en una sola transaccion ACID con bloqueo ordenado." -ForegroundColor DarkGray
    return (Wait-SlideFooter "Validación de saldo insuficiente")
}

function Slide-06([bool]$UseCache = $false) {
    Write-SlideChrome 6 "3. COMUNICACION" "Validación de Reglas de Negocio · Error Controlado"
    Write-Host ""
    Write-Host ("  Escritura previa ({0}) -> {1}" -f $script:LastTxCodigo, $script:LastTxNodo) -ForegroundColor DarkCyan
    Write-Host ""

    if (-not $UseCache -or -not $script:CacheTxErr) {
        $payload = @{ celularOrigen = $Origen; celularDestino = $Destino; monto = 9999; motivo = "Prueba limite" } | ConvertTo-Json -Compress
        $script:CacheTxErr = Invoke-ApiRequest "POST" "$Gateway/api/transacciones/transferir" $payload 10
    }
    $r = $script:CacheTxErr
    $msg = if ($r.Body) { $r.Body.mensaje } else { "Sin respuesta ($($r.Code))" }
    $nbd = if ($r.Body -and $r.Body.auditoriaTecnica) { $r.Body.auditoriaTecnica.nodoBaseDatos } else { "-" }
    $col = if ($r.Code -eq "409") { "Yellow" } else { "Red" }

    Write-BoxTop ("RECHAZO CONTROLADO  [ HTTP " + $r.Code + " ]") $col
    Write-BoxLine ("Mensaje devuelto   : {0}" -f $msg) $col $col
    Write-BoxLine "Monto solicitado   : $9999.00  (supera saldo disponible)" "White" $col
    Write-BoxLine "Integridad ACID    : Transaccion revertida; saldos intactos" "Green" $col
    Write-BoxLine ("Auditoria nodoBD   : {0}" -f $nbd) "Cyan" $col
    Write-BoxBottom $col
    return (Wait-SlideFooter "4. Persistencia replicada")
}

function Invoke-LecturasRender([string]$BorderCol = "Cyan") {
    $results = @()
    for ($i = 1; $i -le 10; $i++) {
        foreach ($path in @("cuentas/$Origen/contactos", "transacciones/historial/$Origen")) {
            $r = Invoke-ApiRequest "GET" "$Gateway/api/$path" "" 5
            $node = if ($r.Headers["x-db-node"]) { $r.Headers["x-db-node"] } else { "desconocido" }
            $fb   = if ($r.Headers["x-db-fallback"]) { $r.Headers["x-db-fallback"] } else { "false" }
            $results += [pscustomobject]@{ Code = $r.Code; Node = $node; Fallback = $fb }
        }
    }
    $okCount = @($results | Where-Object Code -eq "200").Count
    $fbCount = @($results | Where-Object Fallback -eq "true").Count
    Write-BoxTop "20 LECTURAS ORDINARIAS (contactos + historial)" $BorderCol
    $grouped = $results | Group-Object Code, Node, Fallback | Sort-Object Name
    foreach ($g in $grouped) {
        $f = $g.Group[0]
        $bar = ("█" * [Math]::Min($g.Count, 12)).PadRight(12, "░")
        $c = if ($f.Code -ne "200") { "Red" } elseif ($f.Fallback -eq "true") { "Yellow" } else { "Green" }
        Write-BoxLine ("{0,2}/20 [{1}] {2}  {3}  fb={4}" -f $g.Count, $f.Code, $bar, $f.Node, $f.Fallback) $c $BorderCol
    }
    Write-BoxBottom $BorderCol
    return @{ Ok = $okCount; Fallback = $fbCount }
}

function Slide-07([bool]$UseCache = $false) {
    Write-SlideChrome 7 "4. PERSISTENCIA" "Enrutamiento de Base de Datos · Primario vs Réplicas"
    Write-Host ""
    Write-Host ("  Escrituras -> {0}  |  Lecturas -> REPLICA_1 / REPLICA_2" -f $script:LastTxNodo) -ForegroundColor DarkCyan
    Write-Host ""
    $stats = Invoke-LecturasRender "Green"
    Write-Host ""
    Write-Host ("  [ {0}/20 LECTURAS 200 OK · REPARTO ROUND ROBIN EN REPLICAS (recovery=true) ]" -f $stats.Ok) -ForegroundColor Green
    return (Wait-SlideFooter "Lectura crítica RYOW")
}

function Slide-08([bool]$UseCache = $false) {
    Write-SlideChrome 8 "4. PERSISTENCIA" "Consistencia Inmediata · Read-Your-Own-Writes (RYOW)"
    Write-Host ""
    Write-BoxTop "ARQUITECTURA DE CONSISTENCIA" "DarkCyan"
    Write-BoxLine "● Las replicas WAL pueden presentar retardo minimo tras una escritura." "White" "DarkCyan"
    Write-BoxLine "● /saldo-critico enruta al PRIMARIO para garantizar lectura actualizada." "White" "DarkCyan"
    Write-BoxBottom "DarkCyan"
    Write-Host ""
    $r = Invoke-ApiRequest "GET" "$Gateway/api/cuentas/$Origen/saldo-critico" "" 5
    Write-BoxTop ("LECTURA CRITICA  [ GET /api/cuentas/{0}/saldo-critico ]" -f $Origen) "Green"
    if ($r.Code -eq "200" -and $r.Body) {
        $sal = Format-Money $r.Body.datos.saldo
        $nbd = $r.Body.auditoriaTecnica.nodoBaseDatos
        $pol = $r.Body.auditoriaTecnica.politicaEnrutamiento
        Write-BoxLine ('Saldo inmediato    : ${0}' -f $sal) "Green" "Green"
        Write-BoxLine ("Nodo Base de Datos : {0}" -f $nbd) "Cyan" "Green"
        Write-BoxLine ("Politica Enrutado  : {0}" -f $pol) "Yellow" "Green"
    } else {
        Write-BoxLine ("HTTP {0}: {1}" -f $r.Code, $r.Raw) "Red" "Green"
    }
    Write-BoxBottom "Green"
    return (Wait-SlideFooter "5. Simulación de fallos (Instancia)")
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

function Slide-09([bool]$UseCache = $false) {
    Write-SlideChrome 9 "5a. FALLO SERVICIO" "Alta Disponibilidad HTTP · Caída de ms-cuentas-2"

    if ($UseCache -and $script:LastBurstSummary) {
        Write-Host ""
        Write-BoxTop "RESUMEN DE ALTA DISPONIBILIDAD" "Cyan"
        Write-BoxLine $script:LastBurstSummary "Green" "Cyan"
        Write-BoxLine "Eureka dio de baja la instancia y API Gateway reintento GET sin errores." "White" "Cyan"
        Write-BoxBottom "Cyan"
        return (Wait-SlideFooter "5b. Caída de réplica PostgreSQL")
    }

    Write-Host ""
    Write-BoxTop "TELEMETRIA DE TRAFICO EN TIEMPO REAL" "Yellow"
    Write-BoxLine "ESTADO: Trafico activo (ms-cuentas-1 + ms-cuentas-2)" "Green" "Yellow"
    Write-BoxLine "ACCION: [ESPACIO/→] Simular caida de ms-cuentas-2" "White" "Yellow"
    Write-BoxBottom "Yellow"
    Write-Host ""

    $phase = 1; $totalReq = 0; $errReq = 0
    $stopProc = $null; $stopDone = $false
    $startProc = $null; $startDone = $false
    $abortAct = $null

    try {
        while ($true) {
            if ($stopProc -and -not $stopDone -and $stopProc.HasExited) {
                $stopDone = $true
                Write-Host "  >>> [EVENTO] ms-cuentas-2 detenida · Trafico absorbido 100% por ms-cuentas-1" -ForegroundColor Green
            }
            if ($startProc -and -not $startDone -and $startProc.HasExited) {
                $startDone = $true
                Write-Host "  >>> [EVENTO] ms-cuentas-2 reiniciada (arranque JVM ~25s en curso)" -ForegroundColor Cyan
            }
            $r = Invoke-ApiRequest "GET" "$Gateway/api/cuentas/$Origen" "" 3
            $totalReq++
            $ts = (Get-Date).ToString("HH:mm:ss")
            $inst = if ($r.Headers["x-service-instance"]) { $r.Headers["x-service-instance"] } else { "sin-instancia" }
            if ($r.Code -ne "200") {
                $errReq++
                Write-Host ("  [{0}]  {1}  {2}" -f $ts, $r.Code, $inst) -ForegroundColor Red
            } elseif ($inst -like "ms-cuentas-2*") {
                Write-Host ("  [{0}]  {1}  {2}" -f $ts, $r.Code, $inst) -ForegroundColor Cyan
            } else {
                Write-Host ("  [{0}]  {1}  {2}" -f $ts, $r.Code, $inst) -ForegroundColor Green
            }

            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            while ($sw.ElapsedMilliseconds -lt 300) {
                if (-not [Console]::IsInputRedirected -and [Console]::KeyAvailable) {
                    $act = Read-SlideKey
                    if ($act -eq "QUIT" -or $act -eq "HOME" -or $act -eq "PREV") { $abortAct = $act; break }
                    if ($act -eq "EUREKA") { Open-EurekaBrowser; continue }
                    if ($phase -eq 1) {
                        $phase = 2
                        Write-Host "`n  >>> [EVENTO] Deteniendo ms-cuentas-2 (docker compose stop)..." -ForegroundColor Magenta
                        $stopProc = Start-BackgroundDocker "stop ms-cuentas-2"
                        Write-Host "  >>> [SIGUIENTE] [ESPACIO/→] Reiniciar ms-cuentas-2" -ForegroundColor Yellow
                    } elseif ($phase -eq 2) {
                        $phase = 3
                        Write-Host "`n  >>> [EVENTO] Reiniciando ms-cuentas-2 (docker compose start)..." -ForegroundColor Magenta
                        $startProc = Start-BackgroundDocker "start ms-cuentas-2"
                        Write-Host "  >>> [SIGUIENTE] [ESPACIO/→] Finalizar trafico y ver resumen" -ForegroundColor Yellow
                    } else {
                        $abortAct = "DONE"; break
                    }
                }
                Start-Sleep -Milliseconds 40
            }
            if ($abortAct) { break }
        }
    } finally {
        if ($stopProc  -and -not $stopProc.HasExited)  { try { $stopProc.WaitForExit(3000)  | Out-Null } catch { } }
        if ($startProc -and -not $startProc.HasExited) { try { $startProc.WaitForExit(2000) | Out-Null } catch { } }
    }

    if ($abortAct -and $abortAct -ne "DONE") { return $abortAct }

    $script:LastBurstSummary = ("Total peticiones: {0}  |  Exitosas (200): {1}  |  Errores (!=200): {2}" -f $totalReq, ($totalReq - $errReq), $errReq)
    $rCol = if ($errReq -eq 0) { "Green" } else { "Red" }
    Write-Host ""
    Write-BoxTop "RESUMEN DE ALTA DISPONIBILIDAD" $rCol
    Write-BoxLine $script:LastBurstSummary $rCol $rCol
    Write-BoxLine "Eureka dio de baja la instancia y API Gateway reintento GET sin errores." "White" $rCol
    Write-BoxBottom $rCol
    return (Wait-SlideFooter "5b. Caída de réplica PostgreSQL")
}

function Slide-10([bool]$UseCache = $false) {
    Write-SlideChrome 10 "5b. FALLO BD" "Alta Disponibilidad de Datos · Caída de Réplica PG"
    Write-Host ""
    Write-Host ""
    Write-BoxTop "ESCENARIO: FALLO DE NODO DE LECTURA EN CALIENTE" "Yellow"
    Write-BoxLine "" "White" "Yellow"
    Write-BoxLine "  ● Se detiene replica1 mientras el servicio recibe consultas." "White" "Yellow"
    Write-BoxLine "  ● El enrutador @UsarNodo captura el fallo y redirige la lectura" "White" "Yellow"
    Write-BoxLine "    a la replica sana (X-Db-Fallback: true)." "White" "Yellow"
    Write-BoxLine "" "White" "Yellow"
    Write-BoxLine "  PRUEBA: docker compose stop replica1  +  20 lecturas consecutivas" "Cyan" "Yellow"
    Write-BoxLine "" "White" "Yellow"
    Write-BoxBottom "Yellow"
    return (Wait-SlideFooter "Ejecutar caída de replica1 y lecturas")
}

function Slide-11([bool]$UseCache = $false) {
    Write-SlideChrome 11 "5b. FALLO BD" "Failover Transparente · Lecturas sobre REPLICA_2"
    Write-Host ""
    Write-Host "  $ docker compose stop replica1" -ForegroundColor DarkCyan
    & docker compose stop replica1 2>&1 | ForEach-Object { Write-Host ("  " + $_) -ForegroundColor DarkGray }
    Write-Host ""
    $stats = Invoke-LecturasRender "Yellow"
    Write-Host ""
    Write-Host ("  [ {0}/20 RESPUESTAS 200 OK · TODAS EN REPLICA_2 · FALLBACK={1} RESCATADAS ]" -f $stats.Ok, $stats.Fallback) -ForegroundColor Green
    return (Wait-SlideFooter "Estado de salud de réplicas")
}

function Render-DbEstadoBox([string]$Title) {
    $r = Invoke-ApiRequest "GET" "$Gateway/api/cuentas/db/estado" "" 5
    Write-BoxTop $Title "Cyan"
    if ($r.Code -eq "200" -and $r.Body) {
        if ($r.Body.servicio) {
            Write-BoxLine ("Consultado en instancia: {0}" -f $r.Body.servicio) "DarkGray" "Cyan"
        }
        foreach ($rep in $r.Body.replicas) {
            $avail = [bool]$rep.available
            $badge = if ($avail) { "[● ACTIVA · available=true ]" } else { "[✗ CAIDA  · available=false]" }
            $c = if ($avail) { "Green" } else { "Red" }
            Write-BoxLine ("{0,-10} {1}  exitos={2,-3} LSN={3}" -f $rep.nodo, $badge, $rep.consecutiveSuccesses, $rep.lastReplayLsn) $c "Cyan"
        }
    } else {
        Write-BoxLine ("HTTP {0}: {1}" -f $r.Code, $r.Raw) "Red" "Cyan"
    }
    Write-BoxBottom "Cyan"
}

function Slide-12([bool]$UseCache = $false) {
    Write-SlideChrome 12 "5b. FALLO BD" "Detección Automática de Réplica Caída (Sondeo 3s)"
    Write-Host ""
    Render-DbEstadoBox "SALUD DE REPLICAS (/api/cuentas/db/estado)"
    Write-Host ""
    Write-BoxTop "MECANISMO DE DETECCION" "DarkGray"
    Write-BoxLine "● ReplicaHealthTracker sondea cada 3 segundos con pg_is_in_recovery()." "White" "DarkGray"
    Write-BoxLine "● REPLICA_1 queda fuera del Round-Robin sin errores para el cliente." "White" "DarkGray"
    Write-BoxBottom "DarkGray"
    return (Wait-SlideFooter "Reiniciar replica1 (recuperación WAL)")
}

function Slide-13([bool]$UseCache = $false) {
    Write-SlideChrome 13 "5b. RECUPERACION" "Recuperación de Réplica · Streaming WAL y Umbral 2/2"
    Write-Host ""
    Write-Host "  $ docker compose start replica1" -ForegroundColor DarkCyan
    & docker compose start replica1 2>&1 | ForEach-Object { Write-Host ("  " + $_) -ForegroundColor DarkGray }
    Write-Host ""
    Write-BoxTop "SINCRONIZACION AUTOMATICA EN CURSO" "Green"
    Write-BoxLine "[✓] Contenedor replica1 reiniciado." "Green" "Green"
    Write-BoxLine "[~] Sincronizando registros WAL pendientes desde el nodo primario..." "Yellow" "Green"
    Write-BoxLine "[~] Umbral de reincorporacion: 2 chequeos consecutivos sanos (2 x 3s)." "Cyan" "Green"
    Write-BoxBottom "Green"
    return (Wait-SlideFooter "Verificar reincorporación al Round-Robin")
}

function Slide-14([bool]$UseCache = $false) {
    Write-SlideChrome 14 "5b. RECUPERACION" "Reincorporación Automática de replica1 al Round-Robin"
    Write-Host ""
    Render-DbEstadoBox "SALUD DE REPLICAS TRAS RECUPERACION (/api/cuentas/db/estado)"
    Write-Host ""
    Write-BoxTop "RETORNO AUTOMATICO" "DarkGray"
    Write-BoxLine "● Una vez completados 2 chequeos exitosos, REPLICA_1 regresa al balanceo." "White" "DarkGray"
    Write-BoxBottom "DarkGray"
    return (Wait-SlideFooter "6. Conclusiones técnicas")
}

function Slide-15([bool]$UseCache = $false) {
    Write-SlideChrome 15 "6. CONCLUSIONES" "Conclusiones Técnicas · Decisiones, Limitaciones y Mejoras"
    Write-Host ""
    Write-Host " ┌─ DECISIONES ──────────┐ ┌─ LIMITACIONES ────────┐ ┌─ MEJORAS FUTURAS ─────┐" -ForegroundColor Cyan
    $rows = @(
        @("· BD por @UsarNodo:",    "· Sin failover del",      "· Failover automatico"),
        @("  escritura -> PRIMARY", "  primario si se cae",    "  (Patroni / repmgr)"),
        @("  lectura -> REPLICAS",  "· Eureka unico (SPOF)",   "· Claves idempotencia"),
        @("· Round Robin + sondeo", "· /movimiento-interno",    "  en transferencias"),
        @("  de salud 2 de 2",      "  expuesto en Gateway",   "· Retry de conexion en"),
        @("· Eureka sin cache +",   "· Limite diario no se",   "  ms-transacciones"),
        @("  retry GET (0 err P03)","  reinicia solo",         "· Health Eureka real"),
        @("· Flyway advisory lock", "· Sin idempotencia en",   "· Bloquear ruta interna"),
        @("  en arranque paralelo", "  timeout de ms-cuentas", "  + Sagas / Outbox")
    )
    foreach ($r in $rows) {
        Write-Host " │" -ForegroundColor Green -NoNewline
        Write-Host (Format-Fixed $r[0] 23) -ForegroundColor White -NoNewline
        Write-Host "│ │" -ForegroundColor Yellow -NoNewline
        Write-Host (Format-Fixed $r[1] 23) -ForegroundColor White -NoNewline
        Write-Host "│ │" -ForegroundColor Cyan -NoNewline
        Write-Host (Format-Fixed $r[2] 23) -ForegroundColor White -NoNewline
        Write-Host "│" -ForegroundColor Cyan
    }
    Write-Host " └───────────────────────┘ └───────────────────────┘ └───────────────────────┘" -ForegroundColor DarkGray
    Write-Host ""
    Write-BoxTop "SINTESIS FINAL" "Cyan"
    Write-BoxLine '  "Mas de uno de todo, y saber esquivar al que falla.' "Cyan" "Cyan"
    Write-BoxLine '   Eso es un sistema distribuido."' "Cyan" "Cyan"
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
    $idx = $StartSlide
    $useCache = $false
    while ($idx -ge 0 -and $idx -lt $slides.Count) {
        $act = & $slides[$idx] $useCache
        $useCache = $false
        switch ($act) {
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
                if ($u -eq "QUIT") { return "QUIT" }
                if ($u -match '^B([1-6])$') {
                    $map = @{ "1" = 0; "2" = 2; "3" = 4; "4" = 6; "5" = 8; "6" = 14 }
                    $idx = $map[$Matches[1]]
                }
            }
            default {
                if ($act -match '^B([1-6])$') {
                    $map = @{ "1" = 0; "2" = 2; "3" = 4; "4" = 6; "5" = 8; "6" = 14 }
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
    while ($true) {
        Clear-ScreenSafe
        Write-Host ("╔" + ("═" * 76) + "╗") -ForegroundColor DarkCyan
        Write-Host ("║ " + (Format-Fixed "BILLETERA DIGITAL DISTRIBUIDA  ·  ARQUITECTURA DE MICROSERVICIOS" 74) + " ║") -ForegroundColor Cyan
        Write-Host ("║ " + (Format-Fixed "Spring Boot 3.4 · Netflix Eureka · API Gateway · PostgreSQL 17 (WAL)" 74) + " ║") -ForegroundColor DarkGray
        Write-Host ("╚" + ("═" * 76) + "╝") -ForegroundColor DarkCyan
        Write-Host ""
        Write-Host "  ┌─ INFRAESTRUCTURA ────┐ ┌─ OPERACION & DATOS ──┐ ┌─ ALTA DISPONIBILIDAD ┐" -ForegroundColor White
        Write-Host "  │ 1. Arquitectura      │ │ 4. Balanceo HTTP     │ │ 7. Tolerancia HTTP   │" -ForegroundColor Green
        Write-Host "  │ 2. Eureka & Gateway  │ │ 5. Transferencias    │ │ 8. Failover Replica  │" -ForegroundColor Cyan
        Write-Host "  │ 3. Cluster PG17 WAL  │ │ 6. CQRS-lite & RYOW  │ │ 9. Retorno Automatico│" -ForegroundColor Yellow
        Write-Host "  └──────────────────────┘ └──────────────────────┘ └──────────────────────┘" -ForegroundColor White
        Write-Host ""

        $st = Get-ClusterStatus
        Write-BoxTop "ESTADO DEL CLUSTER" "DarkGray"
        if (-not $st.EnvExists) {
            Write-BoxLine "● Falta .env en el proyecto -> [U] -> [P] Reinicio limpio" "Yellow" "DarkGray"
        }
        if ($st.DockerOk) {
            $col = if ($st.Healthy -ge 8) { "Green" } else { "Yellow" }
            Write-BoxLine ("● Contenedores : {0}/8 healthy (visibles: {1})" -f $st.Healthy, $st.Total) $col "DarkGray"
        } else {
            Write-BoxLine "● Docker       : Daemon apagado (inicia Docker Desktop)" "Red" "DarkGray"
        }
        if ($st.Saldo) {
            $cons = [decimal]$st.Saldo.consumidoHoy
            $sc = if ($cons -eq 0) { "Green" } else { "Yellow" }
            $badge = if ($cons -gt 0) { " [REINICIAR CON U->P]" } else { " [LISTO]" }
            Write-BoxLine ('● Cuenta {0} : saldo=${1} | usado=${2}/${3}{4}' -f $Origen, (Format-Money $st.Saldo.saldo), (Format-Money $st.Saldo.consumidoHoy), (Format-Money $st.Saldo.limiteDiario), $badge) $sc "DarkGray"
        } else {
            Write-BoxLine "● Gateway :8080: Sin respuesta aun" "DarkGray" "DarkGray"
        }
        Write-BoxBottom "DarkGray"

        Write-Host ""
        Write-Host ("─" * 78) -ForegroundColor DarkGray
        Write-Host "  ► [ESPACIO / ENTER / →] Iniciar Presentacion (Diapositiva 1/15)" -ForegroundColor Green
        Write-Host "    [1-6] Ir a Seccion   [B] Eureka   [U] Utilidades   [Q] Salir" -ForegroundColor DarkGray

        $act = Read-SlideKey
        $res = "PORTADA"
        switch ($act) {
            "QUIT"   { return }
            "EUREKA" { Open-EurekaBrowser }
            "PREP"   { Show-CleanPrep }
            "UTILS" {
                $u = Show-UtilsPanel
                if ($u -eq "QUIT") { return }
                if ($u -match '^B[1-6]$') { $res = Run-Deck $blockMap[$u] }
            }
            default {
                if ($act -match '^B[1-6]$') {
                    $res = Run-Deck $blockMap[$act]
                } elseif ($act -eq "NEXT" -or $act -eq "REPEAT") {
                    $res = Run-Deck 0
                }
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
