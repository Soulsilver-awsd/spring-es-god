#!/usr/bin/env bash
set -euo pipefail

GATEWAY="http://localhost:8080"
EUREKA="http://localhost:8761"

echo "=== P01: Descubrimiento dinamico en Eureka y acceso via Gateway ==="
curl -s -H "Accept: application/json" "$EUREKA/eureka/apps" | grep -oE '"name":"[^"]+"' || true
curl -i -s "$GATEWAY/api/cuentas/0991112233"
echo ""
curl -i -s "$GATEWAY/api/transacciones/historial/0991112233"
echo ""

echo "=== P02: Rafaga de 100 peticiones para validar balanceo HTTP ==="
for i in $(seq 1 100); do
  curl -s -D - -o /dev/null "$GATEWAY/api/cuentas/instancia" | grep -i "^X-Service-Instance:" || true
done | sort | uniq -c

echo "=== P04: Transferencia P2P valida y caso de rechazo por saldo ==="
curl -i -s -X POST "$GATEWAY/api/transacciones/transferir" \
  -H "Content-Type: application/json" \
  -d '{"celularOrigen":"0991112233","celularDestino":"0984445566","monto":25.00,"motivo":"Prueba P04"}'
echo ""
curl -i -s -X POST "$GATEWAY/api/transacciones/transferir" \
  -H "Content-Type: application/json" \
  -d '{"celularOrigen":"0991112233","celularDestino":"0984445566","monto":99999.00,"motivo":"Saldo insuficiente"}'
echo ""

echo "=== P05: 20 lecturas ordinarias en replicas y estado de BD ==="
for i in $(seq 1 20); do
  curl -s -D - -o /dev/null "$GATEWAY/api/cuentas/0991112233" | grep -i "^X-Db-Node:" || true
done | sort | uniq -c
curl -s "$GATEWAY/api/cuentas/db/estado"
echo ""

echo "=== P07: Lectura critica RYOW en PRIMARY ==="
curl -i -s "$GATEWAY/api/cuentas/0991112233/saldo-critico"
echo ""
curl -i -s -H "X-Consistencia: CRITICA" "$GATEWAY/api/cuentas/0991112233"
echo ""

echo "Nota: P03 (stop ms-cuentas-2), P06 (stop replica1) y P08 (start replica1) requieren ejecutar docker compose stop/start en paralelo."
