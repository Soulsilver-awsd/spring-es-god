#!/usr/bin/env bash
# Pruebas experimentales P01-P08 (docs/srs/06-verificacion-y-trazabilidad/01-criterios-aceptacion-p01-p08.md).
# Solo curl + jq + docker compose. Ejecutar con el entorno levantado: docker compose up -d --build
#
#   ./docs/api/curl-p01-p08.sh            # las 8 pruebas en orden
#   ./docs/api/curl-p01-p08.sh P04 P07    # solo algunas
#
# P03, P06 y P08 detienen/arrancan contenedores (ms-cuentas-2, replica1) y los dejan como estaban.
# P04 y P07 transfieren 25.00 cada una desde 0991112233 (limite diario 300.00): reiniciar los datos
# con "docker compose down -v && docker compose up -d --build" tras unas 6 ejecuciones completas.
set -uo pipefail
# Separador decimal "." en printf/sort aunque el sistema este en es_*.
export LC_ALL=C

GATEWAY="${GATEWAY:-http://localhost:8080}"
EUREKA="${EUREKA:-http://localhost:8761}"
ORIGEN="0991112233"
DESTINO="0984445566"

cd "$(dirname "$0")/../.." || exit 1
command -v jq >/dev/null || { echo "Se requiere jq"; exit 1; }

PASS=0
FAIL=0
FALLIDAS=()
ACTUAL=""
TMP="$(mktemp -d)"
TRAFICO_PID=0
trap '[ "$TRAFICO_PID" -gt 0 ] && kill "$TRAFICO_PID" 2>/dev/null; rm -rf "$TMP"' EXIT

titulo() { ACTUAL="$1"; printf '\n\033[1m=== %s ===\033[0m\n' "$*"; }
ok()     { PASS=$((PASS + 1)); printf '  \033[32m[OK]\033[0m %s\n' "$1"; }
falla()  { FAIL=$((FAIL + 1)); FALLIDAS+=("$ACTUAL: $1"); printf '  \033[31m[FALLA]\033[0m %s\n' "$1"; }
check()  { if eval "$1"; then ok "$2"; else falla "$2"; fi; }
info()   { printf '  %s\n' "$*"; }
ms()     { date +%s%3N; }

# GET/POST que guarda cabeceras y cuerpo; imprime el codigo HTTP.
peticion() { # metodo url [json] [cabecera]
  local args=(-s --max-time 10 -o "$TMP/body" -D "$TMP/headers" -w '%{http_code}' -X "$1" "$2")
  [ -n "${3:-}" ] && args+=(-H 'Content-Type: application/json' -d "$3")
  [ -n "${4:-}" ] && args+=(-H "$4")
  curl "${args[@]}" || echo 000
}
cabecera() { grep -i "^$1:" "$TMP/headers" | head -1 | cut -d' ' -f2- | tr -d '\r'; }
cuerpo()   { jq -r "$1" "$TMP/body" 2>/dev/null; }

saldo_critico() {
  curl -s --max-time 10 "$GATEWAY/api/cuentas/$1/saldo-critico" | jq -r '.datos.saldo'
}
estado_replica() { # servicio nodo -> available
  # Cada instancia tiene su propio ReplicaHealthTracker y el Gateway alterna entre ellas: para
  # ms-cuentas se consultan 2 veces seguidas (ambas instancias) y solo se reporta un valor si coinciden.
  local n=1 v r=""
  [ "$1" = cuentas ] && n=2
  for _ in $(seq 1 "$n"); do
    v=$(curl -s --max-time 10 "$GATEWAY/api/$1/db/estado" | jq -r --arg n "$2" '.replicas[] | select(.nodo == $n) | .available')
    if [ -z "$r" ] || [ "$r" = "$v" ]; then r="$v"; else r="mixto"; fi
  done
  echo "$r"
}
instancias_up() {
  curl -s --max-time 10 -H 'Accept: application/json' "$EUREKA/eureka/apps/$1" \
    | jq '[.application.instance[]? | select(.status == "UP")] | length' 2>/dev/null || echo 0
}
iguales() { [ "$(printf '%.2f' "$1")" = "$(printf '%.2f' "$2")" ]; }

# Lecturas ordinarias alternando contactos (ms-cuentas) e historial (ms-transacciones).
# Deja en $TMP/lecturas lineas "codigo nodo fallback".
lecturas() {
  : > "$TMP/lecturas"
  local i url code
  for i in $(seq 1 "$1"); do
    if (( i % 2 )); then url="$GATEWAY/api/cuentas/$ORIGEN/contactos"; else url="$GATEWAY/api/transacciones/historial/$ORIGEN"; fi
    code=$(peticion GET "$url")
    echo "$code $(cabecera X-Db-Node | cut -d' ' -f1) $(cabecera X-Db-Fallback)" >> "$TMP/lecturas"
  done
}
contar() { grep -c -- "$1" "$TMP/lecturas" || true; }

p01() {
  titulo "P01" "Descubrimiento dinamico en Eureka y acceso via Gateway"
  local cuentas tx
  cuentas=$(instancias_up MS-CUENTAS); tx=$(instancias_up MS-TRANSACCIONES)
  curl -s -H 'Accept: application/json' "$EUREKA/eureka/apps" \
    | jq -r '.applications.application[] | "  \(.name): \([.instance[] | "\(.instanceId) \(.status)"] | join(", "))"'
  check '[ "$cuentas" -eq 2 ]' "MS-CUENTAS con 2 instancias UP ($cuentas)"
  check '[ "$tx" -eq 1 ]' "MS-TRANSACCIONES con 1 instancia UP ($tx)"
  local c1 c2
  c1=$(peticion GET "$GATEWAY/api/cuentas/$ORIGEN")
  check '[ "$c1" = 200 ] && [ -n "$(cabecera X-Gateway-Handled)" ]' "GET :8080/api/cuentas/$ORIGEN -> $c1 via $(cabecera X-Service-Instance) (X-Gateway-Handled: $(cabecera X-Gateway-Handled))"
  c2=$(peticion GET "$GATEWAY/api/transacciones/historial/$ORIGEN")
  check '[ "$c2" = 200 ]' "GET :8080/api/transacciones/historial/$ORIGEN -> $c2 via $(cabecera X-Service-Instance)"
}

p02() {
  titulo "P02" "Balanceo HTTP con 120 peticiones a /api/cuentas/instancia"
  : > "$TMP/p02"
  local i code
  for i in $(seq 1 120); do
    code=$(peticion GET "$GATEWAY/api/cuentas/instancia")
    echo "$code $(cabecera X-Service-Instance)" >> "$TMP/p02"
  done
  sort "$TMP/p02" | uniq -c | sed 's/^/  /'
  local exitos n1 n2
  exitos=$(grep -c '^200 ' "$TMP/p02"); n1=$(grep -c 'ms-cuentas-1' "$TMP/p02"); n2=$(grep -c 'ms-cuentas-2' "$TMP/p02")
  check '[ "$exitos" -eq 120 ]' "120/120 respuestas 200 ($exitos)"
  check '[ "$n1" -ge 40 ] && [ "$n2" -ge 40 ]' "reparto equilibrado ms-cuentas-1=$n1 / ms-cuentas-2=$n2 (minimo 40 cada una)"
}

p03() {
  titulo "P03" "Fallo de instancia: stop/start de ms-cuentas-2 con trafico continuo"
  : > "$TMP/p03"
  ( while :; do
      r=$(curl -s --max-time 5 -o /dev/null -D - -w '%{http_code}' "$GATEWAY/api/cuentas/$ORIGEN" | tr -d '\r')
      echo "$(ms) ${r##*$'\n'} $(echo "$r" | grep -i '^X-Service-Instance:' | cut -d' ' -f2)" >> "$TMP/p03"
      sleep 0.2
    done ) &
  TRAFICO_PID=$!
  sleep 3
  local t0 tdet="" treinc="" t1 n
  t0=$(ms)
  docker compose stop ms-cuentas-2 >/dev/null 2>&1
  info "ms-cuentas-2 detenido en $(( $(ms) - t0 )) ms; esperando convergencia del Gateway..."
  while (( $(ms) - t0 < 90000 )); do
    # Convergencia: las ultimas 15 respuestas son 200 y todas de ms-cuentas-1.
    n=$(awk -v t="$t0" '$1 > t' "$TMP/p03" | tail -15 | grep -c '^[0-9]* 200 ms-cuentas-1')
    if [ "$n" -eq 15 ]; then tdet=$(( $(ms) - t0 )); break; fi
    sleep 0.5
  done
  local errores
  errores=$(awk -v t="$t0" '$1 > t && $2 != 200' "$TMP/p03" | wc -l)
  check '[ -n "$tdet" ]' "convergencia exclusiva a ms-cuentas-1 en ${tdet:-?} ms"
  info "errores transitorios durante la ventana de deteccion: $errores $(awk -v t="$t0" '$1 > t && $2 != 200 {print $2}' "$TMP/p03" | sort | uniq -c | awk '{printf "[HTTP %s x%s] ", $2, $1}')"
  t1=$(ms)
  docker compose start ms-cuentas-2 >/dev/null 2>&1
  info "ms-cuentas-2 arrancado; esperando que vuelva a recibir trafico..."
  while (( $(ms) - t1 < 180000 )); do
    if awk -v t="$t1" '$1 > t && $3 == "ms-cuentas-2:8082"' "$TMP/p03" | grep -q .; then treinc=$(( $(ms) - t1 )); break; fi
    sleep 1
  done
  sleep 3
  kill "$TRAFICO_PID" 2>/dev/null; wait "$TRAFICO_PID" 2>/dev/null; TRAFICO_PID=0
  check '[ -n "$treinc" ]' "ms-cuentas-2 reincorporado al balanceo en ${treinc:-?} ms (arranque JVM + registro Eureka)"
  check '[ "$(instancias_up MS-CUENTAS)" -eq 2 ]' "Eureka vuelve a mostrar 2 instancias UP de MS-CUENTAS"
  info "total peticiones: $(wc -l < "$TMP/p03"), no-200: $(awk '$2 != 200' "$TMP/p03" | wc -l)"
}

p04() {
  titulo "P04" "Comunicacion entre servicios: transferencia exitosa y rechazo controlado"
  local s0 s1 s2 d0 d1 code
  s0=$(saldo_critico "$ORIGEN"); d0=$(saldo_critico "$DESTINO")
  info "saldos iniciales: $ORIGEN=$s0 $DESTINO=$d0"
  code=$(peticion POST "$GATEWAY/api/transacciones/transferir" \
    "{\"celularOrigen\":\"$ORIGEN\",\"celularDestino\":\"$DESTINO\",\"monto\":25.00,\"motivo\":\"Prueba P04\"}")
  info "$(jq -c '{codigo: .datos.codigoComprobante, estado: .datos.estado, auditoria: .auditoriaTecnica}' "$TMP/body")"
  check '[ "$code" = 201 ]' "transferencia de 25.00 -> $code"
  check '[ -n "$(cuerpo ".auditoriaTecnica.instanciaCuentasConsultada // empty")" ]' \
    "instanciaCuentasConsultada = $(cuerpo .auditoriaTecnica.instanciaCuentasConsultada)"
  s1=$(saldo_critico "$ORIGEN"); d1=$(saldo_critico "$DESTINO")
  check 'iguales "$s1" "$(echo "$s0 - 25" | bc)" && iguales "$d1" "$(echo "$d0 + 25" | bc)"' \
    "origen descontado ($s0 -> $s1) y destino acreditado ($d0 -> $d1)"
  code=$(peticion POST "$GATEWAY/api/transacciones/transferir" \
    "{\"celularOrigen\":\"$ORIGEN\",\"celularDestino\":\"$DESTINO\",\"monto\":9999.00,\"motivo\":\"Saldo insuficiente\"}")
  check '[ "$code" = 409 ]' "transferencia de 9999.00 -> $code \"$(cuerpo .mensaje)\""
  s2=$(saldo_critico "$ORIGEN")
  check 'iguales "$s2" "$s1"' "el rechazo no altera el saldo de origen ($s2)"
}

p05() {
  titulo "P05" "Enrutamiento de BD: escritura en PRIMARY y 20 lecturas en replicas"
  info "pg_stat_replication en primary:"
  docker compose exec -T primary sh -c \
    'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SELECT application_name, client_addr, state FROM pg_stat_replication"' \
    2>/dev/null | sed 's/^/    /'
  local code
  code=$(peticion POST "$GATEWAY/api/transacciones/transferir" \
    "{\"celularOrigen\":\"$DESTINO\",\"celularDestino\":\"$ORIGEN\",\"monto\":1.00,\"motivo\":\"Prueba P05\"}")
  check '[ "$code" = 201 ] && [[ "$(cuerpo .auditoriaTecnica.nodoBaseDatos)" == PRIMARY*recovery=false* ]]' \
    "escritura en $(cuerpo .auditoriaTecnica.nodoBaseDatos)"
  lecturas 20
  sort "$TMP/lecturas" | uniq -c | sed 's/^/  /'
  local r1 r2
  r1=$(contar ' REPLICA_1 '); r2=$(contar ' REPLICA_2 ')
  check '[ "$(contar "^200 ")" -eq 20 ]' "20/20 lecturas 200"
  check '[ "$r1" -ge 6 ] && [ "$r2" -ge 6 ]' "reparto Round-Robin REPLICA_1=$r1 / REPLICA_2=$r2"
  peticion GET "$GATEWAY/api/cuentas/$ORIGEN/contactos" >/dev/null
  check '[[ "$(cabecera X-Db-Node)" == REPLICA_*recovery=true* ]]' "lectura ordinaria con recovery=true: $(cabecera X-Db-Node)"
  info "/api/cuentas/db/estado: $(curl -s "$GATEWAY/api/cuentas/db/estado" | jq -c '{consultasTotales, replicas: [.replicas[] | {nodo, available}]}')"
}

p06() {
  titulo "P06" "Fallo de replica: stop replica1 durante lecturas"
  docker compose stop replica1 >/dev/null 2>&1
  info "replica1 detenida"
  lecturas 20
  sort "$TMP/lecturas" | uniq -c | sed 's/^/  /'
  check '[ "$(contar "^200 ")" -eq 20 ]' "20/20 lecturas 200 (0 fallos al cliente)"
  info "lecturas con X-Db-Fallback: true (failover transparente antes de la sonda): $(contar ' true$')"
  sleep 4
  lecturas 10
  check '[ "$(contar " REPLICA_2 ")" -eq 10 ]' "tras la deteccion, 100% de lecturas en REPLICA_2"
  local a1c a2c a1t
  a1c=$(estado_replica cuentas REPLICA_1); a2c=$(estado_replica cuentas REPLICA_2); a1t=$(estado_replica transacciones REPLICA_1)
  check '[ "$a1c" = false ] && [ "$a2c" = true ]' "/api/cuentas/db/estado: REPLICA_1 available=$a1c, REPLICA_2 available=$a2c"
  check '[ "$a1t" = false ]' "/api/transacciones/db/estado: REPLICA_1 available=$a1t"
}

p07() {
  titulo "P07" "Consistencia de lectura (RYOW): transferencia + lecturas criticas inmediatas"
  local s0 s1 code codigo
  s0=$(saldo_critico "$ORIGEN")
  code=$(peticion POST "$GATEWAY/api/transacciones/transferir" \
    "{\"celularOrigen\":\"$ORIGEN\",\"celularDestino\":\"$DESTINO\",\"monto\":25.00,\"motivo\":\"Prueba P07\"}")
  codigo=$(cuerpo .datos.codigoComprobante)
  check '[ "$code" = 201 ]' "transferencia 25.00 -> $code ($codigo)"
  code=$(peticion GET "$GATEWAY/api/cuentas/$ORIGEN/saldo-critico")
  s1=$(cuerpo .datos.saldo)
  check 'iguales "$s1" "$(echo "$s0 - 25" | bc)"' "saldo-critico inmediato descontado ($s0 -> $s1)"
  check '[ "$(cuerpo .auditoriaTecnica.politicaEnrutamiento)" = LECTURA_CRITICA_PRIMARIO ] && [[ "$(cuerpo .auditoriaTecnica.nodoBaseDatos)" == *recovery=false* ]]' \
    "saldo-critico: $(cuerpo .auditoriaTecnica.politicaEnrutamiento) en $(cuerpo .auditoriaTecnica.nodoBaseDatos)"
  code=$(peticion GET "$GATEWAY/api/transacciones/comprobante/$codigo")
  check '[ "$code" = 200 ] && [ "$(cuerpo .datos.codigoComprobante)" = "$codigo" ]' "comprobante $codigo visible de inmediato -> $code"
  check '[ "$(cuerpo .auditoriaTecnica.politicaEnrutamiento)" = LECTURA_CRITICA_PRIMARIO ] && [[ "$(cuerpo .auditoriaTecnica.nodoBaseDatos)" == *recovery=false* ]]' \
    "comprobante: $(cuerpo .auditoriaTecnica.politicaEnrutamiento) en $(cuerpo .auditoriaTecnica.nodoBaseDatos)"
  peticion GET "$GATEWAY/api/cuentas/$ORIGEN" "" "X-Consistencia: CRITICA" >/dev/null
  check '[[ "$(cabecera X-Db-Node)" == PRIMARY*recovery=false* ]] && iguales "$(cuerpo .datos.saldo)" "$s1"' \
    "X-Consistencia: CRITICA -> $(cabecera X-Db-Node), saldo $(cuerpo .datos.saldo)"
}

p08() {
  titulo "P08" "Recuperacion de replica: start replica1 y retorno al Round-Robin"
  if [ "$(estado_replica cuentas REPLICA_1)" = true ]; then
    info "replica1 estaba disponible: se detiene para preparar el escenario"
    docker compose stop replica1 >/dev/null 2>&1; sleep 5
  fi
  # Escrituras nuevas mientras replica1 esta caida (WAL pendiente de sincronizar).
  peticion POST "$GATEWAY/api/transacciones/transferir" \
    "{\"celularOrigen\":\"$DESTINO\",\"celularDestino\":\"$ORIGEN\",\"monto\":1.00,\"motivo\":\"Prueba P08\"}" >/dev/null
  local t0 trec="" lsn_primario
  lsn_primario=$(docker compose exec -T primary sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SELECT pg_current_wal_lsn()"' 2>/dev/null)
  t0=$(ms)
  docker compose start replica1 >/dev/null 2>&1
  info "replica1 arrancada; sondeando /api/cuentas/db/estado..."
  while (( $(ms) - t0 < 90000 )); do
    if [ "$(estado_replica cuentas REPLICA_1)" = true ]; then trec=$(( $(ms) - t0 )); break; fi
    sleep 1
  done
  check '[ -n "$trec" ]' "REPLICA_1 available=true en ms-cuentas-1 y ms-cuentas-2 en ${trec:-?} ms (2/2 sondeos pg_is_in_recovery())"
  curl -s "$GATEWAY/api/cuentas/db/estado" | jq -c '.replicas[] | {nodo, available, consecutiveSuccesses, lastReplayLsn}' | sed 's/^/  /'
  local estado
  estado=$(docker compose exec -T primary sh -c \
    'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SELECT application_name, client_addr, state, sent_lsn, replay_lsn FROM pg_stat_replication"' 2>/dev/null)
  echo "$estado" | sed 's/^/    /'
  check '[ "$(echo "$estado" | grep -c "|streaming|")" -eq 2 ]' "2 replicas en streaming en pg_stat_replication (LSN primario al detener: $lsn_primario)"
  until [ "$(estado_replica transacciones REPLICA_1)" = true ] || (( $(ms) - t0 > 90000 )); do sleep 1; done
  lecturas 20
  sort "$TMP/lecturas" | uniq -c | sed 's/^/  /'
  check '[ "$(contar " REPLICA_1 ")" -ge 6 ] && [ "$(contar "^200 ")" -eq 20 ]' \
    "REPLICA_1 vuelve al Round-Robin ($(contar ' REPLICA_1 ') de 20 lecturas)"
}

PRUEBAS=("$@")
[ ${#PRUEBAS[@]} -eq 0 ] && PRUEBAS=(P01 P02 P03 P04 P05 P06 P07 P08)
for p in "${PRUEBAS[@]}"; do
  "$(echo "$p" | tr '[:upper:]' '[:lower:]')"
done

printf '\n\033[1m=== Resumen: %d OK, %d FALLAS ===\033[0m\n' "$PASS" "$FAIL"
for f in "${FALLIDAS[@]}"; do printf '  - %s\n' "$f"; done
[ "$FAIL" -eq 0 ]
