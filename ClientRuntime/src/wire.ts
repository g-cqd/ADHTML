// Parse the inline hydration state (`<script type="application/adh-state+json">`, RFC-0003/ADR-0007)
// into client signals. Cells are positional: index === the ref used by bindings/scope/deps. A `sig`
// becomes a Signal; a `cmp` (computed) also becomes a Signal seeded with the server-evaluated value —
// the client cannot recompute a Swift formula (it isn't serialized), so computed cells are
// server-updated (via SSE patch) rather than client-recomputed. The runtime's WIRE_VERSION must match
// the server's `ADHTMLCore.wireFormatVersion`.

import { Signal } from "./signals";

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

interface RawPayload {
  v: number;
  cells: Array<{ $: string; v: unknown }>;
  islands?: IslandSpec[];
}

export function parseState(json: unknown): WireState {
  const payload = json as RawPayload;
  if (payload.v !== WIRE_VERSION) {
    throw new Error(`adh: unsupported wire version ${payload.v} (runtime expects ${WIRE_VERSION})`);
  }
  const cells = (payload.cells ?? []).map((cell) => new Signal(cell.v));
  return { cells, islands: payload.islands ?? [] };
}

/** Read + parse the inline state block, or `null` if the page has none. */
export function readState(doc: Document = document): WireState | null {
  const element = doc.getElementById("adh-state");
  if (!element) return null;
  return parseState(JSON.parse(element.textContent ?? "{}"));
}
