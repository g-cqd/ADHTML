// An example component-scoped ES module (Track 4). The component declares `Script.module(name: "counter")`;
// this file is bundled + content-hashed + SRI-served, and registers a mount function by the component's name.
// `ADH` is the runtime global; `ctx.action` (the only network primitive) reaches the signed RFC-0019 endpoint.

/* global ADH */
ADH.mount("Counter", (root, ctx) => {
  const output = root.querySelector("output");
  let count = Number(output?.textContent ?? "0");
  const onClick = () => {
    count += 1;
    if (output) output.textContent = String(count);
    // Persist through the SAME signed endpoint the declarative path uses — never an ad-hoc fetch.
    void ctx.action("/counter/increment", { method: "post", params: { value: String(count) } });
  };
  root.querySelector("button")?.addEventListener("click", onClick);
  return () => root.querySelector("button")?.removeEventListener("click", onClick);
});
