import { expect, test } from "bun:test";

import { applyBehavior, parseInvocation } from "../src/behaviors";
import { Signal, effect } from "../src/signals";
import { WIRE_VERSION, parseState } from "../src/wire";

test("an effect re-runs when a signal it read changes", () => {
  const count = new Signal(0);
  let seen = -1;
  effect(() => {
    seen = count.get();
  });
  expect(seen).toBe(0);
  count.set(5);
  expect(seen).toBe(5);
});

test("an effect drops dependencies it no longer reads (dynamic deps)", () => {
  const useA = new Signal(true);
  const a = new Signal("a");
  const b = new Signal("b");
  let seen = "";
  effect(() => {
    seen = useA.get() ? a.get() : b.get();
  });
  expect(seen).toBe("a");
  useA.set(false);
  expect(seen).toBe("b");
  a.set("a2");  // no longer a dependency
  expect(seen).toBe("b");
  b.set("b2");
  expect(seen).toBe("b2");
});

test("behaviors mirror the Swift registry (increment/toggle/set)", () => {
  const cells = [new Signal(0), new Signal(false), new Signal("a")];
  applyBehavior(parseInvocation("increment#0#2")!, cells);
  expect(cells[0]!.peek()).toBe(2);
  applyBehavior(parseInvocation("toggle#1")!, cells);
  expect(cells[1]!.peek()).toBe(true);
  applyBehavior(parseInvocation("set#2#z")!, cells);
  expect(cells[2]!.peek()).toBe("z");
});

test("malformed invocations are rejected", () => {
  expect(parseInvocation("oops")).toBeNull();
  expect(parseInvocation("increment#x")).toBeNull();
});

test("parseState builds signals and enforces the wire version", () => {
  const state = parseState({
    v: WIRE_VERSION,
    cells: [{ $: "sig", v: 0 }],
    islands: [{ id: "c", on: "load", scope: [0] }],
  });
  expect(state.cells.length).toBe(1);
  expect(state.cells[0]!.peek()).toBe(0);
  expect(state.islands[0]!.id).toBe("c");
  expect(() => parseState({ v: 999, cells: [], islands: [] })).toThrow();
});

test("the runtime wire version matches ADHTMLCore.wireFormatVersion (= 1)", () => {
  expect(WIRE_VERSION).toBe(1);
});
