# Pruebas experimentales P01-P08 (docs/srs/06-verificacion-y-trazabilidad/01-criterios-aceptacion-p01-p08.md).
# Solo curl.exe + docker compose (PowerShell 5.1+ o 7+). Ejecutar con el entorno levantado: docker compose up -d --build
#
#   .\docs\api\curl-p01-p08.ps1             # las 8 pruebas en orden
#   .\docs\api\curl-p01-p08.ps1 P04 P07     # solo algunas
#
# P03, P06 y P08 detienen/arrancan contenedores (ms-cuentas-2, replica1) y los dejan como estaban.
# P04 y P07 transfieren 25.00 cada una desde 0991112233 (limite diario 300.00): reiniciar los datos
# con "docker compose down -v; docker compose up -d --build" tras unas 6 ejecuciones completas.
param([string[]]$Pruebas = @("P01", "P02", "P03", "P04", "P05", "P06", "P07", "P08"))

$ErrorActionPreference = "Continue"
$Gateway = if ($env:GATEWAY) { $env:GATEWAY } else { "http://localhost:8080" }
$Eureka = if ($env:EUREKA) { $env:EUREKA } else { "http://localhost:8761" }
$Origen = "0991112233"
$Destino = "0984445566"
Set-Location (Join-Path $PSScriptRoot "..\..")

$script:Pass = 0
$script:Fail = 0
$script:Fallidas = @()
$script:Actual = ""
$Tmp = Join-Path ([IO.Path]::GetTempPath()) ("p01p08-" + [guid]::NewGuid())
New-Item -ItemType Directory $Tmp | Out-Null
$HeadersFile = Join-Path $Tmp "headers"
$BodyFile = Join-Path $Tmp "body"
$JsonFile = Join-Path $Tmp "req.json"

function Titulo($id, $texto) { $script:Actual = $id; Write-Host ""; Write-Host "=== $id $texto ===" -ForegroundColor White }
function Check([bool]$cond, [string]$msg) {
    if ($cond) { $script:Pass++; Write-Host "  [OK] $msg" -ForegroundColor Green }
    else { $script:Fail++; $script:Fallidas += "$($script:Actual): $msg"; Write-Host "  [FALLA] $msg" -ForegroundColor Red }
}
function Info($msg) { Write-Host "  $msg" }
function Ms() { [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }

# Devuelve @{ Code; Headers (hashtable); Body (objeto JSON o $null) }
function Peticion([string]$Metodo, [string]$Url, [string]$Json = "", [string]$Cabecera = "") {
    $curlArgs = @("-s", "--max-time", "10", "-o", $BodyFile, "-D", $HeadersFile, "-w", "%{http_code}", "-X", $Metodo, $Url)
    if ($Json) {
        # Se envia desde archivo para evitar problemas de comillas de PowerShell con curl.exe.
        [IO.File]::WriteAllText($JsonFile, $Json)
        $curlArgs += @("-H", "Content-Type: application/json", "--data-binary", "@$JsonFile")
    }
    if ($Cabecera) { $curlArgs += @("-H", $Cabecera) }
    $code = & curl.exe @curlArgs
    $headers = @{}
    if (Test-Path $HeadersFile) {
        foreach ($l in Get-Content $HeadersFile) {
            if ($l -match "^([^:]+):\s*(.*)$") { $headers[$Matches[1].ToLower()] = $Matches[2].Trim() }
        }
    }
    $body = $null
    if ((Test-Path $BodyFile) -and (Get-Item $BodyFile).Length -gt 0) {
        try { $body = Get-Content $BodyFile -Raw | ConvertFrom-Json } catch { }
    }
    return @{ Code = "$code"; Headers = $headers; Body = $body }
}
function GetJson([string]$Url) {
    try { return (& curl.exe -s --max-time 10 -H "Accept: application/json" $Url) -join "" | ConvertFrom-Json } catch { return $null }
}
function SaldoCritico($cel) { [decimal](GetJson "$Gateway/api/cuentas/$cel/saldo-critico").datos.saldo }
function EstadoReplica($servicio, $nodo) {
    # Cada instancia tiene su propio ReplicaHealthTracker y el Gateway alterna entre ellas: para
    # ms-cuentas se consulta 2 veces seguidas (ambas instancias) y solo se reporta un valor si coinciden.
    $n = if ($servicio -eq "cuentas") { 2 } else { 1 }
    $valores = @()
    for ($i = 0; $i -lt $n; $i++) {
        $e = GetJson "$Gateway/api/$servicio/db/estado"
        $valores += if ($e) { "$((($e.replicas | Where-Object { $_.nodo -eq $nodo }).available))".ToLower() } else { "" }
    }
    if (@($valores | Select-Object -Unique).Count -eq 1) { return $valores[0] } else { return "mixto" }
}
function InstanciasUp($app) {
    $a = GetJson "$Eureka/eureka/apps/$app"
    if (-not $a) { return 0 }
    return @($a.application.instance | Where-Object { $_.status -eq "UP" }).Count
}
function Psql($sql) { docker compose exec -T primary sh -c "psql -U `"`$POSTGRES_USER`" -d `"`$POSTGRES_DB`" -Atc `"$sql`"" 2>$null }
function Transferir($de, $a, $monto, $motivo) {
    Peticion POST "$Gateway/api/transacciones/transferir" (@{ celularOrigen = $de; celularDestino = $a; monto = $monto; motivo = $motivo } | ConvertTo-Json -Compress)
}

# Lecturas ordinarias alternando contactos (ms-cuentas) e historial (ms-transacciones).
function Lecturas([int]$n) {
    $res = @()
    for ($i = 1; $i -le $n; $i++) {
        $url = if ($i % 2) { "$Gateway/api/cuentas/$Origen/contactos" } else { "$Gateway/api/transacciones/historial/$Origen" }
        $r = Peticion GET $url
        $nodo = "$($r.Headers['x-db-node'])".Split(" ")[0]
        $res += [pscustomobject]@{ Code = $r.Code; Nodo = $nodo; Fallback = $r.Headers['x-db-fallback'] }
    }
    $res | Group-Object Code, Nodo, Fallback | ForEach-Object { Info ("{0,4} {1}" -f $_.Count, $_.Name) }
    return $res
}

function P01 {
    Titulo "P01" "Descubrimiento dinamico en Eureka y acceso via Gateway"
    $apps = GetJson "$Eureka/eureka/apps"
    foreach ($app in $apps.applications.application) {
        Info ("{0}: {1}" -f $app.name, (($app.instance | ForEach-Object { "$($_.instanceId) $($_.status)" }) -join ", "))
    }
    $c = InstanciasUp "MS-CUENTAS"; $t = InstanciasUp "MS-TRANSACCIONES"
    Check ($c -eq 2) "MS-CUENTAS con 2 instancias UP ($c)"
    Check ($t -eq 1) "MS-TRANSACCIONES con 1 instancia UP ($t)"
    $r = Peticion GET "$Gateway/api/cuentas/$Origen"
    Check ($r.Code -eq "200" -and [bool]$r.Headers['x-gateway-handled']) "GET :8080/api/cuentas/$Origen -> $($r.Code) via $($r.Headers['x-service-instance']) (X-Gateway-Handled: $($r.Headers['x-gateway-handled']))"
    $r = Peticion GET "$Gateway/api/transacciones/historial/$Origen"
    Check ($r.Code -eq "200") "GET :8080/api/transacciones/historial/$Origen -> $($r.Code) via $($r.Headers['x-service-instance'])"
}

function P02 {
    Titulo "P02" "Balanceo HTTP con 120 peticiones a /api/cuentas/instancia"
    $res = @()
    for ($i = 1; $i -le 120; $i++) {
        $r = Peticion GET "$Gateway/api/cuentas/instancia"
        $res += [pscustomobject]@{ Code = $r.Code; Instancia = $r.Headers['x-service-instance'] }
    }
    $res | Group-Object Code, Instancia | ForEach-Object { Info ("{0,4} {1}" -f $_.Count, $_.Name) }
    $ok = @($res | Where-Object Code -eq "200").Count
    $n1 = @($res | Where-Object Instancia -like "ms-cuentas-1*").Count
    $n2 = @($res | Where-Object Instancia -like "ms-cuentas-2*").Count
    Check ($ok -eq 120) "120/120 respuestas 200 ($ok)"
    Check ($n1 -ge 40 -and $n2 -ge 40) "reparto equilibrado ms-cuentas-1=$n1 / ms-cuentas-2=$n2 (minimo 40 cada una)"
}

function P03 {
    Titulo "P03" "Fallo de instancia: stop/start de ms-cuentas-2 con trafico continuo"
    $log = Join-Path $Tmp "p03.txt"
    $job = Start-Job -ArgumentList $Gateway, $Origen, $log -ScriptBlock {
        param($gw, $cel, $log)
        while ($true) {
            $h = & curl.exe -s --max-time 5 -o NUL -D - -w "`n%{http_code}" "$gw/api/cuentas/$cel"
            $code = $h[-1]
            $inst = ($h | Select-String -Pattern "^X-Service-Instance:\s*(.+)$").Matches | ForEach-Object { $_.Groups[1].Value.Trim() } | Select-Object -First 1
            Add-Content $log ("{0} {1} {2}" -f [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(), $code, $inst)
            Start-Sleep -Milliseconds 200
        }
    }
    Start-Sleep 3
    $t0 = Ms
    docker compose stop ms-cuentas-2 2>&1 | Out-Null
    Info "ms-cuentas-2 detenido en $((Ms) - $t0) ms; esperando convergencia del Gateway..."
    $tdet = $null
    while (((Ms) - $t0) -lt 90000) {
        $ult = @(Get-Content $log | ForEach-Object { , ($_ -split " ") } | Where-Object { [long]$_[0] -gt $t0 } | Select-Object -Last 15)
        if ($ult.Count -eq 15 -and @($ult | Where-Object { $_[1] -eq "200" -and $_[2] -like "ms-cuentas-1*" }).Count -eq 15) { $tdet = (Ms) - $t0; break }
        Start-Sleep -Milliseconds 500
    }
    $errores = @(Get-Content $log | ForEach-Object { , ($_ -split " ") } | Where-Object { [long]$_[0] -gt $t0 -and $_[1] -ne "200" }).Count
    Check ($null -ne $tdet) "convergencia exclusiva a ms-cuentas-1 en $tdet ms"
    Info "errores transitorios durante la ventana de deteccion: $errores"
    $t1 = Ms
    docker compose start ms-cuentas-2 2>&1 | Out-Null
    Info "ms-cuentas-2 arrancado; esperando que vuelva a recibir trafico..."
    $trein = $null
    while (((Ms) - $t1) -lt 180000) {
        if (Get-Content $log | ForEach-Object { , ($_ -split " ") } | Where-Object { [long]$_[0] -gt $t1 -and $_[2] -eq "ms-cuentas-2:8082" }) { $trein = (Ms) - $t1; break }
        Start-Sleep 1
    }
    Start-Sleep 3
    Stop-Job $job; Remove-Job $job
    Check ($null -ne $trein) "ms-cuentas-2 reincorporado al balanceo en $trein ms (arranque JVM + registro Eureka)"
    Check ((InstanciasUp "MS-CUENTAS") -eq 2) "Eureka vuelve a mostrar 2 instancias UP de MS-CUENTAS"
}

function P04 {
    Titulo "P04" "Comunicacion entre servicios: transferencia exitosa y rechazo controlado"
    $s0 = SaldoCritico $Origen; $d0 = SaldoCritico $Destino
    Info "saldos iniciales: $Origen=$s0 $Destino=$d0"
    $r = Transferir $Origen $Destino 25.00 "Prueba P04"
    Info ($r.Body | Select-Object @{ n = "codigo"; e = { $_.datos.codigoComprobante } }, @{ n = "auditoria"; e = { $_.auditoriaTecnica } } | ConvertTo-Json -Compress -Depth 4)
    Check ($r.Code -eq "201") "transferencia de 25.00 -> $($r.Code)"
    $inst = $r.Body.auditoriaTecnica.instanciaCuentasConsultada
    Check ([bool]$inst) "instanciaCuentasConsultada = $inst"
    $s1 = SaldoCritico $Origen; $d1 = SaldoCritico $Destino
    Check ($s1 -eq $s0 - 25 -and $d1 -eq $d0 + 25) "origen descontado ($s0 -> $s1) y destino acreditado ($d0 -> $d1)"
    $r = Transferir $Origen $Destino 9999.00 "Saldo insuficiente"
    Check ($r.Code -eq "409") "transferencia de 9999.00 -> $($r.Code) `"$($r.Body.mensaje)`""
    $s2 = SaldoCritico $Origen
    Check ($s2 -eq $s1) "el rechazo no altera el saldo de origen ($s2)"
}

function P05 {
    Titulo "P05" "Enrutamiento de BD: escritura en PRIMARY y 20 lecturas en replicas"
    Info "pg_stat_replication en primary:"
    Psql "SELECT application_name, client_addr, state FROM pg_stat_replication" | ForEach-Object { Info "  $_" }
    $r = Transferir $Destino $Origen 1.00 "Prueba P05"
    $nodo = $r.Body.auditoriaTecnica.nodoBaseDatos
    Check ($r.Code -eq "201" -and $nodo -like "PRIMARY*recovery=false*") "escritura en $nodo"
    $res = Lecturas 20
    $r1 = @($res | Where-Object Nodo -eq "REPLICA_1").Count; $r2 = @($res | Where-Object Nodo -eq "REPLICA_2").Count
    Check (@($res | Where-Object Code -eq "200").Count -eq 20) "20/20 lecturas 200"
    Check ($r1 -ge 6 -and $r2 -ge 6) "reparto Round-Robin REPLICA_1=$r1 / REPLICA_2=$r2"
    $r = Peticion GET "$Gateway/api/cuentas/$Origen/contactos"
    Check ($r.Headers['x-db-node'] -like "REPLICA_*recovery=true*") "lectura ordinaria con recovery=true: $($r.Headers['x-db-node'])"
    Info ("/api/cuentas/db/estado: " + ((GetJson "$Gateway/api/cuentas/db/estado") | Select-Object consultasTotales, @{ n = "replicas"; e = { $_.replicas | Select-Object nodo, available } } | ConvertTo-Json -Compress -Depth 4))
}

function P06 {
    Titulo "P06" "Fallo de replica: stop replica1 durante lecturas"
    docker compose stop replica1 2>&1 | Out-Null
    Info "replica1 detenida"
    $res = Lecturas 20
    Check (@($res | Where-Object Code -eq "200").Count -eq 20) "20/20 lecturas 200 (0 fallos al cliente)"
    Info "lecturas con X-Db-Fallback: true (failover transparente antes de la sonda): $(@($res | Where-Object Fallback -eq 'true').Count)"
    Start-Sleep 4
    $res = Lecturas 10
    Check (@($res | Where-Object Nodo -eq "REPLICA_2").Count -eq 10) "tras la deteccion, 100% de lecturas en REPLICA_2"
    $a1 = EstadoReplica "cuentas" "REPLICA_1"; $a2 = EstadoReplica "cuentas" "REPLICA_2"; $a1t = EstadoReplica "transacciones" "REPLICA_1"
    Check ($a1 -eq "false" -and $a2 -eq "true") "/api/cuentas/db/estado: REPLICA_1 available=$a1, REPLICA_2 available=$a2"
    Check ($a1t -eq "false") "/api/transacciones/db/estado: REPLICA_1 available=$a1t"
}

function P07 {
    Titulo "P07" "Consistencia de lectura (RYOW): transferencia + lecturas criticas inmediatas"
    $s0 = SaldoCritico $Origen
    $r = Transferir $Origen $Destino 25.00 "Prueba P07"
    $codigo = $r.Body.datos.codigoComprobante
    Check ($r.Code -eq "201") "transferencia 25.00 -> $($r.Code) ($codigo)"
    $r = Peticion GET "$Gateway/api/cuentas/$Origen/saldo-critico"
    $s1 = [decimal]$r.Body.datos.saldo
    $a = $r.Body.auditoriaTecnica
    Check ($s1 -eq $s0 - 25) "saldo-critico inmediato descontado ($s0 -> $s1)"
    Check ($a.politicaEnrutamiento -eq "LECTURA_CRITICA_PRIMARIO" -and $a.nodoBaseDatos -like "*recovery=false*") "saldo-critico: $($a.politicaEnrutamiento) en $($a.nodoBaseDatos)"
    $r = Peticion GET "$Gateway/api/transacciones/comprobante/$codigo"
    $a = $r.Body.auditoriaTecnica
    Check ($r.Code -eq "200" -and $r.Body.datos.codigoComprobante -eq $codigo) "comprobante $codigo visible de inmediato -> $($r.Code)"
    Check ($a.politicaEnrutamiento -eq "LECTURA_CRITICA_PRIMARIO" -and $a.nodoBaseDatos -like "*recovery=false*") "comprobante: $($a.politicaEnrutamiento) en $($a.nodoBaseDatos)"
    $r = Peticion GET "$Gateway/api/cuentas/$Origen" "" "X-Consistencia: CRITICA"
    Check ($r.Headers['x-db-node'] -like "PRIMARY*recovery=false*" -and [decimal]$r.Body.datos.saldo -eq $s1) "X-Consistencia: CRITICA -> $($r.Headers['x-db-node']), saldo $($r.Body.datos.saldo)"
}

function P08 {
    Titulo "P08" "Recuperacion de replica: start replica1 y retorno al Round-Robin"
    if ((EstadoReplica "cuentas" "REPLICA_1") -eq "true") {
        Info "replica1 estaba disponible: se detiene para preparar el escenario"
        docker compose stop replica1 2>&1 | Out-Null; Start-Sleep 5
    }
    Transferir $Destino $Origen 1.00 "Prueba P08" | Out-Null
    $lsn = Psql "SELECT pg_current_wal_lsn()"
    $t0 = Ms
    docker compose start replica1 2>&1 | Out-Null
    Info "replica1 arrancada; sondeando /api/cuentas/db/estado..."
    $trec = $null
    while (((Ms) - $t0) -lt 90000) {
        if ((EstadoReplica "cuentas" "REPLICA_1") -eq "true") { $trec = (Ms) - $t0; break }
        Start-Sleep 1
    }
    Check ($null -ne $trec) "REPLICA_1 available=true en ms-cuentas-1 y ms-cuentas-2 en $trec ms (2/2 sondeos pg_is_in_recovery())"
    (GetJson "$Gateway/api/cuentas/db/estado").replicas | ForEach-Object { Info ($_ | Select-Object nodo, available, consecutiveSuccesses, lastReplayLsn | ConvertTo-Json -Compress) }
    $estado = @(Psql "SELECT application_name, client_addr, state, sent_lsn, replay_lsn FROM pg_stat_replication")
    $estado | ForEach-Object { Info "  $_" }
    Check (@($estado | Where-Object { $_ -like "*|streaming|*" }).Count -eq 2) "2 replicas en streaming en pg_stat_replication (LSN primario al detener: $lsn)"
    while ((EstadoReplica "transacciones" "REPLICA_1") -ne "true" -and ((Ms) - $t0) -lt 90000) { Start-Sleep 1 }
    $res = Lecturas 20
    $r1 = @($res | Where-Object Nodo -eq "REPLICA_1").Count
    Check ($r1 -ge 6 -and @($res | Where-Object Code -eq "200").Count -eq 20) "REPLICA_1 vuelve al Round-Robin ($r1 de 20 lecturas)"
}

try {
    foreach ($p in $Pruebas) { & $p.ToUpper() }
} finally {
    Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "=== Resumen: $($script:Pass) OK, $($script:Fail) FALLAS ===" -ForegroundColor White
$script:Fallidas | ForEach-Object { Write-Host "  - $_" }
if ($script:Fail -gt 0) { exit 1 }
