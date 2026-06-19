// ADHTMLSRI (gated `ADHTML_SRI`) — compute Subresource Integrity hashes (SHA-256 via swift-crypto) for
// the client runtime asset. Crypto is required *only* here, never for island/cache IDs (those use
// `ADFCore.XXH64`) — ADR-0011. Placeholder this pass.
internal import ADHTMLCore

/// Namespace for Subresource-Integrity hashing of the client runtime (ADR-0006/0011).
public enum ADHTMLSRI {}
