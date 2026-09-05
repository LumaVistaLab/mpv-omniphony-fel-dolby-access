# Repository rules

## Immutable upstream inputs

`sources/` and `releases/` are immutable reference directories. They contain
only original upstream source trees and original release packages.

- Never edit, patch, format, rename, delete, or create files under `sources/`
  or `releases/`.
- Never run builds, tests, formatters, package managers, or other commands in
  those directories when they could create caches, lockfiles, `target/`
  directories, logs or other generated output, or update file timestamps.
- Read-only inspection and hashing are allowed.
- Copy the required upstream inputs to `build_temp/` before applying patches,
  compiling, testing, or otherwise modifying them.
- Keep maintained patches and build tooling under `development/`; place built
  deliverables under `distribution/`.
- If either protected directory is written accidentally, stop and restore its
  exact original contents, directory structure, and file metadata from an
  authoritative pristine copy. Remove all generated artifacts, verify the
  restoration, and report the incident and recovery to the user before
  continuing.
