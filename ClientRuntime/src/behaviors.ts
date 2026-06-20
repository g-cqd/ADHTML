// The closed client-behavior registry (ADR-0005/0009). It MUST mirror the Swift `Behavior` factory
// (set/toggle/increment); a parity test keeps them in sync. Parsing + application are pure (DOM-free)
// and unit-tested. The attribute form is `<name>#<cell>[#param…]`, e.g. `increment#0#1`.

import type { Signal } from "./signals";

export interface Invocation {
  name: string;
  cell: number;
  params: string[];
}

/** Parse a `data-adh-on:<event>` value into an invocation, or `null` if malformed. */
export function parseInvocation(value: string): Invocation | null {
  const parts = value.split("#");
  if (parts.length < 2) return null;
  const cell = Number(parts[1]);
  if (!Number.isInteger(cell)) return null;
  return { name: parts[0]!, cell, params: parts.slice(2) };
}

/** Apply a behavior to its target cell. Unknown behaviors are ignored (forward-compatible). */
export function applyBehavior(inv: Invocation, cells: Array<Signal<unknown>>): void {
  const cell = cells[inv.cell];
  if (!cell) return;
  switch (inv.name) {
    case "increment": {
      const step = Number(inv.params[0] ?? "1") || 1;
      cell.set((cell.peek() as number) + step);
      break;
    }
    case "toggle":
      cell.set(!(cell.peek() as boolean));
      break;
    case "set":
      cell.set(coerce(inv.params[0] ?? "", cell.peek()));
      break;
  }
}

/** Coerce a string param to the cell's current value type (numbers/booleans/strings). */
function coerce(raw: string, like: unknown): unknown {
  if (typeof like === "number") return Number(raw);
  if (typeof like === "boolean") return raw === "true";
  return raw;
}
