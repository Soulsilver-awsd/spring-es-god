import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFile } from 'node:child_process';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_DIR = path.resolve(__dirname, '..');

const PORT = Number(process.env.PORT || 3333);
const GATEWAY = process.env.GATEWAY || 'http://localhost:8080';
const EUREKA = process.env.EUREKA || 'http://localhost:8761';
const ORIGEN = '0991112233';
const DESTINO = '0984445566';

const EXPECTED_SERVICES = [
  { service: 'eureka-server', label: 'Eureka', port: '8761', role: 'Service Discovery' },
  { service: 'api-gateway', label: 'Gateway', port: '8080', role: 'Spring Cloud Gateway' },
  { service: 'ms-cuentas-1', label: 'Cuentas-1', port: '8081', role: 'Microservicio Cuentas' },
  { service: 'ms-cuentas-2', label: 'Cuentas-2', port: '8082', role: 'Microservicio Cuentas' },
  { service: 'ms-transacciones', label: 'Tx', port: '8083', role: 'Orquestador P2P' },
  { service: 'primary', label: 'PG-Primary', port: '5432', role: 'PostgreSQL 17 R/W' },
  { service: 'replica1', label: 'PG-Rep1', port: '5433', role: 'Réplica WAL #1' },
  { service: 'replica2', label: 'PG-Rep2', port: '5434', role: 'Réplica WAL #2' }
];

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml'
};

const sessionState = {
  eventLog: [],
  httpTraces: [],
  traceSeq: 0,
  slideResults: {}
};

function nowTimeStr() {
  const d = new Date();
  return d.toTimeString().slice(0, 8);
}

function addEventLog(level, tag, message) {
  sessionState.eventLog.push({
    time: nowTimeStr(),
    level: String(level || 'INFO').toUpperCase(),
    tag: String(tag || 'SYS').toUpperCase(),
    message: String(message || '')
  });
  if (sessionState.eventLog.length > 300) {
    sessionState.eventLog.shift();
  }
}

function recordHttpTrace({ screen = 'API', method, url, requestBody, status, durationMs, headers, responseBody, note }) {
  sessionState.traceSeq += 1;
  sessionState.httpTraces.push({
    seq: sessionState.traceSeq,
    time: nowTimeStr(),
    screen,
    method,
    url,
    requestBody: requestBody ?? null,
    status: String(status),
    durationMs: Math.round(durationMs || 0),
    headers: headers || {},
    responseBody: responseBody ?? '',
    note: note || ''
  });
  if (sessionState.httpTraces.length > 200) {
    sessionState.httpTraces.shift();
  }
}

function execDocker(args, timeoutMs = 15000) {
  const started = Date.now();
  return new Promise((resolve) => {
    execFile('docker', ['compose', ...args], { cwd: REPO_DIR, timeout: timeoutMs, maxBuffer: 1024 * 1024 }, (err, stdout, stderr) => {
      const durationMs = Date.now() - started;
      resolve({
        ok: !err,
        stdout: (stdout || '').toString(),
        stderr: (stderr || '').toString(),
        error: err ? err.message : null,
        durationMs
      });
    });
  });
}

async function apiFetch(method, url, bodyObj = null, timeoutMs = 5000, traceOptions = null) {
  const started = Date.now();
  const headers = {};
  let reqBodyStr = null;
  if (bodyObj !== null && bodyObj !== undefined) {
    headers['Content-Type'] = 'application/json';
    reqBodyStr = typeof bodyObj === 'string' ? bodyObj : JSON.stringify(bodyObj);
  } else {
    headers['Accept'] = 'application/json';
  }

  let status = '000';
  let respHeaders = {};
  let rawText = '';
  let json = null;
  let error = null;

  try {
    const res = await fetch(url, {
      method,
      headers,
      body: reqBodyStr,
      signal: AbortSignal.timeout(timeoutMs)
    });
    status = String(res.status);
    for (const hk of ['x-gateway-handled', 'x-service-instance', 'x-db-node', 'x-db-fallback', 'x-consistencia', 'content-type']) {
      const val = res.headers.get(hk);
      if (val) respHeaders[hk] = val;
    }
    rawText = await res.text();
    try {
      json = JSON.parse(rawText);
    } catch {
      json = null;
    }
  } catch (err) {
    error = err?.message || 'Error de conexión';
    status = '000';
  }

  const durationMs = Date.now() - started;

  if (traceOptions && traceOptions.record !== false) {
    const shortUrl = url.replace(/^https?:\/\/[^/]+/, '');
    const lvl = status.startsWith('2') ? 'OK' : status === '409' ? 'WARN' : 'ERR';
    addEventLog(lvl, 'HTTP', `${method} ${shortUrl} -> ${status} (${durationMs}ms)`);
    recordHttpTrace({
      screen: traceOptions.screen || 'SLIDE',
      method,
      url,
      requestBody: bodyObj,
      status,
      durationMs,
      headers: respHeaders,
      responseBody: json ?? rawText,
      note: traceOptions.note || ''
    });
  }

  return { status, durationMs, headers: respHeaders, rawText, json, error };
}

function parseDockStatus(statusText) {
  const s = (statusText || '').toLowerCase();
  if (!s) return 'missing';
  if (s.includes('unhealthy')) return 'unhealthy';
  if (s.includes('(healthy)') || s.includes('healthy')) return 'healthy';
  if (s.includes('starting')) return 'starting';
  if (s.includes('up')) return 'healthy';
  if (s.includes('exited') || s.includes('dead') || s.includes('created')) return 'stopped';
  return 'stopped';
}

async function getDockerSnapshot() {
  const res = await execDocker(['ps', '-a', '--format', '{{.Name}}|{{.Service}}|{{.Status}}|{{.Ports}}'], 8000);
  const byService = new Map();

  if (res.ok && res.stdout.trim()) {
    const lines = res.stdout.trim().split(/\r?\n/);
    for (const line of lines) {
      const [name = '', service = '', status = '', ports = ''] = line.split('|');
      if (service) {
        const cleanPorts = ports
          .replace(/0\.0\.0\.0:/g, '')
          .replace(/\[::\]:\d+->\d+\/tcp,?\s*/g, '')
          .replace(/\/tcp/g, '')
          .trim();
        byService.set(service.trim(), {
          name: name.trim(),
          service: service.trim(),
          rawStatus: status.trim(),
          state: parseDockStatus(status),
          ports: cleanPorts
        });
      }
    }
  }

  const containers = EXPECTED_SERVICES.map((meta) => {
    const found = byService.get(meta.service);
    if (found) {
      return { ...meta, ...found };
    }
    return {
      ...meta,
      name: meta.service,
      rawStatus: res.ok ? 'No creado' : 'Docker sin respuesta',
      state: res.ok ? 'missing' : 'unknown',
      ports: `:${meta.port}`
    };
  });

  const healthyCount = containers.filter((c) => c.state === 'healthy').length;
  return {
    dockerAvailable: res.ok,
    error: res.ok ? null : (res.stderr || res.error || 'Docker no disponible'),
    healthyCount,
    totalCount: containers.length,
    containers
  };
}

function sendJson(res, statusCode, payload) {
  res.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store'
  });
  res.end(JSON.stringify(payload));
}

function readJsonBody(req) {
  return new Promise((resolve) => {
    let data = '';
    req.on('data', (chunk) => {
      data += chunk;
      if (data.length > 2 * 1024 * 1024) {
        data = data.slice(0, 2 * 1024 * 1024);
      }
    });
    req.on('end', () => {
      if (!data.trim()) return resolve({});
      try {
        resolve(JSON.parse(data));
      } catch {
        resolve({});
      }
    });
    req.on('error', () => resolve({}));
  });
}

function formatDateFile() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
}

function formatDateReadable() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
}

async function handleApi(req, res, pathname, query) {
  if (req.method === 'GET' && pathname === '/api/dock') {
    const snap = await getDockerSnapshot();
    return sendJson(res, 200, snap);
  }

  if (req.method === 'GET' && pathname === '/api/saldo-portada') {
    const r = await apiFetch('GET', `${GATEWAY}/api/cuentas/${ORIGEN}/saldo-critico`, null, 2500, { record: false });
    const datos = r.json?.datos || null;
    return sendJson(res, 200, {
      ok: r.status === '200' && !!datos,
      status: r.status,
      saldo: datos?.saldo ?? null,
      consumidoHoy: datos?.consumidoHoy ?? null,
      limiteDiario: datos?.limiteDiario ?? null
    });
  }

  if (req.method === 'GET' && pathname === '/api/eureka') {
    const r = await apiFetch('GET', `${EUREKA}/eureka/apps`, null, 5000, {
      screen: 'SLIDE_03',
      note: 'Catálogo de servicios registrados en Eureka'
    });
    let apps = [];
    if (r.status === '200' && r.json?.applications?.application) {
      const rawApps = Array.isArray(r.json.applications.application)
        ? r.json.applications.application
        : [r.json.applications.application];
      apps = rawApps.map((app) => {
        const rawInst = app.instance ? (Array.isArray(app.instance) ? app.instance : [app.instance]) : [];
        return {
          name: app.name,
          instances: rawInst.map((inst) => ({
            instanceId: String(inst.instanceId || '').replace(/:([0-9a-f]{6})[0-9a-f]{26}(?=:|$)/, ':$1'),
            hostName: inst.hostName || '',
            ipAddr: inst.ipAddr || '',
            port: inst.port?.$ ?? inst.port ?? '',
            status: inst.status || 'UNKNOWN'
          }))
        };
      });
    }
    sessionState.slideResults.s03 = `HTTP ${r.status} · ${apps.length} servicios en Eureka`;
    return sendJson(res, 200, {
      ok: r.status === '200',
      status: r.status,
      durationMs: r.durationMs,
      apps,
      error: r.error
    });
  }

  if (req.method === 'POST' && pathname === '/api/demo/balanceo') {
    const started = Date.now();
    const counts = new Map();
    const requests = [];
    let okCount = 0;

    for (let i = 1; i <= 20; i += 1) {
      const traceOpts = i === 1
        ? { screen: 'SLIDE_04', note: 'Muestra testigo de balanceo Round Robin (lote de 20 peticiones)' }
        : { record: false };
      const r = await apiFetch('GET', `${GATEWAY}/api/cuentas/instancia`, null, 5000, traceOpts);
      const inst = r.headers['x-service-instance'] || 'sin-cabecera';
      if (r.status === '200') okCount += 1;
      const key = `${r.status}|${inst}`;
      counts.set(key, (counts.get(key) || 0) + 1);
      requests.push({ index: i, status: r.status, instance: inst, durationMs: r.durationMs });
    }

    const durationMs = Date.now() - started;
    const distribution = Array.from(counts.entries()).map(([k, count]) => {
      const [status, instance] = k.split('|');
      return { status, instance, count, pct: Math.round((count / 20) * 100) };
    });

    const lvl = okCount === 20 ? 'OK' : okCount > 0 ? 'WARN' : 'ERR';
    addEventLog(lvl, 'HTTP', `20x GET /instancia -> ${okCount}/20 OK (${durationMs}ms)`);
    sessionState.slideResults.s04 = `${okCount}/20 HTTP 200 (Round Robin en ${(durationMs / 1000).toFixed(2)}s)`;

    return sendJson(res, 200, {
      ok: okCount === 20,
      okCount,
      errCount: 20 - okCount,
      durationMs,
      distribution,
      requests
    });
  }

  if (req.method === 'POST' && pathname === '/api/demo/transferencia') {
    const body = await readJsonBody(req);
    const monto = Number(body.monto ?? 25);
    const motivo = String(body.motivo || (monto > 1000 ? 'Prueba limite' : 'Transferencia P2P'));
    const isErrTest = monto >= 1000;
    const payload = {
      celularOrigen: ORIGEN,
      celularDestino: DESTINO,
      monto,
      motivo
    };

    const r = await apiFetch('POST', `${GATEWAY}/api/transacciones/transferir`, payload, 10000, {
      screen: isErrTest ? 'SLIDE_06' : 'SLIDE_05',
      note: isErrTest ? 'Validación de saldo insuficiente (HTTP 409)' : 'Transferencia P2P exitosa (ACID)'
    });

    const datos = r.json?.datos || {};
    const aud = r.json?.auditoriaTecnica || {};
    const parsed = {
      status: r.status,
      durationMs: r.durationMs,
      mensaje: r.json?.mensaje || (r.status === '000' ? 'Sin conexión con Gateway :8080' : '-'),
      codigoComprobante: datos.codigoComprobante || '-',
      nuevoSaldoOrigen: datos.nuevoSaldoOrigen ?? null,
      instanciaCuentasConsultada: aud.instanciaCuentasConsultada || '-',
      nodoBaseDatos: aud.nodoBaseDatos || '-',
      politicaEnrutamiento: aud.politicaEnrutamiento || '-',
      raw: r.json ?? r.rawText
    };

    if (isErrTest) {
      sessionState.slideResults.s06 = `HTTP ${r.status} · ${parsed.mensaje}`;
    } else {
      sessionState.slideResults.s05 = `HTTP ${r.status} · Comprobante \`${parsed.codigoComprobante}\` · Nodo \`${parsed.nodoBaseDatos}\``;
    }

    return sendJson(res, 200, parsed);
  }

  if (req.method === 'POST' && pathname === '/api/demo/lecturas') {
    const body = await readJsonBody(req);
    const stopReplica1 = Boolean(body.stopReplica1);
    const tag = String(body.tag || (stopReplica1 ? '11' : '07'));

    let dockerResult = null;
    if (stopReplica1) {
      addEventLog('WARN', 'FAIL', 'docker compose stop replica1');
      dockerResult = await execDocker(['stop', 'replica1'], 15000);
    }

    const started = Date.now();
    const counts = new Map();
    const requests = [];
    let okCount = 0;
    let fallbackCount = 0;

    for (let i = 1; i <= 10; i += 1) {
      for (const ep of [
        { path: `cuentas/${ORIGEN}/contactos`, label: 'contactos' },
        { path: `transacciones/historial/${ORIGEN}`, label: 'historial' }
      ]) {
        const traceOpts = i === 1
          ? {
              screen: `SLIDE_${tag}`,
              note: stopReplica1
                ? `Muestra testigo en réplica superviviente tras caída de replica1 (${ep.label})`
                : `Muestra testigo de lectura ordinaria en réplica (${ep.label})`
            }
          : { record: false };

        const r = await apiFetch('GET', `${GATEWAY}/api/${ep.path}`, null, 5000, traceOpts);
        const node = r.headers['x-db-node'] || 'desconocido';
        const fallback = r.headers['x-db-fallback'] === 'true';
        if (r.status === '200') okCount += 1;
        if (fallback) fallbackCount += 1;

        const key = `${r.status}|${node}|${fallback}`;
        counts.set(key, (counts.get(key) || 0) + 1);
        requests.push({ status: r.status, endpoint: ep.label, node, fallback, durationMs: r.durationMs });
      }
    }

    const durationMs = Date.now() - started;
    const distribution = Array.from(counts.entries()).map(([k, count]) => {
      const [status, node, fb] = k.split('|');
      return { status, node, fallback: fb === 'true', count, pct: Math.round((count / 20) * 100) };
    });

    const lvl = okCount === 20 ? 'OK' : okCount > 0 ? 'WARN' : 'ERR';
    if (stopReplica1) {
      addEventLog(lvl, 'FAIL', `Failover 20x -> ${okCount}/20 OK (${20 - okCount} err) fb=${fallbackCount}`);
      sessionState.slideResults.s11 = `${okCount}/20 HTTP 200 (fallback=${fallbackCount}, ${(durationMs / 1000).toFixed(2)}s)`;
    } else {
      addEventLog(lvl, 'HTTP', `20x lecturas R1/R2 -> ${okCount}/20 OK fb=${fallbackCount}`);
      sessionState.slideResults.s07 = `${okCount}/20 HTTP 200 (${(durationMs / 1000).toFixed(2)}s)`;
    }

    return sendJson(res, 200, {
      ok: okCount === 20,
      okCount,
      errCount: 20 - okCount,
      fallbackCount,
      durationMs,
      stoppedReplica1: stopReplica1,
      dockerOk: dockerResult ? dockerResult.ok : null,
      distribution,
      requests
    });
  }

  if (req.method === 'GET' && pathname === '/api/demo/saldo-critico') {
    const r = await apiFetch('GET', `${GATEWAY}/api/cuentas/${ORIGEN}/saldo-critico`, null, 5000, {
      screen: 'SLIDE_08',
      note: 'Lectura crítica RYOW (consistencia inmediata en Primary)'
    });
    const datos = r.json?.datos || {};
    const aud = r.json?.auditoriaTecnica || {};
    sessionState.slideResults.s08 = `HTTP ${r.status} · Nodo \`${aud.nodoBaseDatos || '-'}\``;

    return sendJson(res, 200, {
      ok: r.status === '200',
      status: r.status,
      durationMs: r.durationMs,
      saldo: datos.saldo ?? null,
      consumidoHoy: datos.consumidoHoy ?? null,
      limiteDiario: datos.limiteDiario ?? null,
      nodoBaseDatos: aud.nodoBaseDatos || '-',
      politicaEnrutamiento: aud.politicaEnrutamiento || '-',
      raw: r.json ?? r.rawText
    });
  }

  if (req.method === 'GET' && pathname === '/api/demo/db-estado') {
    const waitRejoin = query.get('waitRejoin') === '1';
    const maxAttempts = waitRejoin ? 12 : 1;
    let lastRes = null;
    let attempts = 0;

    for (let i = 1; i <= maxAttempts; i += 1) {
      attempts = i;
      const r = await apiFetch('GET', `${GATEWAY}/api/cuentas/db/estado`, null, 5000, { record: false });
      lastRes = r;
      if (waitRejoin && r.status === '200' && Array.isArray(r.json?.replicas)) {
        const rep1 = r.json.replicas.find((x) => x.nodo === 'REPLICA_1');
        if (rep1 && rep1.available === true) break;
      }
      if (i < maxAttempts) {
        await new Promise((resolve) => setTimeout(resolve, 1000));
      }
    }

    const r = lastRes;
    recordHttpTrace({
      screen: waitRejoin ? 'SLIDE_14' : 'SLIDE_12',
      method: 'GET',
      url: `${GATEWAY}/api/cuentas/db/estado`,
      requestBody: null,
      status: r.status,
      durationMs: r.durationMs,
      headers: r.headers,
      responseBody: r.json ?? r.rawText,
      note: waitRejoin
        ? 'Estado del clúster PostgreSQL tras reincorporación de replica1'
        : 'Estado del clúster PostgreSQL tras caída de replica1'
    });
    addEventLog(r.status === '200' ? 'OK' : 'ERR', 'HTTP', `GET /db/estado -> ${r.status} (${attempts} intento/s)`);

    if (waitRejoin) {
      sessionState.slideResults.s14 = `HTTP ${r.status} (reincorporación verificada en ${attempts} consulta/s)`;
    } else {
      sessionState.slideResults.s12 = `HTTP ${r.status}`;
    }

    return sendJson(res, 200, {
      ok: r.status === '200',
      status: r.status,
      durationMs: r.durationMs,
      attempts,
      servicio: r.json?.servicio || null,
      consultasTotales: r.json?.consultasTotales || null,
      replicas: Array.isArray(r.json?.replicas) ? r.json.replicas : [],
      raw: r.json ?? r.rawText
    });
  }

  if (req.method === 'POST' && pathname === '/api/demo/ping-cuenta') {
    const r = await apiFetch('GET', `${GATEWAY}/api/cuentas/${ORIGEN}`, null, 3000, { record: false });
    const instance = r.headers['x-service-instance'] || 'sin-instancia';
    return sendJson(res, 200, {
      status: r.status,
      instance,
      durationMs: r.durationMs,
      time: nowTimeStr()
    });
  }

  if (req.method === 'POST' && pathname === '/api/docker/action') {
    const body = await readJsonBody(req);
    const actionMap = {
      'stop-cuentas-2': { args: ['stop', 'ms-cuentas-2'], lvl: 'WARN', tag: 'FAIL', msg: 'docker compose stop ms-cuentas-2' },
      'start-cuentas-2': { args: ['start', 'ms-cuentas-2'], lvl: 'INFO', tag: 'FAIL', msg: 'docker compose start ms-cuentas-2' },
      'stop-replica-1': { args: ['stop', 'replica1'], lvl: 'WARN', tag: 'FAIL', msg: 'docker compose stop replica1' },
      'start-replica-1': { args: ['start', 'replica1'], lvl: 'INFO', tag: 'FAIL', msg: 'docker compose start replica1 (WAL sync)' },
      'up': { args: ['up', '-d'], lvl: 'INFO', tag: 'DOCK', msg: 'docker compose up -d' },
      'start-all': { args: ['start'], lvl: 'INFO', tag: 'DOCK', msg: 'docker compose start' },
      'reset': { args: ['down', '-v'], lvl: 'WARN', tag: 'DOCK', msg: 'docker compose down -v' }
    };

    const spec = actionMap[body.action];
    if (!spec) {
      return sendJson(res, 400, { ok: false, error: 'Acción Docker no permitida' });
    }

    addEventLog(spec.lvl, spec.tag, spec.msg);
    let result = await execDocker(spec.args, body.action === 'up' || body.action === 'reset' ? 120000 : 25000);

    if (body.action === 'reset' && result.ok) {
      addEventLog('INFO', 'DOCK', 'docker compose up -d --build');
      const upRes = await execDocker(['up', '-d', '--build'], 180000);
      result = {
        ok: upRes.ok,
        stdout: `${result.stdout}\n${upRes.stdout}`.trim(),
        stderr: `${result.stderr}\n${upRes.stderr}`.trim(),
        error: upRes.error,
        durationMs: result.durationMs + upRes.durationMs
      };
    }

    if (!result.ok) {
      addEventLog('ERR', 'DOCK', `${spec.msg} falló: ${result.stderr || result.error}`);
    } else {
      addEventLog('OK', 'DOCK', `${spec.msg} completado (${result.durationMs}ms)`);
    }

    return sendJson(res, 200, result);
  }

  if (req.method === 'POST' && pathname === '/api/log-client') {
    const body = await readJsonBody(req);
    addEventLog(body.level || 'INFO', body.tag || 'UI', body.message || '');
    if (body.slideKey && body.summary) {
      sessionState.slideResults[body.slideKey] = body.summary;
    }
    return sendJson(res, 200, { ok: true });
  }

  if (req.method === 'GET' && pathname === '/api/logs') {
    return sendJson(res, 200, {
      eventLog: sessionState.eventLog,
      httpTraces: sessionState.httpTraces
    });
  }

  if (req.method === 'POST' && pathname === '/api/export') {
    const body = await readJsonBody(req);
    const mode = body.mode || 'LIVE';
    const clientSummary = body.clientSummary || {};
    const dock = await getDockerSnapshot();
    const mergedResults = { ...sessionState.slideResults, ...clientSummary };

    const lines = [];
    lines.push('# Reporte de Ejecución — Billetera Digital Distribuida');
    lines.push('');
    lines.push(`- **Fecha y hora:** ${formatDateReadable()}`);
    lines.push(`- **Generador:** \`presentacion-web\` (Interfaz Web Interactiva)`);
    lines.push(`- **Modo de ejecución:** ${mode}`);
    lines.push(`- **Gateway:** \`${GATEWAY}\``);
    lines.push(`- **Eureka:** \`${EUREKA}\``);
    lines.push(`- **Cuentas de prueba:** Origen \`${ORIGEN}\` / Destino \`${DESTINO}\``);
    lines.push('');
    lines.push('## 1. Estado del Clúster Docker');
    lines.push('');
    if (dock.dockerAvailable) {
      lines.push('| Contenedor | Servicio | Estado | Puertos |');
      lines.push('|---|---|---|---|');
      for (const c of dock.containers) {
        lines.push(`| \`${c.name}\` | \`${c.service}\` | ${c.rawStatus} (${c.state}) | ${c.ports || '-'} |`);
      }
    } else {
      lines.push('_No se pudo obtener estado de Docker Compose (daemon inactivo o modo simulado)._');
    }
    lines.push('');
    lines.push('## 2. Resumen de Pruebas Ejecutadas en la Sesión');
    lines.push('');
    const labels = [
      ['s03', 'Slide 03 · Descubrimiento Eureka'],
      ['s04', 'Slide 04 · Balanceo HTTP Round Robin'],
      ['s05', 'Slide 05 · Transferencia P2P ACID'],
      ['s06', 'Slide 06 · Rechazo Controlado (409)'],
      ['s07', 'Slide 07 · Lecturas en Réplicas WAL'],
      ['s08', 'Slide 08 · Lectura Crítica RYOW'],
      ['s09', 'Slide 09 · Caída y Retorno ms-cuentas-2'],
      ['s11', 'Slide 11 · Failover en Réplica 2'],
      ['s12', 'Slide 12 · Estado BD tras Caída'],
      ['s14', 'Slide 14 · Estado BD Recuperación (2/2)']
    ];
    const rows = labels.filter(([k]) => mergedResults[k]).map(([k, lbl]) => `| ${lbl} | ${mergedResults[k]} |`);
    if (rows.length > 0) {
      lines.push('| Prueba / Diapositiva | Resultado |');
      lines.push('|---|---|');
      lines.push(...rows);
    } else {
      lines.push('_Aún no se han ejecutado diapositivas en esta sesión._');
    }
    lines.push('');
    lines.push('## 3. Salidas de Peticiones HTTP (GET / POST)');
    lines.push('');
    if (sessionState.httpTraces.length === 0) {
      lines.push('_No se capturaron trazas HTTP en vivo durante esta sesión._');
      lines.push('');
    } else {
      for (const tr of sessionState.httpTraces) {
        const shortUrl = tr.url.replace(/^https?:\/\/[^/]+/, '') || tr.url;
        lines.push(`### ${tr.seq}. \`${tr.method} ${shortUrl}\` -> HTTP \`${tr.status}\` (${tr.durationMs} ms)`);
        lines.push('');
        lines.push(`- **Hora:** ${tr.time} | **Pantalla:** \`${tr.screen}\` | **URL:** \`${tr.url}\`${tr.note ? ` | **Nota:** ${tr.note}` : ''}`);
        const hdrEntries = Object.entries(tr.headers || {});
        if (hdrEntries.length > 0) {
          lines.push(`- **Headers de respuesta:** ${hdrEntries.map(([k, v]) => `\`${k}: ${v}\``).join(' · ')}`);
        }
        if (tr.requestBody) {
          lines.push('');
          lines.push('**Request Body:**');
          lines.push('```json');
          lines.push(JSON.stringify(tr.requestBody, null, 2));
          lines.push('```');
        }
        lines.push('');
        lines.push('**Response Body:**');
        if (!tr.responseBody && tr.responseBody !== 0) {
          lines.push('_Sin cuerpo de respuesta._');
        } else {
          const formatted = typeof tr.responseBody === 'string'
            ? tr.responseBody
            : JSON.stringify(tr.responseBody, null, 2);
          const lang = formatted.trim().startsWith('{') || formatted.trim().startsWith('[') ? 'json' : 'text';
          lines.push(`\`\`\`${lang}`);
          lines.push(formatted.length > 6000 ? `${formatted.slice(0, 6000)}\n... [truncado a 6000 caracteres]` : formatted);
          lines.push('```');
        }
        lines.push('');
      }
    }

    lines.push('## 4. Bitácora de Eventos de la Sesión');
    lines.push('');
    if (sessionState.eventLog.length === 0) {
      lines.push('_Sin eventos registrados._');
    } else {
      lines.push('```text');
      for (const ev of sessionState.eventLog) {
        lines.push(`${ev.time} [${ev.level.padEnd(4)}] [${ev.tag.padEnd(4)}] ${ev.message}`);
      }
      lines.push('```');
    }

    const markdown = lines.join('\n');
    const repDir = path.join(REPO_DIR, 'reportes');
    fs.mkdirSync(repDir, { recursive: true });
    const filename = `reporte-${formatDateFile()}.md`;
    const filePath = path.join(repDir, filename);
    fs.writeFileSync(filePath, markdown, 'utf-8');
    addEventLog('OK', 'SYS', `Reporte exportado: reportes/${filename}`);

    return sendJson(res, 200, {
      ok: true,
      filename,
      relativePath: `reportes/${filename}`,
      filePath,
      traceCount: sessionState.httpTraces.length,
      eventCount: sessionState.eventLog.length,
      markdown
    });
  }

  return sendJson(res, 404, { error: 'Endpoint no encontrado' });
}

function serveStatic(res, pathname) {
  const relPath = pathname === '/' ? 'index.html' : pathname.replace(/^\/+/, '');
  const safePath = path.normalize(relPath).replace(/^(\.\.[/\\])+/, '');
  const fullPath = path.join(__dirname, safePath);

  if (!fullPath.startsWith(__dirname) || !fs.existsSync(fullPath) || fs.statSync(fullPath).isDirectory()) {
    res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('404 Not Found');
    return;
  }

  const ext = path.extname(fullPath).toLowerCase();
  res.writeHead(200, {
    'Content-Type': MIME_TYPES[ext] || 'application/octet-stream',
    'Cache-Control': 'no-store'
  });
  fs.createReadStream(fullPath).pipe(res);
}

const server = http.createServer(async (req, res) => {
  const parsedUrl = new URL(req.url || '/', `http://localhost:${PORT}`);
  const pathname = parsedUrl.pathname;

  try {
    if (pathname.startsWith('/api/')) {
      await handleApi(req, res, pathname, parsedUrl.searchParams);
    } else {
      serveStatic(res, pathname);
    }
  } catch (err) {
    sendJson(res, 500, { error: err?.message || 'Error interno del servidor' });
  }
});

server.listen(PORT, '127.0.0.1', () => {
  addEventLog('INFO', 'SYS', `Servidor web iniciado en http://localhost:${PORT}`);
  console.log(`\n  [OK] Presentación interactiva lista en: http://localhost:${PORT}`);
  console.log(`  [i]  Gateway: ${GATEWAY}  |  Eureka: ${EUREKA}`);
  console.log(`  [i]  Presiona Ctrl+C para detener.\n`);
});
