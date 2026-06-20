// Tiny push-pull fine-grained signals (alien-signals/Preact-signals inspired, minimal). An effect
// records the signals it reads; setting a signal re-runs its dependent effects. DOM-free + unit-tested;
// the DOM bindings in runtime.ts are just effects that write to a node.
//
// Updates flow through a small synchronous scheduler: a `set` enqueues its subscribers (deduped via a
// per-effect `queued` flag — no per-`set` array copy) and flushes them; effects triggered during the
// flush (a cascade, e.g. a computed reading a changed cell) join the same flush, so each effect runs at
// most once per propagation. Flushing is synchronous (a behavior's DOM update lands before the event
// handler returns), just batched + deduped.

let active: Effect | null = null;
let flushing = false;
const pending: Effect[] = [];

function enqueue(effect: Effect): void {
  if (effect.queued) return;
  effect.queued = true;
  pending.push(effect);
}

function flush(): void {
  if (flushing) return;  // a re-entrant set() during a flush just appends to `pending`
  flushing = true;
  try {
    for (let i = 0; i < pending.length; i++) {
      const effect = pending[i]!;
      effect.queued = false;
      effect.run();
    }
  } finally {
    pending.length = 0;
    flushing = false;
  }
}

export class Signal<T> {
  #subs = new Set<Effect>();
  #value: T;

  constructor(value: T) {
    this.#value = value;
  }

  /** Read the value, recording a dependency on the active effect. */
  get(): T {
    if (active) {
      this.#subs.add(active);
      active.deps.add(this as Signal<unknown>);
    }
    return this.#value;
  }

  /** Read without subscribing. */
  peek(): T {
    return this.#value;
  }

  /** Set the value; schedules dependent effects (deduped, batched) if it changed. */
  set(value: T): void {
    if (Object.is(value, this.#value)) return;
    this.#value = value;
    for (const effect of this.#subs) enqueue(effect);
    flush();
  }

  /** @internal */
  remove(effect: Effect): void {
    this.#subs.delete(effect);
  }
}

export class Effect {
  deps = new Set<Signal<unknown>>();
  /** @internal — set while this effect is in the scheduler's pending queue (dedup). */
  queued = false;
  #fn: () => void;

  constructor(fn: () => void) {
    this.#fn = fn;
    this.run();
  }

  run(): void {
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

export function effect(fn: () => void): Effect {
  return new Effect(fn);
}
