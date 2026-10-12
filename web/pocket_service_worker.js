/* A release is cached only after every response matches its packaged hash. */
'use strict';
const POCKET_SW_RELEASE = /*POCKET_SW_RELEASE*/null;

function createPocketWorker(env, release, options = {}) {
	const PREFIX = 'pocket-release-';
	const cacheName = PREFIX + release.id;
	const base = new URL('./', env.registration.scope);
	const completeKey = new URL('__pocket_complete__', base).href;
	const bindingsKey = new URL('__pocket_bindings__', base).href;
	const clientCacheName = 'pocket-client-bindings-v1';
	const timeout = options.handshakeTimeout || 2500;
	let staging = null;
	let applying = null;
	let bindings = null;
	const replies = new Map();
	const absolute = (name) => new URL(name, base).href;
	const windows = async () => (await env.clients.matchAll({type: 'window', includeUncontrolled: true}))
		.filter((client) => client.url.startsWith(base.href));
	const tell = (client, data) => client.postMessage(Object.assign({pocket: 1, release: release.id}, data));
	const broadcast = async (data) => { for (const client of await windows()) tell(client, data); };
	const hash = async (bytes) => Array.from(new Uint8Array(await env.crypto.subtle.digest('SHA-256', bytes)))
		.map((byte) => byte.toString(16).padStart(2, '0')).join('');
	function isolate(response) {
		const headers = new Headers(response.headers);
		headers.set('Cross-Origin-Opener-Policy', 'same-origin');
		headers.set('Cross-Origin-Embedder-Policy', 'require-corp');
		return new Response(response.body, {status: response.status, statusText: response.statusText, headers});
	}
	async function verifiedFetch(name) {
		const response = await env.fetch(absolute(name), {cache: 'no-store', credentials: 'same-origin', redirect: 'error'});
		if (!response.ok || response.type === 'opaque') throw new Error('download_failed');
		if (await hash(await response.clone().arrayBuffer()) !== release.files[name]) throw new Error('release_changed');
		return isolate(response);
	}
	async function cacheFiles(names) {
		const cache = await env.caches.open(cacheName);
		// A bounded queue avoids fetching several engine packs at once on a phone.
		let next = 0;
		await Promise.all(Array.from({length: Math.min(2, names.length)}, async () => {
			while (next < names.length) {
				const name = names[next++];
				if (!await cache.match(absolute(name))) await cache.put(absolute(name), await verifiedFetch(name));
			}
		}));
		return cache;
	}
	async function ready() {
		const cache = await env.caches.open(cacheName);
		const marker = await cache.match(completeKey);
		if (!marker) return false;
		// Cache eviction must not turn a previous completion marker into a promise.
		for (const name of Object.keys(release.files)) if (!await cache.match(absolute(name))) return false;
		return true;
	}
	async function stage() {
		if (staging) return staging;
		staging = (async () => {
			await broadcast({type: 'STATUS', state: 'downloading'});
			const cache = await cacheFiles(Object.keys(release.files));
			await cache.put(completeKey, new Response(JSON.stringify({release: release.id})));
			await broadcast({type: 'STATUS', state: 'ready'});
			return true;
		})().catch(async (error) => {
			await broadcast({type: 'STATUS', state: 'error', message: error.message});
			return false;
		}).finally(() => { staging = null; });
		return staging;
	}
	async function loadBindings() {
		if (bindings) return bindings;
		const cache = await env.caches.open(cacheName);
		const response = await cache.match(bindingsKey);
		bindings = response ? await response.json() : {};
		return bindings;
	}
	async function saveBindings(value) {
		bindings = value;
		await (await env.caches.open(cacheName)).put(bindingsKey, new Response(JSON.stringify(value)));
	}
	async function bindClient(id, cache) {
		if (!id) return;
		// Independent keys avoid lost updates between an old worker completing a
		// navigation and its successor activating at the same time.
		await (await env.caches.open(clientCacheName)).put(absolute('__pocket_client__/' + encodeURIComponent(id)), new Response(JSON.stringify({cache})));
	}
	async function clientBinding(id) {
		if (!id) return null;
		const response = await (await env.caches.open(clientCacheName)).match(absolute('__pocket_client__/' + encodeURIComponent(id)));
		if (!response) return null;
		const value = await response.json();
		return typeof value.cache === 'string' && value.cache.startsWith(PREFIX) ? value.cache : null;
	}
	function question(client, type, nonce) {
		return new Promise((resolve) => {
			const key = nonce + ':' + type + ':' + client.id;
			const timer = env.setTimeout(() => { replies.delete(key); resolve(null); }, timeout);
			replies.set(key, (answer) => { env.clearTimeout(timer); replies.delete(key); resolve(answer); });
			tell(client, {type, nonce});
		});
	}
	async function unchangedClients(original) {
		const current = (await windows()).map((client) => client.id).sort();
		return JSON.stringify(current) === JSON.stringify(original.map((client) => client.id).sort());
	}
	async function apply() {
		if (applying) return applying;
		applying = (async () => {
			if (!await ready()) return false;
			const clients = await windows();
			if (!clients.length) return false; // Natural lifecycle handles next launch.
			const nonce = release.id + ':' + env.crypto.randomUUID();
			let committed = false;
			try {
				const prepared = await Promise.all(clients.map((client) => question(client, 'PREPARE', nonce)));
				if (prepared.some((answer) => !answer || !answer.safe) || !await unchangedClients(clients)) return false;
				const confirmed = await Promise.all(clients.map((client) => question(client, 'COMMIT', nonce)));
				if (confirmed.some((answer) => !answer || !answer.safe) || !await unchangedClients(clients)) return false;
				const knownCaches = new Set(await env.caches.keys());
				const saved = await loadBindings();
				for (let i = 0; i < clients.length; i++) {
					const oldCache = prepared[i].cache;
					// Late requests from a page still running its old engine stay coherent,
					// even if its already-queued Start input arrives after the handshake.
					if (typeof oldCache === 'string' && oldCache.startsWith(PREFIX) && knownCaches.has(oldCache)) {
						saved[clients[i].id] = oldCache;
						await bindClient(clients[i].id, oldCache);
					}
				}
				await saveBindings(saved);
				await broadcast({type: 'STATUS', state: 'applying'});
				if (!await unchangedClients(clients)) return false;
				await env.skipWaiting();
				committed = true;
				return true;
			} finally {
				if (!committed) await broadcast({type: 'ABORT', nonce, state: 'deferred'});
			}
		})().finally(() => { applying = null; });
		return applying;
	}
	async function message(event) {
		const data = event.data;
		if (!data || data.pocket !== 1 || !event.source || !event.source.id) return;
		const client = await env.clients.get(event.source.id);
		if (!client || !client.url.startsWith(base.href)) return;
		if (data.type === 'ANSWER') {
			const resolve = replies.get(data.nonce + ':' + data.phase + ':' + client.id);
			if (resolve) resolve({safe: data.safe === true, cache: data.cache});
			return;
		}
		const respond = (extra) => {
			const payload = Object.assign({pocket: 1, release: release.id, cache: cacheName, revision: release.revision, sourceTreeSha256: release.sourceTreeSha256}, extra);
			if (event.ports && event.ports[0]) event.ports[0].postMessage(payload);
			else tell(client, payload);
		};
		if (data.type === 'STATUS') respond({ready: await ready()});
		else if (data.type === 'STAGE') respond({ready: await stage()});
		else if (data.type === 'APPLY') respond({applied: await apply()});
		else if (data.type === 'UNSAFE') {
			// This also rejects an answer that is still pending in either phase.
			for (const [key, resolve] of replies) if (key.endsWith(':' + client.id)) resolve({safe: false});
		}
		// Deliberately ignore Godot's old 'claim', 'clear' and 'update' commands.
	}
	async function fetchResponse(event) {
		const url = new URL(event.request.url);
		if (!url.href.startsWith(base.href) || event.request.method !== 'GET') return env.fetch(event.request);
		let name;
		try { name = decodeURIComponent(url.pathname.slice(base.pathname.length)) || 'index.html'; }
		catch (_) { return new Response('Invalid URL', {status: 400}); }
		// Diagnostics must compare loaded metadata with the real server, not cache.
		if (name === 'version.json' || name.startsWith('api/')) return env.fetch(event.request, {cache: 'no-store'});
		const navigation = event.request.mode === 'navigate';
		const old = !navigation && (await clientBinding(event.clientId) || (await loadBindings())[event.clientId]);
		// A window can appear after the final cohort check while skipWaiting is
		// pending. Never guess its release. Modern predecessor workers record the
		// navigation below; an unacknowledged legacy page fails closed instead of
		// receiving a different engine. Its normal reload establishes a binding.
		if (!navigation && event.clientId && !old) return new Response('Reload from the menu to finish updating this window.', {status: 503});
		const cache = await env.caches.open(old || cacheName);
		const cached = await cache.match(absolute(name));
		const forClient = async (response) => {
			if (navigation) await bindClient(event.resultingClientId || event.clientId, cacheName);
			return response;
		};
		if (cached) return forClient(isolate(cached));
		if (old && old !== cacheName) return new Response('The previous release is no longer cached. Reload from the menu.', {status: 503});
		if (!Object.prototype.hasOwnProperty.call(release.files, name)) return env.fetch(event.request);
		try {
			const response = await verifiedFetch(name);
			await cache.put(absolute(name), response.clone());
			return forClient(response);
		} catch (_) {
			if (event.request.mode === 'navigate') {
				const offline = await cache.match(absolute('index.offline.html'));
				if (offline) return forClient(isolate(offline));
			}
			return new Response('This release is not completely available. Retry when online.', {status: 503});
		}
	}
	async function activate() {
		// No clients.claim(): unknown/legacy windows must never be forcibly adopted.
		// Keep predecessor caches for old client bindings; quota failures leave the
		// current complete release usable rather than deleting it to stage an update.
		await loadBindings();
		await broadcast({type: 'ACTIVATED', ready: await ready()});
	}
	async function install() {
		// A waiting worker can activate naturally once the last old window closes.
		// It therefore must already be complete before replacing an existing app,
		// even if the next launch is offline. First visits download only the shell.
		if (env.registration.active) {
			if (!await stage()) throw new Error('Update payload could not be verified');
		} else await cacheFiles(release.shell);
	}
	function installListeners() {
		env.addEventListener('install', (event) => event.waitUntil(install()));
		env.addEventListener('activate', (event) => event.waitUntil(activate()));
		env.addEventListener('message', (event) => event.waitUntil(message(event)));
		env.addEventListener('fetch', (event) => event.respondWith(fetchResponse(event)));
	}
	return {installListeners, install, stage, ready, apply, message, fetchResponse, activate, cacheName};
}

if (typeof module === 'object' && module.exports) module.exports = {createPocketWorker};
else createPocketWorker(self, POCKET_SW_RELEASE).installListeners();
