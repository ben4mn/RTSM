/* Test-only instrumentation. Inject before the actual Web game loads.
 * Captures the game's existing output graph; does not unlock AudioContext,
 * touch autoplay policy, synthesize cues, or request a microphone.
 * await page.evaluate(() => PocketAudioCapture.finish()) returns playable
 * WebM/Opus blobs as base64 plus signal levels and AudioContext state events.
 * A recording/level measurement does not establish human listening quality.
 */
(() => {
  'use strict';
  if (!window.AudioNode || window.PocketAudioCapture) return;
  const connect = AudioNode.prototype.connect;
  const disconnect = AudioNode.prototype.disconnect;
  const graph = new Map();
  const ids = new Map();
  const id = node => { if (!ids.has(node)) ids.set(node, ids.size); return ids.get(node); };
  const captures = new Map();
  const events = [];
  const at = () => Math.round(performance.now());
  let timer;
  function capture(context) {
    if (captures.has(context)) return captures.get(context);
    if (!context.createMediaStreamDestination) return null;
    const analyser = context.createAnalyser();
    analyser.fftSize = 2048;
    const destination = context.createMediaStreamDestination();
    connect.call(analyser, destination);
    const mimeType = MediaRecorder.isTypeSupported('audio/webm;codecs=opus')
      ? 'audio/webm;codecs=opus' : '';
    const recorder = new MediaRecorder(destination.stream, mimeType ? {mimeType} : {});
    const result = {analyser, recorder, chunks: [], levels: [], states: [],
      buffer: new Float32Array(analyser.fftSize)};
    const state = () => result.states.push({at: at(), state: context.state});
    state();
    context.addEventListener('statechange', state);
    recorder.addEventListener('dataavailable', event => {
      if (event.data.size) result.chunks.push(event.data);
    });
    recorder.start(1000);
    captures.set(context, result);
    events.push({at: at(), event: 'game_audio_destination_connected'});
    return result;
  }
  AudioNode.prototype.connect = function(destination, ...args) {
    const result = connect.call(this, destination, ...args);
    if (!graph.has(this)) graph.set(this, new Set());
    graph.get(this).add(destination);
    id(this); id(destination);
    if (destination === this.context.destination) {
      const entry = capture(this.context);
      if (entry) connect.call(this, entry.analyser);
    }
    return result;
  };
  AudioNode.prototype.disconnect = function(...args) {
    const result = disconnect.apply(this, args);
    if (args.length === 0) graph.set(this, new Set());
    else if (graph.has(this) && args[0] instanceof AudioNode) graph.get(this).delete(args[0]);
    return result;
  };
  timer = setInterval(() => {
    for (const entry of captures.values()) {
      entry.analyser.getFloatTimeDomainData(entry.buffer);
      let square = 0, peak = 0;
      for (const value of entry.buffer) {
        square += value * value;
        peak = Math.max(peak, Math.abs(value));
      }
      entry.levels.push({at: at(), rms: Math.sqrt(square / entry.buffer.length), peak});
    }
  }, 50);
  const mark = event => events.push({at: at(), event});
  document.addEventListener('pointerdown', () => mark('pointerdown'), true);
  document.addEventListener('visibilitychange', () => mark(document.hidden ? 'hidden' : 'visible'));
  window.PocketAudioCapture = {
    mark,
    graph: () => [...graph].map(([node, destinations]) => ({id:id(node), type:node.constructor.name, gain:node.gain?.value, targets:[...destinations].map(n=>({id:id(n),type:n.constructor.name}))})),
    snapshot: () => ({events: events.slice(), contexts: [...captures.values()].map(entry => ({
      states: entry.states.slice(), levels: entry.levels.slice(), mimeType: entry.recorder.mimeType
    }))}),
    finish: async () => {
      clearInterval(timer);
      const recordings = [];
      for (const entry of captures.values()) {
        if (entry.recorder.state !== 'inactive') {
          await new Promise(resolve => {
            entry.recorder.addEventListener('stop', resolve, {once: true});
            entry.recorder.stop();
          });
        }
        const blob = new Blob(entry.chunks, {type: entry.recorder.mimeType});
        const dataUrl = await new Promise(resolve => {
          const reader = new FileReader(); reader.onload = () => resolve(reader.result);
          reader.readAsDataURL(blob);
        });
        recordings.push({mimeType: blob.type, bytes: blob.size, dataUrl,
          states: entry.states, levels: entry.levels});
      }
      return {events, recordings};
    }
  };
})();
