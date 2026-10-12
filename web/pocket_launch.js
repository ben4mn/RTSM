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
            && !document.body.classList.contains('pocket-report-open'));
    }
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
            event.preventDefault();
            const body = dialog.querySelector('.pk-dialog-body');
            (document.activeElement === releaseClose ? body : releaseClose).focus();
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
    if (release) byId('pocket-build-label').textContent = 'Early access · ' + release.version;

    const statusCopy = {
        unsupported: 'This browser may not support app updates. Reopen online for the latest version.',
        checking: 'Checking for updates…', downloading: 'Preparing the next release…',
        ready: 'Your game files are ready.', deferred: 'Update ready. It will apply after open matches return to the main menu.',
        applying: 'Applying the latest release…', offline: 'You’re offline. Update checks will resume when connected.',
        error: 'Update check unavailable. Your current version is kept; we’ll try again online.',
        idle: 'Updates are checked automatically when you’re online.'
    };
    window.addEventListener('pocket-update-status', (event) => {
        if (event.detail.state === 'applying' && (playing || preparing)) {
            try { sessionStorage.setItem('pocket.launch-after-update', '1'); } catch (_) { /* reopening welcome remains safe */ }
        }
        const text = (event.detail.state === 'deferred' && event.detail.message) || statusCopy[event.detail.state] || event.detail.message || '';
        byId('pocket-update-copy').textContent = text;
        byId('pocket-dialog-update-copy').textContent = text + ' Active matches and results stay open.';
    });
    window.addEventListener('pocket-update-hold', (event) => {
        held = event.detail.held === true;
        blocker.hidden = !held;
        app.inert = held || !playing;
        welcome.inert = held;
        if (held) closeReleases(false);
    });

    async function start() {
        if (preparing || bootResolved || held) return;
        preparing = true; play.disabled = true;
        play.textContent = 'Preparing the game…';
        launchStatus.textContent = 'First launch downloads the game. Keep this page open for a moment.';
        try {
            await updatesReady;
            const result = await window.PocketUpdates.prepareForPlay();
            if (!result.ready) throw new Error('The game isn’t ready yet. Check your connection, then try again.');
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
        engineFinishedLoading() { boot.hidden = true; },
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
