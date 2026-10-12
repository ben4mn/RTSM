/* Anonymous, bounded playtest traces. Observers never handle game input. */
(function (root, factory) {
    if (typeof module === 'object' && module.exports) module.exports = factory;
    else root.PocketPlaytestDiagnostics = factory(root);
}(typeof window !== 'undefined' ? window : null, function (w) {
    'use strict';
    const MAX_EVENTS = 600, MAX_PENDING = 8, MAX_BYTES = 240 * 1024;
    const RETENTION = 7 * 24 * 60 * 60 * 1000;
    const STORAGE = 'pocket.playtest.v1';
    const endpoint = '/api/playtest-diagnostics';
    const privateKey = /^(player_?name|user_?name|real_?name|email|address|phone|cookies?|token|authorization|password|ip(_?address)?|latitude|longitude|location|device_?id|user_?id|full_?user_?agent)$/i;
    let serial = 0, events = [], counters = Object.create(null), context = {}, runtime = {}, served = {};
    let session = randomId(), started = new Date().toISOString(), problem = null;
    let pending = [], inFlight = false, dirty = false, activeReport = null;
    let overlay = null, status = null, code = null, note = null;
    let lastPersist = 0, nextAttempt = 0, failures = 0;
    const contacts = new Map();

    function errorText(value) {
        return String(value).replace(/https?:\/\/[^\s]+/g, '[URL]')
            .replace(/\/Users\/[^\s]+/g, '[local path]')
            .replace(/[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}/g, '[email]').slice(0, 192);
    }

    function randomId() {
        const bytes = new Uint8Array(16);
        w.crypto.getRandomValues(bytes);
        return Array.from(bytes, x => x.toString(16).padStart(2, '0')).join('');
    }
    function clean(value, depth = 0) {
        if (depth > 5) return null;
        if (typeof value === 'number') return Number.isFinite(value) ? value : null;
        if (typeof value === 'string') return value.slice(0, 400);
        if (value === null || typeof value === 'boolean') return value;
        if (Array.isArray(value)) return value.slice(0, 32).map(v => clean(v, depth + 1));
        if (value && typeof value === 'object') {
            const out = {};
            for (const [key, item] of Object.entries(value).slice(0, 32)) {
                if (!privateKey.test(key)) out[key.slice(0, 64)] = clean(item, depth + 1);
            }
            return out;
        }
        return null;
    }
    function append(kind, fields = {}, extra = {}) {
        kind = typeof kind === 'string' && kind ? kind.slice(0, 64) : 'unknown';
        if (!Object.prototype.hasOwnProperty.call(counters, kind) && Object.keys(counters).length >= 63) kind = 'other';
        const event = Object.assign({sequence: ++serial, elapsed_ms: Math.round(w.performance.now()),
            utc_ms: Date.now(), kind, fields: clean(fields)}, extra);
        events.push(event);
        if (events.length > MAX_EVENTS) events.shift();
        counters[kind] = (counters[kind] || 0) + 1;
        if (problem && event.sequence > problem.marked_sequence && problem.following_events.length < 80)
            problem.following_events.push(event);
        dirty = true;
        return event;
    }
    function device() {
        const canvas = w.document.getElementById('canvas');
        const rect = canvas ? canvas.getBoundingClientRect() : {width: 0, height: 0};
        const vv = w.visualViewport, ua = w.navigator.userAgent || '';
        return {
            viewport: {width: w.innerWidth, height: w.innerHeight},
            css_canvas: {width: rect.width, height: rect.height},
            backing_canvas: {width: canvas ? canvas.width : 0, height: canvas ? canvas.height : 0},
            visual_viewport: vv ? {width: vv.width, height: vv.height, offset_left: vv.offsetLeft,
                offset_top: vv.offsetTop, scale: vv.scale} : null,
            dpr: w.devicePixelRatio || 1, max_touch_points: w.navigator.maxTouchPoints || 0,
            platform: /iPhone|iPad|iPod/.test(ua) ? 'iOS' : /Android/.test(ua) ? 'Android'
                : /Mac/.test(ua) ? 'macOS' : /Windows/.test(ua) ? 'Windows' : 'other',
            browser: /Edg\//.test(ua) ? 'Edge' : /Firefox\//.test(ua) ? 'Firefox'
                : /Chrome\//.test(ua) ? 'Chrome' : /Safari\//.test(ua) ? 'Safari' : 'other',
            standalone: w.navigator.standalone === true || w.matchMedia('(display-mode: standalone)').matches,
            orientation: w.innerWidth >= w.innerHeight ? 'landscape' : 'portrait',
        };
    }
    function snapshot(reason = 'periodic', reportId = '') {
        const body = {
            schema_version: 1, session_id: session, report_id: reportId || undefined,
            reason, sent_at_utc: new Date().toISOString(), started_utc: started,
            build: Object.assign({}, served, runtime, {
                runtime_revision: runtime.runtime_revision || 'unknown',
                served_revision: served.source_revision || 'unknown',
                source_mismatch: !!runtime.runtime_revision && !!served.source_revision
                    && runtime.runtime_revision !== served.source_revision,
            }),
            device: device(), context: clean(context), counters: Object.assign({}, counters),
            events: events.slice(-180),
        };
        if (problem) body.problem_window = cleanWindow(problem);
        if (activeReport && reportId === activeReport.report_id) body.note = activeReport.note || '';
        return fit(body, MAX_BYTES);
    }
    function cleanWindow(window) {
        return {report_id: window.report_id, marked_sequence: window.marked_sequence,
            preceding_events: window.preceding_events.slice(-120), following_events: window.following_events.slice(0, 80)};
    }
    function fit(body, limit) {
        const result = JSON.parse(JSON.stringify(body));
        let text = JSON.stringify(result);
        while (new TextEncoder().encode(text).length > limit) {
            if (result.events.length > 1) result.events = result.events.slice(Math.ceil(result.events.length / 3));
            else if (result.problem_window && result.problem_window.preceding_events.length > 1)
                result.problem_window.preceding_events = result.problem_window.preceding_events.slice(Math.ceil(result.problem_window.preceding_events.length / 3));
            else if (result.problem_window && result.problem_window.following_events.length > 1)
                result.problem_window.following_events = result.problem_window.following_events.slice(-1);
            else {
                for (const list of [result.events, result.problem_window && result.problem_window.preceding_events,
                    result.problem_window && result.problem_window.following_events])
                    if (list) for (const event of list) event.fields = {trace_truncated: true};
                result.context = {};
                result.build = {runtime_revision: String(result.build.runtime_revision || '').slice(0, 64),
                    served_revision: String(result.build.served_revision || '').slice(0, 64),
                    source_tree_sha256: String(result.build.source_tree_sha256 || '').slice(0, 64)};
                text = JSON.stringify(result);
                if (new TextEncoder().encode(text).length > limit) throw new Error('diagnostic envelope exceeds limit');
                break;
            }
            text = JSON.stringify(result);
        }
        return result;
    }
    function queue(body) {
        if (body.report_id) {
            const index = pending.findIndex(item => item.report_id === body.report_id);
            if (index >= 0) pending[index] = body;
            else pending.push(body);
            pending = pending.slice(-MAX_PENDING);
        }
        persist();
    }
    function persist() {
        lastPersist = Date.now();
        const latest = snapshot('periodic', activeReport ? activeReport.report_id : '');
        if (activeReport) {
            const index = pending.findIndex(item => item.report_id === activeReport.report_id);
            if (index >= 0) pending[index] = Object.assign({}, latest, {reason: 'problem'});
        }
        try { w.localStorage.setItem(STORAGE, JSON.stringify({saved_at: lastPersist, latest, pending})); } catch (_) {}
    }
    function restore() {
        try {
            const saved = JSON.parse(w.localStorage.getItem(STORAGE) || 'null');
            if (saved && Date.now() - saved.saved_at < RETENTION && Array.isArray(saved.pending)) {
                pending = saved.pending.filter(item => item && /^[A-Za-z0-9_-]{1,64}$/.test(item.session_id)
                    && /^[A-Za-z0-9_-]{1,64}$/.test(item.report_id)).slice(-MAX_PENDING).map(item => fit(item, MAX_BYTES));
                if (saved.latest && /^[A-Za-z0-9_-]{1,64}$/.test(saved.latest.session_id) && Array.isArray(saved.latest.events)) {
                    const previous = fit(saved.latest, MAX_BYTES);
                    const index = pending.findIndex(item => item.report_id && item.report_id === previous.report_id);
                    if (index >= 0) pending[index] = previous;
                    else if (pending.length < MAX_PENDING) pending.push(previous);
                }
            }
        } catch (_) {}
    }
    async function flush(reason = 'periodic') {
        if (inFlight || Date.now() < nextAttempt || w.navigator.onLine === false) return false;
        if (!dirty && !pending.length && reason === 'periodic') return true;
        inFlight = true;
        const body = pending[0] || snapshot(reason, activeReport ? activeReport.report_id : '');
        const sequenceAtSend = serial;
        const controller = new w.AbortController();
        const timeout = w.setTimeout(() => controller.abort(), 7000);
        try {
            const response = await w.fetch(endpoint, {method: 'POST', headers: {'Content-Type': 'application/json'},
                credentials: 'omit', cache: 'no-store', body: JSON.stringify(body), signal: controller.signal});
            if (!response.ok) throw new Error('report not stored');
            const acknowledgement = await response.json();
            if (acknowledgement.stored !== true || (body.report_id && acknowledgement.report_id !== body.report_id))
                throw new Error('report not acknowledged');
            if (pending[0] === body || (pending[0] && JSON.stringify(pending[0]) === JSON.stringify(body))) pending.shift();
            failures = 0; nextAttempt = 0; dirty = serial !== sequenceAtSend; persist();
            if (activeReport && activeReport.report_id === body.report_id && status
                && !pending.some(item => item.report_id === body.report_id))
                status.textContent = 'Saved online. Include this code when you report the problem.';
            return true;
        } catch (_) {
            failures += 1;
            nextAttempt = Date.now() + Math.min(60000, 2000 * Math.pow(2, Math.min(5, failures)));
            persist();
            if (activeReport && status) status.textContent = 'Saved on this device. It will upload when online; you can download the log now.';
            return false;
        } finally { w.clearTimeout(timeout); inFlight = false; }
    }
    function record(text) {
        try {
            const packet = typeof text === 'string' ? JSON.parse(text) : text;
            if (!packet || typeof packet.session_id !== 'string' || !/^[A-Za-z0-9_-]{1,64}$/.test(packet.session_id)) return;
            session = packet.session_id; started = packet.started_utc || started;
            runtime = clean(packet.build || {}); context = clean(packet.context || {});
            if (packet.type === 'event' && packet.event) {
                append(packet.event.kind, Object.assign({}, packet.event.fields,
                    {godot_sequence: packet.event.sequence, godot_elapsed_ms: packet.event.elapsed_ms}), {utc_ms: packet.event.utc_ms});
            } else if (packet.type === 'report' && packet.report) {
                const report = packet.report;
                append('problem_marked', {origin: 'pause'});
                openReport(report);
            }
        } catch (_) {} // A diagnostic failure cannot affect a game handler.
    }
    function openReport(report) {
        if (activeReport) queue(snapshot('problem', activeReport.report_id));
        const reportId = 'PK-' + randomId().slice(0, 12).toUpperCase();
        const marker = append('report_opened', {});
        problem = {report_id: reportId, marked_sequence: marker.sequence,
            preceding_events: events.slice(-121, -1), following_events: []};
        if (report && report.problem) {
            context = Object.assign({}, context, clean(report.problem.context || {}));
        }
        activeReport = {report_id: reportId, note: ''};
        showDialog();
        queue(snapshot('problem', reportId)); nextAttempt = 0; flush('problem');
        return reportId;
    }
    function element(tag, text, parent) {
        const node = w.document.createElement(tag);
        if (text) node.textContent = text;
        if (parent) parent.appendChild(node);
        return node;
    }
    function closeDialog() {
        if (overlay) overlay.hidden = true;
        w.document.body.classList.remove('pocket-report-open');
        const canvas = w.document.getElementById('canvas');
        if (canvas) canvas.focus();
    }
    function showDialog() {
        if (!overlay) {
            overlay = element('div', '', w.document.getElementById('pocket-app'));
            overlay.id = 'pocket-report'; overlay.setAttribute('role', 'dialog'); overlay.setAttribute('aria-modal', 'true');
            overlay.setAttribute('aria-labelledby', 'pocket-report-title');
            const card = element('div', '', overlay); card.className = 'pocket-report-card';
            const title = element('h1', 'Report a problem', card); title.id = 'pocket-report-title';
            element('p', 'Includes recent game inputs, build and screen details. No screen recordings.', card);
            const label = element('label', 'Report code', card);
            code = element('input', '', label); code.readOnly = true; code.id = 'pocket-report-code';
            const noteLabel = element('label', 'What went wrong? (optional)', card);
            note = element('textarea', '', noteLabel); note.rows = 2; note.maxLength = 400; note.id = 'pocket-report-note';
            status = element('p', '', card); status.id = 'pocket-report-status'; status.setAttribute('role', 'status');
            const actions = element('div', '', card); actions.className = 'pocket-report-actions';
            const copy = element('button', 'Copy code', actions); copy.className = 'pocket-button'; copy.type = 'button';
            copy.addEventListener('click', async () => {
                try { await w.navigator.clipboard.writeText(code.value); status.textContent = 'Code copied.'; }
                catch (_) { code.focus(); code.select(); status.textContent = 'Select and copy the report code.'; }
            });
            const send = element('button', 'Send report', actions); send.className = 'pocket-button'; send.type = 'button';
            send.addEventListener('click', () => {
                activeReport.note = note.value.slice(0, 400);
                queue(snapshot('problem', activeReport.report_id)); nextAttempt = 0;
                status.textContent = 'Saved on this device. Uploading…'; flush('problem');
            });
            const download = element('button', 'Save log', actions); download.className = 'pocket-button'; download.type = 'button';
            download.addEventListener('click', () => {
                const blob = new w.Blob([JSON.stringify(snapshot('problem', activeReport.report_id), null, 2)], {type: 'application/json'});
                const url = w.URL.createObjectURL(blob), link = element('a', '', w.document.body);
                link.href = url; link.download = activeReport.report_id + '.json'; link.click(); link.remove();
                w.setTimeout(() => w.URL.revokeObjectURL(url), 1000);
            });
            const close = element('button', 'Back to Pause', actions); close.className = 'pocket-button'; close.type = 'button';
            close.addEventListener('click', closeDialog);
            overlay.addEventListener('keydown', event => {
                event.stopPropagation();
                if (event.key === 'Escape') { event.preventDefault(); closeDialog(); }
            });
            for (const name of ['pointerdown', 'pointerup', 'mousedown', 'mouseup', 'touchstart', 'touchend'])
                overlay.addEventListener(name, event => event.stopPropagation());
        }
        overlay.hidden = false; code.value = activeReport.report_id; note.value = '';
        status.textContent = w.navigator.onLine === false
            ? 'Saved on this device. It will upload when online; you can download the log now.'
            : 'Saved on this device. Uploading…';
        w.document.body.classList.add('pocket-report-open');
    }
    function observeCanvas() {
        const canvas = w.document.getElementById('canvas');
        if (!canvas) return;
        function point(event) {
            const rect = canvas.getBoundingClientRect();
            return {x: Math.round((event.clientX - rect.left) * 100) / 100,
                y: Math.round((event.clientY - rect.top) * 100) / 100};
        }
        canvas.addEventListener('pointerdown', event => {
            const position = point(event);
            contacts.set(event.pointerId, {position, started: w.performance.now(), maximum: 0, sampled: 0});
            append('browser_pointer_down', {pointer_id: event.pointerId, pointer_type: event.pointerType,
                position, buttons: event.buttons, contact_count: contacts.size,
                dispatch_delay_ms: Math.max(0, Math.min(5000, event.timeStamp > 1e10
                    ? Date.now() - event.timeStamp : w.performance.now() - (event.timeStamp || w.performance.now())))});
        }, {capture: true, passive: true});
        canvas.addEventListener('pointermove', event => {
            const contact = contacts.get(event.pointerId); if (!contact) return;
            const position = point(event), now = w.performance.now();
            contact.maximum = Math.max(contact.maximum, Math.hypot(position.x - contact.position.x, position.y - contact.position.y));
            if (now - contact.sampled >= 200) {
                append('browser_pointer_move', {pointer_id: event.pointerId, position, max_distance_css: contact.maximum});
                contact.sampled = now;
            }
        }, {capture: true, passive: true});
        for (const type of ['pointerup', 'pointercancel', 'lostpointercapture']) canvas.addEventListener(type, event => {
            const contact = contacts.get(event.pointerId); if (!contact) return;
            const position = point(event);
            const maximum = Math.max(contact.maximum, Math.hypot(position.x - contact.position.x, position.y - contact.position.y));
            append('browser_' + type, {pointer_id: event.pointerId, pointer_type: event.pointerType,
                start: contact.position, end: position, duration_ms: Math.round(w.performance.now() - contact.started),
                max_distance_css: maximum}); contacts.delete(event.pointerId);
        }, {capture: true, passive: true});
        let lastWheel = 0;
        canvas.addEventListener('wheel', event => {
            const now = w.performance.now(); if (now - lastWheel < 200) return; lastWheel = now;
            append('browser_wheel', {delta_x: event.deltaX, delta_y: event.deltaY, mode: event.deltaMode, ctrl: event.ctrlKey});
        }, {capture: true, passive: true});
    }
    restore(); observeCanvas();
    append('browser_start', {device: device()});
    w.fetch('version.json', {cache: 'no-store', credentials: 'omit'}).then(r => r.ok ? r.json() : {}).then(version => {
        served = clean(version); append('served_build', served);
    }).catch(() => {});
    for (const name of ['resize', 'orientationchange', 'blur', 'focus', 'online', 'offline']) w.addEventListener(name, () => {
        append('browser_' + name, {device: device()});
        if (name === 'online') { nextAttempt = 0; flush(); }
    });
    w.addEventListener('error', event => append('browser_error', {error_message: errorText(event.message || 'error'), line: event.lineno}));
    w.addEventListener('unhandledrejection', event => append('browser_rejection', {error_message: errorText(event.reason && event.reason.message || 'promise rejected')}));
    if (w.console) for (const [method, kind] of [['warn', 'browser_console_warning'], ['error', 'browser_console_error']]) {
        const original = w.console[method]; let last = '', lastAt = 0;
        w.console[method] = function (...args) {
            const text = errorText(args.map(value => value instanceof Error ? value.message : String(value)).join(' '));
            if (text !== last || Date.now() - lastAt >= 1000) { append(kind, {error_message: text}); last = text; lastAt = Date.now(); }
            return original.apply(w.console, args);
        };
    }
    function background() {
        append('browser_background', {}); persist();
        const body = fit(snapshot('pagehide', activeReport ? activeReport.report_id : ''), 60 * 1024);
        if (w.navigator.onLine !== false && w.navigator.sendBeacon)
            w.navigator.sendBeacon(endpoint, new w.Blob([JSON.stringify(body)], {type: 'application/json'}));
    }
    w.addEventListener('pagehide', background);
    w.document.addEventListener('visibilitychange', () => { if (w.document.hidden) background(); });
    w.setInterval(() => {
        if (dirty && Date.now() - lastPersist >= 5000) persist();
        flush();
    }, 10000);
    return Object.freeze({record, openReport, flush});
}));
