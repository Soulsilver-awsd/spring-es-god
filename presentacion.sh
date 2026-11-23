#!/usr/bin/env bash
# Presentador interactivo (1 tecla) basado en guion.md
# Uso: ./presentacion.sh   (Linux / macOS / WSL / Git Bash)
set -uo pipefail
export LC_NUMERIC=C

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_DIR" || exit 1

GATEWAY="${GATEWAY:-http://localhost:8080}"
EUREKA="${EUREKA:-http://localhost:8761}"
ORIGEN="0991112233"
DESTINO="0984445566"

SHOW_GUION=1
TMP="$(mktemp -d)"
HEADERS_FILE="$TMP/headers.txt"
BODY_FILE="$TMP/body.json"
TRAFICO_PID=0
BG_DOCKER_PID=0

# Colores ANSI
C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_DIM=$'\033[2m'
C_CYAN=$'\033[36m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_RED=$'\033[31m'
C_BLUE=$'\033[34m'
C_MAGENTA=$'\033[35m'
C_WHITE=$'\033[97m'

cleanup() {
  [ "$TRAFICO_PID" -gt 0 ] && kill "$TRAFICO_PID" 2>/dev/null || true
  [ "$BG_DOCKER_PID" -gt 0 ] && wait "$BG_DOCKER_PID" 2>/dev/null || true
  rm -rf "$TMP"
  printf '\033[?25h%s' "$C_RESET"
}
trap cleanup EXIT INT TERM

# Detectar parser JSON sin depender obligatoriamente de jq
JSON_TOOL="raw"
if command -v jq >/dev/null 2>&1; then
  JSON_TOOL="jq"
elif command -v python3 >/dev/null 2>&1 && python3 -c "import json" >/dev/null 2>&1; then
  JSON_TOOL="python3"
elif command -v python >/dev/null 2>&1 && python -c "import json" >/dev/null 2>&1; then
  JSON_TOOL="python"
fi

clear_safe() {
  [ -t 1 ] && [ -n "${TERM:-}" ] && clear 2>/dev/null || true
}

bar() {
  local ch="${1:-=}" color="${2:-$C_CYAN}"
  printf '%s' "$color"
  printf '%78s\n' '' | tr ' ' "$ch"
  printf '%s' "$C_RESET"
}

header() {
  local tag="$1" title="$2" speaker="$3" trange="$4" doclear="${5:-1}"
  [ "$doclear" -eq 1 ] && clear_safe
  bar "=" "$C_CYAN"
  printf '  %sBILLETERA DIGITAL DISTRIBUIDA  |  %s%s' "${C_BOLD}${C_CYAN}" "$tag" "$C_RESET"
  if [ -n "$speaker" ]; then
    printf '  |  %s%s (%s)%s\n' "$C_YELLOW" "$speaker" "$trange" "$C_RESET"
  else
    printf '\n'
  fi
  printf '  %s%s%s\n' "${C_BOLD}${C_WHITE}" "$title" "$C_RESET"
  bar "=" "$C_CYAN"
}

cue() {
  [ "$SHOW_GUION" -eq 0 ] && return
  printf '\n  %s[GUION]%s\n' "$C_YELLOW" "$C_RESET"
  for line in "$@"; do
    printf '    %s%s%s\n' "$C_DIM" "$line" "$C_RESET"
  done
}

cmd_tag() {
  printf '\n  %s$ %s%s\n\n' "$C_CYAN" "$1" "$C_RESET"
}

leer_tecla() {
  local k="" _rest=""
  IFS= read -rsn1 k || { TECLA="Q"; return; }
  if [ "$k" = $'\x1b' ]; then
    if [ "${BASH_VERSINFO[0]:-3}" -ge 4 ]; then
      IFS= read -rsn2 -t 0.05 _rest || true
    fi
    TECLA="NEXT"
    return
  fi
  case "$k" in
    r|R) TECLA="R" ;;
    m|M) TECLA="M" ;;
    q|Q) TECLA="Q" ;;
    b|B) TECLA="B" ;;
    v|V) TECLA="V" ;;
    p|P) TECLA="P" ;;
    s|S) TECLA="S" ;;
    t|T) TECLA="T" ;;
    c|C) TECLA="C" ;;
    [0-9]) TECLA="$k" ;;
    *) TECLA="NEXT" ;;
  esac
}

wait_key_prompt() {
  local prompt="$1"
  local extras="${2:-[R] Repetir  [B] Eureka  [V] Guion  [M] Menu  [Q] Salir}"
  printf '\n'
  bar "-" "$C_DIM"
  printf '  %s>> %s%s\n' "${C_BOLD}${C_GREEN}" "$prompt" "$C_RESET"
  [ -n "$extras" ] && printf '     %s%s%s\n' "$C_DIM" "$extras" "$C_RESET"
  while true; do
    leer_tecla
    case "$TECLA" in
      B)
        open_eureka
        [ -n "$extras" ] && printf '     %s[OK] Eureka abierto en el navegador.%s\n' "$C_CYAN" "$C_RESET"
        ;;
      V)
        SHOW_GUION=$((1 - SHOW_GUION))
        local g_lbl="OFF"; [ "$SHOW_GUION" -eq 1 ] && g_lbl="ON"
        [ -n "$extras" ] && printf '     %s[OK] Guion en pantalla: %s (desde el siguiente paso).%s\n' "$C_CYAN" "$g_lbl" "$C_RESET"
        ;;
      *) return ;;
    esac
  done
}

open_eureka() {
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$EUREKA" >/dev/null 2>&1 &
  elif command -v open >/dev/null 2>&1; then
    open "$EUREKA" >/dev/null 2>&1 &
  elif command -v wslview >/dev/null 2>&1; then
    wslview "$EUREKA" >/dev/null 2>&1 &
  elif command -v cmd.exe >/dev/null 2>&1; then
    cmd.exe /c start "" "$EUREKA" >/dev/null 2>&1 &
  fi
}

api_req() { # method url [json] [timeout]
  local method="$1" url="$2" json="${3:-}" tout="${4:-10}" code
  local args=(-s --max-time "$tout" -o "$BODY_FILE" -D "$HEADERS_FILE" -w '%{http_code}' -X "$method" "$url")
  if [ -n "$json" ]; then
    args+=(-H 'Content-Type: application/json' -d "$json")
  else
    args+=(-H 'Accept: application/json')
  fi
  code="$(curl "${args[@]}" 2>/dev/null)" || code="000"
  [ -z "$code" ] && code="000"
  echo "$code"
}

get_header() {
  grep -i "^$1:" "$HEADERS_FILE" 2>/dev/null | head -n 1 | cut -d':' -f2- | sed 's/^[[:space:]]*//; s/\r$//'
}

ensure_env() {
  if [ ! -f "$REPO_DIR/.env" ]; then
    if [ -f "$REPO_DIR/.env.example" ]; then
      cp "$REPO_DIR/.env.example" "$REPO_DIR/.env"
      printf '  %s[OK] Se creo .env a partir de .env.example.%s\n' "$C_GREEN" "$C_RESET"
      return 0
    fi
    printf '  %s[ERROR] No existe .env ni .env.example en %s.%s\n' "$C_RED" "$REPO_DIR" "$C_RESET"
    return 1
  fi
  return 0
}

print_eureka_apps() {
  case "$JSON_TOOL" in
    jq)
      jq -r '.applications.application[] | "  \(.name)|\([.instance[] | "\(.instanceId) [\(.status)]"] | join("  ,  "))"' "$BODY_FILE" 2>/dev/null | \
        while IFS='|' read -r name insts; do
          local col="$C_CYAN"; [ "$name" = "MS-CUENTAS" ] && col="$C_GREEN"
          printf '  %s%-18s -> %s%s\n' "$col" "$name" "$insts" "$C_RESET"
        done
      ;;
    python3|python)
      "$JSON_TOOL" - "$BODY_FILE" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
    for app in d.get("applications", {}).get("application", []):
        name = app.get("name", "")
        insts = app.get("instance", [])
        if isinstance(insts, dict):
            insts = [insts]
        s = "  ,  ".join(f"{i.get('instanceId')} [{i.get('status')}]" for i in insts)
        col = "\033[32m" if name == "MS-CUENTAS" else "\033[36m"
        print(f"  {col}{name:<18} -> {s}\033[0m")
except Exception as e:
    print(f"  [ERROR] {e}")
PY
      ;;
    *) cat "$BODY_FILE"; echo ;;
  esac
}

print_transfer_json() {
  case "$JSON_TOOL" in
    jq)
      jq '{mensaje, codigo: .datos.codigoComprobante, nuevoSaldoOrigen: .datos.nuevoSaldoOrigen, instanciaCuentas: .auditoriaTecnica.instanciaCuentasConsultada, nodoBD: .auditoriaTecnica.nodoBaseDatos, politica: .auditoriaTecnica.politicaEnrutamiento}' "$BODY_FILE" 2>/dev/null | sed 's/^/  /'
      ;;
    python3|python)
      "$JSON_TOOL" - "$BODY_FILE" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
    datos = d.get("datos") or {}
    aud = d.get("auditoriaTecnica") or {}
    out = {
        "mensaje": d.get("mensaje"),
        "codigo": datos.get("codigoComprobante"),
        "nuevoSaldoOrigen": datos.get("nuevoSaldoOrigen"),
        "instanciaCuentas": aud.get("instanciaCuentasConsultada"),
        "nodoBD": aud.get("nodoBaseDatos"),
        "politica": aud.get("politicaEnrutamiento"),
    }
    for line in json.dumps(out, indent=2, ensure_ascii=False).splitlines():
        col = "\033[36m" if any(k in line for k in ("instanciaCuentas", "nodoBD", "codigo")) else ("\033[31m" if "Saldo insuficiente" in line else "\033[97m")
        print(f"  {col}{line}\033[0m")
except Exception:
    print(open(sys.argv[1], encoding="utf-8", errors="ignore").read())
PY
      ;;
    *) cat "$BODY_FILE"; echo ;;
  esac
}

print_critico_json() {
  case "$JSON_TOOL" in
    jq)
      jq '{saldo: .datos.saldo, nodoBD: .auditoriaTecnica.nodoBaseDatos, politica: .auditoriaTecnica.politicaEnrutamiento}' "$BODY_FILE" 2>/dev/null | sed 's/^/  /'
      ;;
    python3|python)
      "$JSON_TOOL" - "$BODY_FILE" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
    datos = d.get("datos") or {}
    aud = d.get("auditoriaTecnica") or {}
    out = {
        "saldo": datos.get("saldo"),
        "nodoBD": aud.get("nodoBaseDatos"),
        "politica": aud.get("politicaEnrutamiento"),
    }
    for line in json.dumps(out, indent=2, ensure_ascii=False).splitlines():
        print(f"  \033[32m{line}\033[0m")
except Exception:
    print(open(sys.argv[1], encoding="utf-8", errors="ignore").read())
PY
      ;;
    *) cat "$BODY_FILE"; echo ;;
  esac
}

print_db_estado() {
  case "$JSON_TOOL" in
    jq)
      local srv
      srv="$(jq -r '.servicio // empty' "$BODY_FILE" 2>/dev/null)"
      [ -n "$srv" ] && printf '  %sservicio: %s%s\n' "$C_DIM" "$srv" "$C_RESET"
      jq -c '.replicas[] | {nodo, available, consecutiveSuccesses, lastReplayLsn}' "$BODY_FILE" 2>/dev/null | \
        while read -r line; do
          if echo "$line" | grep -q '"available":true'; then
            printf '  %s%s%s\n' "$C_GREEN" "$line" "$C_RESET"
          else
            printf '  %s%s%s\n' "$C_RED" "$line" "$C_RESET"
          fi
        done
      ;;
    python3|python)
      "$JSON_TOOL" - "$BODY_FILE" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
    if d.get("servicio"):
        print(f"  \033[2mservicio: {d['servicio']}\033[0m")
    for rep in d.get("replicas", []):
        avail = rep.get("available")
        col = "\033[32m" if avail else "\033[31m"
        out = {
            "nodo": rep.get("nodo"),
            "available": avail,
            "consecutiveSuccesses": rep.get("consecutiveSuccesses"),
            "lastReplayLsn": rep.get("lastReplayLsn"),
        }
        print(f"  {col}{json.dumps(out, ensure_ascii=False)}\033[0m")
except Exception:
    print(open(sys.argv[1], encoding="utf-8", errors="ignore").read())
PY
      ;;
    *) cat "$BODY_FILE"; echo ;;
  esac
}

get_saldo_line() {
  local code
  code="$(api_req GET "$GATEWAY/api/cuentas/$ORIGEN/saldo-critico" "" 2)"
  [ "$code" != "200" ] && return 1
  case "$JSON_TOOL" in
    jq)
      jq -r '.datos | "\(.saldo)|\(.consumidoHoy)|\(.limiteDiario)"' "$BODY_FILE" 2>/dev/null
      ;;
    python3|python)
      "$JSON_TOOL" - "$BODY_FILE" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8")).get("datos") or {}
    s = f"{float(d.get('saldo') or 0):.2f}"
    c = f"{float(d.get('consumidoHoy') or 0):.2f}"
    l = f"{float(d.get('limiteDiario') or 0):.2f}"
    print(f"{s}|{c}|{l}")
except Exception:
    sys.exit(1)
PY
      ;;
    *) return 1 ;;
  esac
}

# --- Utilidades Pre-grabacion ---

clean_prep() {
  header "PREPARACION" "Entorno limpio pre-grabacion (down -v + up -d --build)" "Pre-toma" "Fuera de camara"
  ensure_env || { wait_key_prompt "Pulsa una tecla para volver al menu..." ""; return; }
  cmd_tag "docker compose down -v && docker compose up -d --build"
  docker compose down -v
  docker compose up -d --build || {
    printf '\n  %s[ERROR] docker compose up fallo.%s\n' "$C_RED" "$C_RESET"
    wait_key_prompt "Pulsa una tecla para volver al menu..." ""
    return
  }
  printf '\n  %sEsperando a que los 8 contenedores esten healthy...%s\n' "$C_YELLOW" "$C_RESET"
  local start_t now elapsed h
  start_t=$(date +%s)
  while true; do
    now=$(date +%s)
    elapsed=$((now - start_t))
    [ "$elapsed" -ge 240 ] && break
    h=$(docker compose ps -a --format '{{.Status}}' 2>/dev/null | grep -c 'healthy' || true)
    printf '\r  %s[%3ds] Contenedores healthy: %s/8   %s' "$C_CYAN" "$elapsed" "$h" "$C_RESET"
    if [ "$h" -ge 8 ]; then
      printf '\n  %s[OK] Los 8 contenedores estan healthy!%s\n' "$C_GREEN" "$C_RESET"
      break
    fi
    sleep 2
  done
  open_eureka
  printf '  %s[OK] Eureka abierto: %s%s\n' "$C_GREEN" "$EUREKA" "$C_RESET"
  wait_key_prompt "Entorno listo. Pulsa una tecla para volver al menu..." ""
}

start_all() {
  header "RECUPERAR" "Arrancando contenedores detenidos (docker compose start)" "" ""
  ensure_env || true
  cmd_tag "docker compose start"
  docker compose start
  wait_key_prompt "Pulsa una tecla para volver al menu..." ""
}

run_plan_b_suite() {
  header "PLAN B" "Ejecutando suite automatizada P01-P08 (curl-p01-p08.sh)" "" ""
  if [ -f "$REPO_DIR/docs/api/curl-p01-p08.sh" ]; then
    bash "$REPO_DIR/docs/api/curl-p01-p08.sh"
  else
    printf '  %s[ERROR] No se encontro docs/api/curl-p01-p08.sh%s\n' "$C_RED" "$C_RESET"
  fi
  wait_key_prompt "Pulsa una tecla para volver al menu..." ""
}

# --- Pasos de la presentacion ---

step_1a() {
  header "PASO 1/15 · BLOQUE 1/6" "Arquitectura distribuida (8 contenedores)" "Persona A" "0:00 - 0:50"
  cat <<'ART'

  +------------------+      HTTP :8080      +------------------------+
  |  Cliente / Demo  | -------------------> |   api-gateway (:8080)  |
  +------------------+                      +-----------+------------+
                                                        | lb:// (Round Robin)
  +-------------------------+                           v
  |  eureka-server (:8761)  | <====== registro + latido 5s =======
  +-------------------------+       |              |              |
                                    v              v              v
                             +------------+ +------------+ +----------------+
                             |ms-cuentas-1| |ms-cuentas-2| |ms-transacciones|
                             |   :8081    | |   :8082    | |     :8083      |
                             +-----+------+ +-----+------+ +-------+--------+
                                   \              |                /
                                    +----> [Enrutador JDBC] <-----+
                                            /            \
                            Escritura/RYOW /              \ Lecturas
                                          v                v
                       +-----------------------+    +---------------------+
                       | primary :5432 (R/W)   |===>| replica1 :5433 (RO) |
                       | cuentas_db  |  tx_db  |WAL | replica2 :5434 (RO) |
                       +-----------------------+    +---------------------+
ART
  cue \
    "- Billetera P2P: 8 contenedores, todo distribuido y con respaldo." \
    "- 2 microservicios: ms-cuentas (2 instancias) y ms-transacciones (1 instancia)." \
    "- Infra: Gateway :8080, Eureka :8761, PostgreSQL 17 (1 primario + 2 replicas WAL)." \
    "- Esquemas y usuarios disjuntos en BD (garantizado por PostgreSQL)."
  wait_key_prompt "Pulsa UNA TECLA para ejecutar: docker compose ps"
}

step_1b() {
  header "PASO 2/15 · BLOQUE 1/6" "Contenedores activos en Docker Compose" "Persona A" "0:00 - 0:50"
  cmd_tag "docker compose ps"
  if docker compose ps --format 'table {{.Name}}\t{{.Service}}\t{{.Status}}\t{{.Ports}}' >"$TMP/ps.txt" 2>/dev/null; then
    while IFS= read -r line; do
      if echo "$line" | grep -q 'healthy'; then
        printf '  %s%s%s\n' "$C_GREEN" "$line" "$C_RESET"
      elif echo "$line" | grep -q '^NAME'; then
        printf '  %s%s%s\n' "$C_CYAN" "$line" "$C_RESET"
      else
        printf '  %s%s%s\n' "$C_YELLOW" "$line" "$C_RESET"
      fi
    done <"$TMP/ps.txt"
  else
    docker compose ps
  fi
  cue "- Senalar los 8 contenedores en estado (healthy)."
  wait_key_prompt "Pulsa UNA TECLA para ir al Bloque 2 (Persona B - Eureka)"
}

step_2a() {
  header "PASO 3/15 · BLOQUE 2/6" "Descubrimiento dinamico en Eureka" "Persona B" "0:50 - 1:40"
  cmd_tag "GET $EUREKA/eureka/apps  (Navegador: $EUREKA)"
  local code
  code="$(api_req GET "$EUREKA/eureka/apps" "" 5)"
  if [ "$code" = "200" ]; then
    print_eureka_apps
  else
    printf '  %s[AVISO] No se pudo consultar Eureka (HTTP %s).%s\n' "$C_RED" "$code" "$C_RESET"
  fi
  cue \
    "- Mostrar Eureka en navegador (pulsa [B] si quieres abrirlo ahora)." \
    "- MS-CUENTAS con 2 instancias UP (8081 y 8082) y MS-TRANSACCIONES con 1." \
    "- Gateway resuelve por nombre 'ms-cuentas' y aplica Round Robin."
  wait_key_prompt "Pulsa UNA TECLA para ejecutar: balanceo (20 peticiones)"
}

step_2b() {
  header "PASO 4/15 · BLOQUE 2/6" "Balanceo HTTP Round Robin (20 peticiones)" "Persona B" "0:50 - 1:40"
  cmd_tag "balanceo  # 20 x GET $GATEWAY/api/cuentas/instancia"
  : > "$TMP/balanceo.txt"
  local i code inst
  for i in $(seq 1 20); do
    code="$(api_req GET "$GATEWAY/api/cuentas/instancia" "" 5)"
    inst="$(get_header "X-Service-Instance")"
    [ -z "$inst" ] && inst="sin-cabecera"
    printf '%s %s\n' "$code" "$inst" >> "$TMP/balanceo.txt"
  done
  sort "$TMP/balanceo.txt" | uniq -c | while read -r cnt code inst; do
    local col="$C_GREEN"; [ "$code" != "200" ] && col="$C_RED"
    local bar_str
    bar_str="$(printf '%*s' "$cnt" '' | tr ' ' '#')"
    printf '  %s%4s  %s  %-22s  %s%s\n' "$col" "$cnt" "$code" "$inst" "$bar_str" "$C_RESET"
  done
  cue "- Veinte peticiones, diez y diez, cero errores. Parejo, como debe ser."
  wait_key_prompt "Pulsa UNA TECLA para ir al Bloque 3 (transferir 25)"
}

run_transfer_display() {
  local monto="$1" label="$2"
  cmd_tag "$label  # POST $GATEWAY/api/transacciones/transferir (monto=$monto)"
  local payload code
  payload="{\"celularOrigen\":\"$ORIGEN\",\"celularDestino\":\"$DESTINO\",\"monto\":$monto,\"motivo\":\"Demo video\"}"
  code="$(api_req POST "$GATEWAY/api/transacciones/transferir" "$payload" 10)"
  if [ "$code" = "201" ] || [ "$code" = "200" ]; then
    printf '  %sHTTP %s%s\n' "${C_BOLD}${C_GREEN}" "$code" "$C_RESET"
  else
    printf '  %sHTTP %s%s\n' "${C_BOLD}${C_YELLOW}" "$code" "$C_RESET"
  fi
  print_transfer_json
}

step_3a() {
  header "PASO 5/15 · BLOQUE 3/6" "Comunicacion entre servicios (transferencia exitosa)" "Persona B" "1:40 - 2:25"
  run_transfer_display 25 "transferir 25"
  cue \
    "- Senalar HTTP 201, codigoComprobante e instanciaCuentasConsultada." \
    "- ms-transacciones llamo a ms-cuentas por nombre via Eureka (transaccion ACID)."
  wait_key_prompt "Pulsa UNA TECLA para ejecutar: transferir 9999 (error controlado)"
}

step_3b() {
  printf '\n'
  bar "-" "$C_CYAN"
  printf '  %sPASO 6/15 · BLOQUE 3/6  |  Validacion y rechazo controlado%s\n' "$C_CYAN" "$C_RESET"
  run_transfer_display 9999 "transferir 9999"
  cue \
    "- 409, saldo insuficiente. Error controlado y el saldo no se toca." \
    "- Pasar la palabra: 'C, y la base de datos?'"
  wait_key_prompt "Pulsa UNA TECLA para ir al Bloque 4 (Persona C - lecturas)"
}

run_lecturas_block() {
  cmd_tag "lecturas  # 20 lecturas ordinarias (10x contactos + 10x historial)"
  : > "$TMP/lecturas.txt"
  local i u code node fb
  for i in $(seq 1 10); do
    for u in "cuentas/$ORIGEN/contactos" "transacciones/historial/$ORIGEN"; do
      code="$(api_req GET "$GATEWAY/api/$u" "" 5)"
      node="$(get_header "X-Db-Node")"; [ -z "$node" ] && node="desconocido"
      fb="$(get_header "X-Db-Fallback")"; [ -z "$fb" ] && fb="false"
      printf '%s|%s|%s\n' "$code" "$node" "$fb" >> "$TMP/lecturas.txt"
    done
  done
  sort "$TMP/lecturas.txt" | uniq -c | while read -r line; do
    local cnt rest code node fb col
    cnt="$(echo "$line" | awk '{print $1}')"
    rest="$(echo "$line" | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//')"
    code="$(echo "$rest" | cut -d'|' -f1)"
    node="$(echo "$rest" | cut -d'|' -f2)"
    fb="$(echo "$rest" | cut -d'|' -f3)"
    col="$C_GREEN"
    [ "$fb" = "true" ] && col="$C_YELLOW"
    [ "$code" != "200" ] && col="$C_RED"
    printf '  %s%4s  %s  %s  fallback=%s%s\n' "$col" "$cnt" "$code" "$node" "$fb" "$C_RESET"
  done
}

step_4a() {
  header "PASO 7/15 · BLOQUE 4/6" "Persistencia replicada (escritura PRIMARY vs lecturas REPLICA)" "Persona C" "2:25 - 3:10"
  run_lecturas_block
  cue \
    "- Escritura anterior fue a PRIMARY (recovery=false)." \
    "- Estas 20 lecturas: mitad REPLICA_1 y mitad REPLICA_2, recovery=true, con su propia IP." \
    "- Para ver mi saldo recien pagado al instante: lectura critica (RYOW)."
  wait_key_prompt "Pulsa UNA TECLA para ejecutar: critico (saldo-critico)"
}

step_4b() {
  printf '\n'
  bar "-" "$C_CYAN"
  printf '  %sPASO 8/15 · BLOQUE 4/6  |  Lectura critica (Read-Your-Own-Writes)%s\n' "$C_CYAN" "$C_RESET"
  cmd_tag "critico  # GET $GATEWAY/api/cuentas/$ORIGEN/saldo-critico"
  local code
  code="$(api_req GET "$GATEWAY/api/cuentas/$ORIGEN/saldo-critico" "" 5)"
  if [ "$code" = "200" ]; then
    print_critico_json
  else
    printf '  %sHTTP %s%s\n' "$C_RED" "$code" "$C_RESET"
  fi
  cue "- Directo al primario, con el saldo ya descontado (475.00). Read-your-own-writes."
  wait_key_prompt "Pulsa UNA TECLA para ir al Bloque 5a (Trafico continuo + fallo instancia)"
}

step_5a() {
  header "PASO 9/15 · BLOQUE 5a/6" "Simulacion de fallo: caida de ms-cuentas-2 con trafico en vivo" "Persona C" "3:10 - 3:45"
  cue \
    "- Trafico constante alternando ms-cuentas-1 y ms-cuentas-2." \
    "- Pulsa 1 TECLA para tumbar ms-cuentas-2 -> observa 0 errores y solo :8081." \
    "- Pulsa 1 TECLA para arrancarla (no esperar) y 1 TECLA para cortar trafico."
  printf '\n'
  bar "-" "$C_DIM"
  printf '  %s[FASE 1/3] Trafico activo. Pulsa [CUALQUIER TECLA] para TUMBAR ms-cuentas-2 (Q=salir)%s\n' "$C_YELLOW" "$C_RESET"
  bar "-" "$C_DIM"

  : > "$TMP/trafico.log"
  (
    local hdr="$TMP/traf_hdr.txt" code inst ts col
    while :; do
      code="$(curl -s --max-time 3 -o /dev/null -D "$hdr" -w '%{http_code}' "$GATEWAY/api/cuentas/$ORIGEN" 2>/dev/null)" || code="000"
      [ -z "$code" ] && code="000"
      inst="$(grep -i '^X-Service-Instance:' "$hdr" 2>/dev/null | head -n 1 | cut -d':' -f2- | sed 's/^[[:space:]]*//; s/\r$//')"
      [ -z "$inst" ] && inst="sin-instancia"
      ts="$(date +%T)"
      printf '%s\n' "$code" >> "$TMP/trafico.log"
      col="$C_GREEN"
      if [ "$code" != "200" ]; then
        col="$C_RED"
      elif echo "$inst" | grep -q 'ms-cuentas-2'; then
        col="$C_CYAN"
      fi
      printf '  %s[%s] %s %s%s\n' "$col" "$ts" "$code" "$inst" "$C_RESET"
      sleep 0.3
    done
  ) &
  TRAFICO_PID=$!

  local phase=1 abort_to=""
  while :; do
    leer_tecla
    if [ "$TECLA" = "Q" ] || [ "$TECLA" = "M" ]; then
      abort_to="$TECLA"
      break
    fi
    if [ "$phase" -eq 1 ]; then
      phase=2
      printf '\n  %s>>> [ACCION] Ejecutando: docker compose stop ms-cuentas-2 ...%s\n' "$C_MAGENTA" "$C_RESET"
      (
        docker compose stop ms-cuentas-2 >/dev/null 2>&1
        printf '  %s>>> [OK] ms-cuentas-2 detenido. Trafico absorbido 100%% por ms-cuentas-1!%s\n' "$C_GREEN" "$C_RESET"
      ) &
      BG_DOCKER_PID=$!
      printf '  %s[FASE 2/3] Pulsa [CUALQUIER TECLA] cuando quieras ARRANCAR ms-cuentas-2%s\n' "$C_YELLOW" "$C_RESET"
    elif [ "$phase" -eq 2 ]; then
      phase=3
      printf '\n  %s>>> [ACCION] Ejecutando: docker compose start ms-cuentas-2 (en segundo plano) ...%s\n' "$C_MAGENTA" "$C_RESET"
      (
        docker compose start ms-cuentas-2 >/dev/null 2>&1
        printf '  %s>>> [OK] docker compose start ms-cuentas-2 lanzado (~25s de arranque JVM).%s\n' "$C_CYAN" "$C_RESET"
      ) &
      BG_DOCKER_PID=$!
      printf '  %s[FASE 3/3] Pulsa [CUALQUIER TECLA] para cortar trafico y pasar a Persona A (Bloque 5b)%s\n' "$C_YELLOW" "$C_RESET"
    else
      break
    fi
  done

  if [ "$TRAFICO_PID" -gt 0 ]; then
    kill "$TRAFICO_PID" 2>/dev/null || true
    wait "$TRAFICO_PID" 2>/dev/null || true
    TRAFICO_PID=0
  fi
  if [ "$BG_DOCKER_PID" -gt 0 ]; then
    wait "$BG_DOCKER_PID" 2>/dev/null || true
    BG_DOCKER_PID=0
  fi

  if [ -n "$abort_to" ]; then
    TECLA="$abort_to"
    return
  fi

  local total errs col
  total="$(wc -l < "$TMP/trafico.log" | tr -d ' ')"
  errs="$(grep -vc '^200$' "$TMP/trafico.log" || true)"
  col="$C_GREEN"; [ "$errs" -gt 0 ] && col="$C_RED"
  printf '\n'
  bar "-" "$C_CYAN"
  printf '  %sResumen trafico: %s peticiones | Errores (!=200): %s%s\n' "$col" "$total" "$errs" "$C_RESET"
  cue \
    "- Cero errores para el usuario. La volvemos a prender y regresa sola (~25s)." \
    "- Pasar la palabra a Persona A."
  wait_key_prompt "Pulsa UNA TECLA para ir al Bloque 5b (Persona A - Caida replica PG)"
}

step_5b_intro() {
  header "PASO 10/15 · BLOQUE 5b/6" "Simulacion de fallo: caida de replica1 PostgreSQL" "Persona A" "3:45 - 4:20"
  cue \
    "- 'Ahora lo pesado: apagamos una replica de la base de datos.'" \
    "- Al pulsar una tecla se detiene replica1 y se lanzan 20 lecturas."
  wait_key_prompt "Pulsa UNA TECLA para ejecutar: docker compose stop replica1 + lecturas"
}

step_5b_stop_reads() {
  header "PASO 11/15 · BLOQUE 5b/6" "replica1 detenida -> 20 lecturas con failover transparente" "Persona A" "3:45 - 4:20"
  cmd_tag "docker compose stop replica1"
  docker compose stop replica1
  run_lecturas_block
  cue \
    "- Todas las lecturas siguen dando 200, todas en REPLICA_2." \
    "- Las que dicen fallback=true se intentaron en la caida y se rescataron solas."
  wait_key_prompt "Pulsa UNA TECLA para ejecutar: estado (ver salud de replicas)"
}

step_5b_estado_down() {
  printf '\n'
  bar "-" "$C_CYAN"
  printf '  %sPASO 12/15 · BLOQUE 5b/6  |  Estado de replicas tras el sondeo (cada 3s)%s\n' "$C_CYAN" "$C_RESET"
  cmd_tag "estado  # GET $GATEWAY/api/cuentas/db/estado"
  local code
  code="$(api_req GET "$GATEWAY/api/cuentas/db/estado" "" 5)"
  [ "$code" = "200" ] && print_db_estado || printf '  %sHTTP %s%s\n' "$C_RED" "$code" "$C_RESET"
  cue \
    "- Cada 3 segundos se revisa la salud: REPLICA_1 available=false (fuera de ronda)." \
    "- 'Y cuando vuelve?'"
  wait_key_prompt "Pulsa UNA TECLA para arrancar replica1 (docker compose start replica1)"
}

step_5b_start_replica() {
  header "PASO 13/15 · BLOQUE 5b/6" "Recuperacion automatica de replica1 (WAL + 2/2 chequeos)" "Persona A" "3:45 - 4:20"
  cmd_tag "docker compose start replica1"
  docker compose start replica1
  printf '\n  %s[TIP] Habla ~8 segundos mientras replica1 sincroniza WAL y pasa 2 chequeos...%s\n' "$C_YELLOW" "$C_RESET"
  cue \
    "- 'Se pone al dia con el primario, pasa dos chequeos seguidos para demostrar que esta sana" \
    "   y vuelve a la ronda. Sin tocar nada a mano.'"
  wait_key_prompt "Cuando pasen ~8s, pulsa UNA TECLA para consultar estado"
}

step_5b_estado_up() {
  printf '\n'
  bar "-" "$C_CYAN"
  printf '  %sPASO 14/15 · BLOQUE 5b/6  |  Estado tras recuperacion (pulsa [R] si aun esta en chequeo 1/2)%s\n' "$C_CYAN" "$C_RESET"
  cmd_tag "estado  # GET $GATEWAY/api/cuentas/db/estado"
  local code
  code="$(api_req GET "$GATEWAY/api/cuentas/db/estado" "" 5)"
  [ "$code" = "200" ] && print_db_estado || printf '  %sHTTP %s%s\n' "$C_RED" "$code" "$C_RESET"
  cue "- REPLICA_1 available=true! Vuelve al Round-Robin sin tocar nada a mano."
  wait_key_prompt "Pulsa UNA TECLA para ir al Bloque 6 (Conclusiones)"
}

step_6() {
  header "PASO 15/15 · BLOQUE 6/6" "Conclusiones tecnicas del equipo" "A, B y C" "4:20 - 5:00"
  printf '\n  %s[A · DECISIONES]                 [B · LIMITACIONES]               [C · MEJORAS]%s\n' "${C_BOLD}${C_CYAN}" "$C_RESET"
  printf '  %s-------------------------------  -------------------------------  -------------------------------%s\n' "$C_DIM" "$C_RESET"
  printf '  %s%-32s %s%-32s %s%s%s\n' "$C_GREEN" "- Enrutamiento BD por @UsarNodo:" "$C_YELLOW" "- Si cae el primario no hay"      "$C_WHITE" "- Failover automatico primario" "$C_RESET"
  printf '  %s%-32s %s%-32s %s%s%s\n' "$C_GREEN" "  escritura/critica -> primario"  "$C_YELLOW" "  promocion automatica"           "$C_WHITE" "  con Patroni o repmgr"         "$C_RESET"
  printf '  %s%-32s %s%-32s %s%s%s\n' "$C_GREEN" "  lecturas -> replicas"           "$C_YELLOW" "- Eureka es unico (SPOF)"         "$C_WHITE" "- Claves de idempotencia en"    "$C_RESET"
  printf '  %s%-32s %s%-32s %s%s%s\n' "$C_GREEN" "- Round Robin con chequeo 2 de 2" "$C_YELLOW" "- /movimiento-interno expuesto"   "$C_WHITE" "  transferencias"               "$C_RESET"
  printf '  %s%-32s %s%-32s %s%s%s\n' "$C_GREEN" "- Eureka sin cache solo lectura"  "$C_YELLOW" "  por el Gateway"                 "$C_WHITE" "- Reintento de conexion en"     "$C_RESET"
  printf '  %s%-32s %s%-32s %s%s%s\n' "$C_GREEN" "  + retry GET (0 errores P03)"    "$C_YELLOW" "- Limite diario no se reinicia"   "$C_WHITE" "  ms-transacciones"             "$C_RESET"
  printf '  %s%-32s %s%-32s %s%s%s\n' "$C_GREEN" "- Flyway con advisory lock"       "$C_YELLOW" "- Sin idempotencia si ms-cuentas" "$C_WHITE" "- Healthcheck Eureka a salud real" "$C_RESET"
  printf '  %s%-32s %s%-32s %s%s%s\n' "$C_GREEN" "  para arranque paralelo"         "$C_YELLOW" "  tarda mas del timeout"          "$C_WHITE" "- Bloquear ruta interna + Sagas" "$C_RESET"
  printf '\n'
  bar "-" "$C_CYAN"
  printf '  %sLOS TRES: "Mas de uno de todo, y saber esquivar al que falla. Eso es un sistema distribuido. Gracias!"%s\n' "${C_BOLD}${C_CYAN}" "$C_RESET"
  wait_key_prompt "Presentacion completada! Pulsa una tecla para ir al Menu (Q=salir)"
}

# --- Navegacion ---

STEPS=(
  step_1a
  step_1b
  step_2a
  step_2b
  step_3a
  step_3b
  step_4a
  step_4b
  step_5a
  step_5b_intro
  step_5b_stop_reads
  step_5b_estado_down
  step_5b_start_replica
  step_5b_estado_up
  step_6
)

run_from_step() {
  local idx="$1"
  while [ "$idx" -ge 0 ] && [ "$idx" -lt "${#STEPS[@]}" ]; do
    "${STEPS[$idx]}"
    case "$TECLA" in
      R) continue ;;
      B) open_eureka; continue ;;
      V) SHOW_GUION=$((1 - SHOW_GUION)); continue ;;
      M) return 0 ;;
      Q) return 2 ;;
      *) idx=$((idx + 1)) ;;
    esac
  done
  return 0
}

main_menu() {
  while true; do
    clear_safe
    bar "=" "$C_CYAN"
    printf '  %sPRESENTADOR INTERACTIVO (1 TECLA)  ·  BILLETERA DIGITAL DISTRIBUIDA%s\n' "${C_BOLD}${C_CYAN}" "$C_RESET"
    printf '  %sBasado en guion.md  |  Duracion objetivo: 5:00  |  Elenco: A, B y C%s\n' "$C_DIM" "$C_RESET"
    bar "=" "$C_CYAN"
    printf '\n'

    [ ! -f "$REPO_DIR/.env" ] && printf '  %s[AVISO] Falta .env en el repo (usa [P] Preparacion limpia o [C] para copiar .env.example).%s\n' "$C_YELLOW" "$C_RESET"

    local total=0 healthy=0 stopped="" ps_out=""
    if ps_out="$(docker compose ps -a --format '{{.Name}}|{{.State}}|{{.Status}}' 2>/dev/null)"; then
      total="$(echo "$ps_out" | grep -c '|' || true)"
      healthy="$(echo "$ps_out" | grep -c 'healthy' || true)"
      stopped="$(echo "$ps_out" | awk -F'|' '$2 != "running" && $1 != "" {print $1}' | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
      local col="$C_YELLOW"; [ "$healthy" -ge 8 ] && col="$C_GREEN"
      printf '  %sContenedores: %s/8 healthy (total visibles: %s)%s\n' "$col" "$healthy" "$total" "$C_RESET"
      [ -n "$stopped" ] && printf '  %sDetenidos:    %s  (usa [S] para arrancarlos)%s\n' "$C_RED" "$stopped" "$C_RESET"
    else
      printf '  %sDocker:       No responde el daemon (enciende Docker antes de grabar).%s\n' "$C_RED" "$C_RESET"
    fi

    local sinfo
    if sinfo="$(get_saldo_line)"; then
      local s c l col="$C_GREEN"
      s="$(echo "$sinfo" | cut -d'|' -f1)"
      c="$(echo "$sinfo" | cut -d'|' -f2)"
      l="$(echo "$sinfo" | cut -d'|' -f3)"
      awk -v v="${c:-0}" 'BEGIN{exit !(v+0 > 0)}' && col="$C_YELLOW"
      printf '  %sCuenta %s: saldo=%s | consumidoHoy=%s / %s%s\n' "$col" "$ORIGEN" "$s" "$c" "$l" "$C_RESET"
      if [ "$col" = "$C_YELLOW" ]; then
        printf '  %s[TIP] Para la toma buena, [P] reinicia saldo a 500.00 y consumidoHoy a 0.00.%s\n' "$C_YELLOW" "$C_RESET"
      fi
    else
      printf '  %sGateway :8080: Sin respuesta aun.%s\n' "$C_DIM" "$C_RESET"
    fi

    printf '\n'
    bar "-" "$C_DIM"
    printf '  %sMODO PRESENTACION (solo pulsa 1 tecla para avanzar):%s\n' "$C_WHITE" "$C_RESET"
    printf '    %s[ESPACIO / ENTER]  Iniciar presentacion completa desde Bloque 1%s\n\n' "$C_GREEN" "$C_RESET"
    printf '  %sSALTAR A UN BLOQUE:%s\n' "$C_WHITE" "$C_RESET"
    printf '    %s[1] Bloque 1 · Arquitectura (Persona A · 0:00-0:50)%s\n' "$C_CYAN" "$C_RESET"
    printf '    %s[2] Bloque 2 · Descubrimiento y balanceo (Persona B · 0:50-1:40)%s\n' "$C_CYAN" "$C_RESET"
    printf '    %s[3] Bloque 3 · Comunicacion entre servicios (Persona B · 1:40-2:25)%s\n' "$C_CYAN" "$C_RESET"
    printf '    %s[4] Bloque 4 · Persistencia replicada (Persona C · 2:25-3:10)%s\n' "$C_CYAN" "$C_RESET"
    printf '    %s[5] Bloque 5 · Simulacion de fallos (C -> A · 3:10-4:20)%s\n' "$C_CYAN" "$C_RESET"
    printf '    %s[6] Bloque 6 · Conclusiones 3 columnas (A, B, C · 4:20-5:00)%s\n\n' "$C_CYAN" "$C_RESET"
    printf '  %sUTILIDADES PRE-GRABACION / PLAN B:%s\n' "$C_WHITE" "$C_RESET"
    local g_lbl="OFF"; [ "$SHOW_GUION" -eq 1 ] && g_lbl="ON"
    printf '    %s[P] Preparacion limpia (down -v + up -d --build + abrir Eureka)%s\n' "$C_YELLOW" "$C_RESET"
    printf '    %s[B] Abrir Eureka en navegador (%s)   [S] Arrancar detenidos%s\n' "$C_DIM" "$EUREKA" "$C_RESET"
    printf '    %s[V] Guion en pantalla: %-3s                  [T] Suite P01-P08 (Plan B)%s\n' "$C_DIM" "$g_lbl" "$C_RESET"
    printf '    %s[C] Crear .env desde .env.example          [Q] Salir%s\n' "$C_DIM" "$C_RESET"
    bar "-" "$C_DIM"

    leer_tecla
    local rc=0
    case "$TECLA" in
      Q) return 0 ;;
      P) clean_prep ;;
      B) open_eureka ;;
      S) start_all ;;
      T) run_plan_b_suite ;;
      C) ensure_env; sleep 1 ;;
      V) SHOW_GUION=$((1 - SHOW_GUION)) ;;
      1) run_from_step 0 || rc=$? ;;
      2) run_from_step 2 || rc=$? ;;
      3) run_from_step 4 || rc=$? ;;
      4) run_from_step 6 || rc=$? ;;
      5) run_from_step 8 || rc=$? ;;
      6) run_from_step 14 || rc=$? ;;
      *) run_from_step 0 || rc=$? ;;
    esac
    [ "$rc" -eq 2 ] && return 0
  done
}

main_menu
