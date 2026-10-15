# Gatekeeper FAQ

## Why does a local build show a warning?

Ad-hoc signing verifies bundle integrity but does not identify an Apple Developer ID publisher and cannot be notarized as a public release.

## Should users bypass Gatekeeper?

No. Public artifacts must be Developer ID signed and notarized. This project does not instruct users to disable Gatekeeper or remove quarantine metadata.

## What is the current status?

Developer ID signing/notarization is **BLOCKED** until the repository environment receives the required private signing certificate and Apple notarization credentials.

