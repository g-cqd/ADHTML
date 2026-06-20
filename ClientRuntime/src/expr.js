// Iterative evaluator for the closed client-recomputable expression set (mirrors Swift's WireExpr /
// BinaryOp — a parity test keeps the op tokens in sync). A `cmp` cell that carries an `e` formula is
// recomputed in-browser from its dependency cells, with no server round-trip. No recursion (explicit
// work + value stacks), matching the engine's no-recursion stance.

/**
 * A serialized expression node: a cell ref `{c}`, a literal `{i|d|b|s}`, or a binary `{o,l,r}`.
 * @typedef {{c: number} | {i: number} | {d: number} | {b: boolean} | {s: string}
 *   | {o: string, l: WireExprJSON, r: WireExprJSON}} WireExprJSON
 */

/** @typedef {{visit: WireExprJSON} | {fold: string}} Work */

/** The binary op tokens this evaluator supports — must equal Swift `BinaryOp.rawValue` (parity test). */
export const BINARY_OPS = ["+", "-", "*", "++", "==", "!=", "<", "<=", ">", ">=", "&&", "||"];

/** Failure-safe ceiling on the work the evaluator does for one formula — the client-side mirror of the
 * server's `WireSerializer.maxValueDepth` cap. A well-formed `e` from the Swift DSL is tiny; this bounds an
 * adversarial/oversized inline-state formula so a single recompute can't monopolize the main thread. */
const MAX_EXPR_NODES = 4096;

/** Evaluate `expr` over `cells`, reading each referenced cell via `.get()` so an enclosing effect
 * subscribes to it (reactive recompute). Iterative post-order.
 * @param {WireExprJSON} expr
 * @param {Array<import("./signals").Signal<unknown>>} cells
 * @returns {unknown} */
export function evalExpr(expr, cells) {
  /** @type {Work[]} */
  const work = [{ visit: expr }];
  /** @type {unknown[]} */
  const values = [];
  /** @type {Work | undefined} */
  let item;
  let steps = 0;
  while ((item = work.pop())) {
    if (++steps > MAX_EXPR_NODES) return undefined;  // failure-safe: drop an oversized/adversarial formula
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

/** @param {string} op @param {unknown} lhs @param {unknown} rhs @returns {unknown} */
function applyOp(op, lhs, rhs) {
  switch (op) {
    case "+":
      return /** @type {number} */ (lhs) + /** @type {number} */ (rhs);
    case "-":
      return /** @type {number} */ (lhs) - /** @type {number} */ (rhs);
    case "*":
      return /** @type {number} */ (lhs) * /** @type {number} */ (rhs);
    case "++":
      return String(lhs) + String(rhs);
    case "==":
      return lhs === rhs;
    case "!=":
      return lhs !== rhs;
    case "<":
      return /** @type {number} */ (lhs) < /** @type {number} */ (rhs);
    case "<=":
      return /** @type {number} */ (lhs) <= /** @type {number} */ (rhs);
    case ">":
      return /** @type {number} */ (lhs) > /** @type {number} */ (rhs);
    case ">=":
      return /** @type {number} */ (lhs) >= /** @type {number} */ (rhs);
    case "&&":
      return Boolean(lhs) && Boolean(rhs);
    case "||":
      return Boolean(lhs) || Boolean(rhs);
    default:
      return undefined;  // unknown op (forward-compatible: an older runtime ignores a newer formula)
  }
}
