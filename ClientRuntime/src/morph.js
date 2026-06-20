// Lean, id-aware DOM morph (idiomorph-inspired) for SSE `morph` out-of-band swaps. It reconciles a
// target subtree to new server HTML, preserving nodes — and their focus, selection, and bound effects —
// by id and by tag where possible, instead of clobbering `innerHTML`. The walk is **iterative** (an
// explicit worklist of parent pairs, no recursion — matching the Swift engine's no-recursion stance):
// each pair reconciles its direct children, pushing matched element children for deeper reconciliation.
// v1 reconciles positionally with id preference, which still yields a DOM that matches the new HTML.

import { T } from "./tokens";

/** @type {HTMLTemplateElement | undefined} */
let parseTemplate;

/** Reconcile `target`'s children to `html` (parsed as a fragment), morphing in place where possible.
 * @param {Element} target @param {string} html @returns {void} */
export function morph(target, html) {
  // Reuse one <template> across calls (created lazily so importing this module never touches the DOM).
  // `innerHTML =` resets its content each call, and the walk only ever reads/clones template nodes
  // (never moves them out), so reuse is safe.
  const template = (parseTemplate ??= document.createElement("template"));
  template.innerHTML = html;
  drain([[target, template.content]]);
}

/** Morph an existing element to match `source` (a parsed element): sync its attributes, then reconcile its
 * children — preserving the target's identity, focus, selection, and bound effects rather than replacing
 * it. The element-level counterpart of `morph` (which only reconciles children); used by `oobSwap`.
 * @param {Element} target @param {Element} source @returns {void} */
export function morphElement(target, source) {
  patchAttributes(target, source);
  drain([[target, source]]);
}

/** Drain a worklist of (oldParent, newParent) pairs — reconcile each pair's children, which pushes their
 * matched element children back on for deeper morphing. Iterative (no recursion), stack-safe.
 * @param {Array<[Node, Node]>} work @returns {void} */
function drain(work) {
  /** @type {[Node, Node] | undefined} */
  let pair;
  while ((pair = work.pop())) {
    reconcileChildren(pair[0], pair[1], work);
  }
}

/** Apply an out-of-band response (RFC-0019 §6.3-J, contract C3): each top-level element of `html` names
 * the page region it updates — via `data-adh-oob="<id>"` or its own `id` — and is morphed into that
 * region. Parsed inertly through a `<template>` (nothing in `html` runs on parse), and only id-resolved
 * regions are touched; an element naming no live region is ignored. Used by the action `outOfBand` swap.
 * @param {string} html @param {Document} [doc] @returns {void} */
export function oobSwap(html, doc = document) {
  const template = doc.createElement("template");
  template.innerHTML = html;
  for (const element of template.content.children) {
    const id = element.getAttribute(T.oob) || element.id;
    const target = id ? doc.getElementById(id) : null;
    if (!target) continue;
    // Normalize the marker to the target's own id so the attribute sync preserves identity rather than
    // replacing `id` with `data-adh-oob` (which would orphan the region for any later swap).
    element.removeAttribute(T.oob);
    element.id = id;
    morphElement(target, element);
  }
}

/** Make `oldParent`'s children match `newParent`'s; queue matched element pairs for deeper morphing.
 * id-set aware (idiomorph heuristic): a new child whose id exists among the old siblings reuses that
 * node — **moved** into place with `insertBefore` rather than replaced — so keyed nodes (and their
 * focus/state) survive a reorder. Falls back to positional tag matching when there is no id.
 * @param {Node} oldParent @param {Node} newParent @param {Array<[Node, Node]>} work @returns {void} */
function reconcileChildren(oldParent, newParent, work) {
  // Index old element children by id, so a reordered keyed node can be found wherever it now sits.
  /** @type {Map<string, Element>} */
  const oldById = new Map();
  for (let node = oldParent.firstChild; node; node = node.nextSibling) {
    if (node instanceof Element && node.id) oldById.set(node.id, node);
  }

  let oldChild = oldParent.firstChild;
  let newChild = newParent.firstChild;
  while (newChild) {
    const nextNew = newChild.nextSibling;

    // Prefer a keyed match (anywhere among the old siblings); else the current positional node.
    /** @type {ChildNode | null} */
    let match = null;
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

/** Two nodes are "the same slot" (morph in place) vs. a replacement: by id when either has one, else tag.
 * @param {Node} a @param {Node} b @returns {boolean} */
function sameNode(a, b) {
  if (a.nodeType !== b.nodeType) return false;
  if (a instanceof Element && b instanceof Element) {
    if (a.id || b.id) return a.id === b.id && a.tagName === b.tagName;
    return a.tagName === b.tagName;
  }
  return true;  // text / comment of the same node type
}

/** Sync `oldEl`'s attributes to `newEl`'s. Iterates the live `NamedNodeMap`s by index (no `[...attrs]`
 * snapshot allocation): forward for the set pass; backward for the remove pass so deleting an attribute
 * from the live map can't skip the next one.
 * @param {Element} oldEl @param {Element} newEl @returns {void} */
function patchAttributes(oldEl, newEl) {
  const newAttrs = newEl.attributes;
  for (let i = 0; i < newAttrs.length; i++) {
    const attr = /** @type {Attr} */ (newAttrs[i]);
    if (oldEl.getAttribute(attr.name) !== attr.value) oldEl.setAttribute(attr.name, attr.value);
  }
  const oldAttrs = oldEl.attributes;
  for (let i = oldAttrs.length - 1; i >= 0; i--) {
    const attr = /** @type {Attr} */ (oldAttrs[i]);
    if (!newEl.hasAttribute(attr.name)) oldEl.removeAttribute(attr.name);
  }
}
