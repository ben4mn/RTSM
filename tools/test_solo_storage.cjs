'use strict';
// Transaction tests use fake-indexeddb's IndexedDB implementation, not device emulation.
// npm install --prefix ../save-test-deps --no-audit --no-fund fake-indexeddb@6.2.5
// NODE_PATH=../save-test-deps/node_modules node --test tools/test_solo_storage.cjs
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const {join} = require('node:path');
const vm = require('node:vm');
const {IDBFactory, IDBObjectStore} = require('fake-indexeddb');
const html = readFileSync(join(__dirname, '../web/pocket_shell.html'), 'utf8');
const source = html.match(/<script id="pocket-solo-storage-script">([\s\S]*?)<\/script>/)[1];

function fixture(indexedDB = new IDBFactory(), timeout = 500) {
    const events = [];
    const w = {indexedDB, setTimeout, clearTimeout, Event, dispatchEvent:e=>events.push(e.type)};
    const context = vm.createContext({window:w});
    vm.runInContext(source.replace('createPocketSoloStorage(window);', `createPocketSoloStorage(window, ${timeout});`), context);
    return {api:w.PocketSoloStorage, indexedDB, events};
}
const write = (f, value, backup = '') => new Promise(resolve=>f.api.write(value,backup,(...r)=>resolve(r)));
const clear = f => new Promise(resolve=>f.api.clear((...r)=>resolve(r)));
async function rawRecord(factory, key) {
    return new Promise((resolve,reject)=> {
        const request=factory.open('pocket-kingdoms-solo-v1',1);
        request.onerror=()=>reject(request.error);
        request.onsuccess=()=> {
            const db=request.result, tx=db.transaction('slots');
            const get=tx.objectStore('slots').get(key);
            tx.oncomplete=()=>{db.close();resolve(get.result);};
            tx.onabort=()=>reject(tx.error);
        };
    });
}

test('save callback waits for committed bytes; a new app instance loads current and previous good slot',async()=>{
    const f=fixture(); assert.equal(await f.api.ready,true);
    assert.equal(f.api.read(),'');
    const pending=write(f,'first-match');
    assert.equal(f.api.isBusy(),true);
    assert.equal(f.api.read(),'');
    assert.equal((await pending)[0],true);
    assert.equal((await rawRecord(f.indexedDB,'current')).payload,'first-match');
    assert.equal(f.api.isBusy(),false);
    assert.equal((await write(f,'second-match','first-match'))[0],true);
    const reopened=fixture(f.indexedDB); await reopened.api.ready;
    assert.equal(reopened.api.read(),'second-match');
    assert.equal(reopened.api.readBackup(),'first-match');
    assert.equal(f.events.length,4);
});

test('serialized autosave then exit preserves write ordering and callbacks',async()=>{
    const f=fixture(); await f.api.ready;
    const results=await Promise.all([write(f,'autosave'),write(f,'exit','autosave')]);
    assert.deepEqual(results,[[true,''],[true,'']]);
    assert.equal(f.api.read(),'exit'); assert.equal(f.api.readBackup(),'autosave');
    assert.equal(f.api.isBusy(),false);
});

test('quota failure rolls back both slots and keeps last committed match',async()=>{
    const f=fixture(); await f.api.ready; await write(f,'good','older');
    const original=IDBObjectStore.prototype.put;
    IDBObjectStore.prototype.put=function(value,key) {
        if(key==='backup') throw new DOMException('Full','QuotaExceededError');
        return original.call(this,value,key);
    };
    let result;
    try {result=await write(f,'bad','good');} finally {IDBObjectStore.prototype.put=original;}
    assert.equal(result[0],false); assert.match(result[1],/previous save is kept/);
    const reopened=fixture(f.indexedDB); await reopened.api.ready;
    assert.equal(reopened.api.read(),'good'); assert.equal(reopened.api.readBackup(),'older');
    assert.equal(f.api.isBusy(),false);
});

test('stale second window cannot overwrite or resurrect a cleared match',async()=>{
    const f=fixture(); await f.api.ready; await write(f,'before');
    const stale=fixture(f.indexedDB); await stale.api.ready;
    assert.equal((await clear(f))[0],true);
    const result=await write(stale,'resurrected','before');
    assert.equal(result[0],false); assert.match(result[1],/another window/);
    const reopened=fixture(f.indexedDB); await reopened.api.ready;
    assert.equal(reopened.api.read(),''); assert.equal(reopened.api.readBackup(),'');
});

test('invalid/oversize payload cannot replace valid save; recovered backup can become primary',async()=>{
    const f=fixture(); await f.api.ready; await write(f,'valid','backup-valid');
    assert.equal((await write(f,''))[0],false);
    assert.equal((await write(f,'x'.repeat(8*1024*1024+1)))[0],false);
    assert.equal(f.api.read(),'valid');
    // The Godot checksum validator chooses the prior good payload, not the corrupt primary.
    assert.equal((await write(f,'recovered-new','backup-valid'))[0],true);
    assert.equal(f.api.readBackup(),'backup-valid');
});

test('blocked or unavailable storage reports failure without claiming a save',async()=>{
    for(const storage of [null,{open(){throw new DOMException('Denied','SecurityError');}}]) {
        const f=fixture(storage); assert.equal(await f.api.ready,false);
        const result=await write(f,'match');
        assert.equal(result[0],false); assert.match(result[1],/unavailable/);
        assert.equal(f.api.read(),''); assert.equal(f.api.isBusy(),false);
    }
});

test('a stalled open times out and does not hang game startup',async()=>{
    const f=fixture({open:()=>({})},15);
    assert.equal(await f.api.ready,false);
    assert.match(f.api.error(),/too long/);
    assert.equal((await write(f,'match'))[0],false);
});

test('detached engine callback cannot break following queued writes',async()=>{
    const f=fixture(); await f.api.ready;
    f.api.write('first','',()=>{throw new Error('engine closed');});
    assert.equal((await write(f,'second','first'))[0],true);
    assert.equal(f.api.read(),'second'); assert.equal(f.api.isBusy(),false);
});
