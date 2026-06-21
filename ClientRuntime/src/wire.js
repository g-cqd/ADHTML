// Parse the inline hydration state (`<script type="application/adh-state+json">`, RFC-0003/ADR-0007)
// into client signals. Cells are positional: index === the ref used by bindings/scope/deps. A `sig`
// becomes a Signal; a `cmp` (computed) becomes a Signal seeded with the server-evaluated value — and, if
// it carries an `e` formula (built from the Swift `Reactive` DSL), an effect that RECOMPUTES it from its
// dependency cells in-browser (no server round-trip). A `cmp` without `e` (opaque Swift closure) stays
// server-updated via SSE patch. The runtime's WIRE_VERSION must match `ADHTMLCore.wireFormatVersion`.

import { evalExpr } from "./expr";
import { Signal, effect } from "./signals";

export const WIRE_VERSION = 1;

/**
 * @typedef {object} IslandSpec
 * @property {string} id
 * @property {string} on
 * @property {number[]} scope
 */

/**
 * @typedef {object} WireState
 * @property {Signal<unknown>[]} cells
 * @property {IslandSpec[]} islands
 * @property {(region: Element) => void} [rewire] Re-wire a server-swapped region (set by runtime.js
 *   `hydrate`); the action layer calls it after a swap so morphed-in islands/bindings resume.
 */

/**
 * @typedef {object} RawCell
 * @property {string} $
 * @property {unknown} v
 * @property {import("./expr").WireExprJSON} [e]
 */

/**
 * @typedef {object} RawPayload
 * @property {number} v
 * @property {RawCell[]} cells
 * @property {IslandSpec[]} [islands]
 */

/** @param {unknown} json @returns {WireState} */
export function parseState(json) {
  const payload = /** @type {RawPayload} */ (json);
  if (payload.v !== WIRE_VERSION) {
    throw new Error(`adh: unsupported wire version ${payload.v} (runtime expects ${WIRE_VERSION})`);
  }
  const rawCells = payload.cells ?? [];
  const cells = rawCells.map((cell) => new Signal(cell.v));
  // Wire client-recomputable computeds: an effect re-evaluates the formula from its dep cells, so the
  // derived cell tracks them reactively (all signals exist first; cells are in topological order).
  for (let i = 0; i < rawCells.length; i++) {
    const formula = rawCells[i]?.e;
    const target = cells[i];
    if (formula && target) {
      effect(() => target.set(evalExpr(formula, cells)));
    }
  }
  return { cells, islands: payload.islands ?? [] };
}

/** Read + parse the inline state block, or `null` if the page has none / it is malformed or an
 * unsupported version. Failure-safe: a bad block degrades to a static page instead of throwing.
 * @param {Document} [doc] @returns {WireState | null} */
export function readState(doc = document) {
  const element = doc.getElementById("adh-state");
  if (!element) return null;
  try {
    return parseState(JSON.parse(element.textContent ?? "{}"));
  } catch {
    return null;
  }
}
