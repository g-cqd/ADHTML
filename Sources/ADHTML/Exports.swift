// The umbrella re-exports the Foundation-free engine so `import ADHTML` brings the whole DSL, and
// hosts the macro declarations (ADR-0008) and document assembly. The macro target `ADHTMLMacros` is
// a dependency so the plugin builds with the umbrella.
@_exported import ADHTMLCore
