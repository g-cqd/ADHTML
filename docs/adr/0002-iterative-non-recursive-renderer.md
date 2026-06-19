# ADR 0002 — Iterative, non-recursive renderer

- **Status**: Proposed
- **Date**: 2026-06-19
- **Related**: RFC-0002; ADR-0003 (escaping), ADR-0012 (byte sink)

## Context

Every existing Swift HTML library renders by recursion (each node's render calls its children's). With
static generics that is monomorphized, but native call-stack depth still scales with DOM nesting depth.
Under `async` streaming each level is an `async` frame awaiting the sink — a long continuation chain
for deep pages and a stack-depth ceiling for user-/data-driven nesting (CWE-674, uncontrolled
recursion). The prism mandates *avoid recursion*, bounded complexity, memory safety, and failure-safe
behavior.

## Decision

Lower the (compile-time, type-level) element tree to a **flat opcode program** (`ContiguousArray<
HTMLOp>`) and emit bytes with a **single iterative loop** over it. The type structure is unrolled by
the compiler; the program is flat; the walk is a `for`/`while` with exactly one `await` site in the
async variant. Track open-tag depth and throw `RenderError.maxDepthExceeded` past a configurable cap.
Document an explicit-`Deque` work-stack as the alternative for a *future dynamic-AST mode* only; the
static model needs no explicit stack, so `DequeModule` is not a core dependency yet.

Ship **one** renderer. Any alternative is a benchmarked, documented option — never a second live path.

## Consequences

- **Positive**: native stack O(1) (no deep-input stack overflow); cache-friendly sequential emit;
  one place to await/back-pressure the streaming sink; trivial seam to interleave island markers
  (RFC-0003); bounded cyclomatic complexity (a wide switch, `ignores_case_statements`).
- **Negative**: the opcode buffer is O(n) space for the page (acceptable; a future streaming lowering
  can bound it for very large pages). A lowering pass exists between build and emit (measured to be
  cheap; ordo-one gate).
- **Failure-safe**: adversarial nesting yields a typed error, never a crash.
