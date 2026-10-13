# License Options (decision pending)

No license has been selected. Until one is, the code is "all rights reserved" by default and
others cannot legally reuse it. Options:

| License | Type | Effect for CastSprint |
|---|---|---|
| **GPL-3.0** | Strong copyleft | Forks/redistributions must stay open source. Protects "free forever"; blocks closed commercial forks. |
| **MPL-2.0** | File-level copyleft | Modified CastSprint files stay open; can be combined with proprietary code. Middle ground. |
| **Apache-2.0** | Permissive + patent grant | Anyone may reuse, including closed forks. Explicit patent license (relevant for codec-adjacent code). |
| **MIT** | Permissive | Simplest; no patent grant. |

Considerations:
- H.264/H.265 are patent-encumbered; CastSprint uses OS-provided codecs (MediaCodec, Media
  Foundation), so it ships no codec implementation itself.
- Dependency compatibility: none yet beyond OS SDKs and JUnit (test-only, EPL-1.0).
- A permissive license maximizes adoption; GPL best guarantees derivatives stay free.

Please choose; then a `LICENSE` file will be added.
