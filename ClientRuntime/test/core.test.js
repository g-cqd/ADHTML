import { expect, test } from "bun:test";

import { BEHAVIOR_NAMES, applyBehavior, parseInvocation } from "../src/behaviors";
import { BINARY_OPS, UNARY_OPS, evalExpr, highlight } from "../src/expr";
import { Signal, effect } from "../src/signals";
import { B, S, T } from "../src/tokens";
import { WIRE_VERSION, parseState } from "../src/wire";
import spec from "../../wire-tokens.json";

test("tokens.js mirrors wire-tokens.json (generated Swift-side, no drift)", () => {
  // The generator prefixes the attribute category (T) with `data-` (valid HTML5); values (B/S) stay bare.
  const map = (pairs, prefix = "") => Object.fromEntries(pairs.map(([n, t]) => [n, prefix + t]));
  expect(T).toEqual(map(spec.tokens, "data-"));
  expect(B).toEqual(map(spec.behaviors));
  expect(S).toEqual(map(spec.swaps));
  expect(Object.values(T).every((t) => /^data-[a-z0-9]$/.test(t))).toBe(true); // data- + 1 char
  expect([...Object.values(B), ...Object.values(S)].every((t) => t.length === 1)).toBe(true); // bare values
});

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
  applyBehavior(parseInvocation("a#0#2"), cells);
  expect(cells[0].peek()).toBe(2);
  applyBehavior(parseInvocation("b#1"), cells);
  expect(cells[1].peek()).toBe(true);
  applyBehavior(parseInvocation("c#2#z"), cells);
  expect(cells[2].peek()).toBe("z");
});

test("the extended behaviors mirror the Swift registry (P4: setFromValue/listMove/commit/removeLast)", () => {
  // setFromValue reads the triggering element's value.
  const q = [new Signal("")];
  applyBehavior(parseInvocation("d#0"), q, /** @type {any} */ ({ value: "typed" }));
  expect(q[0].peek()).toBe("typed");

  // listMove: index bounded by a live count cell — clamp, then wrap.
  const nav = [new Signal(0), new Signal(3)]; // index=0, count=3
  applyBehavior(parseInvocation("e#0#1#1#false"), nav);
  expect(nav[0].peek()).toBe(1);
  applyBehavior(parseInvocation("e#0#5#1#false"), nav); // clamps to count-1
  expect(nav[0].peek()).toBe(2);
  applyBehavior(parseInvocation("e#0#1#1#true"), nav); // wraps 2->0
  expect(nav[0].peek()).toBe(0);

  // commit: append the query cell's value to the array cell, then clear the query.
  const field = [new Signal(/** @type {string[]} */ ([])), new Signal("apple")]; // tokens, query
  applyBehavior(parseInvocation("f#0#1"), field);
  expect(field[0].peek()).toEqual(["apple"]);
  expect(field[1].peek()).toBe("");

  // removeLast: pop the last element (no-op on empty).
  const list = [new Signal(["a", "b"])];
  applyBehavior(parseInvocation("g#0"), list);
  expect(list[0].peek()).toEqual(["a"]);
});

test("P5 highlight wraps the match in <mark> and escapes everything else (XSS-safe, no RawHTML)", () => {
  expect(highlight("Banana", "an")).toBe("B<mark>an</mark>ana"); // first case-insensitive match
  expect(highlight("BANANA", "an")).toBe("B<mark>AN</mark>ANA"); // case-insensitive, original case kept
  expect(highlight("plum", "xyz")).toBe("plum"); // no match -> escaped text verbatim
  expect(highlight("a&b", "")).toBe("a&amp;b"); // empty query -> just escaped
  // A hostile item cannot inject markup: the text is escaped, only <mark> is literal.
  expect(highlight("<img src=x onerror=alert(1)>", "img")).toBe(
    "&lt;<mark>img</mark> src=x onerror=alert(1)&gt;",
  );
});

test("the behavior-token set is closed and matches Swift Behavior.names (parity)", () => {
  // 1-char tokens, generated from wire-tokens.json (increment=a … commitValue=h).
  expect([...BEHAVIOR_NAMES]).toEqual(["a", "b", "c", "d", "e", "f", "g", "h"]);
});

test("commitValue appends the triggering element's text and clears the query (click-to-commit)", () => {
  const field = [new Signal(/** @type {string[]} */ ([])), new Signal("ap")]; // tokens, query
  applyBehavior(parseInvocation("h#0#1"), field, /** @type {any} */ ({ textContent: " Apple " }));
  expect(field[0].peek()).toEqual(["Apple"]); // trimmed
  expect(field[1].peek()).toBe("");
});

test("removeLast is skipped while the input still has text (Backspace edits, not removes a chip)", () => {
  const list = [new Signal(["a", "b"])];
  applyBehavior(parseInvocation("g#0"), list, /** @type {any} */ ({ value: "typing" }));
  expect(list[0].peek()).toEqual(["a", "b"]); // unchanged — still typing
  applyBehavior(parseInvocation("g#0"), list, /** @type {any} */ ({ value: "" }));
  expect(list[0].peek()).toEqual(["a"]); // empty input -> removes last chip
});

test("malformed invocations are rejected", () => {
  expect(parseInvocation("oops")).toBeNull();
  expect(parseInvocation("a#x")).toBeNull();
});

test("set on a number cell ignores a non-numeric param (failure-safe: no NaN)", () => {
  const cells = [new Signal(5)];
  applyBehavior(parseInvocation("c#0#notanumber"), cells);
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
  expect([...BINARY_OPS]).toEqual(
    ["+", "-", "*", "++", "==", "!=", "<", "<=", ">", ">=", "&&", "||", "has"],
  );
});

test("P5 filter keeps matching elements via an element-bound predicate (recomputes on query change)", () => {
  const cells = [new Signal(["Apple", "apricot", "Banana"]), new Signal("ap")];
  // items.filter(el => el.lowercased().contains(query.lowercased()))
  const expr = { fl: { c: 0 }, p: { o: "has", l: { u: "lc", x: { el: 1 } }, r: { u: "lc", x: { c: 1 } } } };
  expect(evalExpr(expr, cells)).toEqual(["Apple", "apricot"]);
  cells[1].set("ban");
  expect(evalExpr(expr, cells)).toEqual(["Banana"]);
  // count of the filtered result (len over filter) — the listMove keyboard bound
  expect(evalExpr({ u: "len", x: expr }, cells)).toBe(1);
});

test("evalExpr covers the P5 ops: lc/len unary, has binary (parity with Swift UnaryOp/BinaryOp)", () => {
  const cells = [new Signal("Hello"), new Signal(["a", "b", "c"])];
  expect(evalExpr({ u: "lc", x: { c: 0 } }, cells)).toBe("hello");
  expect(evalExpr({ u: "len", x: { c: 1 } }, cells)).toBe(3);
  expect(evalExpr({ o: "has", l: { c: 0 }, r: { s: "ell" } }, cells)).toBe(true); // substring
  expect(evalExpr({ o: "has", l: { c: 0 }, r: { s: "" } }, cells)).toBe(true); // empty needle
  expect(evalExpr({ o: "has", l: { c: 1 }, r: { s: "b" } }, cells)).toBe(true); // array membership
  expect(evalExpr({ o: "has", l: { c: 1 }, r: { s: "z" } }, cells)).toBe(false);
  // case-insensitive substring composes lc + has (the combobox filter predicate)
  const folded = { o: "has", l: { u: "lc", x: { c: 0 } }, r: { s: "ell" } };
  expect(evalExpr(folded, cells)).toBe(true);
  expect([...UNARY_OPS]).toEqual(["lc", "len"]);
});
