package com.castsprint.android.encoder

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class EncoderConfigSelectorTest {

    private class MockCodecCaps(
        override val name: String,
        override val isHardware: Boolean,
        override val widthAlignment: Int = 16,
        override val heightAlignment: Int = 16,
        override val bitrateRange: IntRange = 1_000_000..20_000_000,
        override val supportsCbr: Boolean = true,
        override val supportsHighProfile: Boolean = true,
        private val supportedConfigs: Set<Triple<Int, Int, Int>> = emptySet(),
    ) : CodecCapabilities {
        override fun supports(width: Int, height: Int, fps: Int): Boolean =
            supportedConfigs.contains(Triple(width, height, fps))
    }

    @Test
    fun fitSizePreservesOrientationAndAlignment() {
        // Portrait 1080x2400 in 1080p box (1080x1920)
        val (w1, h1) = EncoderConfigSelector.fitSize(1080, 2400, Resolution.FHD_1080, 16, 16)
        assertEquals(0, w1 % 16)
        assertEquals(0, h1 % 16)
        assertTrue(h1 > w1) // must remain portrait
        assertTrue(w1 <= 1080 && h1 <= 1920)

        // Landscape 2400x1080 in 1080p box (1920x1080)
        val (w2, h2) = EncoderConfigSelector.fitSize(2400, 1080, Resolution.FHD_1080, 16, 16)
        assertEquals(0, w2 % 16)
        assertEquals(0, h2 % 16)
        assertTrue(w2 > h2) // must remain landscape
        assertTrue(w2 <= 1920 && h2 <= 1080)
    }

    @Test
    fun prefersHardwareEncoder() {
        val (w, h) = EncoderConfigSelector.fitSize(1080, 1920, Resolution.FHD_1080, 16, 16)
        val sw = MockCodecCaps("c2.android.avc.encoder", isHardware = false, supportedConfigs = setOf(Triple(w, h, 60)))
        val hw = MockCodecCaps("c2.qti.avc.encoder", isHardware = true, supportedConfigs = setOf(Triple(w, h, 60)))

        val settings = CaptureSettings(Resolution.FHD_1080, 60, 12_000_000, OutputMode.USB_RECEIVER)
        val sel = EncoderConfigSelector.select(1080, 1920, settings, listOf(sw, hw))

        assertTrue(sel is Selection.Ok)
        val ok = sel as Selection.Ok
        assertEquals("c2.qti.avc.encoder", ok.config.codecName)
        assertTrue(ok.config.isHardware)
    }

    @Test
    fun fallsBackToLowerFpsWhen60Unsupported() {
        val (w, h) = EncoderConfigSelector.fitSize(1080, 1920, Resolution.FHD_1080, 16, 16)
        // Codec only supports 30 fps at 1080p
        val codec = MockCodecCaps("hw.encoder", isHardware = true, supportedConfigs = setOf(Triple(w, h, 30)))

        val settings = CaptureSettings(Resolution.FHD_1080, 60, 12_000_000, OutputMode.USB_RECEIVER)
        val sel = EncoderConfigSelector.select(1080, 1920, settings, listOf(codec))

        assertTrue(sel is Selection.Ok)
        val ok = sel as Selection.Ok
        assertEquals(30, ok.config.fps)
        assertNotNull(ok.downgradeNote)
    }

    @Test
    fun fallsBackTo720pWhen1080pUnsupported() {
        val (w720, h720) = EncoderConfigSelector.fitSize(1080, 1920, Resolution.HD_720, 16, 16)
        val codec = MockCodecCaps("hw.encoder", isHardware = true, supportedConfigs = setOf(Triple(w720, h720, 60)))

        val settings = CaptureSettings(Resolution.FHD_1080, 60, 12_000_000, OutputMode.USB_RECEIVER)
        val sel = EncoderConfigSelector.select(1080, 1920, settings, listOf(codec))

        assertTrue(sel is Selection.Ok)
        val ok = sel as Selection.Ok
        assertEquals(w720, ok.config.width)
        assertEquals(h720, ok.config.height)
        assertNotNull(ok.downgradeNote)
    }

    @Test
    fun clampsBitrateToCodecCapabilities() {
        val (w, h) = EncoderConfigSelector.fitSize(1080, 1920, Resolution.FHD_1080, 16, 16)
        val codec = MockCodecCaps(
            "hw.encoder",
            isHardware = true,
            bitrateRange = 2_000_000..8_000_000,
            supportedConfigs = setOf(Triple(w, h, 60))
        )

        // Request 16 Mbps
        val settings = CaptureSettings(Resolution.FHD_1080, 60, 16_000_000, OutputMode.USB_RECEIVER)
        val sel = EncoderConfigSelector.select(1080, 1920, settings, listOf(codec))

        assertTrue(sel is Selection.Ok)
        val ok = sel as Selection.Ok
        assertEquals(8_000_000, ok.config.bitrateBps)
    }

    @Test
    fun failsWhenNoMatchingCapabilities() {
        val codec = MockCodecCaps("hw.encoder", isHardware = true, supportedConfigs = emptySet())
        val settings = CaptureSettings(Resolution.FHD_1080, 60, 12_000_000, OutputMode.USB_RECEIVER)
        val sel = EncoderConfigSelector.select(1080, 1920, settings, listOf(codec))

        assertTrue(sel is Selection.Failed)
    }
}
