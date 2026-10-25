'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {webcrypto, createHash} = require('node:crypto');
const {createPocketWorker} = require('../web/pocket_service_worker.js');
const createPocketUpdates = require('../web/pocket_updates.js');
const BASE = 'https://example.test/games/pocket-kingdoms/';
const pause = (ms = 0) => new Promise((resolve) => setTimeout(resolve, ms));
const digest = (text) => createHash('sha256').update(text).digest('hex');
const bindRelease = (release) => ({...release, id: release.revision + '-' + digest(JSON.stringify(Object.fromEntries(Object.entries(release.files).sort()))).slice(0, 20)});

function workerFixture(options = {}) {
	const content = {'index.html': 'shell', 'index.js': 'engine', 'index.wasm': 'wasm', 'index.pck': 'pack', 'index.offline.html': 'offline', 'release_notes.json': 'notes', 'pocket_updates.js': 'updates', 'pocket_launch.js': 'launch', 'pocket_launch.css': 'css', 'playtest_diagnostics.js': 'diagnostics', 'Barlow-Regular.ttf': 'font', 'kingdom_company_v2.png': 'art', 'index.manifest.json': 'manifest'};
	const release = bindRelease({revision: 'abcdefabcdef', sourceTreeSha256: 'a'.repeat(64), files: Object.fromEntries(Object.entries(content).map(([name, value]) => [name, digest(value)])), shell: Object.keys(content).filter((name) => !['index.js', 'index.wasm', 'index.pck'].includes(name))});
	const storage = new Map();
	const caches = {
		async open(name) {
			if (!storage.has(name)) storage.set(name, new Map());
			const entries = storage.get(name);
			return {match: async (url) => entries.has(String(url)) ? entries.get(String(url)).clone() : undefined, put: async (url, value) => { entries.set(String(url), value.clone()); }, delete: async (url) => entries.delete(String(url))};
		},
		keys: async () => [...storage.keys()],
	};
	const clients = [];
	const requests = [];
	let skipped = 0;
	let offline = false;
	const env = {registration: {scope: BASE, active: options.updating ? {} : null}, crypto: webcrypto, caches, setTimeout, clearTimeout,
		clients: {matchAll: async () => clients.slice(), get: async (id) => clients.find((client) => client.id === id)},
		fetch: async (request) => {
			const url = typeof request === 'string' ? request : request.url;
			requests.push(url);
			if (offline) throw new Error('offline');
			const name = new URL(url).pathname.slice(new URL(BASE).pathname.length);
			return new Response(content[name] || 'server-version', {status: 200});
		}, skipWaiting: async () => { skipped++; }, addEventListener() {},
	};
	const worker = createPocketWorker(env, release, {handshakeTimeout: 15});
	function client(id, safe = true, cache = null, hook = null) {
		const messages = [];
		const value = {id, url: BASE, messages, postMessage(data) {
			messages.push(data);
			if (hook) hook(data);
			if (safe !== null && ['PREPARE', 'COMMIT'].includes(data.type)) worker.message({source: value, data: {pocket: 1, type: 'ANSWER', nonce: data.nonce, phase: data.type, safe, cache}});
		}};
		clients.push(value);
		return value;
	}
	return {worker, env, content, release, storage, clients, requests, client, skipped: () => skipped, offline: (value) => { offline = value; }};
}

test('first visit caches only welcome shell; existing installs require a complete verified update', async () => {
	const first = workerFixture();
	await first.worker.install();
	assert.equal(await first.worker.ready(), false);
	assert.equal(first.requests.some((url) => url.endsWith('.wasm') || url.endsWith('.pck')), false);
	const update = workerFixture({updating: true});
	await update.worker.install();
	assert.equal(await update.worker.ready(), true);
	assert.equal(update.skipped(), 0);
});

test('mixed deploy rejects installation and never writes a complete marker or deletes predecessor cache', async () => {
	const f = workerFixture({updating: true});
	const prior = await f.env.caches.open('pocket-release-old');
	await prior.put(BASE + 'index.pck', new Response('old-pack'));
	f.content['index.pck'] = 'unexpected-pack';
	await assert.rejects(f.worker.install(), /could not be verified/);
	assert.equal(await f.worker.ready(), false);
	assert.equal(await (await prior.match(BASE + 'index.pck')).text(), 'old-pack');
	assert.equal(f.skipped(), 0);
	f.content['index.pck'] = 'pack';
	assert.equal(await f.worker.stage(), true);
	assert.equal(await f.worker.ready(), true);
});

test('completion requires every file, including cache eviction after staging', async () => {
	const f = workerFixture();
	assert.equal(await f.worker.stage(), true);
	assert.equal(await f.worker.ready(), true);
	await (await f.env.caches.open(f.worker.cacheName)).delete(BASE + 'index.pck');
	assert.equal(await f.worker.ready(), false);
});

test('active match, paused/result cohort, or legacy nonresponding client defers all-window activation', async () => {
	for (const safe of [false, null]) {
		const f = workerFixture();
		f.client('menu', true);
		f.client('busy-or-legacy', safe);
		await f.worker.stage();
		assert.equal(await f.worker.apply(), false);
		assert.equal(f.skipped(), 0);
		assert.ok(f.clients[0].messages.some((message) => message.type === 'ABORT'));
	}
});

test('changed client set during either handshake phase defers activation', async () => {
	for (const phase of ['PREPARE', 'COMMIT']) {
		const f = workerFixture();
		f.client('menu', true, null, (data) => { if (data.type === phase && f.clients.length === 1) f.client('new-window', null); });
		await f.worker.stage();
		assert.equal(await f.worker.apply(), false);
		assert.equal(f.skipped(), 0);
	}
});

test('new window during activation preparation aborts; a post-check legacy newcomer never receives mixed assets', async () => {
	const before = workerFixture();
	before.client('menu', true, null, (data) => { if (data.type === 'STATUS' && data.state === 'applying') before.client('late-before-skip', null); });
	await before.worker.stage();
	assert.equal(await before.worker.apply(), false);
	assert.equal(before.skipped(), 0);
	const after = workerFixture();
	after.client('menu', true, after.worker.cacheName);
	await after.worker.stage();
	after.env.skipWaiting = async () => { after.client('legacy-after-final-check', null); };
	assert.equal(await after.worker.apply(), true);
	const response = await after.worker.fetchResponse({request: new Request(BASE + 'index.pck'), clientId: 'legacy-after-final-check'});
	assert.equal(response.status, 503);
	assert.notEqual(await response.text(), 'pack');
});

test('old navigation finishing after activation persists its release for late requests; new navigation binds the new release', async () => {
	const f = workerFixture();
	await f.worker.stage();
	f.content['index.pck'] = 'next-pack';
	f.content['index.html'] = 'next-shell';
	const nextRelease = bindRelease({...f.release, files: {...f.release.files, 'index.pck': digest('next-pack'), 'index.html': digest('next-shell')}});
	const successor = createPocketWorker(f.env, nextRelease);
	await successor.stage();
	await successor.activate();
	const navigation = {url: BASE, method: 'GET', mode: 'navigate'};
	const oldPage = await f.worker.fetchResponse({request: navigation, resultingClientId: 'late-old-page'});
	assert.equal(await oldPage.text(), 'shell');
	const oldPack = await successor.fetchResponse({request: new Request(BASE + 'index.pck'), clientId: 'late-old-page'});
	assert.equal(await oldPack.text(), 'pack');
	const newPage = await successor.fetchResponse({request: navigation, resultingClientId: 'new-page'});
	assert.equal(await newPage.text(), 'next-shell');
	const newPack = await successor.fetchResponse({request: new Request(BASE + 'index.pck'), clientId: 'new-page'});
	assert.equal(await newPack.text(), 'next-pack');
});

test('two acknowledged menu phases activate once and retain removed old assets for a late old client', async () => {
	const f = workerFixture();
	const old = await f.env.caches.open('pocket-release-old');
	await old.put(BASE + 'removed-old.js', new Response('old-only'));
	await old.put(BASE + 'index.pck', new Response('old-pack'));
	f.client('menu', true, 'pocket-release-old');
	await f.worker.stage();
	assert.deepEqual(await Promise.all([f.worker.apply(), f.worker.apply()]), [true, true]);
	assert.equal(f.skipped(), 1);
	// A service-worker process restart must retain the old-client association.
	const restarted = createPocketWorker(f.env, f.release);
	for (const [name, expected] of [['removed-old.js', 'old-only'], ['index.pck', 'old-pack']]) {
		const response = await restarted.fetchResponse({request: new Request(BASE + name), clientId: 'menu'});
		assert.equal(await response.text(), expected);
		assert.equal(response.headers.get('Cross-Origin-Embedder-Policy'), 'require-corp');
	}
});

test('fresh served diagnostics bypass cache, while a complete game boots offline with query strings', async () => {
	const f = workerFixture();
	await f.worker.stage();
	const version = await f.worker.fetchResponse({request: new Request(BASE + 'version.json?receipt=1'), clientId: 'menu'});
	assert.equal(await version.text(), 'server-version');
	f.offline(true);
	await f.worker.fetchResponse({request: {url: BASE, method: 'GET', mode: 'navigate'}, resultingClientId: 'menu'});
	const game = await f.worker.fetchResponse({request: new Request(BASE + 'index.pck?cache=1'), clientId: 'menu'});
	assert.equal(await game.text(), 'pack');
	await assert.rejects(f.worker.fetchResponse({request: new Request(BASE + 'version.json'), clientId: 'menu'}), /offline/);
});

test('legacy stock-worker messages have no activation, navigation, or cache-deletion effect', async () => {
	const f = workerFixture();
	const client = f.client('legacy', null);
	await f.worker.stage();
	for (const command of ['claim', 'clear', 'update']) await f.worker.message({source: client, data: command});
	assert.equal(f.skipped(), 0);
	assert.equal(await f.worker.ready(), true);
});

test('new revision reuses verified unchanged bytes; a changed pack downloads only changed files', async () => {
	const f = workerFixture();
	await f.worker.stage();
	const initial = f.worker.getTransfer();
	f.requests.length = 0;
	const same = createPocketWorker(f.env, bindRelease({...f.release, revision: 'bbbbbbbbbbbb'}));
	assert.equal(await same.stage(), true);
	assert.deepEqual(f.requests, []);
	assert.equal(same.getTransfer().reusedBytes, initial.downloadedBytes);
	f.content['index.pck'] = 'changed-pack';
	f.content['index.html'] = 'changed-shell';
	const changed = createPocketWorker(f.env, bindRelease({...f.release, revision: 'cccccccccccc', files: {...f.release.files, 'index.pck': digest('changed-pack'), 'index.html': digest('changed-shell')}}));
	assert.equal(await changed.stage(), true);
	assert.deepEqual(f.requests.map((url) => url.slice(BASE.length)).sort(), ['index.html', 'index.pck']);
	assert.ok(changed.getTransfer().reusedFiles.includes('index.wasm'));
	assert.equal(changed.getTransfer().downloadedBytes, Buffer.byteLength('changed-packchanged-shell'));
	console.log('CACHE_TRANSFER ' + JSON.stringify({scope: 'isolated worker with in-memory CacheStorage and mocked fetch; real SHA-256 and Response bytes', initial, unchanged: same.getTransfer(), changed: changed.getTransfer()}));
});

test('legacy cache migration hashes actual bytes and replaces a corrupt predecessor without deleting it', async () => {
	const f = workerFixture();
	const old = await f.env.caches.open('pocket-release-legacy');
	for (const [name, bytes] of Object.entries(f.content)) await old.put(BASE + name, new Response(name === 'index.wasm' ? 'truncated' : bytes));
	assert.equal(await f.worker.stage(), true);
	assert.deepEqual(f.requests.map((url) => url.slice(BASE.length)), ['index.wasm']);
	assert.equal(await (await old.match(BASE + 'index.wasm')).text(), 'truncated');
	assert.equal(await f.worker.ready(), true);
});

test('interrupted update preserves offline predecessor and retries only missing verified content', async () => {
	const f = workerFixture();
	await f.worker.stage();
	await f.worker.fetchResponse({request: {url: BASE, method: 'GET', mode: 'navigate'}, resultingClientId: 'old-match'});
	f.content['index.pck'] = 'new-pack';
	const next = createPocketWorker(f.env, bindRelease({...f.release, revision: 'dddddddddddd', files: {...f.release.files, 'index.pck': digest('new-pack')}}));
	const fetch = f.env.fetch;
	f.env.fetch = async (request, options) => { if (String(request).endsWith('index.pck')) throw new Error('interrupted'); return fetch(request, options); };
	assert.equal(await next.stage(), false);
	assert.equal(await next.ready(), false);
	f.offline(true);
	const oldPack = await f.worker.fetchResponse({request: new Request(BASE + 'index.pck'), clientId: 'old-match'});
	assert.equal(await oldPack.text(), 'pack');
	f.offline(false); f.env.fetch = fetch; f.requests.length = 0;
	assert.equal(await next.stage(), true);
	assert.deepEqual(f.requests.map((url) => url.slice(BASE.length)), ['index.pck']);
	assert.equal(await f.worker.ready(), true);
	// Rollback is another immutable release selection and needs no network.
	f.offline(true); f.requests.length = 0;
	assert.equal(await f.worker.stage(), true);
	assert.deepEqual(f.requests, []);
});

test('truncated manifests, unsafe paths and a false release identity never open a playable cache', async () => {
	const f = workerFixture();
	for (const mutate of [
		(r) => { delete r.files['index.pck']; },
		(r) => { r.files['../escape'] = 'a'.repeat(64); },
		(r) => { r.files['index.wasm'] = 'not-a-hash'; },
		(r) => { r.shell = ['index.html']; },
		(r) => { r.files['version.json'] = 'a'.repeat(64); },
	]) {
		const invalid = structuredClone(f.release); mutate(invalid);
		assert.throws(() => createPocketWorker(f.env, invalid), /invalid_release_manifest/);
	}
	const mismatched = createPocketWorker(f.env, {...f.release, id: 'incorrect-but-well-formed'});
	assert.equal(await mismatched.stage(), false);
	assert.equal(f.storage.size, 0);
	assert.deepEqual(f.requests, []);
});

test('completion marker binds the entire manifest and corrupt cached entries are reverified on repair', async () => {
	const f = workerFixture();
	await f.worker.stage();
	const cache = await f.env.caches.open(f.worker.cacheName);
	await cache.put(BASE + '__pocket_complete__', new Response('{truncated'));
	assert.equal(await f.worker.ready(), false);
	await cache.put(BASE + 'index.pck', new Response('corrupt-but-present'));
	f.requests.length = 0;
	assert.equal(await f.worker.stage(), true);
	assert.deepEqual(f.requests.map((url) => url.slice(BASE.length)), ['index.pck']);
	assert.equal(await f.worker.ready(), true);
	await cache.put(BASE + '__pocket_complete__', new Response(JSON.stringify({release: f.release.id, manifestBinding: 'another-manifest'})));
	assert.equal(await f.worker.ready(), false);
	await f.worker.stage();
	await cache.put(BASE + 'index.wasm', new Response('corrupt body with valid metadata', {headers: {'X-Pocket-Content-SHA256': f.release.files['index.wasm']}}));
	const restarted = createPocketWorker(f.env, f.release);
	assert.equal(await restarted.ready(), false);
	assert.equal(await restarted.stage(), true);
	assert.equal(await restarted.ready(), true);
});

test('cold worker restart serves root, install entry, engine, fonts and artwork with no network', async () => {
	const f = workerFixture();
	await f.worker.stage();
	f.offline(true); f.requests.length = 0;
	const cold = createPocketWorker(f.env, f.release);
	assert.equal(await cold.ready(), true);
	for (const entry of ['', 'index.html']) {
		const response = await cold.fetchResponse({request: {url: BASE + entry, method: 'GET', mode: 'navigate'}, resultingClientId: 'cold-' + entry});
		assert.equal(await response.text(), 'shell');
		for (const [name, content] of Object.entries(f.content)) {
			const asset = await cold.fetchResponse({request: new Request(BASE + name + '?offline-check=1'), clientId: 'cold-' + entry});
			assert.equal(await asset.text(), content);
		}
	}
	assert.deepEqual(f.requests, []);
	assert.equal(cold.getTransfer().downloadedBytes, f.worker.getTransfer().downloadedBytes);
});

test('quota failure keeps the predecessor playable and never marks a partial update complete', async () => {
	const f = workerFixture();
	await f.worker.stage();
	const nextRelease = bindRelease({...f.release, revision: 'eeeeeeeeeeee'});
	const nextName = 'pocket-release-' + nextRelease.id;
	const open = f.env.caches.open;
	f.env.caches.open = async (name) => {
		const cache = await open(name);
		return name === nextName ? {...cache, put: async () => { throw new Error('QuotaExceededError'); }} : cache;
	};
	const next = createPocketWorker(f.env, nextRelease);
	assert.equal(await next.stage(), false);
	assert.equal(await next.ready(), false);
	assert.equal(await f.worker.ready(), true);
	assert.equal(f.skipped(), 0);
});

class DetailEvent extends Event { constructor(type, options) { super(type); this.detail = options.detail; } }
class Channel {
	constructor() {
		this.port1 = {onmessage: null, close() {}};
		this.port2 = {postMessage: (data) => queueMicrotask(() => this.port1.onmessage && this.port1.onmessage({data})), close() {}};
	}
}
function browserFixture(options = {}) {
	const host = new EventTarget();
	const sw = new EventTarget();
	const active = new EventTarget();
	const waiting = options.waiting ? new EventTarget() : null;
	const oldInfo = {pocket: 1, ready: true, release: 'old', cache: 'pocket-release-old', revision: 'abcdefabcdef', sourceTreeSha256: 'a'.repeat(64)};
	const nextInfo = {...oldInfo, release: 'new', cache: 'pocket-release-new'};
	const calls = [];
	let reloads = 0;
	const registration = new EventTarget();
	Object.assign(registration, {active, waiting, installing: null, update: async () => { calls.push('check'); }});
	for (const worker of [active, waiting].filter(Boolean)) worker.postMessage = (data, ports) => {
		calls.push(data.type);
		if (!ports) return;
		const info = worker === active ? oldInfo : nextInfo;
		ports[0].postMessage(data.type === 'APPLY' ? {pocket: 1, applied: false} : info);
	};
	sw.controller = options.uncontrolled ? null : active;
	sw.register = options.registerFails ? async () => { throw new Error('blocked'); } : async () => registration;
	if (options.recoverRegistration) sw.getRegistration = async () => registration;
	Object.assign(host, {navigator: {onLine: options.offline !== true, serviceWorker: options.unsupported ? null : sw}, document: Object.assign(new EventTarget(), {visibilityState: 'visible'}), POCKET_RELEASE: {source_revision: oldInfo.revision, source_tree_sha256: oldInfo.sourceTreeSha256}, MessageChannel: Channel, CustomEvent: DetailEvent, setTimeout, clearTimeout, location: {reload() { reloads++; }}});
	if ('persistence' in options) host.navigator.storage = {persisted: async () => false, persist: async () => { calls.push('persist'); return options.persistence; }};
	const api = createPocketUpdates(host);
	const emit = async (data, source = waiting || active) => { const event = new Event('message'); Object.assign(event, {data: {pocket: 1, ...data}, source}); sw.dispatchEvent(event); await pause(); };
	return {host, sw, active, waiting, registration, api, calls, oldInfo, nextInfo, emit, reloads: () => reloads};
}

test('client stays safe-by-default false and never reloads match, paused, or result lifecycle states', async () => {
	for (let lifecycle = 0; lifecycle < 3; lifecycle++) {
		const f = browserFixture({waiting: true});
		await f.api.init({checkTimeout: 20, holdTimeout: 40});
		await f.emit({type: 'PREPARE', nonce: 'n'});
		assert.equal(f.api.isHeld(), false);
		await f.emit({type: 'ACTIVATED', ready: true});
		f.sw.dispatchEvent(new Event('controllerchange'));
		await pause();
		assert.equal(f.reloads(), 0);
	}
});

test('menu hold captures real input; unsafe transition releases hold and suppresses late activation reload', async () => {
	const f = browserFixture({waiting: true});
	await f.api.init({safeToReload: true, checkTimeout: 20, holdTimeout: 100});
	await f.emit({type: 'PREPARE', nonce: 'n'});
	assert.equal(f.api.isHeld(), true);
	let clicks = 0;
	f.host.addEventListener('click', () => { clicks++; });
	const click = new Event('click', {cancelable: true});
	f.host.dispatchEvent(click);
	assert.equal(click.defaultPrevented, true);
	assert.equal(clicks, 0);
	assert.equal(f.api.setSafeToReload(false), false);
	assert.equal(f.api.isHeld(), false);
	await f.emit({type: 'ACTIVATED', ready: true});
	assert.equal(f.reloads(), 0);
	f.host.dispatchEvent(new Event('click'));
	assert.equal(clicks, 1);
});

test('ready activation reloads a held safe menu once, while abort and timeout release input', async () => {
	const f = browserFixture({waiting: true});
	await f.api.init({safeToReload: true, checkTimeout: 20, holdTimeout: 20});
	await f.emit({type: 'PREPARE', nonce: 'a'});
	await f.emit({type: 'ABORT', nonce: 'a'});
	assert.equal(f.api.isHeld(), false);
	await f.emit({type: 'PREPARE', nonce: 'b'});
	await pause(25);
	assert.equal(f.api.isHeld(), false);
	await f.emit({type: 'PREPARE', nonce: 'c'});
	await f.emit({type: 'COMMIT', nonce: 'c'});
	await f.emit({type: 'ACTIVATED', ready: true});
	await f.emit({type: 'ACTIVATED', ready: true});
	assert.equal(f.reloads(), 1);
	f.api.setSafeToReload(false);
});

test('prepare returns coherent prior release when another window blocks a staged update', async () => {
	const f = browserFixture({waiting: true});
	await f.api.init({safeToReload: true, checkTimeout: 20, prepareTimeout: 30});
	const result = await f.api.prepareForPlay();
	assert.equal(result.ready, true);
	assert.equal(result.release, 'old');
	assert.equal(result.pendingUpdate, true);
	assert.equal(f.reloads(), 0);
});

test('offline complete controlled release boots; first complete uncontrolled install reloads before engine', async () => {
	const offline = browserFixture({offline: true});
	await offline.api.init({safeToReload: true, checkTimeout: 20});
	assert.equal((await offline.api.prepareForPlay()).ready, true);
	const first = browserFixture({uncontrolled: true});
	await first.api.init({safeToReload: true, checkTimeout: 20});
	assert.equal((await first.api.prepareForPlay()).ready, false);
	assert.equal(first.reloads(), 1);
});

test('offline registration failure recovers an existing controlled cache; mismatched old page never starts mixed engine', async () => {
	const recovered = browserFixture({registerFails: true, recoverRegistration: true, offline: true});
	await recovered.api.init({safeToReload: true, checkTimeout: 20});
	assert.equal((await recovered.api.prepareForPlay()).ready, true);
	const mixed = browserFixture({waiting: true});
	mixed.host.POCKET_RELEASE.source_revision = 'different';
	await mixed.api.init({safeToReload: true, checkTimeout: 20});
	assert.equal((await mixed.api.prepareForPlay()).ready, false);
});

test('unsupported or permission-blocked service workers permit online direct play, never promise offline readiness', async () => {
	for (const option of [{unsupported: true}, {registerFails: true}]) {
		for (const offline of [false, true]) {
			const f = browserFixture({...option, offline});
			await f.api.init({checkTimeout: 10});
			assert.equal((await f.api.prepareForPlay()).ready, !offline);
		}
	}
});

test('foreground and online return trigger background checks without changing unsafe state', async () => {
	const f = browserFixture();
	await f.api.init({checkTimeout: 20});
	await pause();
	const before = f.calls.filter((call) => call === 'check').length;
	f.host.document.dispatchEvent(new Event('visibilitychange'));
	await pause();
	f.host.dispatchEvent(new Event('online'));
	await pause();
	assert.ok(f.calls.filter((call) => call === 'check').length >= before + 2);
	assert.equal(f.reloads(), 0);
});

test('offline readiness requires a complete controlled release; denied persistence still plays cached Solo', async () => {
	for (const persistence of [false, true]) {
		const f = browserFixture({offline: true, persistence});
		await f.api.init({safeToReload: true, checkTimeout: 20});
		assert.equal((await f.api.prepareForPlay()).ready, true);
		await pause();
		assert.equal(f.api.getStatus().offlineReady, true);
		assert.equal(f.api.getStatus().persistence, persistence ? 'granted' : 'best-effort');
		f.host.dispatchEvent(new Event('offline'));
		assert.equal(f.api.getStatus().state, 'offline');
		assert.equal(f.api.getStatus().offlineReady, true);
		assert.equal(f.reloads(), 0);
	}
	const incomplete = browserFixture({offline: true, persistence: true});
	incomplete.oldInfo.ready = false;
	await incomplete.api.init({safeToReload: true, checkTimeout: 20});
	assert.equal((await incomplete.api.prepareForPlay()).ready, false);
	assert.equal(incomplete.api.getStatus().offlineReady, false);
	assert.equal(incomplete.calls.includes('persist'), false);
});
