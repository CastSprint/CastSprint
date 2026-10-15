# Notarization

The production workflow submits the signed DMG with `xcrun notarytool`, waits for Apple's result, staples the ticket, validates the staple, and assesses the artifact with `spctl`.

Required secrets:

- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APP_SPECIFIC_PASSWORD`

Current status: **BLOCKED** because these credentials are not present locally. No artifact may be described as notarized until Apple's accepted result, stapling, validation, and Gatekeeper assessment all succeed.

