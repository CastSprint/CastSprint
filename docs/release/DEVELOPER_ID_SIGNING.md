# Developer ID signing

The manual release workflow requires an exported Developer ID Application certificate and password in protected GitHub environment secrets. It imports the certificate into an ephemeral keychain, signs with hardened runtime and a trusted timestamp, verifies the bundle, and deletes the keychain afterward.

Required secrets:

- `DEVELOPER_ID_CERTIFICATE_P12_BASE64`
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`

Local packaging remains ad-hoc unless `CODESIGN_IDENTITY` is provided. Setting `REQUIRE_DISTRIBUTION_SIGNING=true` makes absence of a real identity fatal.

