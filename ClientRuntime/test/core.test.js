import { expect, test } from "bun:test";

import { BEHAVIOR_NAMES, applyBehavior, parseInvocation } from "../src/behaviors";
import { BINARY_OPS, evalExpr } from "../src/expr";
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
  applyBehavior(parseInvocation("increment#0#2"), cells);
  expect(cells[0].peek()).toBe(2);
  applyBehavior(parseInvocation("toggle#1"), cells);
  expect(cells[1].peek()).toBe(true);
  applyBehavior(parseInvocation("set#2#z"), cells);
  expect(cells[2].peek()).toBe("z");
});

test("the extended behaviors mirror the Swift registry (P4: setFromValue/listMove/commit/removeLast)", () => {
  // setFromValue reads the triggering element's value.
  const q = [new Signal("")];
  applyBehavior(parseInvocation("setFromValue#0"), q, /** @type {any} */ ({ value: "typed" }));
  expect(q[0].peek()).toBe("typed");

  // listMove: index bounded by a live count cell — clamp, then wrap.
  const nav = [new Signal(0), new Signal(3)]; // index=0, count=3
  applyBehavior(parseInvocation("listMove#0#1#1#false"), nav);
  expect(nav[0].peek()).toBe(1);
  applyBehavior(parseInvocation("listMove#0#5#1#false"), nav); // clamps to count-1
  expect(nav[0].peek()).toBe(2);
  applyBehavior(parseInvocation("listMove#0#1#1#true"), nav); // wraps 2->0
  expect(nav[0].peek()).toBe(0);

  // commit: append the query cell's value to the array cell, then clear the query.
  const field = [new Signal(/** @type {string[]} */ ([])), new Signal("apple")]; // tokens, query
  applyBehavior(parseInvocation("commit#0#1"), field);
  expect(field[0].peek()).toEqual(["apple"]);
  expect(field[1].peek()).toBe("");

  // removeLast: pop the last element (no-op on empty).
  const list = [new Signal(["a", "b"])];
  applyBehavior(parseInvocation("removeLast#0"), list);
  expect(list[0].peek()).toEqual(["a"]);
});

test("the behavior-name set is closed and matches Swift Behavior.names (parity)", () => {
  expect([...BEHAVIOR_NAMES]).toEqual([
    "increment", "toggle", "set", "setFromValue", "listMove", "commit", "removeLast",
  ]);
});

test("malformed invocations are rejected", () => {
  expect(parseInvocation("oops")).toBeNull();
  expect(parseInvocation("increment#x")).toBeNull();
});

test("set on a number cell ignores a non-numeric param (failure-safe: no NaN)", () => {
  const cells = [new Signal(5)];
  applyBehavior(parseInvocation("set#0#notanumber"), cells);
  expect(cells[0].peek()).toBe(5);  // unchanged, never NaN
});

test("parseState builds signals and enforces the wire version", () => {
  const state = parseState({
    v: WIRE_VERSION,
    cells: [{ $: "sig", v: 0 }],
    islands: [{ id: "c", on: "load", scope: [0] }],
  });
  expect(state.cells.length).toBe(1);
  expect(state.cells[0].peek()).toBe(0);
  expect(state.islands[0].id).toBe("c");
  expect(() => parseState({ v: 999, cells: [], islands: [] })).toThrow();
});

test("the runtime wire version matches ADHTMLCore.wireFormatVersion (= 1)", () => {
  expect(WIRE_VERSION).toBe(1);
});

test("a cmp cell with an expression recomputes reactively from its deps (no SSE)", () => {
  const state = parseState({
    v: WIRE_VERSION,
    cells: [
      { $: "sig", v: 3 }, // count = 3
      { $: "cmp", v: 6, e: { o: "*", l: { c: 0 }, r: { i: 2 } } }, // doubled = count * 2
    ],
    islands: [],
  });
  expect(state.cells[1].peek()).toBe(6); // server value, re-derived on hydrate
  state.cells[0].set(10); // count changes client-side
  expect(state.cells[1].peek()).toBe(20); // doubled recomputed in-browser, no round-trip
});

test("evalExpr covers each binary op (parity with Swift BinaryOp.rawValue)", () => {
  const cells = [new Signal(7)];
  expect(evalExpr({ o: "+", l: { c: 0 }, r: { i: 3 } }, cells)).toBe(10);
  expect(evalExpr({ o: "-", l: { c: 0 }, r: { i: 3 } }, cells)).toBe(4);
  expect(evalExpr({ o: "*", l: { c: 0 }, r: { i: 3 } }, cells)).toBe(21);
  expect(evalExpr({ o: "++", l: { s: "a" }, r: { s: "b" } }, cells)).toBe("ab");
  expect(evalExpr({ o: "==", l: { c: 0 }, r: { i: 7 } }, cells)).toBe(true);
  expect(evalExpr({ o: "!=", l: { c: 0 }, r: { i: 1 } }, cells)).toBe(true);
  expect(evalExpr({ o: ">", l: { c: 0 }, r: { i: 3 } }, cells)).toBe(true);
  expect(evalExpr({ o: "<=", l: { c: 0 }, r: { i: 7 } }, cells)).toBe(true);
  expect(evalExpr({ o: "&&", l: { b: true }, r: { o: "<", l: { c: 0 }, r: { i: 9 } } }, cells)).toBe(true);
  expect(evalExpr({ o: "||", l: { b: false }, r: { b: false } }, cells)).toBe(false);
  // mirrors Swift BinaryOp.allCases
  expect([...BINARY_OPS]).toEqual(["+", "-", "*", "++", "==", "!=", "<", "<=", ">", ">=", "&&", "||"]);
});
