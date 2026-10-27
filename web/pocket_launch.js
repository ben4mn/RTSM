(function () {
    'use strict';
    const byId = (id) => document.getElementById(id);
    const welcome = byId('pocket-welcome');
    const app = byId('pocket-app');
    const game = byId('pocket-game');
    const play = byId('pocket-play');
    const install = byId('pocket-install');
    const nativeInstall = byId('pocket-native-install');
    const guide = byId('pocket-install-guide');
    const dialog = byId('pocket-release-dialog');
    const links = byId('pocket-shell-links');
    const releaseOpen = byId('pocket-release-open');
    const releaseClose = byId('pocket-release-close');
    const launchStatus = byId('pocket-launch-status');
    const blocker = byId('pocket-update-blocker');
    const boot = byId('pocket-boot');
    const standalone = window.matchMedia('(display-mode: standalone)');
    let deferredInstall = null;
    let controlsAllowed = false;
    let playing = false;
    let preparing = false;
    let bootResolved = false;
    let engineReady = false;
    let recovery = null;
    let recoveryDismissed = false;
    let held = false;
    let safeWanted = true;
    let installPromptOpen = false;
    let releaseFocus = null;
    let resolveReady;
    const ready = new Promise((resolve) => { resolveReady = resolve; });
    let resumeLaunch = false;
    try { resumeLaunch = sessionStorage.getItem('pocket.launch-after-update') === '1'; sessionStorage.removeItem('pocket.launch-after-update'); } catch (_) { /* private storage may be disabled */ }

    // This describes this window, not whether another installed copy exists.
    function installedWindow() { return navigator.standalone === true || standalone.matches; }
    function showWelcome() {
        document.body.classList.add('pocket-welcome');
        welcome.hidden = false;
        app.inert = true;
        links.hidden = true;
    }
    function showGame() {
        welcome.hidden = true;
        document.body.classList.remove('pocket-welcome');
        app.inert = held;
        window.scrollTo(0, 0);
        window.dispatchEvent(new Event('resize'));
    }
    function selectPlatform(platform) {
        for (const button of document.querySelectorAll('[data-platform]')) {
            button.setAttribute('aria-pressed', String(button.dataset.platform === platform));
        }
        for (const instructions of document.querySelectorAll('[data-instructions]')) {
            instructions.hidden = instructions.dataset.instructions !== platform;
        }
    }
    const apple = /iPhone|iPad|iPod/.test(navigator.userAgent)
        || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
    selectPlatform(apple ? 'apple' : /Android/.test(navigator.userAgent) ? 'android' : 'desktop');
    for (const button of document.querySelectorAll('[data-platform]')) {
        button.addEventListener('click', () => selectPlatform(button.dataset.platform));
    }

    function showInstallGuide() {
        guide.scrollIntoView({behavior: window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth', block: 'start'});
        guide.focus({preventScroll: true});
    }
    function updateSafety() {
        return window.PocketUpdates.setSafeToReload(safeWanted && dialog.hidden && !installPromptOpen
            && !(recovery && !recovery.hidden)
            && !document.body.classList.contains('pocket-report-open'));
    }
    // Browser refresh/back should warn before abandoning an active game. Mobile
    // browsers may omit this prompt, so update controls also enforce safety.
    window.addEventListener('beforeunload', (event) => {
        if (!playing || safeWanted) return;
        event.preventDefault();
        event.returnValue = '';
    });
    // This escape hatch belongs to the browser, not the engine's input loop.
    // It neither claims the game has stopped nor attempts to repair its state.
    function showRuntimeRecovery() {
        if (!engineReady || recoveryDismissed) return;
        if (!recovery) {
            recovery = document.createElement('section');
            recovery.id = 'pocket-runtime-recovery';
            recovery.setAttribute('aria-label', 'Game error recovery');
            const message = document.createElement('p');
            message.setAttribute('role', 'status');
            message.textContent = 'Game reported an error. If controls stop responding, reload.';
            const warning = document.createElement('p');
            warning.className = 'pk-recovery-warning';
            warning.textContent = 'Reloading leaves your current match.';
            const actions = document.createElement('div');
            actions.className = 'pk-recovery-actions';
            function button(text, action) {
                const node = document.createElement('button');
                node.type = 'button'; node.className = 'pocket-button'; node.textContent = text;
                node.addEventListener('click', () => { if (!held) action(); });
                actions.appendChild(node);
            }
            button('Save log', () => {
                try {
                    if (!window.PocketPlaytestDiagnostics.saveLog()) throw new Error('download unavailable');
                    warning.textContent = 'Log download requested. Reloading leaves your current match.';
                } catch (_) {
                    warning.textContent = 'Log download unavailable. Reloading leaves your current match.';
                }
            });
            button('Reload game', () => window.location.reload());
            button('Dismiss', () => {
                recoveryDismissed = true; recovery.hidden = true;
                updateSafety();
            });
            recovery.append(message, warning, actions);
            // Do not take keyboard focus or make the still-running game inert.
            // Once dismissed, later errors remain recorded without nagging again.
            for (const name of ['pointerdown', 'pointerup', 'pointermove', 'pointercancel', 'mousedown', 'mouseup', 'mousemove',
                'touchstart', 'touchmove', 'touchend', 'touchcancel', 'wheel', 'click', 'keydown', 'keyup', 'contextmenu']) {
                recovery.addEventListener(name, event => event.stopPropagation());
            }
            document.body.appendChild(recovery);
        }
        recovery.hidden = false; recovery.inert = held;
        updateSafety();
    }
    window.addEventListener('error', event => {
        // Resource load failures are plain Events, not runtime ErrorEvents.
        if (event instanceof ErrorEvent && typeof event.message === 'string' && event.message.trim()) showRuntimeRecovery();
    });
    window.addEventListener('unhandledrejection', event => {
        if (event.reason instanceof Error) showRuntimeRecovery();
    });
    async function requestInstall() {
        if (!deferredInstall) { showInstallGuide(); return; }
        const prompt = deferredInstall;
        deferredInstall = null;
        nativeInstall.hidden = true;
        installPromptOpen = true;
        updateSafety();
        // prompt() must run directly inside this user gesture, once per event.
        try {
            const result = await prompt.prompt();
            const choice = result || await prompt.userChoice;
            if (!playing) {
                byId('pocket-install-status').textContent = choice && choice.outcome === 'accepted'
                    ? 'Ready when you are. Open the new Pocket Kingdoms icon to play in its own window.'
                    : 'You can install later or keep playing in your browser.';
            }
        } catch (_) {
            if (!playing) { byId('pocket-install-status').textContent = 'Use the steps for your browser below.'; showInstallGuide(); }
        } finally {
            installPromptOpen = false;
            updateSafety();
        }
    }
    window.addEventListener('beforeinstallprompt', (event) => {
        event.preventDefault();
        deferredInstall = event;
        nativeInstall.hidden = false;
    });
    window.addEventListener('appinstalled', () => {
        deferredInstall = null;
        nativeInstall.hidden = true;
        if (!playing) byId('pocket-install-status').textContent = 'Added. Launch Pocket Kingdoms from its new icon for the app experience.';
    });
    install.addEventListener('click', requestInstall);
    nativeInstall.addEventListener('click', requestInstall);

    function closeReleases(focus = true) {
        dialog.hidden = true;
        document.body.classList.remove('pocket-shell-modal');
        game.inert = false;
        updateSafety();
        if (focus && releaseFocus && releaseFocus.isConnected && !links.hidden) releaseFocus.focus();
    }
    function openReleases() {
        if (!controlsAllowed || held) return;
        releaseFocus = document.activeElement;
        dialog.hidden = false;
        document.body.classList.add('pocket-shell-modal');
        game.inert = true;
        updateSafety();
        releaseClose.focus();
    }
    releaseOpen.addEventListener('click', openReleases);
    releaseClose.addEventListener('click', () => closeReleases());
    dialog.addEventListener('keydown', (event) => {
        event.stopPropagation();
        if (event.key === 'Escape') { event.preventDefault(); closeReleases(); }
        if (event.key === 'Tab') {
            const focusable = [...dialog.querySelectorAll('button:not(:disabled), summary, [tabindex="0"]')];
            const index = focusable.indexOf(document.activeElement);
            const next = (index + (event.shiftKey ? -1 : 1) + focusable.length) % focusable.length;
            event.preventDefault();
            focusable[next].focus();
        }
    });
    // Modal scrolling, buttons and keys never enter Godot's input stream.
    for (const element of [dialog, links]) {
        for (const name of ['pointerdown', 'pointerup', 'pointercancel', 'mousedown', 'mouseup', 'touchstart', 'touchend', 'touchcancel', 'wheel', 'click', 'keydown', 'keyup']) {
            element.addEventListener(name, (event) => event.stopPropagation());
        }
    }

    function renderReleases(container, releases) {
        container.replaceChildren();
        for (const release of releases) {
            const article = document.createElement('article'); article.className = 'pk-release';
            const time = document.createElement('time'); time.dateTime = release.date;
            time.textContent = new Date(release.date + 'T12:00:00Z').toLocaleDateString(undefined, {year:'numeric', month:'long', day:'numeric', timeZone:'UTC'}) + (release.version ? ' · ' + release.version : '');
            const title = document.createElement('h3'); title.textContent = release.title;
            const summary = document.createElement('p'); summary.textContent = release.summary;
            const list = document.createElement('ul');
            for (const change of release.changes) { const item = document.createElement('li'); item.textContent = change; list.appendChild(item); }
            article.append(time, title, summary, list); container.appendChild(article);
        }
    }
    fetch('release_notes.json').then((response) => {
        if (!response.ok) throw new Error('notes unavailable');
        return response.json();
    }).then((data) => {
        renderReleases(byId('pocket-release-list'), data.releases);
        renderReleases(byId('pocket-dialog-release-list'), data.releases);
    }).catch(() => {
        for (const id of ['pocket-release-list', 'pocket-dialog-release-list']) byId(id).textContent = 'Release notes are unavailable right now. Reopen online to try again.';
    });
    const release = window.POCKET_RELEASE;
    if (release) {
        byId('pocket-build-label').textContent = 'Early access · ' + release.version;
        byId('pocket-dialog-build').textContent = 'Installed version · ' + release.version;
    }
    const checkButtons = [byId('pocket-update-check'), byId('pocket-dialog-update-check')];
    async function checkUpdates() {
        for (const button of checkButtons) button.disabled = true;
        try { await updatesReady; await window.PocketUpdates.check(); }
        finally { for (const button of checkButtons) button.disabled = false; }
    }
    for (const button of checkButtons) button.addEventListener('click', checkUpdates);
    byId('pocket-refresh').addEventListener('click', async () => {
        if (!safeWanted || held) return;
        closeReleases(false);
        await window.PocketUpdates.refresh();
    });

    const statusCopy = {
        unsupported: 'This browser cannot save offline play. Stay online to play.',
        checking: 'Checking for updates…', downloading: 'Saving game files. Unchanged files are reused…',
        ready: 'Game files saved. Solo is ready offline on this browser.', deferred: 'Update ready. It will apply after open matches return to the main menu.',
        applying: 'Applying the latest release…', offline: 'You’re offline. Connect and choose Play once to save the complete game.',
        error: 'Update check unavailable. Your current version is kept; we’ll try again online.',
        idle: 'Updates are checked automatically when you’re online.'
    };
    window.addEventListener('pocket-update-status', (event) => {
        if (event.detail.state === 'applying' && (playing || preparing)) {
            try { sessionStorage.setItem('pocket.launch-after-update', '1'); } catch (_) { /* reopening welcome remains safe */ }
        }
        let text = event.detail.message || statusCopy[event.detail.state] || '';
        if (event.detail.state === 'ready' && event.detail.pendingUpdate) text = statusCopy.deferred;
        if (event.detail.offlineReady && ['idle', 'offline'].includes(event.detail.state) && !event.detail.message) {
            text = navigator.onLine === false ? 'You’re offline. Solo is ready to play; Online 1v1 needs a connection.' : 'Solo is saved for offline play. Updates download only changed files.';
        }
        if (event.detail.offlineReady && event.detail.persistence === 'best-effort') text += ' Your browser may clear saved files when storage is low.';
        byId('pocket-update-copy').textContent = text;
        byId('pocket-dialog-update-copy').textContent = text + ' Active matches and results stay open.';
        const pending = event.detail.pendingUpdate === true;
        releaseOpen.classList.toggle('pk-update-pending', pending);
        releaseOpen.title = pending ? 'Update ready — open Updates at the main menu' : 'Updates and refresh';
    });
    window.addEventListener('pocket-update-hold', (event) => {
        held = event.detail.held === true;
        blocker.hidden = !held;
        app.inert = held || !playing;
        welcome.inert = held;
        if (recovery) recovery.inert = held;
        if (held) closeReleases(false);
    });

    async function start() {
        if (preparing || bootResolved || held) return;
        preparing = true; play.disabled = true;
        play.textContent = 'Preparing the game…';
        launchStatus.textContent = window.PocketUpdates.getStatus().offlineReady ? 'Opening the saved game…' : 'First launch saves the complete game for offline Solo. Keep this page open for a moment.';
        try {
            await updatesReady;
            const result = await window.PocketUpdates.prepareForPlay();
            if (!result.ready) throw new Error(result.offline ? 'The complete game is not saved yet. Connect and choose Play once, then Solo will work offline.' : 'The game isn’t ready yet. Check your connection, then try again.');
            bootResolved = true; playing = true;
            boot.hidden = false;
            showGame();
            resolveReady();
        } catch (error) {
            showFailure(error.message);
        } finally {
            preparing = false; play.disabled = false;
            if (!bootResolved) play.textContent = 'Play in browser →';
        }
    }
    function showFailure(message) {
        engineReady = false;
        boot.hidden = true;
        playing = false; showWelcome();
        launchStatus.textContent = message;
        // After bootstrap began the engine loader cannot safely be run twice.
        if (bootResolved) { play.textContent = 'Reload and try again'; play.onclick = () => window.location.reload(); }
    }
    play.addEventListener('click', start);
    showWelcome();
    const updatesReady = window.PocketUpdates.init({deferPayload: !installedWindow(), safeToReload: true});
    new MutationObserver(updateSafety).observe(document.body, {attributes:true, attributeFilter:['class']});
    window.PocketLaunch = Object.freeze({
        ready, showFailure,
        engineFinishedLoading() { boot.hidden = true; engineReady = true; },
        setUpdateSafe(safe) { safeWanted = safe === true; return updateSafety(); },
        setControlsVisible(visible) {
            controlsAllowed = visible === true;
            links.hidden = !controlsAllowed || !playing;
            if (!controlsAllowed) closeReleases(false);
        }
    });
    // Installed windows skip the introduction, but first boot may still need
    // a download; keep the explanatory status visible until it is ready.
    if (installedWindow() || resumeLaunch) { showGame(); boot.hidden = false; start(); }
}());
