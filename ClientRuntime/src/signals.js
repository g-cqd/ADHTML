// Tiny push-pull fine-grained signals (alien-signals/Preact-signals inspired, minimal). An effect
// records the signals it reads; setting a signal re-runs its dependent effects. DOM-free + unit-tested;
// the DOM bindings in runtime.js are just effects that write to a node.
//
// Updates flow through a small synchronous scheduler: a `set` enqueues its subscribers (deduped via a
// per-effect `queued` flag — no per-`set` array copy) and flushes them; effects triggered during the
// flush (a cascade, e.g. a computed reading a changed cell) join the same flush, so each effect runs at
// most once per propagation. Flushing is synchronous (a behavior's DOM update lands before the event
// handler returns), just batched + deduped.

/** @type {Effect | null} */
let active = null;
let flushing = false;
/** @type {Effect[]} */
const pending = [];

/** @param {Effect} effect */
function enqueue(effect) {
  if (effect.queued) return;
  effect.queued = true;
  pending.push(effect);
}

function flush() {
  if (flushing) return;  // a re-entrant set() during a flush just appends to `pending`
  flushing = true;
  try {
    for (let i = 0; i < pending.length; i++) {
      const effect = /** @type {Effect} */ (pending[i]);
      effect.queued = false;
      effect.run();
    }
  } finally {
    pending.length = 0;
    flushing = false;
  }
}

/** A reactive value. @template T */
export class Signal {
  /** @type {Set<Effect>} */
  #subs = new Set();
  /** @type {T} */
  #value;

  /** @param {T} value */
  constructor(value) {
    this.#value = value;
  }

  /** Read the value, recording a dependency on the active effect. @returns {T} */
  get() {
    if (active) {
      this.#subs.add(active);
      active.deps.add(/** @type {Signal<unknown>} */ (this));
    }
    return this.#value;
  }

  /** Read without subscribing. @returns {T} */
  peek() {
    return this.#value;
  }

  /** Set the value; schedules dependent effects (deduped, batched) if it changed. @param {T} value */
  set(value) {
    if (Object.is(value, this.#value)) return;
    this.#value = value;
    for (const effect of this.#subs) enqueue(effect);
    flush();
  }

  /** @internal @param {Effect} effect */
  remove(effect) {
    this.#subs.delete(effect);
  }
}

export class Effect {
  /** @type {Set<Signal<unknown>>} */
  deps = new Set();
  /** @internal — set while this effect is in the scheduler's pending queue (dedup). */
  queued = false;
  /** @type {() => void} */
  #fn;

  /** @param {() => void} fn */
  constructor(fn) {
    this.#fn = fn;
    this.run();
  }

  run() {
    for (const dep of this.deps) dep.remove(this);
    this.deps.clear();
    const previous = active;
    active = this;
    try {
      this.#fn();
    } finally {
      active = previous;
    }
  }
}

/** @param {() => void} fn @returns {Effect} */
export function effect(fn) {
  return new Effect(fn);
}
