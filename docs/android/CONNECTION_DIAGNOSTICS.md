# Android connection diagnostics

Implemented link states: TCP_CONNECTING, TLS_HANDSHAKE, PAIRING, AUTHENTICATED, STREAMING and RECONNECTING, plus idle/file states. USB startup additionally reports missing token, ADB authorization and reverse-tunnel verification failure.

`STREAMING` on Android means the first encoded video frame was sent. Desktop success still requires its independent first-frame-received and first-frame-rendered telemetry. Wi-Fi TLS failure details propagate to the reconnect status without logging pairing tokens.

Still missing: explicit desktop firewall/client-isolation classification and an authenticated receiver-to-sender first-frame-rendered acknowledgement.
