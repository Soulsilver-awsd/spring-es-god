$ErrorActionPreference = "Stop"

$Gateway = "http://localhost:8080"
$Eureka = "http://localhost:8761"

Write-Host "=== P01: Descubrimiento dinamico en Eureka y acceso via Gateway ==="
curl.exe -s -H "Accept: application/json" "$Eureka/eureka/apps"
Write-Host ""
curl.exe -i -s "$Gateway/api/cuentas/0991112233"
Write-Host ""
curl.exe -i -s "$Gateway/api/transacciones/historial/0991112233"
Write-Host ""

Write-Host "=== P02: Rafaga de 100 peticiones para validar balanceo HTTP ==="
$instancias = @()
for ($i = 1; $i -le 100; $i++) {
    $headers = curl.exe -s -D - -o NUL "$Gateway/api/cuentas/instancia"
    $match = ($headers | Select-String -Pattern "^X-Service-Instance:\s*(.+)$" -CaseSensitive:$false)
    if ($match) {
        $instancias += $match.Matches[0].Groups[1].Value.Trim()
    }
}
$instancias | Group-Object | Select-Object Name, Count | Format-Table -AutoSize

Write-Host "=== P04: Transferencia P2P valida y caso de rechazo por saldo ==="
curl.exe -i -s -X POST "$Gateway/api/transacciones/transferir" `
  -H "Content-Type: application/json" `
  -d '{"celularOrigen":"0991112233","celularDestino":"0984445566","monto":25.00,"motivo":"Prueba P04"}'
Write-Host ""
curl.exe -i -s -X POST "$Gateway/api/transacciones/transferir" `
  -H "Content-Type: application/json" `
  -d '{"celularOrigen":"0991112233","celularDestino":"0984445566","monto":99999.00,"motivo":"Saldo insuficiente"}'
Write-Host ""

Write-Host "=== P05: 20 lecturas ordinarias en replicas y estado de BD ==="
$nodos = @()
for ($i = 1; $i -le 20; $i++) {
    $headers = curl.exe -s -D - -o NUL "$Gateway/api/cuentas/0991112233"
    $match = ($headers | Select-String -Pattern "^X-Db-Node:\s*(.+)$" -CaseSensitive:$false)
    if ($match) {
        $nodos += $match.Matches[0].Groups[1].Value.Trim()
    }
}
$nodos | Group-Object | Select-Object Name, Count | Format-Table -AutoSize
curl.exe -s "$Gateway/api/cuentas/db/estado"
Write-Host ""

Write-Host "=== P07: Lectura critica RYOW en PRIMARY ==="
curl.exe -i -s "$Gateway/api/cuentas/0991112233/saldo-critico"
Write-Host ""
curl.exe -i -s -H "X-Consistencia: CRITICA" "$Gateway/api/cuentas/0991112233"
Write-Host ""

Write-Host "Nota: P03 (stop ms-cuentas-2), P06 (stop replica1) y P08 (start replica1) requieren ejecutar docker compose stop/start en paralelo."
