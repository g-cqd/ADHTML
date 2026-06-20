// Iterative evaluator for the closed client-recomputable expression set (mirrors Swift's WireExpr /
// BinaryOp — a parity test keeps the op tokens in sync). A `cmp` cell that carries an `e` formula is
// recomputed in-browser from its dependency cells, with no server round-trip. No recursion (explicit
// work + value stacks), matching the engine's no-recursion stance.

import type { Signal } from "./signals";

/** A serialized expression node: a cell ref `{c}`, a literal `{i|d|b|s}`, or a binary `{o,l,r}`. */
export type WireExprJSON =
  | { c: number }
  | { i: number }
  | { d: number }
  | { b: boolean }
  | { s: string }
  | { o: string; l: WireExprJSON; r: WireExprJSON };

/** The binary op tokens this evaluator supports — must equal Swift `BinaryOp.rawValue` (parity test). */
export const BINARY_OPS = ["+", "-", "*", "++"] as const;

/** Evaluate `expr` over `cells`, reading each referenced cell via `.get()` so an enclosing effect
 * subscribes to it (reactive recompute). Iterative post-order. */
export function evalExpr(expr: WireExprJSON, cells: Array<Signal<unknown>>): unknown {
  type Work = { visit: WireExprJSON } | { fold: string };
  const work: Work[] = [{ visit: expr }];
  const values: unknown[] = [];
  let item: Work | undefined;
  while ((item = work.pop())) {
    if ("fold" in item) {
      const rhs = values.pop();
      const lhs = values.pop();
      values.push(applyOp(item.fold, lhs, rhs));
    } else {
      const node = item.visit;
      if ("o" in node) work.push({ fold: node.o }, { visit: node.r }, { visit: node.l });
      else if ("c" in node) values.push(cells[node.c]?.get());
      else if ("i" in node) values.push(node.i);
      else if ("d" in node) values.push(node.d);
      else if ("b" in node) values.push(node.b);
      else values.push(node.s);
    }
  }
  return values.pop();
}

function applyOp(op: string, lhs: unknown, rhs: unknown): unknown {
  switch (op) {
    case "+":
      return (lhs as number) + (rhs as number);
    case "-":
      return (lhs as number) - (rhs as number);
    case "*":
      return (lhs as number) * (rhs as number);
    case "++":
      return String(lhs) + String(rhs);
    default:
      return undefined;  // unknown op (forward-compatible: an older runtime ignores a newer formula)
  }
}
