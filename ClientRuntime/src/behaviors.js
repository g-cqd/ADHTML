// The closed client-behavior registry (ADR-0005/0009). It MUST mirror the Swift `Behavior` factory
// (set/toggle/increment); a parity test keeps them in sync. Parsing + application are pure (DOM-free)
// and unit-tested. The attribute form is `<token>#<cell>[#param…]`, e.g. `a#0#1` (a = increment).

import { B } from "./tokens";

/**
 * @typedef {object} Invocation
 * @property {string} name
 * @property {number} cell
 * @property {string[]} params
 */

/** The closed behavior-name set, mirrored by Swift `Behavior.names` (parity test). Not referenced by the
 * interpreter (the switch lists them inline), so the bundler tree-shakes it out of the runtime — it exists
 * for the parity test only. @type {readonly string[]} */
export const BEHAVIOR_NAMES = Object.values(B);

/** Parse a `data-adh-on:<event>` value into an invocation, or `null` if malformed.
 * @param {string} value
 * @returns {Invocation | null} */
export function parseInvocation(value) {
  const parts = value.split("#");
  if (parts.length < 2) return null;
  const cell = Number(parts[1]);
  if (!Number.isInteger(cell)) return null;
  return { name: /** @type {string} */ (parts[0]), cell, params: parts.slice(2) };
}

/** Apply a behavior to its target cell. Unknown behaviors are ignored (forward-compatible). `node` is the
 * triggering element (for value-reading behaviors); optional, since most behaviors need only the cell.
 * @param {Invocation} inv
 * @param {Array<import("./signals").Signal<unknown>>} cells
 * @param {Element} [node]
 * @returns {void} */
export function applyBehavior(inv, cells, node) {
  const cell = cells[inv.cell];
  if (!cell) return;
  switch (inv.name) {
    case B.increment: {
      const step = Number(inv.params[0] ?? "1") || 1;
      cell.set(/** @type {number} */ (cell.peek()) + step);
      break;
    }
    case B.toggle:
      cell.set(!(/** @type {boolean} */ (cell.peek())));
      break;
    case B.set:
      cell.set(coerce(inv.params[0] ?? "", cell.peek()));
      break;
    // --- P4: the extended vocabulary (mirrors Swift `Behavior`; parity-tested) ---
    case B.setFromValue:
      cell.set(/** @type {HTMLInputElement | undefined} */ (node)?.value ?? "");
      break;
    case B.listMove: {
      const delta = Number(inv.params[0]) || 0;
      const count = Number(cells[Number(inv.params[1])]?.peek() ?? 0);
      if (count > 0) {
        let next = /** @type {number} */ (cell.peek()) + delta;
        next =
          inv.params[2] === "true"
            ? ((next % count) + count) % count  // wrap
            : Math.max(0, Math.min(count - 1, next));  // clamp
        cell.set(next);
      }
      break;
    }
    case B.commit: {
      const query = cells[Number(inv.params[0])];
      const value = String(query?.peek() ?? "");
      if (value) {
        cell.set([.../** @type {unknown[]} */ (cell.peek()), value]);
        query?.set("");
      }
      break;
    }
    case B.removeLast: {
      // Skip while typing (the input still has text) so Backspace deletes a char, not a chip.
      if (/** @type {HTMLInputElement | undefined} */ (node)?.value) break;
      const list = /** @type {unknown[]} */ (cell.peek());
      if (list.length) cell.set(list.slice(0, -1));
      break;
    }
    case B.commitValue: {
      const text = node?.textContent?.trim();  // a clicked suggestion's text
      if (text) {
        cell.set([.../** @type {unknown[]} */ (cell.peek()), text]);
        cells[Number(inv.params[0])]?.set("");  // clear the query
      }
      break;
    }
  }
}

/** Coerce a string param to the cell's current value type (numbers/booleans/strings). Failure-safe:
 * a non-finite number keeps the current value rather than setting NaN/Infinity.
 * @param {string} raw
 * @param {unknown} like
 * @returns {unknown} */
function coerce(raw, like) {
  if (typeof like === "number") {
    const n = Number(raw);
    return Number.isFinite(n) ? n : like;
  }
  if (typeof like === "boolean") return raw === "true";
  return raw;
}
