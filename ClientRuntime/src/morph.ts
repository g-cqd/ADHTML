// Lean, id-aware DOM morph (idiomorph-inspired) for SSE `morph` out-of-band swaps. It reconciles a
// target subtree to new server HTML, preserving nodes — and their focus, selection, and bound effects —
// by id and by tag where possible, instead of clobbering `innerHTML`. Recursion here is over a TRUSTED,
// server-generated subtree whose depth is bounded (not the unbounded/adversarial-input concern the
// server renderer guards against), so it stays simple. v1 reconciles positionally with id preference,
// which still yields a DOM that matches the new HTML; full idiomorph-style reordering is a follow-up.

/** Reconcile `target`'s children to `html` (parsed as a fragment), morphing in place where possible. */
export function morph(target: Element, html: string): void {
  const template = document.createElement("template");
  template.innerHTML = html;
  reconcile(target, template.content);
}

function reconcile(oldParent: Node, newParent: Node): void {
  let oldChild = oldParent.firstChild;
  let newChild = newParent.firstChild;
  while (newChild) {
    const nextNew = newChild.nextSibling;
    if (!oldChild) {
      oldParent.appendChild(newChild.cloneNode(true));
    } else {
      const nextOld = oldChild.nextSibling;
      if (sameNode(oldChild, newChild)) patchNode(oldChild, newChild);
      else oldParent.replaceChild(newChild.cloneNode(true), oldChild);
      oldChild = nextOld;
    }
    newChild = nextNew;
  }
  // Drop any old children the new HTML no longer has.
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

function patchNode(oldNode: ChildNode, newNode: ChildNode): void {
  if (oldNode instanceof Element && newNode instanceof Element) {
    patchAttributes(oldNode, newNode);
    reconcile(oldNode, newNode);
  } else if (oldNode.nodeValue !== newNode.nodeValue) {
    oldNode.nodeValue = newNode.nodeValue;  // text / comment content
  }
}

function patchAttributes(oldEl: Element, newEl: Element): void {
  for (const attr of [...newEl.attributes]) {
    if (oldEl.getAttribute(attr.name) !== attr.value) oldEl.setAttribute(attr.name, attr.value);
  }
  for (const attr of [...oldEl.attributes]) {
    if (!newEl.hasAttribute(attr.name)) oldEl.removeAttribute(attr.name);
  }
}
