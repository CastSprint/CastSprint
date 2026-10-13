package com.castsprint.android.session

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SessionStateMachineTest {

    @Test
    fun standardLifecycleTransitions() {
        val sm = SessionStateMachine()
        assertEquals(Phase.IDLE, sm.snapshot().phase)

        assertTrue(sm.transition(Phase.REQUESTING_PERMISSION, "Requesting"))
        assertEquals(Phase.REQUESTING_PERMISSION, sm.snapshot().phase)

        assertTrue(sm.transition(Phase.STARTING, "Starting"))
        assertEquals(Phase.STARTING, sm.snapshot().phase)

        assertTrue(sm.transition(Phase.CAPTURING, "Capturing", nowMs = 12345L))
        assertEquals(Phase.CAPTURING, sm.snapshot().phase)
        assertEquals(12345L, sm.snapshot().startedAtElapsedMs)

        assertTrue(sm.transition(Phase.STOPPING, "Stopping"))
        assertEquals(Phase.STOPPING, sm.snapshot().phase)

        assertTrue(sm.transition(Phase.IDLE, "Idle"))
        assertEquals(Phase.IDLE, sm.snapshot().phase)
    }

    @Test
    fun rejectsInvalidTransitions() {
        val sm = SessionStateMachine()
        assertFalse(sm.transition(Phase.CAPTURING))
        assertEquals(Phase.IDLE, sm.snapshot().phase)

        assertFalse(sm.transition(Phase.STOPPING))
        assertEquals(Phase.IDLE, sm.snapshot().phase)

        sm.transition(Phase.REQUESTING_PERMISSION)
        assertFalse(sm.transition(Phase.CAPTURING)) // must go through STARTING
        assertEquals(Phase.REQUESTING_PERMISSION, sm.snapshot().phase)
    }

    @Test
    fun permissionCancellationReturnsToIdle() {
        val sm = SessionStateMachine()
        sm.transition(Phase.REQUESTING_PERMISSION)
        assertTrue(sm.transition(Phase.IDLE, "Cancelled by user"))
        assertEquals(Phase.IDLE, sm.snapshot().phase)
        assertEquals("Cancelled by user", sm.snapshot().message)
    }

    @Test
    fun errorTransitionAndRecovery() {
        val sm = SessionStateMachine()
        sm.transition(Phase.REQUESTING_PERMISSION)
        sm.transition(Phase.STARTING)
        assertTrue(sm.transition(Phase.ERROR, error = "Encoder initialization failed"))
        assertEquals(Phase.ERROR, sm.snapshot().phase)
        assertEquals("Encoder initialization failed", sm.snapshot().error)

        // Can recover to IDLE
        assertTrue(sm.transition(Phase.IDLE, "Reset"))
        assertEquals(Phase.IDLE, sm.snapshot().phase)

        // Or directly retry permission
        sm.transition(Phase.ERROR, error = "Socket closed")
        assertTrue(sm.transition(Phase.REQUESTING_PERMISSION, "Retrying"))
        assertEquals(Phase.REQUESTING_PERMISSION, sm.snapshot().phase)
        assertNull(sm.snapshot().error)
    }

    @Test
    fun resetForcesIdle() {
        val sm = SessionStateMachine()
        sm.transition(Phase.REQUESTING_PERMISSION)
        sm.transition(Phase.STARTING)
        sm.transition(Phase.CAPTURING)

        sm.reset("Hard reset")
        assertEquals(Phase.IDLE, sm.snapshot().phase)
        assertEquals("Hard reset", sm.snapshot().message)
    }
}
