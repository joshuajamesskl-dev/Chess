// public/stockfish-worker.js
// This file is served statically and loaded as a Web Worker.
// It proxies messages between the main thread and Stockfish WASM.
//
// Stockfish is loaded from the npm CDN — swap the importScripts URL
// for a self-hosted copy if you need offline support.

let engine = null;

function initEngine() {
  try {
    // Try loading Stockfish from jsDelivr (fast, reliable, same major version as npm pkg)
    importScripts('https://cdn.jsdelivr.net/npm/stockfish@16.0.0/src/stockfish-nnue-16.js');
    engine = Stockfish();
    engine.onmessage = function (line) {
      self.postMessage(line);
    };
    engine.postMessage('uci');
    engine.postMessage('isready');
  } catch (e) {
    // Fallback: try the non-NNUE version (smaller, faster to load)
    try {
      importScripts('https://cdn.jsdelivr.net/npm/stockfish@16.0.0/src/stockfish.js');
      engine = Stockfish();
      engine.onmessage = function (line) {
        self.postMessage(line);
      };
      engine.postMessage('uci');
      engine.postMessage('isready');
    } catch (e2) {
      self.postMessage('error: failed to load Stockfish — ' + e2.message);
    }
  }
}

self.onmessage = function (e) {
  const msg = e.data;
  if (!engine) {
    initEngine();
    return;
  }
  engine.postMessage(msg);
};

// Auto-init on load
initEngine();
