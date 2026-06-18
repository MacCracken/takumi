# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.0.x   | Yes       |

## Reporting a Vulnerability

If you discover a security vulnerability in Takumi, please report it
responsibly:

1. **Do not** open a public issue
2. Email the maintainer directly (see git log for contact)
3. Include a clear description and reproduction steps
4. Allow reasonable time for a fix before public disclosure

## Security Considerations

Takumi handles untrusted input (recipe files, source tarball bytes, the
network, and — for the `ark` consumer — `.ark` packages) and produces packages
for system installation. A full threat model + the completed pre-v1 security
audit (22 findings, all remediated) is in
[`docs/compliance/security-audit-2026.md`](docs/compliance/security-audit-2026.md).
Key controls:

- **Verify-before-use**: a source download is SHA-256-checked against the
  recipe's pinned hash as a hard gate *before* it is extracted; a mismatch
  aborts. TLS is native (no libssl), with an https-only policy (a loopback
  carve-out for local mirrors).
- **Hardened extraction**: tar parsing (`ustar`/`v7`/PAX/GNU) is bounds- and
  overflow-checked; a fail-closed path-traversal guard rejects `..`, absolute
  paths, and escaping symlink targets; setuid/setgid/sticky bits are stripped.
- **Build sandbox** (best-effort + reported; `--require-sandbox` to fail-closed):
  each build step runs in an unprivileged network namespace (hermetic — no
  build-time network), under Landlock filesystem confinement (writes limited to
  the build root), and a wall-clock timeout. The build is unprivileged and
  installs only into a DESTDIR fake-root.
- **Integrity + authenticity**: every package carries SHA-256 (root + per-file)
  and an ed25519 signature (`--signing-key`), verified on read.
- **Robust `.ark` reader**: all length/offset fields are bounds-validated against
  the verified region; a malformed package is rejected, never an OOB read.
- **Strict recipe validation**: rejects unsafe package/dependency names (path
  traversal, control bytes), non-https remote URLs, and malformed SHA-256 — early
  and with clear errors.
- **Reproducible builds**: same recipe + sources + `SOURCE_DATE_EPOCH` →
  byte-identical `.ark`.

Trust model: recipes are curated/trusted (build steps are arbitrary shell by
design); the sandbox is defense-in-depth, not a containment boundary against a
malicious recipe. Run builds as a throwaway unprivileged user.
