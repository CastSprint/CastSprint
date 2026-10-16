# Platform parity matrix

`VERIFIED_HARDWARE` requires physical-device evidence; `BUILD_ONLY` does not prove media flow.

| User journey | macOS | Windows | Linux | Android | iOS |
|---|---|---|---|---|---|
| Discover peer | IMPLEMENTED_UNTESTED | PARTIAL | PARTIAL | BUILD_ONLY | IMPLEMENTED_UNTESTED |
| Pair/authenticate | IMPLEMENTED_UNTESTED | IMPLEMENTED_UNTESTED | IMPLEMENTED_UNTESTED | BUILD_ONLY | IMPLEMENTED_UNTESTED |
| Secure transport | MISSING | STUB | MISSING | BUILD_ONLY | MISSING |
| H.264 encode | receiver | receiver | receiver | BUILD_ONLY | IMPLEMENTED_UNTESTED |
| H.264 decode | IMPLEMENTED_UNTESTED | PARTIAL | MISSING | sender | sender |
| GPU presentation | VERIFIED_HARDWARE | PARTIAL | MISSING | sender | sender |
| AAC encode/decode | IMPLEMENTED_UNTESTED | PARTIAL | MISSING | BUILD_ONLY | IMPLEMENTED_UNTESTED |
| App-only audio/no mic | IMPLEMENTED_UNTESTED | PARTIAL | MISSING | BUILD_ONLY | IMPLEMENTED_UNTESTED |
| Reconnect/rotation | PARTIAL | PARTIAL | MISSING | BUILD_ONLY | IMPLEMENTED_UNTESTED |

The next parity gate is a mutually authenticated encrypted transport, then real Windows/Linux decode/render/audio integration.
