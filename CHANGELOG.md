# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.0] - 2026-11-02

### Added

- `Oo7::Keyring`, the collection: `new`, `unlock`, `lock`, `locked?`, `items`,
  `search(attributes)`, `create(label, attributes, secret, replace)` and
  `delete(attributes)`.
- `Oo7::Item`, one stored secret: `label`, `label=`, `attributes`,
  `attributes=`, `secret`, `secret=`, `locked?`, `lock`, `unlock`, `delete`,
  `created` and `modified`.
- A magnus native extension over the `oo7` crate (0.6), built with
  `native_crypto` and `tokio` and no default features, so the object links
  `libc`, `libgcc_s` and `libm` and nothing else. Neither libsecret, libgcr nor
  libgcrypt is in the address space -- which is the reason this gem exists,
  since a fault in those is not a caller's to fix.
- Precompiled platform gems for Linux (gnu and musl, x86_64/aarch64/arm) and
  Darwin (x86_64/arm64), cross-compiled in CI.

### Changed

- Every method is synchronous. The crate's API is async throughout; each
  binding drives it to completion on a Tokio runtime owned by the extension.
  The runtime is multi-threaded with one worker rather than current-thread,
  because zbus spawns its own socket reader task and the runtime has to keep
  driving it while a call waits.

### Removed

- Windows is not a supported platform and is excluded from the cross-compile
  matrix. The Secret Service is a freedesktop D-Bus API, and `ashpd` -- which
  oo7 uses to ask whether the process is sandboxed -- is Unix-only, so the
  dependency does not compile there.
