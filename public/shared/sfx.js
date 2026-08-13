'use strict';

// Synthesized Web Audio sounds — no audio files. Master volume ~0.6; each tone:
// 12 ms linear attack to peak gain, exponential decay to silence.
// The AudioContext unlocks on the first user gesture.
const SFX = (() => {
  const VOL = 0.6;
  let ac = null;
  let enabled = true;

  function unlock() {
    try {
      if (!ac) ac = new (window.AudioContext || window.webkitAudioContext)();
      if (ac.state === 'suspended') ac.resume();
    } catch (e) { /* no audio available */ }
  }
  window.addEventListener('pointerdown', unlock, { passive: true });
  window.addEventListener('keydown', unlock);

  function tone(freq, delay, dur, type, gain) {
    if (!ac) return;
    try {
      const o = ac.createOscillator();
      const v = ac.createGain();
      o.type = type || 'square';
      o.frequency.value = freq;
      const t = ac.currentTime + delay;
      v.gain.setValueAtTime(0.0001, t);
      v.gain.linearRampToValueAtTime(gain * VOL, t + 0.012);
      v.gain.exponentialRampToValueAtTime(0.0001, t + dur);
      o.connect(v);
      v.connect(ac.destination);
      o.start(t);
      o.stop(t + dur + 0.05);
    } catch (e) { /* ignore */ }
  }

  const recipes = {
    tick: () => tone(1100, 0, 0.04, 'square', 0.03),
    blip: () => tone(1500, 0, 0.06, 'square', 0.035),
    join: () => { tone(700, 0, 0.06, 'triangle', 0.06); tone(1050, 0.07, 0.09, 'triangle', 0.06); },
    qstart: () => [440, 660, 880].forEach((f, i) => tone(f, i * 0.08, 0.09, 'square', 0.05)),
    reveal: () => [523, 659, 784, 1046].forEach((f, i) => tone(f, i * 0.09, 0.14, 'square', 0.055)),
    lb: () => [880, 990, 1100, 1320].forEach((f, i) => tone(f, i * 0.05, 0.06, 'triangle', 0.05)),
    fanfare: () => [523, 523, 659, 784, 1046, 1318].forEach((f, i) => tone(f, i * 0.12, 0.2, 'square', 0.055))
  };

  return {
    play(name) { if (enabled && recipes[name]) { unlock(); recipes[name](); } },
    setEnabled(v) { enabled = !!v; }
  };
})();
