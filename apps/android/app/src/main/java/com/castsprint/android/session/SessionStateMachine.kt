package com.castsprint.android.session

/** Lifecycle phases of one mirroring session. See docs/architecture/ANDROID_CAPTURE.md. */
enum class Phase { IDLE, REQUESTING_PERMISSION, STARTING, CAPTURING, STOPPING, ERROR }

/** State of the outbound stream (receiver link or diagnostic file). */
enum class LinkState { NONE, WAITING_FOR_RECEIVER, HANDSHAKING, CONNECTED, WRITING_FILE }

data class SessionSnapshot(
    val phase: Phase = Phase.IDLE,
    val link: LinkState = LinkState.NONE,
    val linkDetail: String = "",
    val message: String = "",
    val error: String? = null,
    val encoderName: String = "",
    val encoderDetail: String = "",
    val startedAtElapsedMs: Long = 0L,
)

/**
 * Pure, thread-safe state machine. Invalid transitions are rejected and leave state unchanged.
 *
 * IDLE -> REQUESTING_PERMISSION -> STARTING -> CAPTURING -> STOPPING -> IDLE
 * Any active phase may go to ERROR; ERROR -> IDLE (after teardown) or REQUESTING_PERMISSION (retry).
 */
class SessionStateMachine {
    private var state = SessionSnapshot()

    @Synchronized
    fun snapshot(): SessionSnapshot = state

    @Synchronized
    fun transition(to: Phase, message: String = "", error: String? = null, nowMs: Long = 0L): Boolean {
        if (!isAllowed(state.phase, to)) return false
        state = when (to) {
            Phase.IDLE -> SessionSnapshot(message = message, error = state.error.takeIf { state.phase == Phase.ERROR })
            Phase.REQUESTING_PERMISSION, Phase.STARTING -> state.copy(phase = to, message = message, error = null)
            Phase.CAPTURING -> state.copy(phase = to, message = message, startedAtElapsedMs = nowMs)
            Phase.STOPPING -> state.copy(phase = to, message = message)
            Phase.ERROR -> state.copy(phase = to, message = message, error = error ?: message, link = LinkState.NONE)
        }
        return true
    }

    @Synchronized
    fun update(block: (SessionSnapshot) -> SessionSnapshot) {
        val next = block(state)
        state = next.copy(phase = state.phase) // phase changes only via transition()
    }

    /** Recovery path: forces IDLE when the owner of the session is known to be gone. */
    @Synchronized
    fun reset(message: String = "") {
        state = SessionSnapshot(message = message)
    }

    companion object {
        fun isAllowed(from: Phase, to: Phase): Boolean = when (from) {
            Phase.IDLE -> to == Phase.REQUESTING_PERMISSION
            Phase.REQUESTING_PERMISSION -> to == Phase.STARTING || to == Phase.IDLE || to == Phase.ERROR
            Phase.STARTING -> to == Phase.CAPTURING || to == Phase.STOPPING || to == Phase.ERROR
            Phase.CAPTURING -> to == Phase.STOPPING || to == Phase.ERROR
            Phase.STOPPING -> to == Phase.IDLE || to == Phase.ERROR
            Phase.ERROR -> to == Phase.IDLE || to == Phase.REQUESTING_PERMISSION
        }
    }
}
