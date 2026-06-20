// Lean, id-aware DOM morph (idiomorph-inspired) for SSE `morph` out-of-band swaps. It reconciles a
// target subtree to new server HTML, preserving nodes — and their focus, selection, and bound effects —
// by id and by tag where possible, instead of clobbering `innerHTML`. The walk is **iterative** (an
// explicit worklist of parent pairs, no recursion — matching the Swift engine's no-recursion stance):
// each pair reconciles its direct children, pushing matched element children for deeper reconciliation.
// v1 reconciles positionally with id preference, which still yields a DOM that matches the new HTML;
// full idiomorph-style reordering is a follow-up.

/** Reconcile `target`'s children to `html` (parsed as a fragment), morphing in place where possible. */
export function morph(target: Element, html: string): void {
  const template = document.createElement("template");
  template.innerHTML = html;
  const work: Array<[Node, Node]> = [[target, template.content]];
  let pair: [Node, Node] | undefined;
  while ((pair = work.pop())) {
    reconcileChildren(pair[0], pair[1], work);
  }
}

/** Make `oldParent`'s children match `newParent`'s; queue matched element pairs for deeper morphing.
 * id-set aware (idiomorph heuristic): a new child whose id exists among the old siblings reuses that
 * node — **moved** into place with `insertBefore` rather than replaced — so keyed nodes (and their
 * focus/state) survive a reorder. Falls back to positional tag matching when there is no id. */
function reconcileChildren(oldParent: Node, newParent: Node, work: Array<[Node, Node]>): void {
  // Index old element children by id, so a reordered keyed node can be found wherever it now sits.
  const oldById = new Map<string, Element>();
  for (let node = oldParent.firstChild; node; node = node.nextSibling) {
    if (node instanceof Element && node.id) oldById.set(node.id, node);
  }

  let oldChild = oldParent.firstChild;
  let newChild = newParent.firstChild;
  while (newChild) {
    const nextNew = newChild.nextSibling;

    // Prefer a keyed match (anywhere among the old siblings); else the current positional node.
    let match: ChildNode | null = null;
    if (newChild instanceof Element && newChild.id && oldById.has(newChild.id)) {
      match = oldById.get(newChild.id) ?? null;
      oldById.delete(newChild.id);
    } else if (oldChild && sameNode(oldChild, newChild)) {
      match = oldChild;
    }

    if (match) {
      if (match === oldChild) {
        oldChild = oldChild.nextSibling;  // consumed in place
      } else {
        oldParent.insertBefore(match, oldChild);  // move the keyed node into position (cursor unchanged)
      }
      if (match instanceof Element && newChild instanceof Element) {
        patchAttributes(match, newChild);
        work.push([match, newChild]);  // reconcile its children later (iteratively)
      } else if (match.nodeValue !== newChild.nodeValue) {
        match.nodeValue = newChild.nodeValue;  // text / comment content
      }
    } else {
      oldParent.insertBefore(newChild.cloneNode(true), oldChild);  // new node (before cursor, or at end)
    }
    newChild = nextNew;
  }

  // Drop any old children the new HTML no longer has (matched/moved nodes are before the cursor).
  while (oldChild) {
    const nextOld = oldChild.nextSibling;
    oldParent.removeChild(oldChild);
    oldChild = nextOld;
  }
}

/** Two nodes are "the same slot" (morph in place) vs. a replacement: by id when either has one, else tag. */
function sameNode(a: Node, b: Node): boolean {
  if (a.nodeType !== b.nodeType) return false;
  if (a instanceof Element && b instanceof Element) {
    if (a.id || b.id) return a.id === b.id && a.tagName === b.tagName;
    return a.tagName === b.tagName;
  }
  return true;  // text / comment of the same node type
}

function patchAttributes(oldEl: Element, newEl: Element): void {
  for (const attr of [...newEl.attributes]) {
    if (oldEl.getAttribute(attr.name) !== attr.value) oldEl.setAttribute(attr.name, attr.value);
  }
  for (const attr of [...oldEl.attributes]) {
    if (!newEl.hasAttribute(attr.name)) oldEl.removeAttribute(attr.name);
  }
}
