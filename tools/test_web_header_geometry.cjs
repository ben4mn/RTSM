'use strict';
// Source-level DOM model only. No browser, engine, server or pixels are exercised.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const repo = process.argv[2] || path.resolve(__dirname, '..');
const html = fs.readFileSync(path.join(repo, 'web/pocket_shell.html'), 'utf8');
const source = html.match(/<script id="pocket-web-shell-script">([\s\S]*?)<\/script>/)[1];
let checks = 0;
function equal(actual, expected, label) { assert.equal(actual, expected, label); checks++; }
function close(actual, expected, label) { assert(Math.abs(actual - expected) < 0.00001, label); checks++; }
for (const [width, height, logicalWidth, standalone] of [[2560,1234,844,false], [1280,720,844,false], [844,390,734,false], [932,430,810,false], [390,844,390,false], [844,390,734,true]]) {
    const nodes = new Map(), callbacks = new Map();
    function node(id) {
        if (nodes.has(id)) return nodes.get(id);
        const attrs = {}, events = {}, label = {textContent: ''};
        const element = {id, hidden:true, width:0, height:0, textContent:'', title:'', attrs, events,
            style:{setProperty(k,v){this[k]=v;},removeProperty(k){delete this[k];}},
            getBoundingClientRect(){return {left:id==='pocket-app'?13:19,top:id==='pocket-app'?20:27,width,height};},
            addEventListener(k,fn){events[k]=fn;},setAttribute(k,v){attrs[k]=v;},
            querySelector(selector){assert.equal(selector,'[data-shell-label]');return label;},focus(){},
        };
        nodes.set(id,element);return element;
    }
    const document = {getElementById:node,documentElement:{},addEventListener(k,fn){callbacks.set(k,fn);},fullscreenElement:null};
    const window = {document,navigator:{standalone,userAgent:'Fixture'},innerWidth:width,innerHeight:height,devicePixelRatio:2,
        matchMedia(q){return {matches:q==='(display-mode: standalone)' && standalone,addEventListener(){}};},
        addEventListener(k,fn){callbacks.set(k,fn);},requestAnimationFrame(){return 1;},
        getComputedStyle(element){const scale=Number(node('pocket-menu-tools').style['--pocket-tools-scale']||1); return {width:Math.max(48,(width<=680?48:132)*scale)+'px',gap:8*scale+'px',top:'12px',minHeight:'48px',paddingLeft:'0',paddingTop:'0',paddingRight:'0',paddingBottom:'0'};},
        PocketLaunch:{setControlsVisible(){},setUpdateSafe(v){return v;}},
    };
    const context = {window,document,navigator:window.navigator,console};
    vm.runInNewContext(source,context);
    const bridge=window.PocketWebShell, tools=node('pocket-menu-tools'), screen=node('pocket-screen-control');
    const scale=width/logicalWidth;
    const cssWidth=Math.max(48,(width<=680?48:132)*scale)*(standalone?1:2)+(standalone?0:8*scale);
    close(bridge.getMenuHeaderWidth(logicalWidth)*logicalWidth, cssWidth*logicalWidth/width, 'reservation maps into Godot logical viewport');
    close(Number(tools.style['--pocket-tools-scale']),scale,'browser controls use the canvas interface scale');
    const slotLeft=width-cssWidth-80, top=24, gearHeight=standalone?55:48;
    bridge.setMenuHeader([slotLeft/width,top/height,cssWidth/width,gearHeight/height]);
    close(parseFloat(tools.style.left),slotLeft+6,'toolbar uses normalized slot plus app offset');
    close(parseFloat(tools.style.top),top+7,'toolbar shares gear vertical center');
    bridge.engineStarted();bridge.setControlsVisible(true);
    equal(screen.hidden,standalone,'installed display keeps fullscreen visibility contract');
    equal(screen.attrs['aria-label'],'Full screen','fullscreen accessible action preserved');
    equal(screen.querySelector('[data-shell-label]').textContent,'Full screen','icon child survives label update');
    document.fullscreenElement={};callbacks.get('fullscreenchange')();
    equal(screen.hidden,false,'Exit fullscreen remains available in an installed window');
    equal(screen.attrs['aria-label'],'Exit full screen','fullscreen accessible label follows state');
    equal(screen.querySelector('[data-shell-label]').textContent,'Exit full screen','fullscreen state preserves nested icon structure');
    bridge.setMenuHeader([NaN,0,1,1]);
    close(parseFloat(tools.style.left),slotLeft+6,'malformed geometry does not replace valid position');
    bridge.clearMenuHeader();
    for(const property of ['left','top','right','--pocket-tools-height','--pocket-tools-scale']) equal(tools.style[property],undefined,'leaving MainMenu clears '+property);
    bridge.setControlsVisible(false);
    equal(screen.hidden,true,'leaving menu hides fullscreen controls');
    close(bridge.getMenuTopClearance(),68/height,'fallback clearance remains independent of control visibility');
}
console.log(JSON.stringify({scope:'Actual inline shell in a minimal DOM model; no browser/engine/render claim',checks,passed:true}));
