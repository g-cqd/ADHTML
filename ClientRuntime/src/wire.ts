// Parse the inline hydration state (`<script type="application/adh-state+json">`, RFC-0003/ADR-0007)
// into client signals. Cells are positional: index === the ref used by bindings/scope/deps. A `sig`
// becomes a Signal; a `cmp` (computed) becomes a Signal seeded with the server-evaluated value — and, if
// it carries an `e` formula (built from the Swift `Reactive` DSL), an effect that RECOMPUTES it from its
// dependency cells in-browser (no server round-trip). A `cmp` without `e` (opaque Swift closure) stays
// server-updated via SSE patch. The runtime's WIRE_VERSION must match `ADHTMLCore.wireFormatVersion`.

import { type WireExprJSON, evalExpr } from "./expr";
import { Signal, effect } from "./signals";

export const WIRE_VERSION = 1;

export interface IslandSpec {
  id: string;
  on: string;
  scope: number[];
}

export interface WireState {
  cells: Signal<unknown>[];
  islands: IslandSpec[];
}

interface RawCell {
  $: string;
  v: unknown;
  e?: WireExprJSON;
}

interface RawPayload {
  v: number;
  cells: RawCell[];
  islands?: IslandSpec[];
}

export function parseState(json: unknown): WireState {
  const payload = json as RawPayload;
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
 * unsupported version. Failure-safe: a bad block degrades to a static page instead of throwing. */
export function readState(doc: Document = document): WireState | null {
  const element = doc.getElementById("adh-state");
  if (!element) return null;
  try {
    return parseState(JSON.parse(element.textContent ?? "{}"));
  } catch {
    return null;
  }
}
