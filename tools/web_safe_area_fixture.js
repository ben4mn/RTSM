/* Run against the source-controlled shell in a real browser, not a DOM mock. */
window.PocketSafeAreaFixture = (() => {
    'use strict';
    const app = document.getElementById('pocket-app');
    const game = document.getElementById('pocket-game');
    const canvas = document.getElementById('canvas');
    const near = (a, b) => Math.abs(a - b) <= 0.05;
    const frame = () => new Promise(resolve => requestAnimationFrame(resolve));
    const settle = async () => { for (let i = 0; i < 5; i++) await frame(); };
    const require = (value, label) => { if (!value) throw new Error(label); };
    const rect = element => {
        const r = element.getBoundingClientRect();
        return {x: r.x, y: r.y, width: r.width, height: r.height};
    };
    function applyInsets(values) {
        ['left', 'top', 'right', 'bottom'].forEach((side, i) => {
            document.documentElement.style.setProperty(`--pocket-safe-${side}`, `${values[i]}px`);
        });
    }
    function checkCoverage(label) {
        const a = rect(app), g = rect(game), c = rect(canvas);
        const v = window.visualViewport;
        const expected = {x: v?.offsetLeft || 0, y: v?.offsetTop || 0,
            width: v?.width || innerWidth, height: v?.height || innerHeight};
        for (const box of [a, g, c]) for (const key of Object.keys(expected)) {
            require(near(box[key], expected[key]), `${label}: full-bleed ${key} ${box[key]} != ${expected[key]}`);
        }
        require(canvas.width === Math.round(c.width * devicePixelRatio), `${label}: backing width counts full canvas once`);
        require(canvas.height === Math.round(c.height * devicePixelRatio), `${label}: backing height counts full canvas once`);
        return {app: a, game: g, canvas: c, backing: [canvas.width, canvas.height], dpr: devicePixelRatio};
    }
    function checkInsets(values, label) {
        const c = rect(canvas), actual = window.PocketWebShell.getSafeArea();
        require(Array.isArray(actual) && actual.length === 4, `${label}: four normalized safe fractions`);
        const expected = [values[0] / c.width, values[1] / c.height, values[2] / c.width, values[3] / c.height];
        actual.forEach((n, i) => require(Math.abs(n - expected[i]) < 0.00001, `${label}: inset ${i} ${n} != ${expected[i]}`));
        // Mutating a caller's copy must not poison the shared bridge state.
        actual[0] = 99;
        require(Math.abs(window.PocketWebShell.getSafeArea()[0] - expected[0]) < 0.00001, `${label}: caller cannot mutate shared safe fractions`);
        return expected;
    }
    function checkHtmlControls(values, label) {
        const c = rect(canvas);
        const bounds = {left: c.x + values[0], top: c.y + values[1],
            right: c.x + c.width - values[2], bottom: c.y + c.height - values[3]};
        const inside = (element, name) => {
            const r = element.getBoundingClientRect();
            require(r.left >= bounds.left - 0.1 && r.top >= bounds.top - 0.1
                && r.right <= bounds.right + 0.1 && r.bottom <= bounds.bottom + 0.1,
                `${label}: ${name} stays inside the safe controls rectangle`);
        };
        window.PocketWebShell.setControlsVisible(false);
        const hiddenClearance = window.PocketWebShell.getMenuTopClearance();
        require(Number.isFinite(hiddenClearance) && hiddenClearance > 0 && hiddenClearance < 1,
            `${label}: hidden toolbar has a finite normalized menu clearance`);
        window.PocketWebShell.engineStarted();
        window.PocketWebShell.setControlsVisible(true);
        const visibleClearance = window.PocketWebShell.getMenuTopClearance();
        require(near(hiddenClearance, visibleClearance), `${label}: menu can reserve toolbar space before it becomes visible`);
        const clearancePixels = visibleClearance * c.height;
        let toolbarBottom = 0;
        for (const id of ['pocket-screen-control', 'pocket-release-open']) {
            const element = document.getElementById(id);
            inside(element, id);
            const target = element.getBoundingClientRect();
            require(target.height >= 48 && target.width >= 48, `${label}: ${id} preserves 48px physical touch targets`);
            toolbarBottom = Math.max(toolbarBottom, target.bottom - c.y);
            require(clearancePixels >= target.bottom - c.y + 8 - 0.1,
                `${label}: menu clearance protects the real ${id} bottom plus 8px`);
        }
        require(near(clearancePixels, toolbarBottom + 8), `${label}: menu clearance applies viewport/DPR and safe top exactly once`);
        for (const [overlayId, cardSelector] of [
            ['pocket-screen-help', '.pocket-help-card'],
            ['pocket-release-dialog', '.pk-dialog-card'],
        ]) {
            const overlay = document.getElementById(overlayId);
            overlay.hidden = false;
            inside(overlay.querySelector(cardSelector), cardSelector);
            overlay.hidden = true;
        }
        window.PocketPlaytestDiagnostics.openReport({});
        const report = document.getElementById('pocket-report');
        inside(report.querySelector('.pocket-report-card'), 'report card');
        for (const field of report.querySelectorAll('input, textarea, button')) {
            const target = field.getBoundingClientRect();
            require(target.height >= 48 && target.width >= 48, `${label}: report field preserves 48px touch size`);
        }
        report.hidden = true;
        document.body.classList.remove('pocket-report-open');
        window.PocketWebShell.setControlsVisible(false);
        return {menuTopClearance: visibleClearance, clearancePixels, toolbarBottom};
    }
    function paintReceipt() {
        const ctx = canvas.getContext('2d');
        const dpr = devicePixelRatio, c = rect(canvas);
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        ctx.fillStyle = '#6e9c94'; ctx.fillRect(0, 0, c.width, c.height);
        ctx.strokeStyle = '#a9c7bb'; ctx.lineWidth = 1;
        for (let x = -c.height; x < c.width; x += 40) {
            ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x + c.height, c.height); ctx.stroke();
        }
        const [l, t, r, b] = window.PocketWebShell.getSafeArea();
        const safe = {x: l * c.width, y: t * c.height, w: (1 - l - r) * c.width, h: (1 - t - b) * c.height};
        ctx.strokeStyle = '#e8e5db'; ctx.lineWidth = 2;
        ctx.strokeRect(safe.x, safe.y, safe.w, safe.h);
        ctx.fillStyle = '#171c1d'; ctx.font = '16px Barlow, sans-serif';
        ctx.fillText('SHELL GEOMETRY FIXTURE — full-bleed canvas; outlined safe controls region', safe.x + 14, safe.y + 30);
        ctx.font = '13px Barlow, sans-serif';
        ctx.fillText(`${c.width}×${c.height} CSS · DPR ${dpr} · safe ${Math.round(safe.w)}×${Math.round(safe.h)}`, safe.x + 14, safe.y + 52);
        for (const [x, y] of [[safe.x + 12, safe.y + 70], [safe.x + safe.w - 60, safe.y + safe.h - 60]]) {
            ctx.fillStyle = '#171c1d'; ctx.fillRect(x, y, 48, 48);
            ctx.fillStyle = '#e8e5db'; ctx.fillText('48px', x + 8, y + 29);
        }
    }
    async function run() {
        require(window.PocketWebShell?.getSafeArea, 'safe-area bridge exists');
        require(window.PocketWebShell?.getMenuTopClearance, 'menu toolbar clearance bridge exists');
        require(document.getElementById('pocket-safe-area'), 'CSS environment probe exists');
        const results = [];
        let notifications = 0;
        const listener = () => { notifications++; };
        window.PocketWebShell.addSafeAreaListener(listener);
        applyInsets([0, 0, 0, 0]);
        window.dispatchEvent(new Event('resize'));
        await settle();
        const unnotchedControls = checkHtmlControls([0, 0, 0, 0], 'unnotched');
        results.push({label: 'unnotched', ...checkCoverage('unnotched'), insets: checkInsets([0, 0, 0, 0], 'unnotched'), htmlControls: unnotchedControls});
        const dimensions = [canvas.width, canvas.height];
        for (const [label, values] of [
            ['left cutout', [53, 0, 24, 21]],
            ['reversed cutout', [24, 0, 53, 21]],
            ['second reversal', [53, 0, 24, 21]],
            ['top and bottom', [0, 24, 0, 18]],
        ]) {
            const before = notifications;
            applyInsets(values);
            // Real left/right orientation reversal sends orientationchange
            // even when width, height and total horizontal inset are unchanged.
            if (label.includes('revers')) window.dispatchEvent(new Event('orientationchange'));
            await settle();
            require(notifications > before, `${label}: safe-only CSS change notifies Godot`);
            require(canvas.width === dimensions[0] && canvas.height === dimensions[1], `${label}: safe area does not resize backing buffer`);
            const htmlControls = checkHtmlControls(values, label);
            results.push({label, ...checkCoverage(label), insets: checkInsets(values, label), notifications, htmlControls});
        }
        const unchanged = notifications;
        window.dispatchEvent(new Event('resize'));
        await settle();
        require(notifications === unchanged, 'unchanged resize does not send duplicate safe-area updates');
        window.PocketWebShell.removeSafeAreaListener(listener);
        applyInsets([53, 0, 24, 21]);
        await settle();
        require(notifications === unchanged, 'removed listener receives no later updates');
        checkCoverage('after listener removal');
        checkInsets([53, 0, 24, 21], 'after listener removal');
        paintReceipt();
        const report = {passed: true, cases: results, listenerLifecycle: 'passed', userAgent: navigator.userAgent};
        window.PocketSafeAreaFixture.result = report;
        return report;
    }
    return {run, result: null};
})();
