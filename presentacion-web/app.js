(() => {
  'use strict';

  const ORIGEN = '0991112233';
  const DESTINO = '0984445566';

  const BLOCKS = {
    1: { name: 'Arquitectura y Docker', start: 1, range: '01–02', desc: 'Topología C4 y salud de los 8 contenedores' },
    2: { name: 'Eureka y Balanceo HTTP', start: 3, range: '03–04', desc: 'Service Discovery (lb://) y Round Robin 10/10' },
    3: { name: 'Transferencia P2P ACID', start: 5, range: '05–06', desc: 'Orquestación P2P, bloqueo pesimista y 409' },
    4: { name: 'Lecturas Réplica / RYOW', start: 7, range: '07–08', desc: '@UsarNodo WAL y Read-Your-Own-Writes' },
    5: { name: 'Caídas: App y Postgres', start: 9, range: '09–14', desc: 'Failover en vivo ms-cuentas-2 y replica1' },
    6: { name: 'Conclusiones Técnicas', start: 15, range: '15', desc: 'Decisiones, limitaciones y exportación' }
  };

  const SLIDE_META = [
    {
      id: 0, block: 0, title: 'Portada · Billetera Digital Distribuida', duration: '~20s',
      nextLabel: 'Iniciar Presentación (1/15)',
      quote: 'Presentamos una billetera digital distribuida P2P diseñada para demostrar arquitectura desacoplada, consistencia ACID, enrutamiento Primario/Réplicas WAL y tolerancia a fallos en vivo.',
      points: [
        'Pulsa [ESPACIO] o [→] para avanzar paso a paso.',
        'Usa [1-6] para saltar directo a cualquier bloque.',
        'Si Docker no está levantado, cambia arriba a "PLAN B · SIMULADO" en cualquier momento.'
      ]
    },
    {
      id: 1, block: 1, title: 'Slide 01 · Arquitectura del Sistema (8 Contenedores Docker)', duration: '~35s',
      nextLabel: 'Detalle del clúster',
      quote: 'Presentamos una billetera digital distribuida P2P ejecutada sobre 8 contenedores Docker independientes. La arquitectura se basa en el principio de estricto desacoplamiento: tenemos dos microservicios de negocio (ms-cuentas y ms-transacciones), cada uno con su propio esquema y credenciales en base de datos. Ningún servicio accede directamente a las tablas del otro. Todo el tráfico externo entra centralizado a través de un API Gateway en el puerto 8080.',
      points: [
        'Segregación Database-per-Service: cuentas_db y tx_db en esquemas aislados.',
        'Cero acoplamiento físico directo entre clientes y microservicios.',
        'Haz clic en cualquier nodo del diagrama para ver su puerto y responsabilidad.'
      ]
    },
    {
      id: 2, block: 1, title: 'Slide 02 · Clúster Docker Compose (Estado de Servicios)', duration: '~25s',
      nextLabel: '2. Descubrimiento en Eureka',
      quote: 'Verificamos la topología en tiempo real: Eureka Server para descubrimiento, API Gateway, dos instancias de cuentas (ms-cuentas-1 y ms-cuentas-2) para balanceo y alta disponibilidad, ms-transacciones, y un clúster PostgreSQL 17 compuesto por un primario de escritura y dos réplicas sincronizadas mediante streaming físico de registros WAL. Todos los servicios reportan estado healthy.',
      points: [
        '8 contenedores en red wallet-net.',
        'PostgreSQL 17: 1 Primario (:5432) + 2 Réplicas WAL (:5433 y :5434).'
      ]
    },
    {
      id: 3, block: 2, title: 'Slide 03 · Descubrimiento Dinámico con Netflix Eureka', duration: '~35s',
      nextLabel: 'Balanceo HTTP Round Robin',
      quote: 'En arquitecturas dinámicas no se configuran direcciones IP fijas. Cada microservicio se registra automáticamente en Eureka al inicializar y envía un latido (heartbeat) cada 5 segundos. El API Gateway resuelve dinámicamente las rutas utilizando el identificador lógico lb://ms-cuentas. Esto permite añadir o reemplazar réplicas de cómputo de manera transparente.',
      points: [
        'lb:// = Load Balanced (Spring Cloud LoadBalancer + Eureka).',
        'Heartbeat configurado cada 5 segundos.',
        '2 instancias registradas bajo MS-CUENTAS.'
      ]
    },
    {
      id: 4, block: 2, title: 'Slide 04 · Balanceo de Carga HTTP (Round Robin)', duration: '~40s',
      nextLabel: '3. Comunicación entre servicios',
      quote: 'Lanzamos una ráfaga de 20 peticiones concurrentes al endpoint /api/cuentas/instancia. En la cabecera X-Service-Instance observamos un reparto equitativo 10/10 entre la instancia 8081 y la 8082 mediante Round Robin en capa 7. Los microservicios son totalmente stateless, permitiendo distribuir carga sin afinidad de sesión.',
      points: [
        'Cabecera X-Service-Instance demuestra alternancia 10/10.',
        'Servicios stateless: cualquier réplica atiende cualquier request.'
      ]
    },
    {
      id: 5, block: 3, title: 'Slide 05 · Orquestación P2P entre Microservicios (ACID)', duration: '~50s',
      nextLabel: 'Validación saldo insuficiente',
      quote: 'Ejecutamos una transferencia P2P de $25. El cliente invoca a ms-transacciones, pero este delega el movimiento contable en ms-cuentas resolviéndolo por Eureka. Dentro de ms-cuentas, débito y crédito se ejecutan en una única transacción ACID. Para prevenir deadlocks por concurrencia, aplicamos bloqueo pesimista ordenando las cuentas por su identificador numérico. La auditoría técnica confirma que la escritura se canalizó obligatoriamente al nodo primario de la base de datos.',
      points: [
        'Señalar instanciaCuentasConsultada en la auditoría técnica.',
        'Señalar nodoBaseDatos: PRIMARY (recovery=false).',
        'Bloqueo pesimista ordenado por ID evita deadlocks.'
      ]
    },
    {
      id: 6, block: 3, title: 'Slide 06 · Validación de Reglas de Negocio (Error Controlado)', duration: '~40s',
      nextLabel: '4. Persistencia replicada',
      quote: 'Probamos ahora una solicitud que excede el saldo disponible. El servicio responde un error controlado 409 Conflict. La transacción es revertida en su totalidad preservando la integridad del saldo, mientras que en ms-transacciones queda auditado el comprobante con estado RECHAZADA para garantizar trazabilidad financiera completa.',
      points: [
        'Monto $9999.00 supera el saldo disponible.',
        'Rollback total en cuentas_db + comprobante auditado RECHAZADA en tx_db.'
      ]
    },
    {
      id: 7, block: 4, title: 'Slide 07 · Enrutamiento BD: Primario vs Réplicas WAL', duration: '~45s',
      nextLabel: 'Lectura crítica RYOW',
      quote: 'El sistema implementa un RoutingDataSource dinámico. Las escrituras van siempre al primario, pero las lecturas ordinarias que toleran consistencia eventual se desvían a las réplicas PostgreSQL. Las 20 peticiones se reparten equitativamente entre REPLICA_1 y REPLICA_2 (ambas con recovery=true), descargando al primario del tráfico masivo de lectura.',
      points: [
        'Anotación @UsarNodo dirige lecturas ordinarias a réplicas.',
        'Cabecera X-Db-Node muestra REPLICA_1 y REPLICA_2 (recovery=true).'
      ]
    },
    {
      id: 8, block: 4, title: 'Slide 08 · Consistencia Inmediata: Read-Your-Own-Writes (RYOW)', duration: '~45s',
      nextLabel: '5. Simulación de fallos (en vivo)',
      quote: 'La replicación asíncrona por WAL introduce un retardo mínimo (lag de replicación). Si un usuario realiza una transferencia y consulta inmediatamente su saldo, una réplica podría devolver un dato desactualizado. Para mitigar esto, diseñamos el endpoint de saldo crítico con la política Read-Your-Own-Writes, forzando la lectura directa en el nodo primario para garantizar consistencia inmediata.',
      points: [
        'GET /api/cuentas/{origen}/saldo-critico lee siempre en PRIMARY.',
        'Evita lecturas obsoletas (stale reads) justo después de transferir.'
      ]
    },
    {
      id: 9, block: 5, title: 'Slide 09 · Alta Disponibilidad HTTP: Caída de ms-cuentas-2', duration: '~50s',
      nextLabel: 'Avanzar fase / Siguiente',
      quote: 'Iniciamos tráfico continuo contra el sistema y forzamos la caída súbita de ms-cuentas-2. El Gateway y Eureka detectan la degradación y en menos de 400 milisegundos convergen el 100% del tráfico a ms-cuentas-1, registrando cero errores 5xx de cara al usuario. Al reiniciar el contenedor, el sistema espera su calentamiento antes de reintegrarlo al pool de Round Robin.',
      points: [
        'Fase 1: Tráfico 50/50 -> Pulsa [ESPACIO] para detener ms-cuentas-2.',
        'Fase 2: Convergencia a ms-cuentas-1 -> Pulsa [ESPACIO] para reiniciar.',
        'Fase 3: Calentamiento JVM y retorno -> Pulsa [ESPACIO] para ver resumen.'
      ]
    },
    {
      id: 10, block: 5, title: 'Slide 10 · Introducción al Fallo en la Capa de Datos', duration: '~20s',
      nextLabel: 'Ejecutar stop replica1 + 20 lecturas',
      quote: 'Trasladamos ahora la prueba de fallos a la capa de persistencia. Analizaremos qué ocurre con las consultas activas cuando una de las réplicas físicas de PostgreSQL queda fuera de servicio.',
      points: [
        '@UsarNodo captura fallos SQL y reintenta en réplica sana (X-Db-Fallback: true).',
        'ReplicaHealthTracker sondea cada 3s.',
        'Al avanzar a la Slide 11 se detendrá replica1 en caliente.'
      ]
    },
    {
      id: 11, block: 5, title: 'Slide 11 · Failover Transparente: Lecturas sobre REPLICA_2', duration: '~40s',
      nextLabel: 'Estado de salud de réplicas',
      quote: 'Detenemos replica1 en caliente. El pool de conexiones intercepta la indisponibilidad y redirige automáticamente las 20 lecturas ordinarias a replica2. Ninguna solicitud falló; el cliente recibe respuestas 200 transparentes a pesar de haber perdido la mitad del clúster de lectura.',
      points: [
        '20/20 peticiones HTTP 200 sin caída para el usuario.',
        'X-Db-Fallback: true evidencia la captura y reintento en caliente.'
      ]
    },
    {
      id: 12, block: 5, title: 'Slide 12 · Detección Automática de Réplicas (Health Tracker)', duration: '~25s',
      nextLabel: 'Reiniciar replica1 (WAL)',
      quote: 'Un componente interno denominado ReplicaHealthTracker sondea cada 3 segundos la función pg_is_in_recovery(). Al registrar el fallo, marca la réplica como no disponible y la remueve del algoritmo de selección para no degradar la latencia.',
      points: [
        'REPLICA_1 aparece con available=false.',
        'Limitación: failover solo de lectura (no promueve PRIMARY).'
      ]
    },
    {
      id: 13, block: 5, title: 'Slide 13 · Recuperación y Sincronización WAL', duration: '~20s',
      nextLabel: 'Verificar retorno (2/2)',
      quote: 'Reiniciamos replica1. Al levantar, PostgreSQL restablece el enlace de replicación por streaming con el primario y aplica de inmediato los registros WAL acumulados durante el periodo de desconexión.',
      points: [
        'docker compose start replica1 restablece el stream WAL.',
        'Se esperan 2 chequeos sanos seguidos antes de recibir tráfico.'
      ]
    },
    {
      id: 14, block: 5, title: 'Slide 14 · Reincorporación Automática con Umbral 2/2', duration: '~30s',
      nextLabel: '6. Conclusiones técnicas',
      quote: 'Para evitar fluctuaciones transitorias (flapping), el enrutador no reincorpora el nodo al primer pulso de vida. Exige un umbral estricto de 2 chequeos de salud consecutivos saludables (2 x 3s) antes de habilitarlo nuevamente para recibir tráfico productivo.',
      points: [
        'Umbral 2/2 evita flapping en nodos recién levantados.',
        'REPLICA_1 regresa con available=true y LSN sincronizado.'
      ]
    },
    {
      id: 15, block: 6, title: 'Slide 15 · Conclusiones, Decisiones y Mejoras', duration: '~50s',
      nextLabel: 'Volver a Portada',
      quote: 'En conclusión, logramos una arquitectura tolerante a fallos tanto en capa de aplicación como en persistencia. Separamos lecturas críticas al primario y consultas masivas en réplicas; reconocemos que la promoción del primario requeriría Patroni y proponemos Outbox transaccional e idempotencia como mejoras futuras. Para cerrar, exportamos el reporte forense Markdown.',
      points: [
        'Decisión clave: @UsarNodo (Primary vs Réplicas) + Round Robin.',
        'Limitación: Sin failover automático del primario ni idempotencia P2P.',
        'Pulsa [E] para descargar/guardar el reporte Markdown completo.'
      ]
    }
  ];

  const ARCH_NODES = {
    gateway: { title: 'API Gateway (:8080)', detail: 'Spring Cloud Gateway. Punto único de entrada HTTP. Resuelve rutas dinámicas vía lb://ms-cuentas y lb://ms-transacciones usando Eureka y reintenta peticiones GET idempotentes ante fallos transitorios.' },
    eureka: { title: 'Eureka Server (:8761)', detail: 'Netflix Eureka Service Discovery. Recibe auto-registro de todos los microservicios y latidos (heartbeats) cada 5s. Mantiene el catálogo vivo sin IPs estáticas.' },
    cuentas1: { title: 'ms-cuentas-1 (:8081)', detail: 'Instancia #1 de cuentas (stateless). Maneja saldos, bloqueo pesimista ordenado en transferencias y enrutamiento dinámico JDBC (@UsarNodo) hacia Primary o Réplicas.' },
    cuentas2: { title: 'ms-cuentas-2 (:8082)', detail: 'Instancia #2 de cuentas (stateless). Comparte el tráfico 50/50 por Round Robin y permite demostrar tolerancia a fallos en la Slide 09.' },
    tx: { title: 'ms-transacciones (:8083)', detail: 'Orquestador P2P. Expone /api/transacciones/transferir e historial. Invoca a ms-cuentas por Eureka y audita comprobantes APROBADA / RECHAZADA en su propio esquema tx_db.' },
    primary: { title: 'PostgreSQL Primary (:5432)', detail: 'Nodo maestro Read/Write (pg_is_in_recovery() = false). Recibe el 100% de escrituras ACID y las lecturas críticas RYOW (/saldo-critico). Emite registros WAL.' },
    replica1: { title: 'PostgreSQL Réplica 1 (:5433)', detail: 'Réplica física streaming WAL (pg_is_in_recovery() = true). Atiende lecturas ordinarias (contactos/historial). Monitoreada cada 3s por ReplicaHealthTracker.' },
    replica2: { title: 'PostgreSQL Réplica 2 (:5434)', detail: 'Réplica física streaming WAL (pg_is_in_recovery() = true). Absorbe el 100% del tráfico de lectura ordinaria cuando replica1 cae en la Slide 11.' }
  };

  const state = {
    currentSlide: 0,
    mode: 'live', // 'live' | 'sim'
    scriptOpen: false,
    modalOpen: false,
    dock: null,
    portadaSaldo: null,
    selectedArchNode: 'gateway',
    cache: {},
    simDown: { 'ms-cuentas-2': false, 'replica1': false },
    simLogs: [],
    simSummary: {},
    s9: {
      active: false,
      phase: 1, // 1=running both, 2=c2 stopped, 3=restarting, 4=summary
      timer: null,
      inFlight: false,
      total: 0,
      ok: 0,
      err: 0,
      c1: 0,
      c2: 0,
      ring: [],
      points: [],
      stopAtMs: 0,
      startAtMs: 0,
      detectMs: -1,
      rejoinMs: -1,
      consecC1: 0,
      streakMs: 0,
      eventMsg: 'Listo para iniciar telemetría continua contra Gateway :8080'
    }
  };

  // DOM helpers
  const $ = (id) => document.getElementById(id);
  const stageEl = $('slide-stage');

  function esc(str) {
    return String(str ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function showToast(msg) {
    const t = $('toast');
    t.textContent = msg;
    t.classList.remove('hidden');
    clearTimeout(showToast._tid);
    showToast._tid = setTimeout(() => t.classList.add('hidden'), 3200);
  }

  function addLocalLog(level, tag, message, slideKey = null, summary = null) {
    const time = new Date().toTimeString().slice(0, 8);
    state.simLogs.push({ time, level, tag, message });
    if (state.simLogs.length > 150) state.simLogs.shift();
    if (slideKey && summary) state.simSummary[slideKey] = summary;
    fetch('/api/log-client', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ level, tag, message, slideKey, summary })
    }).catch(() => {});
  }

  // Simulated fallback dataset ("Plan B")
  const SIM_BASE_CONTAINERS = [
    { service: 'eureka-server', label: 'Eureka', port: '8761', role: 'Service Discovery' },
    { service: 'api-gateway', label: 'Gateway', port: '8080', role: 'Spring Cloud Gateway' },
    { service: 'ms-cuentas-1', label: 'Cuentas-1', port: '8081', role: 'Microservicio Cuentas' },
    { service: 'ms-cuentas-2', label: 'Cuentas-2', port: '8082', role: 'Microservicio Cuentas' },
    { service: 'ms-transacciones', label: 'Tx', port: '8083', role: 'Orquestador P2P' },
    { service: 'primary', label: 'PG-Primary', port: '5432', role: 'PostgreSQL 17 R/W' },
    { service: 'replica1', label: 'PG-Rep1', port: '5433', role: 'Réplica WAL #1' },
    { service: 'replica2', label: 'PG-Rep2', port: '5434', role: 'Réplica WAL #2' }
  ];

  function getSimulatedDock() {
    const containers = SIM_BASE_CONTAINERS.map((c) => {
      const isDown = Boolean(state.simDown[c.service]);
      return {
        ...c,
        name: c.service.startsWith('primary') ? 'postgres-primary' : c.service === 'replica1' ? 'postgres-replica-1' : c.service === 'replica2' ? 'postgres-replica-2' : c.service,
        state: isDown ? 'stopped' : 'healthy',
        rawStatus: isDown ? 'Exited (0) (Simulado)' : 'Up 14 minutes (healthy)',
        ports: `${c.port}->${c.port}`
      };
    });
    return {
      dockerAvailable: true,
      simulated: true,
      healthyCount: containers.filter((c) => c.state === 'healthy').length,
      totalCount: containers.length,
      containers
    };
  }

  async function refreshDock() {
    if (state.mode === 'sim') {
      state.dock = getSimulatedDock();
      renderDock();
      return state.dock;
    }
    try {
      const r = await fetch('/api/dock');
      const data = await r.json();
      state.dock = data;
      renderDock();
      return data;
    } catch {
      return state.dock;
    }
  }

  function renderDock() {
    const dockEl = $('cluster-dock');
    const containers = state.dock?.containers || SIM_BASE_CONTAINERS.map((c) => ({ ...c, state: 'unknown', rawStatus: 'Consultando…' }));
    dockEl.innerHTML = containers.map((c) => `
      <div class="dock-chip ${esc(c.state)}" title="${esc(c.name)} (${esc(c.rawStatus)})">
        <span class="dot"></span>
        <span>${esc(c.label)}</span>
      </div>
    `).join('');
  }

  function setMode(nextMode) {
    state.mode = nextMode;
    $('btn-mode-live').classList.toggle('active', nextMode === 'live');
    $('btn-mode-sim').classList.toggle('sim-active', nextMode === 'sim');
    showToast(nextMode === 'sim' ? 'Modo PLAN B (Simulado) activado' : 'Modo EN VIVO activado (Docker + Gateway)');
    refreshDock();
    loadSlide(state.currentSlide, false);
  }

  function renderChrome() {
    const meta = SLIDE_META[state.currentSlide];
    $('header-block-tag').textContent = meta.block === 0 ? 'PORTADA' : `BLOQUE ${meta.block}`;
    $('header-slide-counter').textContent = `${state.currentSlide} / 15`;
    $('progress-fill').style.width = `${(state.currentSlide / 15) * 100}%`;

    const nextLabel = state.currentSlide === 9 && state.s9.active && state.s9.phase < 4
      ? (state.s9.phase === 1 ? 'Detener ms-cuentas-2' : state.s9.phase === 2 ? 'Reiniciar ms-cuentas-2' : 'Ver resumen')
      : meta.nextLabel;
    $('btn-next-label').textContent = nextLabel;

    document.querySelectorAll('.blk-pill').forEach((btn) => {
      btn.classList.toggle('active', Number(btn.dataset.block) === meta.block);
    });

    const dotsEl = $('slide-dots');
    if (!dotsEl.children.length) {
      dotsEl.innerHTML = SLIDE_META.map((s) => `<button class="s-dot" data-slide="${s.id}" title="${esc(s.title)}"></button>`).join('');
      dotsEl.addEventListener('click', (e) => {
        const dot = e.target.closest('.s-dot');
        if (dot) goToSlide(Number(dot.dataset.slide), true);
      });
    }
    Array.from(dotsEl.children).forEach((d, idx) => d.classList.toggle('active', idx === state.currentSlide));

    // Update presenter script drawer
    $('drawer-slide-title').textContent = meta.title;
    $('drawer-duration').textContent = meta.duration;
    $('drawer-body').innerHTML = `
      <div>
        <div class="script-section-lbl">Qué decir en voz alta</div>
        <div class="script-quote">“${esc(meta.quote)}”</div>
      </div>
      <div>
        <div class="script-section-lbl">Puntos clave & acción</div>
        <ul class="script-points">
          ${meta.points.map((p) => `<li>• ${esc(p)}</li>`).join('')}
        </ul>
      </div>
    `;
  }

  function stopSlide09Loop() {
    if (state.s9.timer) {
      clearInterval(state.s9.timer);
      state.s9.timer = null;
    }
    state.s9.active = false;
  }

  function goToSlide(idx, useCache = true) {
    if (idx < 0) idx = 0;
    if (idx > 15) idx = 0;
    if (state.currentSlide === 9 && idx !== 9) {
      stopSlide09Loop();
    }
    state.currentSlide = idx;
    renderChrome();
    loadSlide(idx, useCache);
  }

  function nextAction() {
    if (state.currentSlide === 9 && state.s9.active && state.s9.phase < 4) {
      advanceSlide09Phase();
      return;
    }
    goToSlide(state.currentSlide === 15 ? 0 : state.currentSlide + 1, false);
  }

  function prevAction() {
    goToSlide(Math.max(0, state.currentSlide - 1), true);
  }

  function offlineBanner(errMsg) {
    return `
      <div class="callout warn">
        <div>
          <strong>Sin conexión con Gateway / Docker en vivo</strong>
          <div style="font-size:12px;opacity:.85;margin-top:2px;">${esc(errMsg || 'Verifica que docker compose up -d esté levantado, o usa el Plan B simulado.')}</div>
        </div>
        <button class="action-btn amber" onclick="window.__walletApp.setMode('sim')">⚡ Cambiar a Plan B (Simulado)</button>
      </div>
    `;
  }

  function renderLoading(msg) {
    const meta = SLIDE_META[state.currentSlide];
    stageEl.innerHTML = `
      <div class="slide-head">
        <div>
          <div class="slide-kicker">BLOQUE ${meta.block} · DIAPOSITIVA ${String(meta.id).padStart(2, '0')}</div>
          <h1 class="slide-title">${esc(meta.title.replace(/^Slide \d+ · /, ''))}</h1>
        </div>
        <span class="pill info">${state.mode === 'sim' ? 'PLAN B · SIMULADO' : 'EN VIVO'}</span>
      </div>
      <div class="glass-card" style="display:flex;align-items:center;gap:14px;padding:34px 26px;">
        <span class="spinner"></span>
        <div>
          <div style="font-weight:700;">${esc(msg)}</div>
          <div style="font-size:12px;color:var(--text-2);margin-top:3px;">Capturando telemetría y trazas HTTP…</div>
        </div>
      </div>
    `;
  }

  // ==================== SLIDE LOADERS & RENDERERS ====================

  async function loadSlide(idx, useCache) {
    renderChrome();
    switch (idx) {
      case 0: return renderPortada(useCache);
      case 1: return renderSlide01();
      case 2: return renderSlide02(useCache);
      case 3: return renderSlide03(useCache);
      case 4: return renderSlide04(useCache);
      case 5: return renderSlide05(useCache);
      case 6: return renderSlide06(useCache);
      case 7: return renderSlide07(useCache);
      case 8: return renderSlide08(useCache);
      case 9: return startSlide09(useCache);
      case 10: return renderSlide10();
      case 11: return renderSlide11(useCache);
      case 12: return renderSlide12(useCache);
      case 13: return renderSlide13(useCache);
      case 14: return renderSlide14(useCache);
      case 15: return renderSlide15();
    }
  }

  async function renderPortada() {
    const dock = await refreshDock();
    let saldoData = null;
    if (state.mode === 'sim') {
      saldoData = { ok: true, saldo: 1000.00, consumidoHoy: 0.00, limiteDiario: 500.00 };
    } else {
      try {
        const r = await fetch('/api/saldo-portada');
        saldoData = await r.json();
      } catch {
        saldoData = { ok: false };
      }
    }

    const healthy = dock?.healthyCount ?? 0;
    const total = dock?.totalCount ?? 8;

    stageEl.innerHTML = `
      <div class="hero-banner">
        <div class="hero-badge">
          <span>● ARQUITECTURA DISTRIBUIDA</span>
          <span>SPRING CLOUD + POSTGRESQL 17 WAL</span>
        </div>
        <h1 class="hero-title">Billetera Digital Distribuida · Demo en Vivo</h1>
        <p class="hero-sub">
          Plataforma P2P desacoplada con descubrimiento dinámico en <strong>Netflix Eureka</strong>,
          balanceo HTTP <strong>lb:// Round Robin</strong>, transacciones <strong>ACID</strong> y
          enrutamiento inteligente <strong>Primario / Réplicas WAL</strong> con tolerancia a fallos.
        </p>
        <div class="hero-stats">
          <div class="stat-pill">
            <span>Clúster Docker:</span>
            <strong>${healthy}/${total} healthy</strong>
          </div>
          <div class="stat-pill">
            <span>Cuenta Demo ${ORIGEN}:</span>
            <strong>${saldoData?.ok ? `$${Number(saldoData.saldo).toFixed(2)} (Hoy $${Number(saldoData.consumidoHoy).toFixed(2)} / $${Number(saldoData.limiteDiario).toFixed(2)})` : 'Gateway sin conexión'}</strong>
          </div>
          <div class="stat-pill">
            <span>Modo actual:</span>
            <strong>${state.mode === 'sim' ? 'PLAN B · SIMULADO' : 'EN VIVO REAL'}</strong>
          </div>
        </div>
      </div>

      <div class="grid-6">
        ${Object.entries(BLOCKS).map(([bNum, b]) => `
          <button class="block-card" onclick="window.__walletApp.goToSlide(${b.start}, false)">
            <div class="block-card-top">
              <span class="block-num">BLOQUE ${bNum}</span>
              <span class="block-range">Slides ${b.range}</span>
            </div>
            <div class="block-name">${esc(b.name)}</div>
            <div class="block-desc">${esc(b.desc)}</div>
          </button>
        `).join('')}
      </div>

      <div class="callout" style="margin-top:16px;">
        <div>
          <strong>Controles rápidos:</strong>
          <kbd>Espacio</kbd> / <kbd>→</kbd> Siguiente · <kbd>←</kbd> Atrás · <kbd>R</kbd> Re-ejecutar ·
          <kbd>G</kbd> Guion · <kbd>L</kbd> Trazas HTTP · <kbd>E</kbd> Exportar Markdown
        </div>
        <button class="action-btn emerald" onclick="window.__walletApp.goToSlide(1, false)">► Iniciar Presentación</button>
      </div>
    `;
  }

  function renderSlide01() {
    const info = ARCH_NODES[state.selectedArchNode] || ARCH_NODES.gateway;
    stageEl.innerHTML = `
      <div class="slide-head">
        <div>
          <div class="slide-kicker">BLOQUE 1 · DIAPOSITIVA 01</div>
          <h1 class="slide-title">Arquitectura del Sistema · 8 Contenedores Docker</h1>
          <p class="slide-subtitle">Topología en red <code>wallet-net</code> con aislamiento <em>Database-per-Service</em>. Haz clic en un nodo.</p>
        </div>
        <span class="pill info">C4 CONTENEDORES</span>
      </div>

      <div class="arch-svg-wrap">
        <svg viewBox="0 0 1000 420" class="arch-svg" role="img" aria-label="Diagrama C4 de 8 contenedores">
          <defs>
            <marker id="arrowCyan" markerWidth="8" markerHeight="8" refX="6" refY="4" orient="auto">
              <path d="M0,0 L8,4 L0,8 Z" fill="#22d3ee" />
            </marker>
            <marker id="arrowEmerald" markerWidth="8" markerHeight="8" refX="6" refY="4" orient="auto">
              <path d="M0,0 L8,4 L0,8 Z" fill="#10b981" />
            </marker>
            <marker id="arrowBlue" markerWidth="8" markerHeight="8" refX="6" refY="4" orient="auto">
              <path d="M0,0 L8,4 L0,8 Z" fill="#60a5fa" />
            </marker>
          </defs>

          <!-- Flow lines -->
          <line x1="140" y1="78" x2="365" y2="78" stroke="#22d3ee" stroke-width="2.5" class="flow-line" marker-end="url(#arrowCyan)" />
          <line x1="590" y1="78" x2="725" y2="78" stroke="#a78bfa" stroke-width="2" class="flow-line-slow" />
          <text x="657" y="66" fill="#a78bfa" font-size="11" text-anchor="middle" font-family="monospace">latido 5s</text>

          <!-- lb:// branches -->
          <path d="M475,112 L475,148 L210,148 L210,178" fill="none" stroke="#22d3ee" stroke-width="2.2" class="flow-line" marker-end="url(#arrowCyan)" />
          <path d="M475,112 L475,178" fill="none" stroke="#22d3ee" stroke-width="2.2" class="flow-line" marker-end="url(#arrowCyan)" />
          <path d="M475,112 L475,148 L770,148 L770,178" fill="none" stroke="#22d3ee" stroke-width="2.2" class="flow-line" marker-end="url(#arrowCyan)" />
          <text x="340" y="139" fill="#67e8f9" font-size="12" font-family="monospace" font-weight="bold">lb://ms-cuentas (Round Robin)</text>

          <!-- P2P ms-transacciones -> ms-cuentas -->
          <line x1="655" y1="215" x2="590" y2="215" stroke="#f59e0b" stroke-width="2" stroke-dasharray="5 4" />
          <text x="622" y="205" fill="#fcd34d" font-size="10" text-anchor="middle" font-family="monospace">P2P</text>

          <!-- DB Routing -->
          <path d="M210,252 L210,295 L235,295 L235,318" fill="none" stroke="#10b981" stroke-width="2.2" class="flow-line" marker-end="url(#arrowEmerald)" />
          <path d="M475,252 L475,282 L255,282 L255,318" fill="none" stroke="#10b981" stroke-width="2.2" class="flow-line" marker-end="url(#arrowEmerald)" />
          <path d="M770,252 L770,282 L275,282 L275,318" fill="none" stroke="#10b981" stroke-width="2" class="flow-line" marker-end="url(#arrowEmerald)" />
          <text x="415" y="274" fill="#6ee7b7" font-size="11" font-family="monospace">@UsarNodo: Escritura / RYOW -> Primary | Lecturas -> Réplicas</text>

          <!-- WAL Replication -->
          <line x1="365" y1="358" x2="495" y2="358" stroke="#60a5fa" stroke-width="2.5" class="flow-line" marker-end="url(#arrowBlue)" />
          <path d="M365,374 L440,374 L440,382 L735,382 L735,365" fill="none" stroke="#60a5fa" stroke-width="2" class="flow-line-slow" />
          <text x="430" y="349" fill="#93c5fd" font-size="11" text-anchor="middle" font-family="monospace">WAL</text>

          <!-- Cliente -->
          <rect x="24" y="46" width="115" height="64" rx="12" fill="#0f172a" stroke="#475569" stroke-width="1.5" />
          <text x="81" y="75" fill="#f8fafc" font-size="13" font-weight="bold" text-anchor="middle">Cliente HTTP</text>
          <text x="81" y="95" fill="#94a3b8" font-size="11" text-anchor="middle" font-family="monospace">REST / JSON</text>

          <!-- API Gateway -->
          <g class="svg-node" onclick="window.__walletApp.selectArchNode('gateway')">
            <rect x="370" y="42" width="220" height="70" rx="12" fill="#082f49" stroke="${state.selectedArchNode === 'gateway' ? '#22d3ee' : '#0284c7'}" stroke-width="2.2" />
            <text x="480" y="72" fill="#e0f2fe" font-size="15" font-weight="bold" text-anchor="middle">api-gateway</text>
            <text x="480" y="94" fill="#38bdf8" font-size="12" text-anchor="middle" font-family="monospace">:8080 · Spring Cloud</text>
          </g>

          <!-- Eureka -->
          <g class="svg-node" onclick="window.__walletApp.selectArchNode('eureka')">
            <rect x="730" y="42" width="230" height="70" rx="12" fill="#1e1b4b" stroke="${state.selectedArchNode === 'eureka' ? '#c4b5fd' : '#7c3aed'}" stroke-width="2.2" />
            <text x="845" y="72" fill="#ede9fe" font-size="15" font-weight="bold" text-anchor="middle">eureka-server</text>
            <text x="845" y="94" fill="#a78bfa" font-size="12" text-anchor="middle" font-family="monospace">:8761 · Discovery</text>
          </g>

          <!-- ms-cuentas-1 -->
          <g class="svg-node" onclick="window.__walletApp.selectArchNode('cuentas1')">
            <rect x="95" y="182" width="230" height="70" rx="12" fill="#052e16" stroke="${state.selectedArchNode === 'cuentas1' ? '#34d399' : '#059669'}" stroke-width="2.2" />
            <text x="210" y="212" fill="#dcfce7" font-size="15" font-weight="bold" text-anchor="middle">ms-cuentas-1</text>
            <text x="210" y="234" fill="#34d399" font-size="12" text-anchor="middle" font-family="monospace">:8081 · cuentas_db</text>
          </g>

          <!-- ms-cuentas-2 -->
          <g class="svg-node" onclick="window.__walletApp.selectArchNode('cuentas2')">
            <rect x="360" y="182" width="230" height="70" rx="12" fill="#052e16" stroke="${state.selectedArchNode === 'cuentas2' ? '#34d399' : '#059669'}" stroke-width="2.2" />
            <text x="475" y="212" fill="#dcfce7" font-size="15" font-weight="bold" text-anchor="middle">ms-cuentas-2</text>
            <text x="475" y="234" fill="#34d399" font-size="12" text-anchor="middle" font-family="monospace">:8082 · cuentas_db</text>
          </g>

          <!-- ms-transacciones -->
          <g class="svg-node" onclick="window.__walletApp.selectArchNode('tx')">
            <rect x="655" y="182" width="245" height="70" rx="12" fill="#172554" stroke="${state.selectedArchNode === 'tx' ? '#60a5fa' : '#2563eb'}" stroke-width="2.2" />
            <text x="777" y="212" fill="#dbeafe" font-size="15" font-weight="bold" text-anchor="middle">ms-transacciones</text>
            <text x="777" y="234" fill="#60a5fa" font-size="12" text-anchor="middle" font-family="monospace">:8083 · tx_db</text>
          </g>

          <!-- Primary -->
          <g class="svg-node" onclick="window.__walletApp.selectArchNode('primary')">
            <rect x="115" y="322" width="250" height="72" rx="12" fill="#1e293b" stroke="${state.selectedArchNode === 'primary' ? '#fbbf24' : '#d97706'}" stroke-width="2.2" />
            <text x="240" y="352" fill="#fef3c7" font-size="15" font-weight="bold" text-anchor="middle">postgres-primary</text>
            <text x="240" y="374" fill="#fbbf24" font-size="12" text-anchor="middle" font-family="monospace">:5432 · R/W (RYOW)</text>
          </g>

          <!-- Replica 1 -->
          <g class="svg-node" onclick="window.__walletApp.selectArchNode('replica1')">
            <rect x="500" y="322" width="205" height="72" rx="12" fill="#0f172a" stroke="${state.selectedArchNode === 'replica1' ? '#22d3ee' : '#0284c7'}" stroke-width="2" />
            <text x="602" y="352" fill="#e0f2fe" font-size="14" font-weight="bold" text-anchor="middle">postgres-replica-1</text>
            <text x="602" y="374" fill="#38bdf8" font-size="12" text-anchor="middle" font-family="monospace">:5433 · Read Only</text>
          </g>

          <!-- Replica 2 -->
          <g class="svg-node" onclick="window.__walletApp.selectArchNode('replica2')">
            <rect x="735" y="322" width="205" height="72" rx="12" fill="#0f172a" stroke="${state.selectedArchNode === 'replica2' ? '#22d3ee' : '#0284c7'}" stroke-width="2" />
            <text x="837" y="352" fill="#e0f2fe" font-size="14" font-weight="bold" text-anchor="middle">postgres-replica-2</text>
            <text x="837" y="374" fill="#38bdf8" font-size="12" text-anchor="middle" font-family="monospace">:5434 · Read Only</text>
          </g>
        </svg>
      </div>

      <div class="callout ok">
        <div>
          <strong>${esc(info.title)}</strong>
          <div style="margin-top:3px;color:var(--text-1);">${esc(info.detail)}</div>
        </div>
        <span class="pill info">Click en los nodos</span>
      </div>
    `;
  }

  async function renderSlide02(useCache) {
    if (!useCache || !state.cache.s02) {
      renderLoading('Consultando telemetría de los 8 contenedores (docker compose ps)…');
      const dock = await refreshDock();
      state.cache.s02 = dock;
    }
    const dock = state.cache.s02;
    const healthy = dock.healthyCount || 0;

    stageEl.innerHTML = `
      <div class="slide-head">
        <div>
          <div class="slide-kicker">BLOQUE 1 · DIAPOSITIVA 02</div>
          <h1 class="slide-title">Clúster Docker Compose · Estado de Servicios</h1>
          <p class="slide-subtitle">Telemetría en vivo de los 8 contenedores independientes en <code>wallet-net</code>.</p>
        </div>
        <span class="pill ${healthy === 8 ? 'ok' : healthy > 0 ? 'warn' : 'err'}">${healthy}/8 HEALTHY</span>
      </div>

      <div class="glass-card">
        <div class="card-title-row">
          <span class="card-title">TELEMETRÍA DE CONTENEDORES (docker compose ps)</span>
          <span style="font-family:var(--font-mono);font-size:12px;color:var(--text-2);">${dock.simulated ? 'SIMULADO' : 'DOCKER ENGINE'}</span>
        </div>
        <table class="data-table">
          <thead>
            <tr>
              <th>Contenedor</th>
              <th>Servicio</th>
              <th>Rol</th>
              <th>Estado</th>
              <th>Puertos</th>
            </tr>
          </thead>
          <tbody>
            ${dock.containers.map((c) => {
              const badgeCls = c.state === 'healthy' ? 'ok' : c.state === 'starting' ? 'warn' : 'err';
              return `
                <tr>
                  <td><strong>${esc(c.name)}</strong></td>
                  <td>${esc(c.service)}</td>
                  <td style="font-family:var(--font-sans);color:var(--text-2);">${esc(c.role)}</td>
                  <td><span class="pill ${badgeCls}">${esc(c.rawStatus)}</span></td>
                  <td>${esc(c.ports || `:${c.port}`)}</td>
                </tr>
              `;
            }).join('')}
          </tbody>
        </table>
      </div>
      ${!dock.dockerAvailable && state.mode === 'live' ? offlineBanner(dock.error) : ''}
    `;
  }

  async function renderSlide03(useCache) {
    if (!useCache || !state.cache.s03) {
      renderLoading('Consultando catálogo en vivo desde Eureka (:8761/eureka/apps)…');
      if (state.mode === 'sim') {
        await new Promise((r) => setTimeout(r, 260));
        state.cache.s03 = {
          ok: true, status: '200', durationMs: 18,
          apps: [
            { name: 'API-GATEWAY', instances: [{ instanceId: 'api-gateway:8080', ipAddr: '172.20.0.8', port: 8080, status: 'UP' }] },
            {
              name: 'MS-CUENTAS',
              instances: [
                { instanceId: 'ms-cuentas-1:ms-cuentas:8081', ipAddr: '172.20.0.5', port: 8081, status: 'UP' },
                { instanceId: 'ms-cuentas-2:ms-cuentas:8082', ipAddr: '172.20.0.6', port: 8082, status: 'UP' }
              ]
            },
            { name: 'MS-TRANSACCIONES', instances: [{ instanceId: 'ms-transacciones:8083', ipAddr: '172.20.0.7', port: 8083, status: 'UP' }] }
          ]
        };
        addLocalLog('OK', 'HTTP', 'GET /eureka/apps -> 200 (18ms) [SIM]', 's03', 'HTTP 200 · 3 servicios registrados (Simulado)');
      } else {
        const res = await fetch('/api/eureka');
        state.cache.s03 = await res.json();
      }
    }

    const d = state.cache.s03;
    stageEl.innerHTML = `
      <div class="slide-head">
        <div>
          <div class="slide-kicker">BLOQUE 2 · DIAPOSITIVA 03</div>
          <h1 class="slide-title">Descubrimiento Dinámico con Netflix Eureka</h1>
          <p class="slide-subtitle">Resolución lógica mediante <code>lb://ms-cuentas</code> sin direcciones IP fijas.</p>
        </div>
        <span class="pill ${d.ok ? 'ok' : 'err'}">HTTP ${esc(d.status)} · ${d.durationMs || 0}ms</span>
      </div>

      <div class="grid-2" style="margin-bottom:16px;">
        <div class="glass-card">
          <div class="card-title-row">
            <span class="card-title">¿QUÉ SIGNIFICA <code>lb://ms-cuentas</code>?</span>
            <span class="pill info">HEARTBEAT 5s</span>
          </div>
          <div class="kv-list">
            <div class="kv-item"><span class="kv-k">Prefijo <code>lb://</code></span><span class="kv-v" style="color:var(--cyan);">Load Balanced (Spring Cloud)</span></div>
            <div class="kv-item"><span class="kv-k">Nombre lógico</span><span class="kv-v">ms-cuentas (spring.application.name)</span></div>
            <div class="kv-item"><span class="kv-k">Sin IPs estáticas</span><span class="kv-v" style="color:var(--emerald);">Escala o reemplaza nodos en caliente</span></div>
          </div>
        </div>
        <div class="glass-card">
          <div class="card-title-row">
            <span class="card-title">CICLO DE REGISTRO Y LATIDO</span>
            <span class="pill ok">ACTIVO</span>
          </div>
          <div style="font-size:13.5px;line-height:1.6;color:var(--text-1);">
            1. Cada microservicio se auto-registra en <strong>Eureka :8761</strong> al arrancar.<br/>
            2. Envía un <strong>heartbeat cada 5 segundos</strong> confirmando disponibilidad.<br/>
            3. El <strong>API Gateway</strong> consulta el registro y balancea entre las instancias <code>UP</code>.
          </div>
        </div>
      </div>

      <div class="glass-card">
        <div class="card-title-row">
          <span class="card-title">CATÁLOGO EUREKA EN VIVO (:8761/eureka/apps)</span>
          <button class="action-btn" onclick="window.open('http://localhost:8761','_blank')">↗ Abrir Panel Eureka</button>
        </div>
        ${d.ok && d.apps.length ? `
          <div class="grid-3">
            ${d.apps.map((app) => `
              <div style="padding:14px;border-radius:11px;border:1px solid ${app.name === 'MS-CUENTAS' ? 'rgba(16,185,129,0.45)' : 'var(--border)'};background:rgba(15,23,42,0.72);">
                <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:10px;">
                  <strong style="font-family:var(--font-mono);color:${app.name === 'MS-CUENTAS' ? 'var(--emerald)' : 'var(--cyan)'};">${esc(app.name)}</strong>
                  <span class="pill ok">${app.instances.length} inst</span>
                </div>
                <div style="display:flex;flex-direction:column;gap:6px;">
                  ${app.instances.map((i) => `
                    <div style="font-family:var(--font-mono);font-size:11.5px;padding:7px 9px;border-radius:7px;background:#050811;border:1px solid var(--border);display:flex;justify-content:space-between;gap:8px;">
                      <span style="overflow:hidden;text-overflow:ellipsis;">${esc(i.instanceId)}</span>
                      <span style="color:var(--emerald);font-weight:700;">[${esc(i.status)}]</span>
                    </div>
                  `).join('')}
                </div>
              </div>
            `).join('')}
          </div>
        ` : offlineBanner(d.error || `Eureka devolvió HTTP ${d.status}`)}
      </div>
    `;
  }

  async function renderSlide04(useCache) {
    if (!useCache || !state.cache.s04) {
      renderLoading('Ejecutando ráfaga de 20 peticiones GET /api/cuentas/instancia…');
      if (state.mode === 'sim') {
        await new Promise((r) => setTimeout(r, 420));
        const requests = Array.from({ length: 20 }, (_, i) => ({
          index: i + 1,
          status: '200',
          instance: i % 2 === 0 ? 'ms-cuentas-1:8081' : 'ms-cuentas-2:8082',
          durationMs: 12 + (i % 7)
        }));
        state.cache.s04 = {
          ok: true, okCount: 20, errCount: 0, durationMs: 310,
          distribution: [
            { status: '200', instance: 'ms-cuentas-1:8081', count: 10, pct: 50 },
            { status: '200', instance: 'ms-cuentas-2:8082', count: 10, pct: 50 }
          ],
          requests
        };
        addLocalLog('OK', 'HTTP', '20x GET /instancia -> 20/20 OK (10/10) [SIM]', 's04', '20/20 HTTP 200 (Round Robin 10/10)');
      } else {
        const res = await fetch('/api/demo/balanceo', { method: 'POST' });
        state.cache.s04 = await res.json();
      }
    }

    const d = state.cache.s04;
    stageEl.innerHTML = `
      <div class="slide-head">
        <div>
          <div class="slide-kicker">BLOQUE 2 · DIAPOSITIVA 04</div>
          <h1 class="slide-title">Balanceo de Carga HTTP · Round Robin</h1>
          <p class="slide-subtitle">20 peticiones secuenciales a <code>GET /api/cuentas/instancia</code> midiendo <code>X-Service-Instance</code>.</p>
        </div>
        <span class="pill ${d.ok ? 'ok' : 'err'}">${d.okCount}/20 OK · ${(d.durationMs / 1000).toFixed(2)}s</span>
      </div>

      <div class="glass-card" style="margin-bottom:16px;">
        <div class="card-title-row">
          <span class="card-title">DISTRIBUCIÓN POR INSTANCIA (20 PETICIONES)</span>
          <span class="pill info">CAPA 7 STATELESS</span>
        </div>
        ${d.distribution.map((row) => {
          const cls = row.status !== '200' ? 'err' : row.instance.includes('ms-cuentas-2') ? 'c2' : 'c1';
          return `
            <div class="bar-row">
              <div class="bar-head">
                <span><strong>${esc(row.instance)}</strong> <span class="pill ${row.status === '200' ? 'ok' : 'err'}">HTTP ${esc(row.status)}</span></span>
                <span><strong>${row.count}/20</strong> (${row.pct}%)</span>
              </div>
              <div class="bar-track"><div class="bar-fill ${cls}" style="width:${row.pct}%"></div></div>
            </div>
          `;
        }).join('')}
      </div>

      <div class="glass-card">
        <div class="card-title-row">
          <span class="card-title">TRAZA DE LAS 20 PETICIONES CONSECUTIVAS</span>
          <span style="font-size:12px;color:var(--text-2);">Alternancia 100% stateless</span>
        </div>
        <div class="req-matrix">
          ${d.requests.map((r, i) => {
            const cls = r.status !== '200' ? 'err' : r.instance.includes('ms-cuentas-2') ? 'c2' : 'c1';
            const lbl = r.status !== '200' ? `ERR ${r.status}` : r.instance.includes('ms-cuentas-2') ? ':8082' : ':8081';
            return `<div class="req-cell ${cls}" style="animation-delay:${i * 18}ms">#${r.index}<br/>${esc(lbl)}</div>`;
          }).join('')}
        </div>
      </div>
      ${d.okCount === 0 && state.mode === 'live' ? offlineBanner('Gateway :8080 no respondió a la ráfaga.') : ''}
    `;
  }

  async function renderSlide05(useCache) {
    if (!useCache || !state.cache.s05) {
      renderLoading('Ejecutando transferencia P2P de $25.00 vía Gateway -> ms-transacciones -> ms-cuentas…');
      if (state.mode === 'sim') {
        await new Promise((r) => setTimeout(r, 380));
        state.cache.s05 = {
          status: '201', durationMs: 84,
          mensaje: 'Transferencia P2P ejecutada con éxito',
          codigoComprobante: 'TX-2026-849201',
          nuevoSaldoOrigen: 975.00,
          instanciaCuentasConsultada: 'ms-cuentas-1 (172.20.0.5:8081)',
          nodoBaseDatos: 'PRIMARY (recovery=false)',
          politicaEnrutamiento: 'ESCRITURA_FORZADA_PRIMARIO',
          raw: {
            mensaje: 'Transferencia P2P ejecutada con éxito',
            datos: { codigoComprobante: 'TX-2026-849201', monto: 25.0, nuevoSaldoOrigen: 975.0 },
            auditoriaTecnica: {
              instanciaCuentasConsultada: 'ms-cuentas-1 (172.20.0.5:8081)',
              nodoBaseDatos: 'PRIMARY (recovery=false)',
              politicaEnrutamiento: 'ESCRITURA_FORZADA_PRIMARIO'
            }
          }
        };
        addLocalLog('OK', 'HTTP', 'POST /api/transacciones/transferir ($25) -> 201 [SIM]', 's05', 'HTTP 201 · TX-2026-849201 · PRIMARY');
      } else {
        const res = await fetch('/api/demo/transferencia', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ monto: 25, motivo: 'Transferencia P2P' })
        });
        state.cache.s05 = await res.json();
      }
    }

    const d = state.cache.s05;
    const isOk = d.status === '201' || d.status === '200';
    stageEl.innerHTML = `
      <div class="slide-head">
        <div>
          <div class="slide-kicker">BLOQUE 3 · DIAPOSITIVA 05</div>
          <h1 class="slide-title">Orquestación P2P entre Microservicios · ACID</h1>
          <p class="slide-subtitle"><code>POST :8080</code> → <code>ms-transacciones</code> → Eureka → <code>ms-cuentas</code> → <strong>PRIMARY</strong>.</p>
        </div>
        <span class="pill ${isOk ? 'ok' : 'err'}">HTTP ${esc(d.status)} · ${d.durationMs}ms</span>
      </div>

      <div class="grid-2">
        <div class="glass-card">
          <div class="card-title-row">
            <span class="card-title">COMPROBANTE Y AUDITORÍA TÉCNICA</span>
            <span class="pill ${isOk ? 'ok' : 'warn'}">$25.00 USD</span>
          </div>
          <div class="kv-list">
            <div class="kv-item"><span class="kv-k">Estado / Mensaje</span><span class="kv-v" style="color:var(--emerald);">${esc(d.mensaje)}</span></div>
            <div class="kv-item"><span class="kv-k">Código Comprobante</span><span class="kv-v">${esc(d.codigoComprobante)}</span></div>
            <div class="kv-item"><span class="kv-k">Nuevo Saldo Origen (${ORIGEN})</span><span class="kv-v">${d.nuevoSaldoOrigen !== null ? `$${Number(d.nuevoSaldoOrigen).toFixed(2)}` : '-'}</span></div>
            <div class="kv-item"><span class="kv-k">Instancia Cuentas (Eureka)</span><span class="kv-v" style="color:var(--cyan);">${esc(d.instanciaCuentasConsultada)}</span></div>
            <div class="kv-item"><span class="kv-k">Nodo Base de Datos</span><span class="kv-v" style="color:var(--amber);">${esc(d.nodoBaseDatos)}</span></div>
            <div class="kv-item"><span class="kv-k">Política Enrutamiento</span><span class="kv-v">${esc(d.politicaEnrutamiento)}</span></div>
          </div>
        </div>

        <div class="glass-card">
          <div class="card-title-row">
            <span class="card-title">GARANTÍA ACID & PREVENCIÓN DE DEADLOCKS</span>
            <span class="pill info">LOCK ORDENADO</span>
          </div>
          <div style="font-size:13.5px;line-height:1.6;color:var(--text-1);margin-bottom:12px;">
            • Débito y crédito ocurren en una sola transacción <code>@Transactional</code>.<br/>
            • Bloqueo pesimista <code>SELECT ... FOR UPDATE</code> ordenado por <code>id</code> numérico ascendente.<br/>
            • Cero acceso directo entre esquemas: <code>ms-transacciones</code> audita en <code>tx_db</code>.
          </div>
          <div class="card-title" style="margin-bottom:6px;">RESPUESTA JSON CRUDA</div>
          <pre class="code-block">${esc(typeof d.raw === 'string' ? d.raw : JSON.stringify(d.raw, null, 2))}</pre>
        </div>
      </div>
      ${d.status === '000' && state.mode === 'live' ? offlineBanner('No se pudo conectar con Gateway :8080.') : ''}
    `;
  }

  async function renderSlide06(useCache) {
    if (!useCache || !state.cache.s06) {
      renderLoading('Probando validación de saldo insuficiente ($9999.00 > saldo)…');
      if (state.mode === 'sim') {
        await new Promise((r) => setTimeout(r, 320));
        state.cache.s06 = {
          status: '409', durationMs: 49,
          mensaje: 'Saldo insuficiente para realizar la transferencia',
          codigoComprobante: 'TX-2026-849202-REJ',
          nodoBaseDatos: 'PRIMARY (recovery=false)',
          raw: {
            mensaje: 'Saldo insuficiente para realizar la transferencia',
            estadoComprobante: 'RECHAZADA',
            auditoriaTecnica: { nodoBaseDatos: 'PRIMARY (recovery=false)' }
          }
        };
        addLocalLog('WARN', 'HTTP', 'POST /api/transacciones/transferir ($9999) -> 409 [SIM]', 's06', 'HTTP 409 · Saldo insuficiente (Rollback ACID)');
      } else {
        const res = await fetch('/api/demo/transferencia', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ monto: 9999, motivo: 'Prueba limite' })
        });
        state.cache.s06 = await res.json();
      }
    }

    const d = state.cache.s06;
    const is409 = d.status === '409';
    stageEl.innerHTML = `
      <div class="slide-head">
        <div>
          <div class="slide-kicker">BLOQUE 3 · DIAPOSITIVA 06</div>
          <h1 class="slide-title">Validación de Reglas de Negocio · Error Controlado</h1>
          <p class="slide-subtitle">Intento de transferencia por <strong>$9,999.00</strong> excediendo saldo disponible.</p>
        </div>
        <span class="pill ${is409 ? 'warn' : 'err'}">HTTP ${esc(d.status)} CONFLICT</span>
      </div>

      <div class="grid-2">
        <div class="glass-card" style="border-color:rgba(245,158,11,0.4);">
          <div class="card-title-row">
            <span class="card-title">RECHAZO CONTROLADO DE NEGOCIO</span>
            <span class="pill warn">ROLLBACK ACID</span>
          </div>
          <div class="kv-list">
            <div class="kv-item"><span class="kv-k">Código HTTP</span><span class="kv-v" style="color:var(--amber);">HTTP ${esc(d.status)}</span></div>
            <div class="kv-item"><span class="kv-k">Mensaje devuelto</span><span class="kv-v">${esc(d.mensaje)}</span></div>
            <div class="kv-item"><span class="kv-k">Integridad cuentas_db</span><span class="kv-v" style="color:var(--emerald);">Transacción revertida; saldos intactos</span></div>
            <div class="kv-item"><span class="kv-k">Auditoría en tx_db</span><span class="kv-v">Comprobante registrado como RECHAZADA</span></div>
            <div class="kv-item"><span class="kv-k">Nodo Base de Datos</span><span class="kv-v">${esc(d.nodoBaseDatos)}</span></div>
          </div>
        </div>

        <div class="glass-card">
          <div class="card-title-row">
            <span class="card-title">EVIDENCIA JSON DEL RECHAZO</span>
            <span class="pill info">TRAZABILIDAD</span>
          </div>
          <pre class="code-block" style="max-height:260px;">${esc(typeof d.raw === 'string' ? d.raw : JSON.stringify(d.raw, null, 2))}</pre>
        </div>
      </div>
      ${d.status === '000' && state.mode === 'live' ? offlineBanner('Gateway :8080 sin respuesta.') : ''}
    `;
  }

  async function renderSlide07(useCache) {
    if (!useCache || !state.cache.s07) {
      renderLoading('Ejecutando 20 lecturas ordinarias (contactos + historial) hacia réplicas PostgreSQL…');
      if (state.mode === 'sim') {
        await new Promise((r) => setTimeout(r, 450));
        state.cache.s07 = {
          ok: true, okCount: 20, errCount: 0, fallbackCount: 0, durationMs: 390,
          distribution: [
            { status: '200', node: 'REPLICA_1 (recovery=true)', fallback: false, count: 10, pct: 50 },
            { status: '200', node: 'REPLICA_2 (recovery=true)', fallback: false, count: 10, pct: 50 }
          ]
        };
        addLocalLog('OK', 'HTTP', '20x lecturas R1/R2 -> 20/20 OK fb=0 [SIM]', 's07', '20/20 HTTP 200 (10 R1 + 10 R2)');
      } else {
        const res = await fetch('/api/demo/lecturas', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ stopReplica1: false, tag: '07' })
        });
        state.cache.s07 = await res.json();
      }
    }

    const d = state.cache.s07;
    stageEl.innerHTML = `
      <div class="slide-head">
        <div>
          <div class="slide-kicker">BLOQUE 4 · DIAPOSITIVA 07</div>
          <h1 class="slide-title">Enrutamiento BD · Primario vs Réplicas WAL</h1>
          <p class="slide-subtitle">20 lecturas ordinarias (<code>/contactos</code> + <code>/historial</code>) desviadas mediante <code>@UsarNodo</code>.</p>
        </div>
        <span class="pill ${d.ok ? 'ok' : 'err'}">${d.okCount}/20 OK · ${(d.durationMs / 1000).toFixed(2)}s</span>
      </div>

      <div class="glass-card">
        <div class="card-title-row">
          <span class="card-title">DISTRIBUCIÓN DE LECTURAS POR NODO POSTGRESQL</span>
          <span class="pill info">X-Db-Node · recovery=true</span>
        </div>
        ${d.distribution.map((row) => {
          const isR2 = row.node.includes('REPLICA_2');
          const cls = row.status !== '200' ? 'err' : isR2 ? 'c2' : 'c1';
          return `
            <div class="bar-row">
              <div class="bar-head">
                <span>
                  <strong>${esc(row.node)}</strong>
                  <span class="pill ${row.status === '200' ? 'ok' : 'err'}">HTTP ${esc(row.status)}</span>
                  <span class="pill ${row.fallback ? 'warn' : 'info'}">fallback=${row.fallback}</span>
                </span>
                <span><strong>${row.count}/20</strong> (${row.pct}%)</span>
              </div>
              <div class="bar-track"><div class="bar-fill ${cls}" style="width:${row.pct}%"></div></div>
            </div>
          `;
        }).join('')}
      </div>

      <div class="callout ok">
        <span><strong>Resultado:</strong> El nodo <code>PRIMARY</code> queda libre de consultas masivas mientras <code>REPLICA_1</code> y <code>REPLICA_2</code> absorben el 100% de las lecturas ordinarias.</span>
        <span class="pill ok">Fallback: ${d.fallbackCount}</span>
      </div>
      ${d.okCount === 0 && state.mode === 'live' ? offlineBanner('Sin respuesta del Gateway.') : ''}
    `;
  }

  async function renderSlide08(useCache) {
    if (!useCache || !state.cache.s08) {
      renderLoading('Consultando /api/cuentas/' + ORIGEN + '/saldo-critico directo al PRIMARIO…');
      if (state.mode === 'sim') {
        await new Promise((r) => setTimeout(r, 260));
        state.cache.s08 = {
          ok: true, status: '200', durationMs: 28,
          saldo: 975.00, consumidoHoy: 25.00, limiteDiario: 500.00,
          nodoBaseDatos: 'PRIMARY (recovery=false)',
          politicaEnrutamiento: 'READ_YOUR_OWN_WRITES_PRIMARY',
          raw: {
            datos: { celular: ORIGEN, saldo: 975.00, consumidoHoy: 25.00, limiteDiario: 500.00 },
            auditoriaTecnica: { nodoBaseDatos: 'PRIMARY (recovery=false)', politicaEnrutamiento: 'READ_YOUR_OWN_WRITES_PRIMARY' }
          }
        };
        addLocalLog('OK', 'HTTP', 'GET /saldo-critico -> 200 PRIMARY [SIM]', 's08', 'HTTP 200 · PRIMARY (RYOW)');
      } else {
        const res = await fetch('/api/demo/saldo-critico');
        state.cache.s08 = await res.json();
      }
    }

    const d = state.cache.s08;
    stageEl.innerHTML = `
      <div class="slide-head">
        <div>
          <div class="slide-kicker">BLOQUE 4 · DIAPOSITIVA 08</div>
          <h1 class="slide-title">Consistencia Inmediata · Read-Your-Own-Writes (RYOW)</h1>
          <p class="slide-subtitle">Mitigación del lag de replicación WAL forzando lectura en <code>PRIMARY</code> tras escribir.</p>
        </div>
        <span class="pill ${d.ok ? 'ok' : 'err'}">HTTP ${esc(d.status)} · ${d.durationMs}ms</span>
      </div>

      <div class="grid-2">
        <div class="glass-card">
          <div class="card-title-row">
            <span class="card-title">POLÍTICA RYOW EN VIVO</span>
            <span class="pill ok">CONSISTENCIA FUERTE</span>
          </div>
          <div class="kv-list">
            <div class="kv-item"><span class="kv-k">Endpoint crítico</span><span class="kv-v">/api/cuentas/${ORIGEN}/saldo-critico</span></div>
            <div class="kv-item"><span class="kv-k">Saldo Inmediato</span><span class="kv-v" style="color:var(--emerald);font-size:16px;">${d.saldo !== null ? `$${Number(d.saldo).toFixed(2)}` : '-'}</span></div>
            <div class="kv-item"><span class="kv-k">Nodo Base de Datos</span><span class="kv-v" style="color:var(--cyan);">${esc(d.nodoBaseDatos)}</span></div>
            <div class="kv-item"><span class="kv-k">Política Enrutamiento</span><span class="kv-v" style="color:var(--amber);">${esc(d.politicaEnrutamiento)}</span></div>
          </div>
        </div>

        <div class="glass-card">
          <div class="card-title-row">
            <span class="card-title">¿POR QUÉ ES NECESARIO RYOW?</span>
            <span class="pill warn">WAL ASÍNCRONO</span>
          </div>
          <div style="font-size:13.5px;line-height:1.6;color:var(--text-1);margin-bottom:12px;">
            1. El usuario transfiere $25 en <strong>PRIMARY</strong>.<br/>
            2. La réplica WAL puede tardar unos milisegundos en aplicar el cambio.<br/>
            3. Si consultara el saldo en una réplica, vería el saldo viejo.<br/>
            4. <code>/saldo-critico</code> fuerza <code>PRIMARY</code> y evita lecturas obsoletas.
          </div>
          <pre class="code-block">${esc(typeof d.raw === 'string' ? d.raw : JSON.stringify(d.raw, null, 2))}</pre>
        </div>
      </div>
      ${!d.ok && state.mode === 'live' ? offlineBanner('No se pudo consultar /saldo-critico.') : ''}
    `;
  }

  // ==================== SLIDE 09 LIVE HA TELEMETRY ====================

  function startSlide09(useCache) {
    if (useCache && state.s9.total > 0 && state.s9.phase === 4) {
      renderSlide09View();
      return;
    }

    stopSlide09Loop();
    const s9 = state.s9;
    s9.active = true;
    s9.phase = 1;
    s9.inFlight = false;
    s9.total = 0;
    s9.ok = 0;
    s9.err = 0;
    s9.c1 = 0;
    s9.c2 = 0;
    s9.ring = [];
    s9.points = [];
    s9.stopAtMs = 0;
    s9.startAtMs = 0;
    s9.detectMs = -1;
    s9.rejoinMs = -1;
    s9.consecC1 = 0;
    s9.streakMs = 0;
    s9.eventMsg = 'Tráfico activo 50/50 entre ms-cuentas-1 y ms-cuentas-2';

    addLocalLog('INFO', 'FAIL', 'Iniciada telemetría en vivo Slide 09 (:8080)');
    renderSlide09View();

    s9.timer = setInterval(tickSlide09, 360);
    tickSlide09();
  }

  async function tickSlide09() {
    const s9 = state.s9;
    if (!s9.active || s9.phase === 4 || s9.inFlight || state.currentSlide !== 9) return;
    s9.inFlight = true;

    let res;
    const nowMs = Date.now();

    if (state.mode === 'sim') {
      const elapsedAfterStart = s9.startAtMs ? nowMs - s9.startAtMs : 0;
      const c2Up = s9.phase === 1 || (s9.phase === 3 && elapsedAfterStart >= 3600);
      const chooseC2 = c2Up && (s9.total % 2 === 1);
      res = {
        status: '200',
        instance: chooseC2 ? 'ms-cuentas-2:8082' : 'ms-cuentas-1:8081',
        durationMs: 14 + (s9.total % 9),
        time: new Date().toTimeString().slice(0, 8)
      };
    } else {
      try {
        const r = await fetch('/api/demo/ping-cuenta', { method: 'POST' });
        res = await r.json();
      } catch {
        res = { status: '000', instance: 'sin-conexion', durationMs: 0, time: new Date().toTimeString().slice(0, 8) };
      }
    }

    s9.inFlight = false;
    if (!s9.active || state.currentSlide !== 9) return;

    s9.total += 1;
    let kind = 'c1';
    if (res.status !== '200') {
      s9.err += 1;
      kind = 'err';
      s9.consecC1 = 0;
      s9.streakMs = 0;
    } else if (String(res.instance).includes('ms-cuentas-2')) {
      s9.ok += 1;
      s9.c2 += 1;
      kind = 'c2';
      s9.consecC1 = 0;
      s9.streakMs = 0;
      if (s9.phase === 3 && s9.rejoinMs < 0 && s9.startAtMs > 0) {
        s9.rejoinMs = nowMs - s9.startAtMs;
        if (state.mode === 'sim') {
          state.simDown['ms-cuentas-2'] = false;
          refreshDock();
        }
        const rsec = `${(s9.rejoinMs / 1000).toFixed(2)}s`;
        s9.eventMsg = `[EVENTO] ms-cuentas-2 reincorporada en ${rsec}!`;
        addLocalLog('OK', 'FAIL', `Reincorporada ms-cuentas-2 (${rsec})`);
      }
    } else {
      s9.ok += 1;
      s9.c1 += 1;
      kind = 'c1';
      if (s9.phase >= 2 && s9.detectMs < 0 && s9.stopAtMs > 0) {
        if (s9.consecC1 === 0) s9.streakMs = nowMs;
        s9.consecC1 += 1;
        if (s9.consecC1 >= 3) {
          s9.detectMs = Math.max(0, s9.streakMs - s9.stopAtMs);
          const dsec = `${(s9.detectMs / 1000).toFixed(2)}s`;
          s9.eventMsg = `[EVENTO] Convergencia exclusiva a ms-cuentas-1 (${dsec})`;
          addLocalLog('OK', 'FAIL', `Convergencia a ms-cuentas-1 (${dsec})`);
        }
      }
    }

    s9.ring.unshift({ time: res.time, status: res.status, instance: res.instance, durationMs: res.durationMs, kind });
    if (s9.ring.length > 7) s9.ring.pop();

    s9.points.push(kind);
    if (s9.points.length > 44) s9.points.shift();

    renderSlide09View();
  }

  async function advanceSlide09Phase() {
    const s9 = state.s9;
    if (s9.phase === 1) {
      s9.phase = 2;
      s9.stopAtMs = Date.now();
      s9.consecC1 = 0;
      s9.streakMs = 0;
      s9.eventMsg = '[ACCIÓN] Deteniendo ms-cuentas-2 (docker compose stop)…';
      addLocalLog('WARN', 'FAIL', 'docker compose stop ms-cuentas-2');
      renderChrome();
      renderSlide09View();

      if (state.mode === 'sim') {
        state.simDown['ms-cuentas-2'] = true;
        refreshDock();
      } else {
        fetch('/api/docker/action', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ action: 'stop-cuentas-2' })
        }).then(() => refreshDock()).catch(() => {});
      }
    } else if (s9.phase === 2) {
      s9.phase = 3;
      s9.startAtMs = Date.now();
      s9.eventMsg = '[ACCIÓN] Reiniciando ms-cuentas-2 (esperando calentamiento JVM)…';
      addLocalLog('INFO', 'FAIL', 'docker compose start ms-cuentas-2');
      renderChrome();
      renderSlide09View();

      if (state.mode === 'live') {
        fetch('/api/docker/action', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ action: 'start-cuentas-2' })
        }).then(() => refreshDock()).catch(() => {});
      }
    } else if (s9.phase === 3) {
      s9.phase = 4;
      stopSlide09Loop();
      const detStr = s9.detectMs >= 0 ? `${(s9.detectMs / 1000).toFixed(2)}s` : 'inmediata';
      const rejStr = s9.rejoinMs >= 0 ? `${(s9.rejoinMs / 1000).toFixed(2)}s` : '~25s JVM';
      addLocalLog(s9.err === 0 ? 'OK' : 'WARN', 'FAIL', `Resumen S09: ${s9.total} req, ${s9.err} err, det=${detStr}`, 's09',
        `${s9.total} req (${s9.err} err) · c1=${s9.c1}, c2=${s9.c2} · det=${detStr}, retorno=${rejStr}`);
      renderChrome();
      renderSlide09View();
    }
  }

  function renderSlide09View() {
    const s9 = state.s9;
    const phaseBannerText = s9.phase === 1
      ? 'FASE 1 · Tráfico activo (ms-cuentas-1 + ms-cuentas-2)'
      : s9.phase === 2
        ? 'FASE 2 · ms-cuentas-2 DETENIDA · Midiendo convergencia'
        : s9.phase === 3
          ? 'FASE 3 · Recuperando ms-cuentas-2 (calentamiento JVM)'
          : 'RESUMEN · Prueba de Alta Disponibilidad HTTP completada';

    const btnText = s9.phase === 1
      ? '⚡ Detener ms-cuentas-2'
      : s9.phase === 2
        ? '▶ Reiniciar ms-cuentas-2'
        : '📊 Ver Resumen Final';

    const detStr = s9.detectMs >= 0 ? `${(s9.detectMs / 1000).toFixed(2)}s` : (s9.phase >= 2 ? 'midiéndose…' : '-');
    const rejStr = s9.rejoinMs >= 0 ? `${(s9.rejoinMs / 1000).toFixed(2)}s` : (s9.phase >= 3 ? 'esperando…' : '-');

    stageEl.innerHTML = `
      <div class="slide-head">
        <div>
          <div class="slide-kicker">BLOQUE 5 · DIAPOSITIVA 09</div>
          <h1 class="slide-title">Alta Disponibilidad HTTP · Caída ms-cuentas-2</h1>
          <p class="slide-subtitle">Ráfaga continua contra Gateway <code>:8080</code> mientras derribamos y levantamos una instancia.</p>
        </div>
        <span class="pill ${s9.err === 0 ? 'ok' : 'warn'}">${s9.err} ERRORES 5xx</span>
      </div>

      ${s9.phase < 4 ? `
        <div class="phase-banner ${s9.phase === 1 ? 'ok' : ''}">
          <div>
            <strong>${esc(phaseBannerText)}</strong>
            <div style="font-size:12px;color:var(--text-1);margin-top:2px;">${esc(s9.eventMsg)}</div>
          </div>
          <button class="action-btn ${s9.phase === 1 ? 'rose' : s9.phase === 2 ? 'emerald' : ''}" onclick="window.__walletApp.advanceSlide09Phase()">
            ${btnText}
          </button>
        </div>
      ` : ''}

      <div class="kpi-strip">
        <div class="kpi-box"><div class="kpi-lbl">Total Peticiones</div><div class="kpi-val">${s9.total}</div></div>
        <div class="kpi-box"><div class="kpi-lbl">ms-cuentas-1</div><div class="kpi-val" style="color:var(--emerald);">${s9.c1}</div></div>
        <div class="kpi-box"><div class="kpi-lbl">ms-cuentas-2</div><div class="kpi-val" style="color:var(--cyan);">${s9.c2}</div></div>
        <div class="kpi-box"><div class="kpi-lbl">Errores HTTP</div><div class="kpi-val" style="color:${s9.err === 0 ? 'var(--emerald)' : 'var(--rose)'};">${s9.err}</div></div>
        <div class="kpi-box"><div class="kpi-lbl">Detección / Retorno</div><div class="kpi-val" style="font-size:15px;margin-top:8px;color:var(--amber);">${esc(detStr)} / ${esc(rejStr)}</div></div>
      </div>

      ${s9.phase === 4 ? `
        <div class="glass-card">
          <div class="card-title-row">
            <span class="card-title">RESUMEN DE FALLO Y CONVERGENCIA</span>
            <span class="pill ok">COMPLETADO</span>
          </div>
          <div class="kv-list">
            <div class="kv-item"><span class="kv-k">Total / Exitosas (200) / Errores</span><span class="kv-v">${s9.total} total · ${s9.ok} OK · ${s9.err} errores</span></div>
            <div class="kv-item"><span class="kv-k">Distribución observada</span><span class="kv-v">ms-cuentas-1 = ${s9.c1} | ms-cuentas-2 = ${s9.c2}</span></div>
            <div class="kv-item"><span class="kv-k">Detección / Retorno JVM</span><span class="kv-v" style="color:var(--cyan);">${esc(detStr)} · ${esc(rejStr)}</span></div>
            <div class="kv-item"><span class="kv-k">Limitación conocida</span><span class="kv-v" style="color:var(--amber);">Gateway reintenta GET idempotentes (no POST /transferir)</span></div>
          </div>
        </div>
      ` : `
        <div class="grid-2">
          <div class="glass-card">
            <div class="card-title-row">
              <span class="card-title">LÍNEA DE TIEMPO EN VIVO (ÚLTIMAS 44)</span>
              <span style="font-size:11px;color:var(--text-2);">🟢 cta-1 · 🔵 cta-2 · 🔴 error</span>
            </div>
            <div style="display:flex;align-items:flex-end;gap:4px;height:130px;padding:12px 6px;background:#050811;border-radius:10px;border:1px solid var(--border);">
              ${s9.points.map((pt) => {
                const bg = pt === 'c1' ? 'var(--emerald)' : pt === 'c2' ? 'var(--cyan)' : 'var(--rose)';
                const h = pt === 'c1' ? '72%' : pt === 'c2' ? '96%' : '45%';
                return `<div style="flex:1;min-width:4px;height:${h};background:${bg};border-radius:3px;"></div>`;
              }).join('')}
            </div>
          </div>

          <div class="glass-card">
            <div class="card-title-row">
              <span class="card-title">ÚLTIMAS PETICIONES</span>
              <span class="spinner"></span>
            </div>
            <div class="stream-list">
              ${s9.ring.map((r) => `
                <div class="stream-row ${r.kind}">
                  <span>[${esc(r.time)}] HTTP ${esc(r.status)}</span>
                  <span>→ ${esc(r.instance)} (${r.durationMs}ms)</span>
                </div>
              `).join('')}
            </div>
          </div>
        </div>
      `}
    `;
  }

  function renderSlide10() {
    stageEl.innerHTML = `
      <div class="slide-head">
        <div>
          <div class="slide-kicker">BLOQUE 5 · DIAPOSITIVA 10</div>
          <h1 class="slide-title">Alta Disponibilidad BD · Caída de Réplica PostgreSQL</h1>
          <p class="slide-subtitle">Preparación para el failover en caliente sobre la capa de persistencia replicada.</p>
        </div>
        <span class="pill warn">PRUEBA EN VIVO SIGUIENTE</span>
      </div>

      <div class="grid-2">
        <div class="glass-card">
          <div class="card-title-row">
            <span class="card-title">MECANISMO DE FAILOVER DE LECTURA</span>
            <span class="pill info">@UsarNodo + HEALTH TRACKER</span>
          </div>
          <div class="kv-list">
            <div class="kv-item"><span class="kv-k">Objetivo</span><span class="kv-v">Continuidad de lecturas si cae replica1</span></div>
            <div class="kv-item"><span class="kv-k">Interceptor @UsarNodo</span><span class="kv-v">Captura fallo SQL y reintenta en réplica sana</span></div>
            <div class="kv-item"><span class="kv-k">Cabecera de auditoría</span><span class="kv-v" style="color:var(--amber);">X-Db-Fallback: true</span></div>
            <div class="kv-item"><span class="kv-k">ReplicaHealthTracker</span><span class="kv-v">Sondea pg_is_in_recovery() cada 3s</span></div>
          </div>
        </div>

        <div class="glass-card" style="border-color:rgba(245,158,11,0.45);">
          <div class="card-title-row">
            <span class="card-title">PREVENCIÓN · ACCIÓN AL AVANZAR</span>
            <span class="pill warn">CUIDADO EN VIVO</span>
          </div>
          <p style="font-size:14px;line-height:1.65;color:var(--text-1);">
            Al pulsar <kbd>Espacio</kbd> o <strong>Ejecutar</strong> hacia la Slide 11, el sistema ejecutará:
          </p>
          <pre class="code-block" style="margin:12px 0;">docker compose stop replica1
+ ráfaga de 20 lecturas ordinarias (contactos + historial)</pre>
          <p style="font-size:13px;color:var(--amber);">
            Observa cómo el dock superior marcará <strong>PG-Rep1</strong> en rojo mientras todas las respuestas HTTP siguen siendo <code>200 OK</code> en <strong>REPLICA_2</strong>.
          </p>
        </div>
      </div>
    `;
  }

  async function renderSlide11(useCache) {
    if (!useCache || !state.cache.s11) {
      renderLoading('Deteniendo replica1 y ejecutando 20 lecturas con failover automático…');
      if (state.mode === 'sim') {
        state.simDown['replica1'] = true;
        await refreshDock();
        await new Promise((r) => setTimeout(r, 520));
        state.cache.s11 = {
          ok: true, okCount: 20, errCount: 0, fallbackCount: 2, durationMs: 430,
          stoppedReplica1: true,
          distribution: [
            { status: '200', node: 'REPLICA_2 (recovery=true)', fallback: true, count: 2, pct: 10 },
            { status: '200', node: 'REPLICA_2 (recovery=true)', fallback: false, count: 18, pct: 90 }
          ]
        };
        addLocalLog('WARN', 'FAIL', 'docker compose stop replica1 [SIM]');
        addLocalLog('OK', 'FAIL', 'Failover 20x -> 20/20 OK (0 err) fb=2 [SIM]', 's11', '20/20 HTTP 200 en REPLICA_2 (fallback=2)');
      } else {
        const res = await fetch('/api/demo/lecturas', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ stopReplica1: true, tag: '11' })
        });
        state.cache.s11 = await res.json();
        refreshDock();
      }
    }

    const d = state.cache.s11;
    stageEl.innerHTML = `
      <div class="slide-head">
        <div>
          <div class="slide-kicker">BLOQUE 5 · DIAPOSITIVA 11</div>
          <h1 class="slide-title">Failover Transparente · Lecturas sobre REPLICA_2</h1>
          <p class="slide-subtitle"><code>$ docker compose stop replica1</code> seguido de 20 consultas ordinarias sin errores.</p>
        </div>
        <span class="pill ${d.ok ? 'ok' : 'warn'}">${d.okCount}/20 OK · Fallback=${d.fallbackCount}</span>
      </div>

      <div class="glass-card">
        <div class="card-title-row">
          <span class="card-title">20 LECTURAS TRAS CAÍDA DE REPLICA_1</span>
          <span class="pill ok">${(d.durationMs / 1000).toFixed(2)}s</span>
        </div>
        ${d.distribution.map((row) => `
          <div class="bar-row">
            <div class="bar-head">
              <span>
                <strong>${esc(row.node)}</strong>
                <span class="pill ${row.status === '200' ? 'ok' : 'err'}">HTTP ${esc(row.status)}</span>
                <span class="pill ${row.fallback ? 'warn' : 'info'}">X-Db-Fallback: ${row.fallback}</span>
              </span>
              <span><strong>${row.count}/20</strong> (${row.pct}%)</span>
            </div>
            <div class="bar-track"><div class="bar-fill ${row.status === '200' ? 'c2' : 'err'}" style="width:${row.pct}%"></div></div>
          </div>
        `).join('')}
      </div>

      <div class="callout ok">
        <span><strong>Tolerancia verificada:</strong> Pese a perder el 50% del clúster de lectura en caliente, <code>@UsarNodo</code> redirigió las peticiones a <code>REPLICA_2</code> con <strong>${d.errCount} errores</strong>.</span>
      </div>
    `;
  }

  async function renderSlide12(useCache) {
    if (!useCache || !state.cache.s12) {
      renderLoading('Consultando estado de salud de réplicas (/api/cuentas/db/estado)…');
      if (state.mode === 'sim') {
        await new Promise((r) => setTimeout(r, 250));
        state.cache.s12 = {
          ok: true, status: '200', durationMs: 22,
          servicio: 'ms-cuentas-1:8081',
          consultasTotales: { PRIMARY: 3, REPLICA_1: 10, REPLICA_2: 30 },
          replicas: [
            { nodo: 'REPLICA_1', available: false, consecutiveSuccesses: 0, lastReplayLsn: '0/1A04F10' },
            { nodo: 'REPLICA_2', available: true, consecutiveSuccesses: 18, lastReplayLsn: '0/1A08C40' }
          ]
        };
        addLocalLog('OK', 'HTTP', 'GET /db/estado -> 200 (REPLICA_1=false) [SIM]', 's12', 'HTTP 200 · REPLICA_1 available=false');
      } else {
        const res = await fetch('/api/demo/db-estado');
        state.cache.s12 = await res.json();
      }
    }

    const d = state.cache.s12;
    const ct = d.consultasTotales || {};
    stageEl.innerHTML = `
      <div class="slide-head">
        <div>
          <div class="slide-kicker">BLOQUE 5 · DIAPOSITIVA 12</div>
          <h1 class="slide-title">Detección Automática · Sondeo cada 3s</h1>
          <p class="slide-subtitle"><code>ReplicaHealthTracker</code> retira del pool a <code>REPLICA_1</code> al fallar <code>pg_is_in_recovery()</code>.</p>
        </div>
        <span class="pill ${d.ok ? 'ok' : 'err'}">HTTP ${esc(d.status)}</span>
      </div>

      <div class="grid-2" style="margin-bottom:14px;">
        ${(d.replicas || []).map((rep) => `
          <div class="glass-card" style="border-color:${rep.available ? 'rgba(16,185,129,0.45)' : 'rgba(244,63,94,0.5)'};">
            <div class="card-title-row">
              <strong style="font-family:var(--font-mono);font-size:17px;">${esc(rep.nodo)}</strong>
              <span class="pill ${rep.available ? 'ok' : 'err'}">${rep.available ? '● ACTIVA · available=true' : '✗ CAÍDA · available=false'}</span>
            </div>
            <div class="kv-list">
              <div class="kv-item"><span class="kv-k">Éxitos consecutivos</span><span class="kv-v">${esc(rep.consecutiveSuccesses)}</span></div>
              <div class="kv-item"><span class="kv-k">Último LSN aplicado</span><span class="kv-v">${esc(rep.lastReplayLsn || '-')}</span></div>
            </div>
          </div>
        `).join('')}
      </div>

      <div class="callout warn">
        <span><strong>Limitación arquitectónica:</strong> El failover automático cubre únicamente réplicas de lectura; promover un nuevo <code>PRIMARY</code> requeriría un orquestador como Patroni.</span>
        ${d.consultasTotales ? `<span class="pill info">Consultas: PRI=${ct.PRIMARY ?? 0} · R1=${ct.REPLICA_1 ?? 0} · R2=${ct.REPLICA_2 ?? 0}</span>` : ''}
      </div>
    `;
  }

  async function renderSlide13(useCache) {
    if (!useCache || !state.cache.s13) {
      renderLoading('Reiniciando replica1 (docker compose start replica1) y enlazando WAL…');
      if (state.mode === 'sim') {
        await new Promise((r) => setTimeout(r, 380));
        state.simDown['replica1'] = false;
        await refreshDock();
        state.cache.s13 = { ok: true, durationMs: 360 };
        addLocalLog('INFO', 'FAIL', 'docker compose start replica1 (WAL sync) [SIM]');
      } else {
        const res = await fetch('/api/docker/action', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ action: 'start-replica-1' })
        });
        state.cache.s13 = await res.json();
        refreshDock();
      }
    }

    stageEl.innerHTML = `
      <div class="slide-head">
        <div>
          <div class="slide-kicker">BLOQUE 5 · DIAPOSITIVA 13</div>
          <h1 class="slide-title">Recuperación WAL · Reinicio de replica1</h1>
          <p class="slide-subtitle"><code>$ docker compose start replica1</code> — Restableciendo streaming físico desde el primario.</p>
        </div>
        <span class="pill ok">SINCRONIZANDO WAL</span>
      </div>

      <div class="glass-card">
        <div class="card-title-row">
          <span class="card-title">PROCESO DE RECUPERACIÓN AUTOMÁTICA</span>
          <span class="pill info">UMBRAL 2/2 (2 × 3s)</span>
        </div>
        <div class="kv-list">
          <div class="kv-item"><span class="kv-k">1. Contenedor</span><span class="kv-v" style="color:var(--emerald);">[✓] replica1 reiniciado y conectado al PRIMARY :5432</span></div>
          <div class="kv-item"><span class="kv-k">2. Streaming WAL</span><span class="kv-v" style="color:var(--amber);">[~] Aplicando registros WAL acumulados durante la caída</span></div>
          <div class="kv-item"><span class="kv-k">3. Política anti-flapping</span><span class="kv-v" style="color:var(--cyan);">[~] Exige 2 chequeos sanos seguidos antes de recibir tráfico</span></div>
        </div>
      </div>
    `;
  }

  async function renderSlide14(useCache) {
    if (!useCache || !state.cache.s14) {
      renderLoading('Esperando umbral 2/2 de reincorporación para replica1 (~6s)…');
      if (state.mode === 'sim') {
        await new Promise((r) => setTimeout(r, 650));
        state.simDown['replica1'] = false;
        await refreshDock();
        state.cache.s14 = {
          ok: true, status: '200', attempts: 2, durationMs: 42,
          servicio: 'ms-cuentas-1:8081',
          consultasTotales: { PRIMARY: 3, REPLICA_1: 10, REPLICA_2: 30 },
          replicas: [
            { nodo: 'REPLICA_1', available: true, consecutiveSuccesses: 2, lastReplayLsn: '0/1A08C40' },
            { nodo: 'REPLICA_2', available: true, consecutiveSuccesses: 21, lastReplayLsn: '0/1A08C40' }
          ]
        };
        addLocalLog('OK', 'HTTP', 'GET /db/estado -> REPLICA_1 reincorporada (2/2) [SIM]', 's14', 'HTTP 200 · REPLICA_1 available=true (LSN sincronizado)');
      } else {
        const res = await fetch('/api/demo/db-estado?waitRejoin=1');
        state.cache.s14 = await res.json();
      }
    }

    const d = state.cache.s14;
    stageEl.innerHTML = `
      <div class="slide-head">
        <div>
          <div class="slide-kicker">BLOQUE 5 · DIAPOSITIVA 14</div>
          <h1 class="slide-title">Reincorporación Automática · Umbral 2/2</h1>
          <p class="slide-subtitle">Confirmación de retorno sin flapping tras 2 chequeos saludables consecutivos de <code>pg_is_in_recovery()</code>.</p>
        </div>
        <span class="pill ${d.ok ? 'ok' : 'err'}">HTTP ${esc(d.status)} · ${d.attempts || 1} sondeo(s)</span>
      </div>

      <div class="grid-2" style="margin-bottom:14px;">
        ${(d.replicas || []).map((rep) => `
          <div class="glass-card" style="border-color:${rep.available ? 'rgba(16,185,129,0.45)' : 'rgba(244,63,94,0.5)'};">
            <div class="card-title-row">
              <strong style="font-family:var(--font-mono);font-size:17px;">${esc(rep.nodo)}</strong>
              <span class="pill ${rep.available ? 'ok' : 'err'}">${rep.available ? '● ACTIVA · available=true' : '✗ INICIANDO · available=false'}</span>
            </div>
            <div class="kv-list">
              <div class="kv-item"><span class="kv-k">Éxitos consecutivos</span><span class="kv-v">${esc(rep.consecutiveSuccesses)}</span></div>
              <div class="kv-item"><span class="kv-k">Último LSN aplicado</span><span class="kv-v">${esc(rep.lastReplayLsn || '-')}</span></div>
            </div>
          </div>
        `).join('')}
      </div>

      <div class="callout ok">
        <span><strong>Nota de producción:</strong> La recuperación WAL depende de <code>wal_keep_size</code>; en entornos productivos prolongados se recomienda usar <em>replication slots</em>. Si sigue iniciando, pulsa <kbd>R</kbd>.</span>
      </div>
    `;
  }

  function renderSlide15() {
    stageEl.innerHTML = `
      <div class="slide-head">
        <div>
          <div class="slide-kicker">BLOQUE 6 · DIAPOSITIVA 15</div>
          <h1 class="slide-title">Conclusiones · Decisiones, Limitaciones y Mejoras</h1>
          <p class="slide-subtitle">Síntesis arquitectónica del sistema distribuido y exportación del reporte forense.</p>
        </div>
        <button class="action-btn emerald" onclick="window.__walletApp.openExportModal()">📄 Exportar Reporte Forense [E]</button>
      </div>

      <div class="grid-3" style="margin-bottom:16px;">
        <div class="glass-card" style="border-color:rgba(16,185,129,0.4);">
          <div class="card-title-row"><span class="card-title" style="color:var(--emerald);">DECISIONES CLAVE</span><span class="pill ok">✓</span></div>
          <ul class="concl-list">
            <li><strong>BD por @UsarNodo:</strong> escrituras y RYOW al Primario, lecturas ordinarias a Réplicas.</li>
            <li><strong>Round Robin + Salud 2/2:</strong> evita flapping al recuperar réplicas.</li>
            <li><strong>Eureka sin caché + Retry GET:</strong> 0 errores en caídas de app.</li>
            <li><strong>Flyway advisory lock:</strong> migraciones seguras entre réplicas.</li>
          </ul>
        </div>

        <div class="glass-card" style="border-color:rgba(245,158,11,0.4);">
          <div class="card-title-row"><span class="card-title" style="color:var(--amber);">LIMITACIONES TÉCNICAS</span><span class="pill warn">!</span></div>
          <ul class="concl-list">
            <li><strong>Sin failover del primario:</strong> requiere un orquestador externo.</li>
            <li><strong>Eureka único (SPOF):</strong> clúster peer-to-peer en producción.</li>
            <li><strong>/movimiento-interno:</strong> expuesto actualmente en Gateway.</li>
            <li><strong>Sin idempotencia P2P</strong> ni auto-reset de límite diario.</li>
          </ul>
        </div>

        <div class="glass-card" style="border-color:rgba(34,211,238,0.4);">
          <div class="card-title-row"><span class="card-title" style="color:var(--cyan);">MEJORAS FUTURAS</span><span class="pill info">→</span></div>
          <ul class="concl-list">
            <li><strong>Patroni / HA Primario:</strong> promoción automática ante caída del nodo R/W.</li>
            <li><strong>Claves de idempotencia</strong> en transferencias P2P.</li>
            <li><strong>Patrón Outbox & Sagas</strong> para consistencia eventual asíncrona.</li>
            <li><strong>Cerrar /movimiento-interno</strong> y retry controlado en ms-transacciones.</li>
          </ul>
        </div>
      </div>

      <div class="hero-banner" style="padding:20px 24px;margin-bottom:0;text-align:center;">
        <div style="font-size:18px;font-weight:700;color:var(--text-0);">
          “Redundancia en cada capa y failover transparente con integridad ACID.”
        </div>
        <div style="margin-top:8px;font-size:13px;color:var(--text-2);">
          Pulsa <kbd>E</kbd> para generar y guardar el archivo <code>reportes/reporte-YYYYMMDD-HHMMSS.md</code> con toda la evidencia HTTP de la sesión.
        </div>
      </div>
    `;
  }

  // ==================== MODALS ====================

  function openModal(title, htmlContent) {
    state.modalOpen = true;
    $('modal-title').textContent = title;
    $('modal-body').innerHTML = htmlContent;
    $('modal-backdrop').classList.remove('hidden');
  }

  function closeModal() {
    state.modalOpen = false;
    $('modal-backdrop').classList.add('hidden');
  }

  async function openLogsModal() {
    let serverData = { eventLog: [], httpTraces: [] };
    try {
      const r = await fetch('/api/logs');
      serverData = await r.json();
    } catch {}

    const traces = serverData.httpTraces || [];
    const logs = serverData.eventLog?.length ? serverData.eventLog : state.simLogs;

    openModal('📡 Bitácora de Eventos y Trazas HTTP', `
      <div>
        <div class="card-title" style="margin-bottom:8px;">TRAZAS HTTP CAPTURADAS (${traces.length})</div>
        ${traces.length === 0 ? '<div style="color:var(--text-2);font-size:13px;">Aún no hay trazas en vivo capturadas en esta sesión.</div>' : traces.slice().reverse().map((t) => `
          <details style="margin-bottom:8px;border:1px solid var(--border);border-radius:9px;padding:10px 12px;background:#070c18;">
            <summary style="cursor:pointer;font-family:var(--font-mono);font-size:12px;">
              <strong>#${t.seq} [${esc(t.time)}] ${esc(t.method)} ${esc(t.url)}</strong> → HTTP ${esc(t.status)} (${t.durationMs}ms)
            </summary>
            <div style="margin-top:8px;font-size:12px;color:var(--text-2);">${esc(t.note)}</div>
            <pre class="code-block" style="margin-top:8px;">${esc(typeof t.responseBody === 'string' ? t.responseBody : JSON.stringify(t.responseBody, null, 2))}</pre>
          </details>
        `).join('')}
      </div>
      <div>
        <div class="card-title" style="margin-bottom:8px;">EVENTOS DE LA SESIÓN (${logs.length})</div>
        <pre class="code-block">${esc(logs.slice().reverse().map((e) => `${e.time} [${e.level}] [${e.tag}] ${e.message}`).join('\n') || 'Sin eventos aún.')}</pre>
      </div>
    `);
  }

  async function openUtilsModal() {
    const dock = await refreshDock();
    openModal('⚙ Utilidades del Clúster y Controles', `
      <div class="grid-2">
        <button class="action-btn emerald" onclick="window.__walletApp.runDockerUtil('start-all', 'Arrancando contenedores detenidos…')">▶ docker compose start</button>
        <button class="action-btn" onclick="window.__walletApp.runDockerUtil('up', 'Levantando clúster Docker (up -d)…')">🚀 docker compose up -d</button>
        <button class="action-btn amber" onclick="window.__walletApp.runDockerUtil('start-cuentas-2', 'Arrancando ms-cuentas-2…')">▶ Start ms-cuentas-2</button>
        <button class="action-btn amber" onclick="window.__walletApp.runDockerUtil('start-replica-1', 'Arrancando replica1…')">▶ Start replica1</button>
        <button class="action-btn" onclick="window.open('http://localhost:8761','_blank')">↗ Abrir Eureka (:8761)</button>
        <button class="action-btn rose" onclick="if(confirm('¿Ejecutar down -v y reconstruir los 8 contenedores?')) window.__walletApp.runDockerUtil('reset', 'Reinicio limpio en progreso (down -v + up -d --build)…')">♻ Reinicio limpio (down -v)</button>
      </div>
      <div class="callout" style="margin-top:6px;">
        <span>Estado actual: <strong>${dock?.healthyCount ?? 0}/8 healthy</strong></span>
        <button class="action-btn" onclick="window.__walletApp.openUtilsModal()">↻ Refrescar</button>
      </div>
    `);
  }

  async function runDockerUtil(action, msg) {
    showToast(msg);
    if (state.mode === 'sim') {
      state.simDown = { 'ms-cuentas-2': false, 'replica1': false };
      await refreshDock();
      showToast('Operación simulada completada.');
      return;
    }
    try {
      const r = await fetch('/api/docker/action', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action })
      });
      const data = await r.json();
      await refreshDock();
      showToast(data.ok ? `Completado (${(data.durationMs / 1000).toFixed(1)}s)` : `Error: ${data.error || data.stderr}`);
    } catch (err) {
      showToast('Error comunicando con servidor local');
    }
  }

  async function openExportModal() {
    openModal('📄 Exportación de Reporte Forense Markdown', `
      <div style="display:flex;align-items:center;gap:12px;">
        <span class="spinner"></span>
        <span>Generando archivo Markdown en <code>reportes/</code>…</span>
      </div>
    `);

    try {
      const r = await fetch('/api/export', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          mode: state.mode === 'sim' ? 'PLAN B (SIMULADO)' : 'EN VIVO REAL',
          clientSummary: state.simSummary
        })
      });
      const data = await r.json();
      const blobUrl = URL.createObjectURL(new Blob([data.markdown], { type: 'text/markdown;charset=utf-8' }));
      openModal('📄 Reporte Forense Generado Exitosamente', `
        <div class="kv-list">
          <div class="kv-item"><span class="kv-k">Archivo guardado en el repo</span><span class="kv-v" style="color:var(--emerald);">${esc(data.relativePath)}</span></div>
          <div class="kv-item"><span class="kv-k">Ruta completa</span><span class="kv-v">${esc(data.filePath)}</span></div>
          <div class="kv-item"><span class="kv-k">Trazas HTTP / Eventos</span><span class="kv-v">${data.traceCount} trazas · ${data.eventCount} eventos</span></div>
        </div>
        <div style="display:flex;gap:10px;">
          <a class="action-btn emerald" href="${blobUrl}" download="${esc(data.filename)}" style="text-decoration:none;">⬇ Descargar ${esc(data.filename)}</a>
        </div>
        <pre class="code-block" style="max-height:320px;">${esc(data.markdown)}</pre>
      `);
    } catch {
      openModal('Error al exportar', '<div class="callout err">No se pudo contactar con /api/export.</div>');
    }
  }

  function openHelpModal() {
    openModal('⌨ Atajos de Teclado de la Presentación', `
      <div class="kv-list">
        <div class="kv-item"><span class="kv-k">Avanzar diapositiva / Siguiente fase</span><span class="kv-v"><kbd>Espacio</kbd> o <kbd>→</kbd></span></div>
        <div class="kv-item"><span class="kv-k">Diapositiva anterior</span><span class="kv-v"><kbd>←</kbd></span></div>
        <div class="kv-item"><span class="kv-k">Re-ejecutar prueba de la slide actual</span><span class="kv-v"><kbd>R</kbd></span></div>
        <div class="kv-item"><span class="kv-k">Saltar directo a Bloque 1..6</span><span class="kv-v"><kbd>1</kbd> .. <kbd>6</kbd></span></div>
        <div class="kv-item"><span class="kv-k">Abrir / cerrar Guion del Presentador</span><span class="kv-v"><kbd>G</kbd></span></div>
        <div class="kv-item"><span class="kv-k">Ver Bitácora y Trazas HTTP</span><span class="kv-v"><kbd>L</kbd></span></div>
        <div class="kv-item"><span class="kv-k">Exportar Reporte Markdown</span><span class="kv-v"><kbd>E</kbd></span></div>
        <div class="kv-item"><span class="kv-k">Utilidades Docker / Eureka</span><span class="kv-v"><kbd>U</kbd></span></div>
        <div class="kv-item"><span class="kv-k">Volver a Portada</span><span class="kv-v"><kbd>M</kbd></span></div>
      </div>
    `);
  }

  function toggleScriptDrawer() {
    state.scriptOpen = !state.scriptOpen;
    $('script-drawer').classList.toggle('hidden', !state.scriptOpen);
    $('btn-script').classList.toggle('active-toggle', state.scriptOpen);
  }

  // ==================== EVENT LISTENERS ====================

  $('btn-home').addEventListener('click', () => goToSlide(0, true));
  $('btn-prev').addEventListener('click', prevAction);
  $('btn-next').addEventListener('click', nextAction);
  $('btn-refresh').addEventListener('click', () => loadSlide(state.currentSlide, false));
  $('btn-mode-live').addEventListener('click', () => setMode('live'));
  $('btn-mode-sim').addEventListener('click', () => setMode('sim'));
  $('btn-script').addEventListener('click', toggleScriptDrawer);
  $('btn-close-script').addEventListener('click', toggleScriptDrawer);
  $('btn-logs').addEventListener('click', openLogsModal);
  $('btn-utils').addEventListener('click', openUtilsModal);
  $('btn-export').addEventListener('click', openExportModal);
  $('btn-help').addEventListener('click', openHelpModal);
  $('modal-close').addEventListener('click', closeModal);
  $('modal-backdrop').addEventListener('click', (e) => {
    if (e.target === $('modal-backdrop')) closeModal();
  });

  document.querySelectorAll('.blk-pill').forEach((btn) => {
    btn.addEventListener('click', () => {
      const b = BLOCKS[Number(btn.dataset.block)];
      if (b) goToSlide(b.start, false);
    });
  });

  window.addEventListener('keydown', (e) => {
    const tag = (e.target?.tagName || '').toLowerCase();
    if (tag === 'input' || tag === 'textarea' || tag === 'select') return;

    if (e.key === 'Escape') {
      if (state.modalOpen) closeModal();
      else if (state.scriptOpen) toggleScriptDrawer();
      return;
    }
    if (state.modalOpen) return;

    if (e.key === ' ' || e.key === 'ArrowRight') {
      e.preventDefault();
      nextAction();
    } else if (e.key === 'ArrowLeft') {
      e.preventDefault();
      prevAction();
    } else if (e.key === 'r' || e.key === 'R') {
      loadSlide(state.currentSlide, false);
    } else if (e.key === 'g' || e.key === 'G') {
      toggleScriptDrawer();
    } else if (e.key === 'l' || e.key === 'L') {
      openLogsModal();
    } else if (e.key === 'u' || e.key === 'U') {
      openUtilsModal();
    } else if (e.key === 'e' || e.key === 'E') {
      openExportModal();
    } else if (e.key === 'm' || e.key === 'M') {
      goToSlide(0, true);
    } else if (e.key === '?') {
      openHelpModal();
    } else if (['1', '2', '3', '4', '5', '6'].includes(e.key)) {
      goToSlide(BLOCKS[Number(e.key)].start, false);
    }
  });

  window.__walletApp = {
    goToSlide,
    setMode,
    advanceSlide09Phase,
    openExportModal,
    openUtilsModal,
    runDockerUtil,
    selectArchNode: (nodeId) => {
      state.selectedArchNode = nodeId;
      if (state.currentSlide === 1) renderSlide01();
    }
  };

  // Init
  setInterval(refreshDock, 3500);
  goToSlide(0, true);
})();
