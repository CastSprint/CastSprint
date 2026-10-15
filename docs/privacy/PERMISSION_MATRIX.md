# Permission matrix

| Feature | macOS permission | When requested |
|---|---|---|
| iPhone USB display video | Camera | when USB capture starts |
| iPhone USB digital audio | Microphone category | only after user enables **Capture iPhone internal audio** and starts capture |
| LAN sender discovery/receive | Local Network | when LAN features are used |
| Optional proximity discovery | Bluetooth | only when explicitly enabled |

Video-only capture does not intentionally request audio authorization. Denial of audio permission must leave video working. CastSprint does not use the Mac microphone as a fallback.

