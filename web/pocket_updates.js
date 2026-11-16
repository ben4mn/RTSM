(function (root, factory) {
	'use strict';
	if (typeof module === 'object' && module.exports) module.exports = factory;
	else root.PocketUpdates = factory(root);
})(typeof window !== 'undefined' ? window : globalThis, function createPocketUpdates(host) {
	'use strict';
	const sw = host.navigator && host.navigator.serviceWorker;
	let registration = null;
	let initialized = null;
	let safe = false;
	let wanted = false;
	let held = null;
	let holdTimer = null;
	let currentCache = null;
	let currentRelease = null;
	let preparing = false;
	let checking = null;
	let applying = false;
	let reloading = false;
	let offlineReady = false;
	let persistence = 'unavailable';
	let persistenceRequested = false;
	let status = {state: 'idle', release: null, message: ''};
	let settings = {checkTimeout: 3000, prepareTimeout: 30000, holdTimeout: 10000};
	const events = ['pointerdown', 'pointerup', 'touchstart', 'touchend', 'mousedown', 'mouseup', 'click', 'keydown', 'keyup', 'wheel'];
	const emit = (name, detail) => host.dispatchEvent(new host.CustomEvent(name, {detail}));
	function update(state, data = {}) {
		status = {state, release: data.release || status.release, message: data.message || '', pendingUpdate: !!(registration && registration.waiting), offlineReady, persistence, transfer: data.transfer || status.transfer || null};
		emit('pocket-update-status', Object.assign({}, status));
	}
	function block(event) {
		if (!held) return;
		if (event.cancelable) event.preventDefault();
		event.stopImmediatePropagation();
	}
	function releaseHold() {
		if (holdTimer) host.clearTimeout(holdTimer);
		holdTimer = null;
		held = null;
		for (const type of events) host.removeEventListener(type, block, true);
		emit('pocket-update-hold', {held: false});
	}
	function acquireHold(nonce) {
		if (held && held !== nonce) return false;
		held = nonce;
		for (const type of events) host.addEventListener(type, block, {capture: true, passive: false});
		if (holdTimer) host.clearTimeout(holdTimer);
		holdTimer = host.setTimeout(() => { releaseHold(); update('deferred', {message: 'Update will apply from the menu or next launch.'}); }, settings.holdTimeout);
		emit('pocket-update-hold', {held: true});
		return true;
	}
	const bounded = (promise, ms, fallback = null) => new Promise((resolve) => {
		const timer = host.setTimeout(() => resolve(fallback), ms);
		Promise.resolve(promise).then((value) => { host.clearTimeout(timer); resolve(value); }, () => { host.clearTimeout(timer); resolve(fallback); });
	});
	function rpc(worker, type, ms = settings.checkTimeout) {
		if (!worker) return Promise.resolve(null);
		return new Promise((resolve) => {
			const channel = new host.MessageChannel();
			let settled = false;
			const finish = (value) => { if (settled) return; settled = true; host.clearTimeout(timer); channel.port1.close(); resolve(value); };
			const timer = host.setTimeout(() => finish(null), ms);
			channel.port1.onmessage = (event) => finish(event.data && event.data.pocket === 1 ? event.data : null);
			try { worker.postMessage({pocket: 1, type}, [channel.port2]); } catch (_) { finish(null); }
		});
	}
	function trusted(worker) {
		return worker && registration && [registration.active, registration.waiting, registration.installing, sw.controller].includes(worker);
	}
	function reload() {
		if (!safe || reloading) return false;
		reloading = true;
		update('applying');
		host.location.reload();
		return true;
	}
	async function activeStatus() {
		const worker = sw.controller || (registration && registration.active);
		const info = await rpc(worker, 'STATUS');
		if (info && !currentCache) { currentCache = info.cache; currentRelease = info.release; }
		return info;
	}
	function pageMatches(info) {
		const page = host.POCKET_RELEASE;
		return !!info && (!page || (page.source_revision === info.revision && page.source_tree_sha256 === info.sourceTreeSha256));
	}
	function playable(info) {
		return !!(info && info.ready && sw.controller && pageMatches(info));
	}
	async function preserveOfflineCache() {
		if (!offlineReady || persistenceRequested) return;
		persistenceRequested = true;
		const storage = host.navigator.storage;
		if (!storage || typeof storage.persist !== 'function') return;
		// Best effort only: denial must never prevent cached Solo play. The browser
		// can still remove nonpersistent storage under pressure or on user request.
		try {
			const already = typeof storage.persisted === 'function' && await storage.persisted();
			persistence = already || await storage.persist() ? 'granted' : 'best-effort';
		} catch (_) { persistence = 'best-effort'; }
		update(status.state, status);
	}
	async function maybeApply() {
		if (!registration || !safe || applying || reloading) return false;
		const worker = registration.waiting;
		if (!worker) return false;
		const info = await rpc(worker, 'STATUS');
		if (!info || !info.ready) return false;
		applying = true;
		try {
			const applied = await rpc(worker, 'APPLY', settings.holdTimeout);
			if (!applied || !applied.applied) update('deferred', {release: info.release, message: 'Another game window is busy. Update will wait.'});
			return !!(applied && applied.applied);
		} finally { applying = false; }
	}
	async function observeWaiting() {
		if (!registration || !registration.waiting) return;
		const waiting = registration.waiting;
		let info = await rpc(waiting, 'STATUS');
		if (wanted && info && !info.ready) info = await rpc(waiting, 'STAGE', settings.prepareTimeout);
		if (info && info.ready) {
			update('ready', {release: info.release});
			await maybeApply();
		} else if (info && !wanted) {
			update('deferred', {release: info.release, message: 'An update will download when you play.'});
		}
	}
	async function onMessage(event) {
		const data = event.data;
		if (!data || data.pocket !== 1 || !trusted(event.source)) return;
		if (data.type === 'PREPARE' || data.type === 'COMMIT') {
			const allowed = safe && !reloading && (data.type === 'PREPARE' ? acquireHold(data.nonce) : held === data.nonce);
			event.source.postMessage({pocket: 1, type: 'ANSWER', phase: data.type, nonce: data.nonce, safe: allowed, cache: currentCache});
			return;
		}
		if (data.type === 'ABORT') {
			if (held === data.nonce) releaseHold();
			update('deferred', data);
		} else if (data.type === 'ACTIVATED') {
			// Never reload a result or match, even when a start contact queued before
			// the handshake reached the engine after the browser input hold began.
			if (data.ready && held && safe) reload();
			else { releaseHold(); if (data.ready) update('ready', data); }
		} else if (data.type === 'STATUS') {
			update(data.state, data);
			if (data.state === 'ready' && !preparing) maybeApply();
		}
	}
	function monitor(worker) {
		if (!worker) return;
		worker.addEventListener('statechange', () => {
			if (worker.state === 'installed') observeWaiting();
		});
	}
	function check() {
		if (checking) return checking;
		checking = (async () => {
			if (!registration) return status;
			if (host.navigator.onLine === false) { update('offline'); return status; }
			update('checking');
			const checked = await bounded(Promise.resolve(registration.update()).then(() => true), settings.checkTimeout, false);
			if (!checked) { update('error', {message: 'Could not reach the update service. Your current game is kept. Try again when connected.'}); return status; }
			monitor(registration.installing);
			await observeWaiting();
			if (status.state === 'checking') update('idle', {message: 'You have the latest available version.'});
			return status;
		})().catch(() => { update('error', {message: 'Update check unavailable; the current game is unchanged.'}); return status; })
			.finally(() => { checking = null; });
		return checking;
	}
	function init(options = {}) {
		if (initialized) return initialized;
		settings = Object.assign(settings, options);
		safe = options.safeToReload === true;
		wanted = options.deferPayload === false;
		initialized = (async () => {
			if (!sw) { update('unsupported'); return status; }
			sw.addEventListener('message', onMessage);
			registration = await bounded(sw.register('index.service.worker.js', {scope: './', updateViaCache: 'none'}), settings.checkTimeout);
			// Registration can fail while an installed controller/cache still works
			// offline. Recover the existing registration before choosing direct play.
			if (!registration && typeof sw.getRegistration === 'function') registration = await bounded(sw.getRegistration(), settings.checkTimeout);
			if (!registration) { update('offline', {message: 'Update service unavailable.'}); return status; }
			registration.addEventListener('updatefound', () => monitor(registration.installing));
			monitor(registration.installing);
			const active = await activeStatus();
			offlineReady = playable(active);
			host.addEventListener('online', check);
			host.addEventListener('offline', () => update('offline'));
			host.addEventListener('pageshow', check);
			host.document.addEventListener('visibilitychange', () => { if (host.document.visibilityState === 'visible') check(); });
			sw.addEventListener('controllerchange', async () => {
				const info = await rpc(sw.controller, 'STATUS');
				if (held && safe && info && info.ready) reload();
			});
			check();
			return status;
		})();
		return initialized;
	}
	async function prepareForPlay() {
		if (!initialized) await init(); else await initialized;
		if (sw && !registration) { initialized = null; await init(settings); }
		if (!sw || !registration) return {ready: host.navigator.onLine !== false, release: currentRelease, offline: host.navigator.onLine === false, pendingUpdate: false};
		wanted = true;
		preparing = true;
		try {
			await bounded(check(), settings.checkTimeout);
			// A first installation may still be fetching its small welcome shell.
			await bounded(new Promise((resolve) => {
				if (!registration.installing) { resolve(); return; }
				const worker = registration.installing;
				worker.addEventListener('statechange', () => { if (['installed', 'activated', 'redundant'].includes(worker.state)) resolve(); });
			}), settings.checkTimeout);
			const target = registration.waiting || registration.active;
			let info = await rpc(target, 'STATUS');
			if (info && !info.ready) info = await rpc(target, 'STAGE', settings.prepareTimeout);
			if (info && info.ready && target === registration.waiting) {
				await maybeApply();
				if (held || reloading) return {ready: false, release: info.release, pendingUpdate: true};
				const old = await activeStatus();
				return {ready: playable(old), release: old && old.release, offline: host.navigator.onLine === false, pendingUpdate: true};
			}
			if (info && info.ready) {
				if (!sw.controller || !pageMatches(info)) {
					update('ready', info);
					reload();
					return {ready: false, release: info.release, pendingUpdate: true};
				}
				currentCache = info.cache;
				currentRelease = info.release;
				offlineReady = true;
				update('ready', info);
				preserveOfflineCache();
				return {ready: !held && !reloading, release: info.release, offline: host.navigator.onLine === false, pendingUpdate: false};
			}
			const old = await activeStatus();
			offlineReady = playable(old);
			update(host.navigator.onLine === false ? 'offline' : 'error', {message: 'Could not finish downloading. The previous complete game is kept.'});
			return {ready: playable(old), release: old && old.release, offline: host.navigator.onLine === false, pendingUpdate: !!registration.waiting};
		} finally { preparing = false; }
	}
	function setSafeToReload(value) {
		const wasHeld = !!held;
		safe = value === true;
		settings.safeToReload = safe;
		if (!safe) {
			try { if (registration && registration.waiting) registration.waiting.postMessage({pocket: 1, type: 'UNSAFE'}); }
			catch (_) { /* A worker that became redundant cannot commit a hold. */ }
			releaseHold();
		} else {
			maybeApply();
			// A new worker may already be active while this page deliberately kept
			// its old match/result. Its own safe menu can now reload independently.
			if (registration && registration.active && currentRelease) rpc(registration.active, 'STATUS').then((info) => {
				if (info && info.ready && info.release !== currentRelease && safe) reload();
			});
		}
		return !wasHeld;
	}
	async function refresh() {
		// An explicit refresh uses the same safety gate as an automatic update.
		// A match may have started while the network check was in flight.
		if (!safe || held || reloading) return false;
		await check();
		if (!safe || held || reloading || ['error', 'offline'].includes(status.state)) return false;
		if (registration && registration.waiting) return maybeApply();
		return reload();
	}
	return Object.freeze({init, check, refresh, prepareForPlay, setSafeToReload, isHeld: () => !!held, getStatus: () => Object.assign({}, status)});
});
