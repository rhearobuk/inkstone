# Contributing to Scribe

Thanks for improving Scribe. We welcome bug reports, feature requests,
documentation improvements, tests, and pull requests.

## Before you begin

- Search existing issues and pull requests before opening a new one.
- Use feature requests to describe the problem and intended outcome before
  implementing substantial new behavior.
- Keep changes focused. Include tests for behavior changes and update relevant
  documentation.
- Run `swift test` before opening a pull request.
- Do not include secrets, personal writing, Scrivener projects, generated
  build products, or other material you do not have permission to redistribute.

## Pull requests

1. Fork the repository and create a focused branch from `main`.
2. Make your change using the existing Swift style and platform support.
3. Explain the user-visible change, implementation notes, and validation in
   the pull request template.
4. Submit the pull request against `main`.

Maintainers review all pull requests. Opening a pull request does not
guarantee it will be merged, but constructive contributions will receive
consideration.

## Scrivener interoperability

Scribe’s Scrivener project import compatibility is deliberately **one way**:
it reads selected user project data and imports it into Scribe without modifying
the source project. Contributions must not imply, promise, or add export,
synchronization, round-trip editing, or compatibility guarantees with Scrivener
without prior maintainer agreement. See
[Scrivener Project Import Compatibility](Documentation/Scrivener-Interoperability.md)
for the full boundary and test-data requirements.

Scrivener is a trademark of Literature & Latte Ltd. Scribe is an independent
project and is not affiliated with, endorsed by, or sponsored by Literature &
Latte Ltd.

## Contributor license

By submitting a contribution, you agree that your contribution is your
original work and that you have the right to submit it under the repository’s
[MIT License](LICENSE).
