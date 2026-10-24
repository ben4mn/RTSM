'use strict';

// Run with Node; exercise the real factory without a browser or game focus.
const assert = require('node:assert/strict');
const factory = require('../web/playtest_diagnostics.js');
const {spawnSync} = require('node:child_process');
const path = require('node:path');
const RealDate = Date;
let clock = RealDate.now();
class TestDate extends RealDate {
    constructor(...args) { super(...(args.length ? args : [clock])); }
    static now() { return clock; }
}
global.Date = TestDate;

function storage(initial = {}) {
    const values = new Map(Object.entries(initial));
    return {
        getItem: key => values.get(key) || null,
        setItem: (key, value) => values.set(key, String(value)),
        snapshot: () => JSON.parse(values.get('pocket.playtest.v1') || 'null'),
    };
}
function deferred() {
    let resolve, reject;
    const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
    return {promise, resolve, reject};
}
function response(body, status = 202) {
    return {ok: status >= 200 && status < 300, status, json: async () => body};
}
function fakeWindow(options = {}) {
    const listeners = new Map(), intervals = [], timeouts = new Map(), posts = [], beacons = [], downloads = [];
    let nextTimer = 1, nextRandom = 1;
    function target(tag = '') {
        const callbacks = new Map();
        const node = {
            tag, children: [], textContent: '', value: '', hidden: false,
            classList: {add() {}, remove() {}},
            appendChild(child) { child.parent = this; this.children.push(child); return child; },
            remove() { if (this.parent) this.parent.children.splice(this.parent.children.indexOf(this), 1); },
            setAttribute(name, value) { this[name] = value; },
            focus() { this.focused = true; }, select() { this.selected = true; },
            getBoundingClientRect() { return {left: 0, top: 0, width: 844, height: 390}; },
            addEventListener(name, fn, flags) {
                if (!callbacks.has(name)) callbacks.set(name, []);
                callbacks.get(name).push({fn, flags});
            },
            async dispatch(name, event = {}) {
                for (const callback of callbacks.get(name) || []) await callback.fn(event);
            },
            click() { return this.dispatch('click', {stopPropagation() {}, preventDefault() {}}); },
            callbacks,
        };
        return node;
    }
    const body = target('body'), app = body.appendChild(target('main'));
    app.id = 'pocket-app';
    const canvas = app.appendChild(target('canvas'));
    canvas.id = 'canvas'; canvas.width = 844; canvas.height = 390;
    function all(node) { return [node, ...node.children.flatMap(all)]; }
    const document = target('document');
    Object.assign(document, {
        body, hidden: false, createElement: target,
        getElementById: id => all(body).find(node => node.id === id) || null,
    });
    const w = {
        document, localStorage: options.storage || storage(),
        innerWidth: 844, innerHeight: 390, devicePixelRatio: 3,
        visualViewport: {width: 844, height: 390, offsetLeft: 0, offsetTop: 0, scale: 1},
        navigator: {onLine: options.online !== false, maxTouchPoints: 5,
            userAgent: 'Mozilla/5.0 (iPhone; secret-full-UA-device-fingerprint) AppleWebKit Safari/604.1',
            clipboard: {writeText: async () => {}}, sendBeacon(url, blob) { beacons.push({url, blob}); return true; }},
        crypto: {getRandomValues(bytes) { bytes.fill(nextRandom++); return bytes; }},
        performance: {now: () => clock % 1000000},
        matchMedia: () => ({matches: false}), AbortController, Blob,
        URL: {createObjectURL: blob => { downloads.push(blob); return 'blob:test'; }, revokeObjectURL() {}},
        console: {warn() {}, error() {}},
        addEventListener(name, fn) {
            if (!listeners.has(name)) listeners.set(name, []);
            listeners.get(name).push(fn);
        },
        setTimeout(fn, delay) { const id = nextTimer++; timeouts.set(id, {fn, delay}); return id; },
        clearTimeout(id) { timeouts.delete(id); },
        setInterval(fn, delay) { intervals.push({fn, delay}); return nextTimer++; },
        async fetch(url, request = {}) {
            if (url === 'version.json') return response(options.version || {source_revision: 'served-new'}, 200);
            const post = {url, request, body: JSON.parse(request.body)};
            posts.push(post);
            if (options.post) return options.post(post, posts.length);
            return response({stored: true, report_id: post.body.report_id});
        },
    };
    return {
        w, document, canvas, posts, beacons, intervals, timeouts, downloads,
        buttons: () => all(body).filter(node => node.tag === 'button'),
        button: text => all(body).find(node => node.tag === 'button' && node.textContent === text),
        async dispatch(name, event = {}) { for (const fn of listeners.get(name) || []) await fn(event); },
        async tick(milliseconds = 10000) { clock += milliseconds; for (const item of intervals) await item.fn(); await settle(); },
    };
}
async function settle() {
    for (let index = 0; index < 8; index++) await Promise.resolve();
}
async function boot(options = {}) {
    const env = fakeWindow(options);
    env.client = factory(env.w);
    await settle();
    return env;
}
function record(env, kind = 'selection_tap_result', fields = {}, sequence = 1) {
    env.client.record(JSON.stringify({schema: 1, session_id: 'anonymous-runtime-session',
        started_utc: '2026-10-11T18:00:00Z', type: 'event',
        build: {game_version: 'fixture', runtime_revision: 'loaded-old'},
        context: {ui_scale: 1.15, map_seed: 101},
        event: {kind, fields, sequence, elapsed_ms: sequence * 100, utc_ms: clock}}));
}
function status(env) { return env.document.getElementById('pocket-report-status').textContent; }

const failures = [];
async function check(name, run) {
    try { await run(); console.log('[PASS] ' + name); }
    catch (error) { failures.push({name, error}); console.error('[FAIL] ' + name + ': ' + error.message); }
}

(async () => {
    await check('canvas observers are passive and do not handle gestures', async () => {
        const env = await boot({online: false});
        let prevented = 0, stopped = 0;
        for (const [name, callbacks] of env.canvas.callbacks) {
            assert(callbacks.every(item => item.flags && item.flags.passive === true && item.flags.capture === true), name);
        }
        const pointer = {pointerId: 41, pointerType: 'touch', clientX: 120, clientY: 140,
            buttons: 1, timeStamp: env.w.performance.now(),
            preventDefault() { prevented++; }, stopPropagation() { stopped++; }};
        await env.canvas.dispatch('pointerdown', pointer);
        clock += 30; await env.canvas.dispatch('pointermove', {...pointer, clientX: 144});
        clock += 220; await env.canvas.dispatch('pointermove', {...pointer, clientX: 180});
        await env.canvas.dispatch('pointerup', {...pointer, clientX: 181});
        assert.equal(prevented, 0); assert.equal(stopped, 0);
        await env.dispatch('pagehide');
        const latest = env.w.localStorage.snapshot().latest;
        assert.equal(latest.counters.browser_pointer_down, 1);
        assert.equal(latest.counters.browser_pointerup, 1);
        assert(latest.counters.browser_pointer_move <= 2);
        assert.equal(latest.events.find(event => event.kind === 'browser_pointerup').fields.max_distance_css, 61);
    });

    await check('bounded delivery and authoritative cached runtime build identity', async () => {
        const env = await boot({online: false});
        for (let index = 0; index < 700; index++) record(env, 'selection_tap_result', {hit: 'worker'}, index);
        await env.dispatch('pagehide');
        const latest = env.w.localStorage.snapshot().latest;
        assert(latest.events.length <= 180);
        assert.equal(latest.counters.selection_tap_result, 700);
        assert.equal(latest.events.filter(event => event.kind === 'selection_tap_result').at(-1).fields.godot_sequence, 699);
        assert.equal(latest.build.runtime_revision, 'loaded-old');
        assert.equal(latest.build.served_revision, 'served-new');
        assert.equal(latest.build.source_mismatch, true);
        assert(!JSON.stringify(latest).includes('secret-full-UA-device-fingerprint'));
        assert.equal(latest.device.platform, 'iOS');
    });

    await check('runtime result report retains its entry point and outcome', async () => {
        const env = await boot({online: false});
        record(env, 'report_context', {entry_point: 'result', game_seconds: 582}, 1);
        record(env, 'match_result', {winner_id: 1, is_victory: false, victory_reason: 'Sacred Site held'}, 2);
        env.client.record(JSON.stringify({type: 'report', session_id: 'runtime-session',
            context: {map_seed: 424242}, report: {events: [
                {kind: 'report_context', fields: {entry_point: 'pause'}},
                {kind: 'report_context', fields: {entry_point: 'result'}}],
                problem: {context: {map_seed: 424242}}}}));
        const saved = env.w.localStorage.snapshot().pending.at(-1);
        assert.equal(saved.events.find(event => event.kind === 'problem_marked').fields.origin, 'result');
        assert.equal(saved.events.find(event => event.kind === 'match_result').fields.winner_id, 1);
        assert.equal(saved.context.map_seed, 424242);
        await env.button('Back to result').click();
        assert.equal(env.document.getElementById('pocket-report').hidden, true);
        assert.equal(env.canvas.focused, true);
        env.client.openReport();
        assert(env.button('Back to Pause'), 'pause entry did not restore its return label');
    });

    await check('acknowledged 202 report removes pending and claims online success', async () => {
        const env = await boot(); record(env);
        const id = env.client.openReport(); await settle();
        assert.match(id, /^PK-[A-F0-9]{12}$/);
        assert.equal(env.posts[0].request.credentials, 'omit');
        assert.equal(env.posts[0].body.report_id, id);
        assert.equal(env.w.localStorage.snapshot().pending.length, 0);
        assert.match(status(env), /Saved online/);
    });

    await check('offline problem survives reload with latest subsequent window', async () => {
        const shared = storage();
        const env = await boot({online: false, storage: shared}); record(env);
        const id = env.client.openReport();
        for (let index = 0; index < 95; index++) record(env, 'camera_pan_sample', {distance: index}, index);
        await env.dispatch('pagehide');
        const saved = shared.snapshot();
        assert.equal(saved.pending[0].report_id, id);
        assert.equal(saved.pending[0].problem_window.following_events.length, 80);
        const restored = await boot({online: true, storage: shared});
        await restored.client.flush('online');
        assert.equal(restored.posts[0].body.report_id, id);
        assert.equal(restored.posts[0].body.problem_window.following_events.length, 80);
        assert.equal(restored.posts[0].body.events.filter(event => event.kind === 'camera_pan_sample').at(-1).fields.godot_sequence, 94);
        assert.equal(shared.snapshot().pending.length, 0);
    });

    await check('HTTP failure stays local, backs off, and retries on reconnect', async () => {
        const env = await boot({post: (post, index) => index === 1
            ? response({stored: false}, 503) : response({stored: true, report_id: post.body.report_id})});
        record(env); env.client.openReport(); await settle();
        assert.match(status(env), /Saved on this device/);
        assert.equal(env.w.localStorage.snapshot().pending.length, 1);
        assert.equal(await env.client.flush(), false);
        assert.equal(env.posts.length, 1);
        clock += 4500;
        assert.equal(await env.client.flush(), true);
        assert.equal(env.posts.length, 2);
        assert.match(status(env), /Saved online/);
    });

    await check('unacknowledged success does not claim report storage', async () => {
        const env = await boot({post: () => response({stored: false}, 202)});
        record(env); env.client.openReport(); await settle();
        assert.match(status(env), /Saved on this device/);
        assert.equal(env.w.localStorage.snapshot().pending.length, 1);
    });

    await check('wrong report acknowledgement is rejected and reconnect retries transport failure', async () => {
        const env = await boot({post: (post, index) => {
            if (index === 1) return response({stored: true, report_id: 'wrong-code'}, 202);
            if (index === 2) return Promise.reject(new Error('network unavailable'));
            return response({stored: true, report_id: post.body.report_id});
        }});
        record(env); const id = env.client.openReport(); await settle();
        assert.match(status(env), /Saved on this device/);
        assert.equal(env.w.localStorage.snapshot().pending[0].report_id, id);
        await env.dispatch('online'); await settle();
        assert.equal(env.posts.length, 2);
        assert.match(status(env), /Saved on this device/);
        await env.dispatch('online'); await settle();
        assert.equal(env.posts.length, 3);
        assert.equal(env.w.localStorage.snapshot().pending.length, 0);
        assert.match(status(env), /Saved online/);
    });

    await check('new input arriving during async upload remains dirty for next upload', async () => {
        const held = deferred();
        const env = await boot({post: (post, index) => index === 1 ? held.promise
            : response({stored: true, report_id: post.body.report_id})});
        record(env, 'selection_tap_result', {hit: 'worker'}, 1);
        const flushing = env.client.flush(); await settle();
        record(env, 'camera_pan_end', {distance: 55}, 2);
        held.resolve(response({stored: true, report_id: ''}));
        assert.equal(await flushing, true);
        assert.equal(await env.client.flush(), true);
        assert.equal(env.posts.length, 2);
        assert(env.posts[1].body.events.some(event => event.kind === 'camera_pan_end'));
    });

    await check('problem note edits during upload remain pending after old acknowledgement', async () => {
        const held = deferred();
        const env = await boot({post: (post, index) => index === 1 ? held.promise
            : response({stored: true, report_id: post.body.report_id})});
        record(env); const id = env.client.openReport(); await settle();
        env.document.getElementById('pocket-report-note').value = 'Worker taps missed after I panned.';
        await env.button('Send report').click();
        held.resolve(response({stored: true, report_id: id})); await settle();
        assert.equal(env.w.localStorage.snapshot().pending.length, 1);
        assert.match(status(env), /Saved on this device/);
        assert.equal(await env.client.flush(), true);
        assert.equal(env.posts[1].body.note, 'Worker taps missed after I panned.');
        assert.equal(env.w.localStorage.snapshot().pending.length, 0);
    });

    await check('expired local pending snapshots do not upload', async () => {
        const shared = storage();
        const env = await boot({online: false, storage: shared}); record(env); env.client.openReport();
        clock += 8 * 24 * 60 * 60 * 1000;
        const restored = await boot({storage: shared}); await restored.client.flush();
        assert.equal(Object.prototype.hasOwnProperty.call(restored.posts[0].body, 'report_id'), false);
        assert.equal(restored.posts[0].body.events.filter(event => event.kind === 'selection_tap_result').length, 0);
    });

    await check('local report queue stays bounded across repeated reports', async () => {
        const env = await boot({online: false}); record(env);
        const ids = [];
        for (let index = 0; index < 12; index++) ids.push(env.client.openReport());
        const pending = env.w.localStorage.snapshot().pending;
        assert.equal(pending.length, 8);
        assert.deepEqual(pending.map(item => item.report_id), ids.slice(-8));
    });

    await check('private fields and full user agent excluded; console errors redacted', async () => {
        const env = await boot({online: false});
        record(env, 'selection_tap_result', {player_name: 'Private Person', email: 'person@example.test',
            token: 'secret-token', cookie: 'secret-cookie', full_user_agent: 'private-full-UA', target: 'Villager'});
        env.w.console.error('Failed https://example.test/path?token=secret at /Users/private/file for person@example.test');
        env.w.console.error('Failed https://example.test/path?token=secret at /Users/private/file for person@example.test');
        await env.dispatch('pagehide');
        const latest = env.w.localStorage.snapshot().latest;
        const text = JSON.stringify(latest);
        for (const secret of ['Private Person', 'person@example.test', 'secret-token', 'secret-cookie',
            'private-full-UA', 'secret-full-UA-device-fingerprint', 'https://example.test', '/Users/private']) assert(!text.includes(secret), secret);
        assert.equal(latest.counters.browser_console_error, 1);
        assert.match(latest.events.find(event => event.kind === 'browser_console_error').fields.error_message, /\[URL\]/);
    });

    await check('runtime source details retain basenames and bounded frames without sensitive stack text', async () => {
        const env = await boot({online: false});
        const error = new RangeError('Invalid array length');
        error.stack = 'RangeError: secret-token\n' + Array.from({length: 40}, (_, index) =>
            '    at person@example.test (https://private.example/user/PrivatePerson/index.js?token=secret-token:' + (index + 1) + ':42)').join('\n');
        await env.dispatch('error', {message: error.message, error, filename: 'https://private.example/index.js?token=secret-token', lineno: 1, colno: 42});
        await env.dispatch('unhandledrejection', {reason: error});
        await env.dispatch('error', {message: 'Failed C:\\Users\\Private Person\\secret.txt, token=secret-token', lineno: Infinity, colno: -1});
        await env.dispatch('error', {message: 'Authorization: Bearer OPAQUE_AUTH_VALUE, api_key=OPAQUE_API_VALUE'});
        await env.dispatch('error', {message: 'Failed /opt/private-user/secret file.js'});
        await env.dispatch('error', {message: 'Authorization="Bearer QUOTED_AUTH_VALUE", password="QUOTED PASSWORD VALUE"'});
        await env.dispatch('error', {message: 'Failed "/opt/quoted-private-user/quoted secret file.js"'});
        await env.dispatch('error', {message: 'password="PRIVATE_PREFIX,PRIVATE_SUFFIX"'});
        await env.dispatch('error', {message: 'Cookie: sid=PRIVATE_FIRST; other=PRIVATE_COOKIE_TAIL'});
        await env.dispatch('error', {message: 'secret="PRIVATE_SECRET;PRIVATE_TAIL"'});
        await env.dispatch('error', {message: '{"access_token":"PRIVATE_JSON_TOKEN"}'});
        await env.dispatch('error', {message: 'Failed file:///C:/Users/PRIVATE_FILE_PREFIX PRIVATE_FILE_TAIL/file.js'});
        await env.dispatch('error', {message: 'Failed "/home/PRIVATE_PATH_PREFIX,PRIVATE_PATH_SUFFIX;PRIVATE_PATH_TAIL/file.js"'});
        await env.dispatch('unhandledrejection', {reason: {get message() { throw new Error('hostile getter'); }}});
        await env.dispatch('pagehide');
        const latest = env.w.localStorage.snapshot().latest;
        const first = latest.events.find(event => event.kind === 'browser_error').fields;
        assert.equal(first.file, 'index.js'); assert.equal(first.line, 1); assert.equal(first.column, 42);
        assert.equal(first.stack.length, 8); assert.deepEqual(first.stack[0], {file: 'index.js', line: 1, column: 42});
        const text = JSON.stringify(latest);
        for (const secret of ['secret-token', 'Private Person', 'private.example', 'person@example.test', 'C:\\\\Users',
            'OPAQUE_AUTH_VALUE', 'OPAQUE_API_VALUE', 'QUOTED_AUTH_VALUE', 'QUOTED PASSWORD VALUE',
            'private-user', 'secret file.js', 'PRIVATE_PREFIX', 'PRIVATE_SUFFIX', 'PRIVATE_FIRST',
            'PRIVATE_COOKIE_TAIL', 'PRIVATE_SECRET', 'PRIVATE_TAIL', 'PRIVATE_JSON_TOKEN', 'PRIVATE_FILE_PREFIX',
            'PRIVATE_FILE_TAIL', 'PRIVATE_PATH_PREFIX', 'PRIVATE_PATH_SUFFIX', 'PRIVATE_PATH_TAIL']) assert(!text.includes(secret), secret);
        assert(text.includes('Error details unavailable'));
    });

    await check('direct log download survives storage failure and does not open or grow the report queue', async () => {
        const env = await boot({online: false, storage: {getItem() { throw new Error('disabled'); }, setItem() { throw new Error('full'); }}});
        record(env, 'match_result', {winner_id: 1});
        await env.dispatch('error', {message: 'Invalid array length', lineno: 1});
        assert.equal(env.client.saveLog(), true);
        assert.equal(env.document.getElementById('pocket-report'), null);
        const saved = JSON.parse(await env.downloads[0].text());
        assert(saved.events.some(event => event.kind === 'browser_error'));
        assert(saved.events.some(event => event.kind === 'match_result'));
        assert.match(saved.report_id, /^PK-[A-F0-9]{12}$/);
        assert(Buffer.byteLength(JSON.stringify(saved)) <= 240 * 1024);
        env.w.URL.createObjectURL = () => { throw new Error('download unavailable'); };
        assert.equal(env.client.saveLog(), false);
    });

    await check('dense bounded events and problem windows fit 240 KiB transport cap', async () => {
        const env = await boot({online: false});
        const fields = Object.fromEntries(Array.from({length: 32}, (_, index) => ['candidate_' + index, 'x'.repeat(400)]));
        for (let index = 0; index < 130; index++) record(env, 'selection_tap_result', fields, index);
        env.client.openReport();
        for (let index = 0; index < 85; index++) record(env, 'camera_pan_sample', fields, index);
        await env.dispatch('pagehide');
        const pending = env.w.localStorage.snapshot().pending[0];
        assert(Buffer.byteLength(JSON.stringify(pending)) <= 240 * 1024, 'report exceeded 240 KiB: ' + Buffer.byteLength(JSON.stringify(pending)));
    });

    await check('background beacon fits the 60 KiB browser payload cap', async () => {
        const env = await boot();
        const fields = Object.fromEntries(Array.from({length: 32}, (_, index) => ['candidate_' + index, 'x'.repeat(400)]));
        for (let index = 0; index < 130; index++) record(env, 'selection_tap_result', fields, index);
        env.w.navigator.onLine = false; env.client.openReport();
        for (let index = 0; index < 85; index++) record(env, 'camera_pan_sample', fields, index);
        env.w.navigator.onLine = true;
        await env.dispatch('pagehide');
        assert.equal(env.beacons.length, 1);
        const bytes = Buffer.byteLength(await env.beacons[0].blob.text());
        assert(bytes <= 60 * 1024, 'background beacon exceeded 60 KiB: ' + bytes);
    });

    await check('ordinary and marked Web envelopes satisfy the actual collector contract', async () => {
        const env = await boot(); record(env, 'selection_tap_result', {target_type: 'Villager'});
        await env.client.flush(); env.client.openReport(); await settle();
        const validate = 'import importlib.util,json,sys; s=importlib.util.spec_from_file_location("collector",sys.argv[1]); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); m.validate_envelope(json.loads(sys.stdin.read()))';
        assert(env.posts.some(post => !post.body.report_id));
        assert(env.posts.some(post => post.body.report_id));
        for (const post of env.posts) {
            const result = spawnSync(process.env.PYTHON || (process.platform === 'win32' ? 'python' : 'python3'), ['-X', 'utf8', '-B', '-c', validate, path.join(__dirname, '../deploy/diagnostics_server.py')],
                {input: JSON.stringify(post.body), encoding: 'utf8'});
            assert.equal(result.status, 0, result.stderr);
        }
    });
})().catch(error => failures.push({name: 'test runner', error})).finally(() => {
    global.Date = RealDate;
    if (failures.length) {
        console.error(failures.length + ' regression check(s) failed.');
        process.exitCode = 1;
    } else console.log('[PASS] playtest_web_client: all real-factory regression checks');
});
