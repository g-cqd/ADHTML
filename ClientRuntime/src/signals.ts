// Tiny push-pull fine-grained signals (alien-signals/Preact-signals inspired, minimal). An effect
// records the signals it reads; setting a signal re-runs its dependent effects. DOM-free + unit-tested;
// the DOM bindings in runtime.ts are just effects that write to a node.

let active: Effect | null = null;

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

  /** Set the value; re-runs dependent effects if it changed. */
  set(value: T): void {
    if (Object.is(value, this.#value)) return;
    this.#value = value;
    for (const effect of [...this.#subs]) effect.run();
  }

  /** @internal */
  remove(effect: Effect): void {
    this.#subs.delete(effect);
  }
}

export class Effect {
  deps = new Set<Signal<unknown>>();
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
