# Release security gates

Public release is intentionally manual.

1. Operator dispatches the release workflow for an exact commit.
2. The commit must have a successful `CI Complete` check.
3. GitHub `production` environment approval must pass.
4. Signing and notarization secrets must exist.
5. Tests and packaging must succeed.
6. Signature, notarization staple, and Gatekeeper assessment must pass.
7. Only then may the workflow create a GitHub release.

The workflow does not run automatically after every main-branch build. This prevents an unsigned, unreviewed, or merely compilable artifact from becoming a public release.

