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

$RepoDir = $env:PRESENTACION_DIR.TrimEnd('\', '/')
Set-Location -LiteralPath $RepoDir

$Gateway = if ($env:GATEWAY) { $env:GATEWAY } else { "http://localhost:8080" }
$Eureka = if ($env:EUREKA) { $env:EUREKA } else { "http://localhost:8761" }
$Origen = "0991112233"
$Destino = "0984445566"

$script:ShowGuion = $true
$script:TmpDir = Join-Path ([IO.Path]::GetTempPath()) ("billetera-pres-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Path $script:TmpDir -Force | Out-Null
$script:HeadersFile = Join-Path $script:TmpDir "headers.txt"
$script:BodyFile = Join-Path $script:TmpDir "body.json"
$script:JsonFile = Join-Path $script:TmpDir "req.json"
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

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

function Write-Bar([string]$Char = "=", [string]$Color = "DarkCyan", [int]$Width = 78) {
    Write-Host ($Char * $Width) -ForegroundColor $Color
}

function Write-Header([string]$StepTag, [string]$Title, [string]$Speaker, [string]$TimeRange, [bool]$Clear = $true) {
    if ($Clear) { Clear-ScreenSafe }
    Write-Bar "=" "DarkCyan"
    Write-Host ("  BILLETERA DIGITAL DISTRIBUIDA  |  {0}" -f $StepTag) -ForegroundColor Cyan -NoNewline
    if ($Speaker) {
        Write-Host ("  |  {0} ({1})" -f $Speaker, $TimeRange) -ForegroundColor Yellow
    } else {
        Write-Host ""
    }
    Write-Host ("  {0}" -f $Title) -ForegroundColor White
    Write-Bar "=" "DarkCyan"
}

function Write-Cue([string[]]$Lines) {
    if (-not $script:ShowGuion -or -not $Lines -or $Lines.Count -eq 0) { return }
    Write-Host ""
    Write-Host "  [GUION]" -ForegroundColor DarkYellow
    foreach ($line in $Lines) {
        Write-Host ("    {0}" -f $line) -ForegroundColor Gray
    }
}

function Write-CmdTag([string]$CmdText) {
    Write-Host ""
    Write-Host ("  `$ {0}" -f $CmdText) -ForegroundColor DarkCyan
    Write-Host ""
}

function Wait-KeyPrompt([string]$Prompt, [string]$Extras = "[R] Repetir  [B] Eureka  [V] Guion  [M] Menu  [Q] Salir") {
    Write-Host ""
    Write-Bar "-" "DarkGray"
    Write-Host ("  >> {0}" -f $Prompt) -ForegroundColor Green
    if ($Extras) {
        Write-Host ("     {0}" -f $Extras) -ForegroundColor DarkGray
    }
    while ($true) {
        if ([Console]::IsInputRedirected) { return "Q" }
        $k = [Console]::ReadKey($true)
        $ch = "$($k.KeyChar)".ToUpperInvariant()
        switch ($ch) {
            "B" {
                Open-EurekaBrowser
                if ($Extras) { Write-Host "     [OK] Eureka abierto en el navegador." -ForegroundColor DarkCyan }
                continue
            }
            "V" {
                $script:ShowGuion = -not $script:ShowGuion
                $estado = if ($script:ShowGuion) { "ON" } else { "OFF" }
                if ($Extras) { Write-Host ("     [OK] Guion en pantalla: {0} (desde el siguiente paso)." -f $estado) -ForegroundColor DarkCyan }
                continue
            }
            "R" { return "R" }
            "M" { return "M" }
            "Q" { return "Q" }
            "P" { return "P" }
            "S" { return "S" }
            "T" { return "T" }
            "C" { return "C" }
            default {
                if ($ch -match '^[0-9]$') { return $ch }
                return "NEXT"
            }
        }
    }
}

function Open-EurekaBrowser {
    try { Start-Process "$Eureka" | Out-Null } catch { }
}

function Invoke-ApiRequest([string]$Method, [string]$Url, [string]$JsonBody = "", [int]$TimeoutSec = 10) {
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

function Get-ContainerHealthSummary {
    $envOk = Test-Path (Join-Path $RepoDir ".env")
    $dockerOk = $false
    $total = 0
    $healthy = 0
    $stoppedList = @()
    try {
        $out = & docker compose ps -a --format "{{.Name}}|{{.State}}|{{.Status}}" 2>$null
        if ($LASTEXITCODE -eq 0) {
            $dockerOk = $true
            foreach ($line in $out) {
                if (-not $line -or ($line -notmatch '\|')) { continue }
                $parts = $line -split '\|', 3
                $total++
                if ($parts[2] -match 'healthy') { $healthy++ }
                if ($parts[1] -ne 'running') { $stoppedList += $parts[0] }
            }
        }
    } catch { }
    $saldoInfo = $null
    $r = Invoke-ApiRequest "GET" "$Gateway/api/cuentas/$Origen/saldo-critico" "" 2
    if ($r.Code -eq "200" -and $r.Body -and $r.Body.datos) {
        $saldoInfo = $r.Body.datos
    }
    return @{
        EnvExists = $envOk
        DockerOk  = $dockerOk
        Total     = $total
        Healthy   = $healthy
        Stopped   = $stoppedList
        Saldo     = $saldoInfo
    }
}

function Invoke-EnsureEnv {
    $envPath = Join-Path $RepoDir ".env"
    $examplePath = Join-Path $RepoDir ".env.example"
    if (-not (Test-Path $envPath)) {
        if (Test-Path $examplePath) {
            Copy-Item -LiteralPath $examplePath -Destination $envPath
            Write-Host "  [OK] Se creo .env a partir de .env.example." -ForegroundColor Green
            return $true
        }
        Write-Host "  [ERROR] No existe .env ni .env.example en $RepoDir." -ForegroundColor Red
        return $false
    }
    return $true
}

function Invoke-CleanPrep {
    Write-Header "PREPARACION" "Entorno limpio pre-grabacion (down -v + up -d --build)" "Pre-toma" "Fuera de camara"
    if (-not (Invoke-EnsureEnv)) {
        [void](Wait-KeyPrompt "Pulsa una tecla para volver al menu..." "")
        return
    }
    Write-CmdTag "docker compose down -v && docker compose up -d --build"
    & docker compose down -v
    & docker compose up -d --build
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "  [ERROR] docker compose up fallo. Revisa Docker Desktop." -ForegroundColor Red
        [void](Wait-KeyPrompt "Pulsa una tecla para volver al menu..." "")
        return
    }
    Write-Host ""
    Write-Host "  Esperando a que los 8 contenedores esten healthy..." -ForegroundColor Yellow
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt 240) {
        $st = Get-ContainerHealthSummary
        Write-Host ("`r  [{0,3}s] Contenedores healthy: {1}/8   " -f [int]$sw.Elapsed.TotalSeconds, $st.Healthy) -NoNewline -ForegroundColor Cyan
        if ($st.Healthy -ge 8) {
            Write-Host ""
            Write-Host "  [OK] Los 8 contenedores estan healthy!" -ForegroundColor Green
            break
        }
        Start-Sleep -Seconds 2
    }
    Open-EurekaBrowser
    Write-Host "  [OK] Navegador abierto en $Eureka" -ForegroundColor Green
    $s = Invoke-ApiRequest "GET" "$Gateway/api/cuentas/$Origen/saldo-critico" "" 4
    if ($s.Code -eq "200" -and $s.Body.datos) {
        Write-Host ("  [OK] Cuenta {0}: saldo={1} | consumidoHoy={2} / limite={3}" -f $Origen, $s.Body.datos.saldo, $s.Body.datos.consumidoHoy, $s.Body.datos.limiteDiario) -ForegroundColor Green
    }
    [void](Wait-KeyPrompt "Entorno listo. Pulsa una tecla para volver al menu..." "")
}

function Invoke-StartAll {
    Write-Header "RECUPERAR" "Arrancando contenedores detenidos (docker compose start)" "" ""
    [void](Invoke-EnsureEnv)
    Write-CmdTag "docker compose start"
    & docker compose start
    [void](Wait-KeyPrompt "Pulsa una tecla para volver al menu..." "")
}

function Invoke-VerificationSuite {
    Write-Header "PLAN B" "Ejecutando suite automatizada P01-P08 (curl-p01-p08.ps1)" "" ""
    $ps1 = Join-Path $RepoDir "docs\api\curl-p01-p08.ps1"
    if (Test-Path $ps1) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ps1
    } else {
        Write-Host "  [ERROR] No se encontro $ps1" -ForegroundColor Red
    }
    [void](Wait-KeyPrompt "Pulsa una tecla para volver al menu..." "")
}

# --- Pasos de la presentacion ---

function Step-1A {
    Write-Header "PASO 1/15 · BLOQUE 1/6" "Arquitectura distribuida (8 contenedores)" "Persona A" "0:00 - 0:50"
    Write-Host ""
    Write-Host "  +------------------+      HTTP :8080      +------------------------+" -ForegroundColor White
    Write-Host "  |  Cliente / Demo  | -------------------> |   api-gateway (:8080)  |" -ForegroundColor Cyan
    Write-Host "  +------------------+                      +-----------+------------+" -ForegroundColor White
    Write-Host "                                                        | lb:// (Round Robin)" -ForegroundColor DarkGray
    Write-Host "  +-------------------------+                           v" -ForegroundColor White
    Write-Host "  |  eureka-server (:8761)  | <====== registro + latido 5s =======" -ForegroundColor Yellow
    Write-Host "  +-------------------------+       |              |              |" -ForegroundColor White
    Write-Host "                                    v              v              v" -ForegroundColor DarkGray
    Write-Host "                             +------------+ +------------+ +----------------+" -ForegroundColor White
    Write-Host "                             |ms-cuentas-1| |ms-cuentas-2| |ms-transacciones|" -ForegroundColor Green
    Write-Host "                             |   :8081    | |   :8082    | |     :8083      |" -ForegroundColor Green
    Write-Host "                             +-----+------+ +-----+------+ +-------+--------+" -ForegroundColor White
    Write-Host "                                   \              |                /" -ForegroundColor DarkGray
    Write-Host "                                    +----> [Enrutador JDBC] <-----+" -ForegroundColor Magenta
    Write-Host "                                            /            \" -ForegroundColor DarkGray
    Write-Host "                            Escritura/RYOW /              \ Lecturas" -ForegroundColor DarkGray
    Write-Host "                                          v                v" -ForegroundColor DarkGray
    Write-Host "                       +-----------------------+    +---------------------+" -ForegroundColor White
    Write-Host "                       | primary :5432 (R/W)   |===>| replica1 :5433 (RO) |" -ForegroundColor Blue
    Write-Host "                       | cuentas_db  |  tx_db  |WAL | replica2 :5434 (RO) |" -ForegroundColor Blue
    Write-Host "                       +-----------------------+    +---------------------+" -ForegroundColor White
    Write-Cue @(
        "- Billetera P2P: 8 contenedores, todo distribuido y con respaldo.",
        "- 2 microservicios: ms-cuentas (2 instancias) y ms-transacciones (1 instancia).",
        "- Infra: Gateway :8080, Eureka :8761, PostgreSQL 17 (1 primario + 2 replicas WAL).",
        "- Esquemas y usuarios disjuntos en BD (garantizado por PostgreSQL)."
    )
    return (Wait-KeyPrompt "Pulsa UNA TECLA para ejecutar: docker compose ps")
}

function Step-1B {
    Write-Header "PASO 2/15 · BLOQUE 1/6" "Contenedores activos en Docker Compose" "Persona A" "0:00 - 0:50"
    Write-CmdTag "docker compose ps"
    $out = & docker compose ps --format "table {{.Name}}\t{{.Service}}\t{{.Status}}\t{{.Ports}}" 2>$null
    if ($LASTEXITCODE -eq 0 -and $out) {
        $out | ForEach-Object {
            if ($_ -match 'healthy') { Write-Host ("  " + $_) -ForegroundColor Green }
            elseif ($_ -match '^NAME') { Write-Host ("  " + $_) -ForegroundColor Cyan }
            else { Write-Host ("  " + $_) -ForegroundColor Yellow }
        }
    } else {
        & docker compose ps
    }
    Write-Cue @(
        "- Senalar los 8 contenedores en estado (healthy)."
    )
    return (Wait-KeyPrompt "Pulsa UNA TECLA para ir al Bloque 2 (Persona B - Eureka)")
}

function Step-2A {
    Write-Header "PASO 3/15 · BLOQUE 2/6" "Descubrimiento dinamico en Eureka" "Persona B" "0:50 - 1:40"
    Write-CmdTag "GET $Eureka/eureka/apps  (Navegador: $Eureka)"
    $r = Invoke-ApiRequest "GET" "$Eureka/eureka/apps" "" 5
    if ($r.Code -eq "200" -and $r.Body -and $r.Body.applications) {
        foreach ($app in $r.Body.applications.application) {
            $insts = @($app.instance | ForEach-Object { "$($_.instanceId) [$($_.status)]" }) -join "  ,  "
            $color = if ($app.name -eq "MS-CUENTAS") { "Green" } else { "Cyan" }
            Write-Host ("  {0,-18} -> {1}" -f $app.name, $insts) -ForegroundColor $color
        }
    } else {
        Write-Host ("  [AVISO] No se pudo consultar Eureka en {0} (HTTP {1})." -f $Eureka, $r.Code) -ForegroundColor Red
    }
    Write-Cue @(
        "- Mostrar Eureka en navegador (pulsa [B] si quieres abrirlo ahora).",
        "- MS-CUENTAS con 2 instancias UP (8081 y 8082) y MS-TRANSACCIONES con 1.",
        "- Gateway resuelve por nombre 'ms-cuentas' y aplica Round Robin."
    )
    return (Wait-KeyPrompt "Pulsa UNA TECLA para ejecutar: balanceo (20 peticiones)")
}

function Step-2B {
    Write-Header "PASO 4/15 · BLOQUE 2/6" "Balanceo HTTP Round Robin (20 peticiones)" "Persona B" "0:50 - 1:40"
    Write-CmdTag "balanceo  # 20 x GET $Gateway/api/cuentas/instancia"
    $results = @()
    for ($i = 1; $i -le 20; $i++) {
        $r = Invoke-ApiRequest "GET" "$Gateway/api/cuentas/instancia" "" 5
        $inst = if ($r.Headers["x-service-instance"]) { $r.Headers["x-service-instance"] } else { "sin-cabecera" }
        $results += [pscustomobject]@{ Code = $r.Code; Instance = $inst }
    }
    $grouped = $results | Group-Object Code, Instance | Sort-Object Name
    foreach ($g in $grouped) {
        $first = $g.Group[0]
        $code = $first.Code
        $inst = $first.Instance
        $bar = "#" * [Math]::Min($g.Count, 20)
        $color = if ($code -eq "200") { "Green" } else { "Red" }
        Write-Host ("  {0,4}  {1}  {2,-22}  {3}" -f $g.Count, $code, $inst, $bar) -ForegroundColor $color
    }
    Write-Cue @(
        "- Veinte peticiones, diez y diez, cero errores. Parejo, como debe ser."
    )
    return (Wait-KeyPrompt "Pulsa UNA TECLA para ir al Bloque 3 (transferir 25)")
}

function Invoke-TransferDisplay([decimal]$Amount, [string]$Label) {
    $payload = @{
        celularOrigen  = $Origen
        celularDestino = $Destino
        monto          = $Amount
        motivo         = "Demo video"
    } | ConvertTo-Json -Compress
    Write-CmdTag ("{0}  # POST {1}/api/transacciones/transferir (monto={2})" -f $Label, $Gateway, $Amount)
    $r = Invoke-ApiRequest "POST" "$Gateway/api/transacciones/transferir" $payload 10
    $isOk = ($r.Code -eq "201" -or $r.Code -eq "200")
    $badgeColor = if ($isOk) { "Green" } else { "Yellow" }
    Write-Host ("  HTTP {0}" -f $r.Code) -ForegroundColor $badgeColor
    if ($r.Body) {
        $out = [ordered]@{
            mensaje          = $r.Body.mensaje
            codigo           = if ($r.Body.datos) { $r.Body.datos.codigoComprobante } else { $null }
            nuevoSaldoOrigen = if ($r.Body.datos) { $r.Body.datos.nuevoSaldoOrigen } else { $null }
            instanciaCuentas = if ($r.Body.auditoriaTecnica) { $r.Body.auditoriaTecnica.instanciaCuentasConsultada } else { $null }
            nodoBD           = if ($r.Body.auditoriaTecnica) { $r.Body.auditoriaTecnica.nodoBaseDatos } else { $null }
            politica         = if ($r.Body.auditoriaTecnica) { $r.Body.auditoriaTecnica.politicaEnrutamiento } else { $null }
        }
        $jsonPretty = $out | ConvertTo-Json -Depth 4
        foreach ($line in ($jsonPretty -split "`r?`n")) {
            $c = if ($line -match 'instanciaCuentas|nodoBD|codigo') { "Cyan" } elseif ($line -match 'Saldo insuficiente') { "Red" } else { "White" }
            Write-Host ("  " + $line) -ForegroundColor $c
        }
    } else {
        Write-Host ("  {0}" -f $r.Raw) -ForegroundColor Red
    }
}

function Step-3A {
    Write-Header "PASO 5/15 · BLOQUE 3/6" "Comunicacion entre servicios (transferencia exitosa)" "Persona B" "1:40 - 2:25"
    Invoke-TransferDisplay 25 "transferir 25"
    Write-Cue @(
        "- Senalar HTTP 201, codigoComprobante e instanciaCuentasConsultada.",
        "- ms-transacciones llamo a ms-cuentas por nombre via Eureka (transaccion ACID)."
    )
    return (Wait-KeyPrompt "Pulsa UNA TECLA para ejecutar: transferir 9999 (error controlado)")
}

function Step-3B {
    # No limpiamos pantalla para mantener visible nodoBD de la transferencia previa (guion Bloque 4)
    Write-Host ""
    Write-Bar "-" "DarkCyan"
    Write-Host "  PASO 6/15 · BLOQUE 3/6  |  Validacion y rechazo controlado" -ForegroundColor Cyan
    Invoke-TransferDisplay 9999 "transferir 9999"
    Write-Cue @(
        "- 409, saldo insuficiente. Error controlado y el saldo no se toca.",
        "- Pasar la palabra: 'C, y la base de datos?'"
    )
    return (Wait-KeyPrompt "Pulsa UNA TECLA para ir al Bloque 4 (Persona C - lecturas)")
}

function Invoke-LecturasBlock {
    Write-CmdTag "lecturas  # 20 lecturas ordinarias (10x contactos + 10x historial)"
    $results = @()
    for ($i = 1; $i -le 10; $i++) {
        foreach ($path in @("cuentas/$Origen/contactos", "transacciones/historial/$Origen")) {
            $r = Invoke-ApiRequest "GET" "$Gateway/api/$path" "" 5
            $node = if ($r.Headers["x-db-node"]) { $r.Headers["x-db-node"] } else { "desconocido" }
            $fb = if ($r.Headers["x-db-fallback"]) { $r.Headers["x-db-fallback"] } else { "false" }
            $results += [pscustomobject]@{ Code = $r.Code; Node = $node; Fallback = $fb }
        }
    }
    $grouped = $results | Group-Object Code, Node, Fallback | Sort-Object Name
    foreach ($g in $grouped) {
        $first = $g.Group[0]
        $code = $first.Code
        $node = $first.Node
        $fb = $first.Fallback
        $c = if ($code -ne "200") { "Red" } elseif ($fb -eq "true") { "Yellow" } else { "Green" }
        Write-Host ("  {0,4}  {1}  {2}  fallback={3}" -f $g.Count, $code, $node, $fb) -ForegroundColor $c
    }
}

function Step-4A {
    Write-Header "PASO 7/15 · BLOQUE 4/6" "Persistencia replicada (escritura PRIMARY vs lecturas REPLICA)" "Persona C" "2:25 - 3:10"
    Invoke-LecturasBlock
    Write-Cue @(
        "- Escritura anterior fue a PRIMARY (recovery=false).",
        "- Estas 20 lecturas: mitad REPLICA_1 y mitad REPLICA_2, recovery=true, con su propia IP.",
        "- Para ver mi saldo recien pagado al instante: lectura critica (RYOW)."
    )
    return (Wait-KeyPrompt "Pulsa UNA TECLA para ejecutar: critico (saldo-critico)")
}

function Step-4B {
    Write-Host ""
    Write-Bar "-" "DarkCyan"
    Write-Host "  PASO 8/15 · BLOQUE 4/6  |  Lectura critica (Read-Your-Own-Writes)" -ForegroundColor Cyan
    Write-CmdTag "critico  # GET $Gateway/api/cuentas/$Origen/saldo-critico"
    $r = Invoke-ApiRequest "GET" "$Gateway/api/cuentas/$Origen/saldo-critico" "" 5
    if ($r.Code -eq "200" -and $r.Body) {
        $out = [ordered]@{
            saldo    = $r.Body.datos.saldo
            nodoBD   = $r.Body.auditoriaTecnica.nodoBaseDatos
            politica = $r.Body.auditoriaTecnica.politicaEnrutamiento
        }
        $jsonPretty = $out | ConvertTo-Json -Depth 4
        foreach ($line in ($jsonPretty -split "`r?`n")) {
            $c = if ($line -match 'PRIMARY|LECTURA_CRITICA|saldo') { "Green" } else { "White" }
            Write-Host ("  " + $line) -ForegroundColor $c
        }
    } else {
        Write-Host ("  HTTP {0}: {1}" -f $r.Code, $r.Raw) -ForegroundColor Red
    }
    Write-Cue @(
        "- Directo al primario, con el saldo ya descontado (475.00). Read-your-own-writes."
    )
    return (Wait-KeyPrompt "Pulsa UNA TECLA para ir al Bloque 5a (Trafico continuo + fallo instancia)")
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

function Step-5A {
    Write-Header "PASO 9/15 · BLOQUE 5a/6" "Simulacion de fallo: caida de ms-cuentas-2 con trafico en vivo" "Persona C" "3:10 - 3:45"
    Write-Cue @(
        "- Trafico constante alternando ms-cuentas-1 y ms-cuentas-2.",
        "- Pulsa 1 TECLA para tumbar ms-cuentas-2 -> observa 0 errores y solo :8081.",
        "- Pulsa 1 TECLA para arrancarla (no esperar) y 1 TECLA para cortar trafico."
    )
    Write-Host ""
    Write-Bar "-" "DarkGray"
    Write-Host "  [FASE 1/3] Trafico activo. Pulsa [CUALQUIER TECLA] para TUMBAR ms-cuentas-2 (Q=salir)" -ForegroundColor Yellow
    Write-Bar "-" "DarkGray"

    $phase = 1
    $totalReq = 0
    $errReq = 0
    $stopProc = $null
    $stopReported = $false
    $startProc = $null
    $startReported = $false
    $abortTo = $null

    try {
        while ($true) {
            # Verificar fin de procesos docker en segundo plano
            if ($stopProc -and -not $stopReported -and $stopProc.HasExited) {
                $stopReported = $true
                Write-Host "  >>> [OK] Contenedor ms-cuentas-2 detenido. Trafico absorbido 100% por ms-cuentas-1!" -ForegroundColor Green
            }
            if ($startProc -and -not $startReported -and $startProc.HasExited) {
                $startReported = $true
                Write-Host "  >>> [OK] docker compose start ms-cuentas-2 lanzado (~25s de arranque JVM)." -ForegroundColor Cyan
            }

            $r = Invoke-ApiRequest "GET" "$Gateway/api/cuentas/$Origen" "" 3
            $totalReq++
            $ts = (Get-Date).ToString("HH:mm:ss")
            $inst = if ($r.Headers["x-service-instance"]) { $r.Headers["x-service-instance"] } else { "sin-instancia" }
            if ($r.Code -ne "200") {
                $errReq++
                Write-Host ("  [{0}] {1} {2}" -f $ts, $r.Code, $inst) -ForegroundColor Red
            } elseif ($inst -like "ms-cuentas-2*") {
                Write-Host ("  [{0}] {1} {2}" -f $ts, $r.Code, $inst) -ForegroundColor Cyan
            } else {
                Write-Host ("  [{0}] {1} {2}" -f $ts, $r.Code, $inst) -ForegroundColor Green
            }

            # Esperar ~300ms comprobando teclado cada 40ms
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            while ($sw.ElapsedMilliseconds -lt 300) {
                if (-not [Console]::IsInputRedirected -and [Console]::KeyAvailable) {
                    $k = [Console]::ReadKey($true)
                    $ch = "$($k.KeyChar)".ToUpperInvariant()
                    if ($ch -eq "Q") { $abortTo = "Q"; break }
                    if ($ch -eq "M") { $abortTo = "M"; break }
                    if ($phase -eq 1) {
                        $phase = 2
                        Write-Host ""
                        Write-Host "  >>> [ACCION] Ejecutando: docker compose stop ms-cuentas-2 ..." -ForegroundColor Magenta
                        $stopProc = Start-BackgroundDocker "stop ms-cuentas-2"
                        Write-Host "  [FASE 2/3] Pulsa [CUALQUIER TECLA] cuando quieras ARRANCAR ms-cuentas-2" -ForegroundColor Yellow
                    } elseif ($phase -eq 2) {
                        $phase = 3
                        Write-Host ""
                        Write-Host "  >>> [ACCION] Ejecutando: docker compose start ms-cuentas-2 (en segundo plano) ..." -ForegroundColor Magenta
                        $startProc = Start-BackgroundDocker "start ms-cuentas-2"
                        Write-Host "  [FASE 3/3] Pulsa [CUALQUIER TECLA] para cortar trafico y pasar a Persona A (Bloque 5b)" -ForegroundColor Yellow
                    } else {
                        $abortTo = "DONE"
                        break
                    }
                }
                Start-Sleep -Milliseconds 40
            }
            if ($abortTo) { break }
        }
    } finally {
        if ($stopProc -and -not $stopProc.HasExited) { try { $stopProc.WaitForExit(3000) | Out-Null } catch { } }
        if ($startProc -and -not $startProc.HasExited) { try { $startProc.WaitForExit(2000) | Out-Null } catch { } }
    }

    if ($abortTo -eq "Q" -or $abortTo -eq "M") { return $abortTo }

    Write-Host ""
    Write-Bar "-" "DarkCyan"
    $errColor = if ($errReq -eq 0) { "Green" } else { "Red" }
    Write-Host ("  Resumen trafico: {0} peticiones | Errores (!=200): {1}" -f $totalReq, $errReq) -ForegroundColor $errColor
    Write-Cue @(
        "- Cero errores para el usuario. La volvemos a prender y regresa sola (~25s).",
        "- Pasar la palabra a Persona A."
    )
    return (Wait-KeyPrompt "Pulsa UNA TECLA para ir al Bloque 5b (Persona A - Caida replica PG)")
}

function Step-5B-Intro {
    Write-Header "PASO 10/15 · BLOQUE 5b/6" "Simulacion de fallo: caida de replica1 PostgreSQL" "Persona A" "3:45 - 4:20"
    Write-Cue @(
        "- 'Ahora lo pesado: apagamos una replica de la base de datos.'",
        "- Al pulsar una tecla se detiene replica1 y se lanzan 20 lecturas."
    )
    return (Wait-KeyPrompt "Pulsa UNA TECLA para ejecutar: docker compose stop replica1 + lecturas")
}

function Step-5B-StopAndReads {
    Write-Header "PASO 11/15 · BLOQUE 5b/6" "replica1 detenida -> 20 lecturas con failover transparente" "Persona A" "3:45 - 4:20"
    Write-CmdTag "docker compose stop replica1"
    & docker compose stop replica1
    Invoke-LecturasBlock
    Write-Cue @(
        "- Todas las lecturas siguen dando 200, todas en REPLICA_2.",
        "- Las que dicen fallback=true se intentaron en la caida y se rescataron solas."
    )
    return (Wait-KeyPrompt "Pulsa UNA TECLA para ejecutar: estado (ver salud de replicas)")
}

function Show-DbEstado {
    Write-CmdTag "estado  # GET $Gateway/api/cuentas/db/estado"
    $r = Invoke-ApiRequest "GET" "$Gateway/api/cuentas/db/estado" "" 5
    if ($r.Code -eq "200" -and $r.Body) {
        if ($r.Body.servicio) {
            Write-Host ("  servicio: {0}" -f $r.Body.servicio) -ForegroundColor DarkGray
        }
        foreach ($rep in $r.Body.replicas) {
            $avail = "$($rep.available)".ToLowerInvariant()
            $c = if ($rep.available) { "Green" } else { "Red" }
            Write-Host ("  {{ ""nodo"": ""{0}"", ""available"": {1}, ""consecutiveSuccesses"": {2}, ""lastReplayLsn"": ""{3}"" }}" -f $rep.nodo, $avail, $rep.consecutiveSuccesses, $rep.lastReplayLsn) -ForegroundColor $c
        }
    } else {
        Write-Host ("  HTTP {0}: {1}" -f $r.Code, $r.Raw) -ForegroundColor Red
    }
}

function Step-5B-EstadoDown {
    Write-Host ""
    Write-Bar "-" "DarkCyan"
    Write-Host "  PASO 12/15 · BLOQUE 5b/6  |  Estado de replicas tras el sondeo (cada 3s)" -ForegroundColor Cyan
    Show-DbEstado
    Write-Cue @(
        "- Cada 3 segundos se revisa la salud: REPLICA_1 available=false (fuera de ronda).",
        "- 'Y cuando vuelve?'"
    )
    return (Wait-KeyPrompt "Pulsa UNA TECLA para arrancar replica1 (docker compose start replica1)")
}

function Step-5B-StartReplica {
    Write-Header "PASO 13/15 · BLOQUE 5b/6" "Recuperacion automatica de replica1 (WAL + 2/2 chequeos)" "Persona A" "3:45 - 4:20"
    Write-CmdTag "docker compose start replica1"
    & docker compose start replica1
    Write-Host ""
    Write-Host "  [TIP] Habla ~8 segundos mientras replica1 sincroniza WAL y pasa 2 chequeos..." -ForegroundColor Yellow
    Write-Cue @(
        "- 'Se pone al dia con el primario, pasa dos chequeos seguidos para demostrar que esta sana",
        "   y vuelve a la ronda. Sin tocar nada a mano.'"
    )
    return (Wait-KeyPrompt "Cuando pasen ~8s, pulsa UNA TECLA para consultar estado")
}

function Step-5B-EstadoUp {
    Write-Host ""
    Write-Bar "-" "DarkCyan"
    Write-Host "  PASO 14/15 · BLOQUE 5b/6  |  Estado tras recuperacion (pulsa [R] si aun esta en chequeo 1/2)" -ForegroundColor Cyan
    Show-DbEstado
    Write-Cue @(
        "- REPLICA_1 available=true! Vuelve al Round-Robin sin tocar nada a mano."
    )
    return (Wait-KeyPrompt "Pulsa UNA TECLA para ir al Bloque 6 (Conclusiones)")
}

function Step-6 {
    Write-Header "PASO 15/15 · BLOQUE 6/6" "Conclusiones tecnicas del equipo" "A, B y C" "4:20 - 5:00"
    Write-Host ""
    Write-Host "  [A · DECISIONES]                 [B · LIMITACIONES]               [C · MEJORAS]" -ForegroundColor Cyan
    Write-Host "  -------------------------------  -------------------------------  -------------------------------" -ForegroundColor DarkGray
    $rows = @(
        @("- Enrutamiento BD por @UsarNodo:", "- Si cae el primario no hay",      "- Failover automatico primario"),
        @("  escritura/critica -> primario",  "  promocion automatica",           "  con Patroni o repmgr"),
        @("  lecturas -> replicas",           "- Eureka es unico (SPOF)",         "- Claves de idempotencia en"),
        @("- Round Robin con chequeo 2 de 2", "- /movimiento-interno expuesto",   "  transferencias"),
        @("- Eureka sin cache solo lectura",  "  por el Gateway",                 "- Reintento de conexion en"),
        @("  + retry GET (0 errores P03)",    "- Limite diario no se reinicia",   "  ms-transacciones"),
        @("- Flyway con advisory lock",       "- Sin idempotencia si ms-cuentas", "- Healthcheck Eureka a salud real"),
        @("  para arranque paralelo",         "  tarda mas del timeout",          "- Bloquear ruta interna + Sagas")
    )
    foreach ($r in $rows) {
        Write-Host ("  {0,-32} " -f $r[0]) -ForegroundColor Green -NoNewline
        Write-Host ("{0,-32} " -f $r[1]) -ForegroundColor Yellow -NoNewline
        Write-Host ("{0}" -f $r[2]) -ForegroundColor White
    }
    Write-Host ""
    Write-Bar "-" "DarkCyan"
    Write-Host "  LOS TRES: ""Mas de uno de todo, y saber esquivar al que falla. Eso es un sistema distribuido. Gracias!""" -ForegroundColor Cyan
    return (Wait-KeyPrompt "Presentacion completada! Pulsa una tecla para ir al Menu (Q=salir)")
}

# --- Motor de navegacion por pasos ---

function Run-FromStep([int]$StartIndex) {
    $steps = @(
        "Step-1A",
        "Step-1B",
        "Step-2A",
        "Step-2B",
        "Step-3A",
        "Step-3B",
        "Step-4A",
        "Step-4B",
        "Step-5A",
        "Step-5B-Intro",
        "Step-5B-StopAndReads",
        "Step-5B-EstadoDown",
        "Step-5B-StartReplica",
        "Step-5B-EstadoUp",
        "Step-6"
    )
    $idx = $StartIndex
    while ($idx -ge 0 -and $idx -lt $steps.Count) {
        $action = & $steps[$idx]
        switch ($action) {
            "R" { continue }
            "B" { Open-EurekaBrowser; continue }
            "V" { $script:ShowGuion = -not $script:ShowGuion; continue }
            "M" { return "MENU" }
            "Q" { return "QUIT" }
            default { $idx++ }
        }
    }
    return "MENU"
}

function Show-MainMenu {
    while ($true) {
        Clear-ScreenSafe
        Write-Bar "=" "DarkCyan"
        Write-Host "  PRESENTADOR INTERACTIVO (1 TECLA)  ·  BILLETERA DIGITAL DISTRIBUIDA" -ForegroundColor Cyan
        Write-Host "  Basado en guion.md  |  Duracion objetivo: 5:00  |  Elenco: A, B y C" -ForegroundColor DarkGray
        Write-Bar "=" "DarkCyan"

        $st = Get-ContainerHealthSummary
        Write-Host ""
        if (-not $st.EnvExists) {
            Write-Host "  [AVISO] Falta .env en el repo (usa [P] Preparacion limpia o [C] para copiar .env.example)." -ForegroundColor Yellow
        }
        if ($st.DockerOk) {
            $cColor = if ($st.Healthy -ge 8) { "Green" } else { "Yellow" }
            Write-Host ("  Contenedores: {0}/8 healthy (total visibles: {1})" -f $st.Healthy, $st.Total) -ForegroundColor $cColor
            if ($st.Stopped.Count -gt 0) {
                Write-Host ("  Detenidos:    {0}  (usa [S] para arrancarlos)" -f ($st.Stopped -join ", ")) -ForegroundColor Red
            }
        } else {
            Write-Host "  Docker:       No responde el daemon (enciende Docker Desktop antes de grabar)." -ForegroundColor Red
        }
        if ($st.Saldo) {
            $cons = [decimal]$st.Saldo.consumidoHoy
            $sColor = if ($cons -eq 0) { "Green" } else { "Yellow" }
            Write-Host ("  Cuenta {0}: saldo={1} | consumidoHoy={2} / {3}" -f $Origen, $st.Saldo.saldo, $st.Saldo.consumidoHoy, $st.Saldo.limiteDiario) -ForegroundColor $sColor
            if ($cons -gt 0) {
                Write-Host "  [TIP] Para la toma buena, [P] reinicia saldo a 500.00 y consumidoHoy a 0.00." -ForegroundColor Yellow
            }
        } else {
            Write-Host "  Gateway :8080: Sin respuesta aun." -ForegroundColor DarkGray
        }

        Write-Host ""
        Write-Bar "-" "DarkGray"
        Write-Host "  MODO PRESENTACION (solo pulsa 1 tecla para avanzar):" -ForegroundColor White
        Write-Host "    [ESPACIO / ENTER]  Iniciar presentacion completa desde Bloque 1" -ForegroundColor Green
        Write-Host ""
        Write-Host "  SALTAR A UN BLOQUE:" -ForegroundColor White
        Write-Host "    [1] Bloque 1 · Arquitectura (Persona A · 0:00-0:50)" -ForegroundColor Cyan
        Write-Host "    [2] Bloque 2 · Descubrimiento y balanceo (Persona B · 0:50-1:40)" -ForegroundColor Cyan
        Write-Host "    [3] Bloque 3 · Comunicacion entre servicios (Persona B · 1:40-2:25)" -ForegroundColor Cyan
        Write-Host "    [4] Bloque 4 · Persistencia replicada (Persona C · 2:25-3:10)" -ForegroundColor Cyan
        Write-Host "    [5] Bloque 5 · Simulacion de fallos (C -> A · 3:10-4:20)" -ForegroundColor Cyan
        Write-Host "    [6] Bloque 6 · Conclusiones 3 columnas (A, B, C · 4:20-5:00)" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  UTILIDADES PRE-GRABACION / PLAN B:" -ForegroundColor White
        $guionEstado = if ($script:ShowGuion) { "ON" } else { "OFF" }
        Write-Host ("    [P] Preparacion limpia (down -v + up -d --build + abrir Eureka)") -ForegroundColor Yellow
        Write-Host ("    [B] Abrir Eureka en navegador ($Eureka)   [S] Arrancar detenidos") -ForegroundColor DarkGray
        Write-Host ("    [V] Guion en pantalla: {0,-3}                  [T] Suite P01-P08 (Plan B)" -f $guionEstado) -ForegroundColor DarkGray
        Write-Host ("    [C] Crear .env desde .env.example          [Q] Salir") -ForegroundColor DarkGray
        Write-Bar "-" "DarkGray"

        if ([Console]::IsInputRedirected) { break }
        $k = [Console]::ReadKey($true)
        $ch = "$($k.KeyChar)".ToUpperInvariant()
        $res = "MENU"
        switch ($ch) {
            "Q" { return }
            "P" { Invoke-CleanPrep }
            "B" { Open-EurekaBrowser }
            "S" { Invoke-StartAll }
            "T" { Invoke-VerificationSuite }
            "C" { [void](Invoke-EnsureEnv); Start-Sleep -Seconds 1 }
            "V" { $script:ShowGuion = -not $script:ShowGuion }
            "1" { $res = Run-FromStep 0 }
            "2" { $res = Run-FromStep 2 }
            "3" { $res = Run-FromStep 4 }
            "4" { $res = Run-FromStep 6 }
            "5" { $res = Run-FromStep 8 }
            "6" { $res = Run-FromStep 14 }
            default { $res = Run-FromStep 0 }
        }
        if ($res -eq "QUIT") { return }
    }
}

try {
    Show-MainMenu
} finally {
    Invoke-Cleanup
}
