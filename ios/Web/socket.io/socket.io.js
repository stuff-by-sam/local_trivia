'use strict';

/* The Socket.IO client for a game hosted from the Trivia app — served at the
   path where a laptop-hosted game serves the real one, so the same player
   page (public/play) works against both.

   It's the part of socket.io-client the player page uses, and no more:
   io() → one socket to this page's own host, over WebSocket only (the
   phone's server has no long-polling), with on(), emit(), and the 'connect'
   and 'disconnect' events. Engine.IO v4 / Socket.IO v5 framing: 0 open,
   2/3 ping/pong, 40 connect, 41 disconnect, 42 event.

   Like socket.io-client, it reconnects on its own with a jittered backoff,
   buffers emits made while disconnected, and stops when the server says
   goodbye (41) — until the player tries to join again. It also gives up on a socket that's gone silent
   past the server's ping interval + timeout, and reconnects at once when the
   page comes back from a locked screen. */

(function () {
  function io() {
    const url = (location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host +
      '/socket.io/?EIO=4&transport=websocket';
    const handlers = {};
    const buffered = [];
    let ws = null;
    let attached = false;
    let ended = false;
    // Why the last socket closed, in socket.io-client's words.
    let reason = 'transport close';
    let attempts = 0;
    let silence = 45000;
    let watchdog = null;
    let retry = null;

    const fire = (name, data) => (handlers[name] || []).slice().forEach(fn => fn(data));

    function watch() {
      clearTimeout(watchdog);
      watchdog = setTimeout(() => {
        reason = 'ping timeout';
        if (ws) ws.close();
      }, silence);
    }

    function connect() {
      clearTimeout(retry);
      if (ended || ws) return;
      const socket = new WebSocket(url);
      ws = socket;
      socket.onmessage = e => {
        if (typeof e.data !== 'string' || socket !== ws) return;
        watch();
        const type = e.data[0];
        if (type === '0') {
          const open = JSON.parse(e.data.slice(1));
          silence = open.pingInterval + open.pingTimeout;
          socket.send('40');
        } else if (type === '2') {
          socket.send('3');
        } else if (type === '4') {
          packet(e.data.slice(1));
        }
      };
      socket.onclose = () => {
        if (socket !== ws) return;
        ws = null;
        clearTimeout(watchdog);
        const was = attached;
        attached = false;
        if (was) fire('disconnect', reason);
        reason = 'transport close';
        if (ended) return;
        attempts += 1;
        const delay = Math.min(5000, 500 * 2 ** Math.min(attempts - 1, 4));
        retry = setTimeout(connect, delay * (0.5 + Math.random() / 2));
      };
    }

    function packet(p) {
      const type = p[0];
      if (type === '0') {
        attached = true;
        attempts = 0;
        while (buffered.length) ws.send(buffered.shift());
        fire('connect');
      } else if (type === '1') {
        // The server let us go — the host stopped. Don't knock on a closed door.
        ended = true;
        reason = 'io server disconnect';
        if (ws) ws.close();
      } else if (type === '2') {
        // An optional namespace and ack id come before the JSON; neither is used here.
        const body = p.slice(1).replace(/^\/[^,]*,/, '').replace(/^\d+/, '');
        let event;
        try { event = JSON.parse(body); } catch (_) { return; }
        if (Array.isArray(event) && typeof event[0] === 'string') fire(event[0], event[1]);
      } else if (type === '4') {
        fire('connect_error', p.slice(1));
      }
    }

    // A locked phone's socket is often already dead by the time it's back.
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible') connect();
    });

    connect();

    return {
      get connected() { return attached; },
      on(name, fn) {
        (handlers[name] = handlers[name] || []).push(fn);
        return this;
      },
      emit(name, data) {
        const frame = '42' + JSON.stringify(data === undefined ? [name] : [name, data]);
        if (attached && ws && ws.readyState === WebSocket.OPEN) {
          ws.send(frame);
        } else {
          buffered.push(frame);
          // A player joining again after the host stopped — perhaps a new game
          // on the same phone: knock once more.
          if (ended) {
            ended = false;
            connect();
          }
        }
        return this;
      }
    };
  }

  window.io = io;
})();
