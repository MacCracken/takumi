# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 0.1.x   | Yes       |

## Reporting a Vulnerability

If you discover a security vulnerability in Takumi, please report it
responsibly:

1. **Do not** open a public issue
2. Email the maintainer directly (see git log for contact)
3. Include a clear description and reproduction steps
4. Allow reasonable time for a fix before public disclosure

## Security Considerations

Takumi handles untrusted input (recipe files, source URLs) and produces
packages for system installation. Key security measures:

- **Package name validation**: rejects path traversal (`../`), null bytes,
  spaces, backslashes, and shell metacharacters
- **Dependency name validation**: same restrictions as package names
- **URL scheme enforcement**: only `https://` and `http://` are accepted
- **SHA-256 integrity**: all source downloads and produced artifacts are
  checksummed
- **Symlink-safe directory traversal**: uses `symlink_metadata` to avoid
  following symlinks during recipe loading
- **Security hardening flags**: PIE, RELRO, FORTIFY_SOURCE, stack protector,
  and bind-now are supported for compiled packages
