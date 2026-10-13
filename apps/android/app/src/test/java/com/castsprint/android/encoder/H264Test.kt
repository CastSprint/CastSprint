package com.castsprint.android.encoder

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class H264Test {

    private val start4 = byteArrayOf(0, 0, 0, 1)
    private val start3 = byteArrayOf(0, 0, 1)

    @Test
    fun detectsStartCodes() {
        val b4 = byteArrayOf(0, 0, 0, 1, 0x67)
        assertTrue(H264.hasStartCode(b4, 0, b4.size))

        val b3 = byteArrayOf(0, 0, 1, 0x68)
        assertTrue(H264.hasStartCode(b3, 0, b3.size))

        val noStart = byteArrayOf(0, 0, 2, 0x67)
        assertFalse(H264.hasStartCode(noStart, 0, noStart.size))
    }

    @Test
    fun convertsAvccToAnnexB() {
        // Two NALs in AVCC: [len=2][0x67, 0x42], [len=2][0x68, 0xCE]
        val avcc = byteArrayOf(
            0, 0, 0, 2, 0x67, 0x42,
            0, 0, 0, 2, 0x68, 0xCE.toByte()
        )
        assertTrue(H264.isAvcc(avcc, 0, avcc.size))

        val annexB = H264.toAnnexB(avcc)
        val expected = byteArrayOf(
            0, 0, 0, 1, 0x67, 0x42,
            0, 0, 0, 1, 0x68, 0xCE.toByte()
        )
        assertArrayEquals(expected, annexB)
    }

    @Test
    fun wrapsRawNalWithAnnexBStartCode() {
        val raw = byteArrayOf(0x65, 0x88.toByte(), 0x12) // raw IDR slice
        val annexB = H264.toAnnexB(raw)
        val expected = byteArrayOf(0, 0, 0, 1, 0x65, 0x88.toByte(), 0x12)
        assertArrayEquals(expected, annexB)
    }

    @Test
    fun idrDetection() {
        // NAL header: forbidden_zero_bit(1) | nal_ref_idc(2) | nal_unit_type(5)
        // 0x65 = 01100101 -> type 5 (IDR)
        // 0x41 = 01000001 -> type 1 (non-IDR slice)
        val idrAu = byteArrayOf(0, 0, 0, 1, 0x65, 0x10, 0x20)
        val nonIdrAu = byteArrayOf(0, 0, 0, 1, 0x41, 0x10, 0x20)

        assertTrue(H264.containsIdr(idrAu, idrAu.size))
        assertFalse(H264.containsIdr(nonIdrAu, nonIdrAu.size))
    }

    @Test
    fun parsesProfileAndLevelFromSps() {
        // SPS NAL (type 7): 0x67, profile_idc = 100 (0x64), constraint_flags = 0, level_idc = 41 (0x29)
        val sps = byteArrayOf(0, 0, 0, 1, 0x67, 0x64, 0x00, 0x29, 0x10)
        val pl = H264.profileLevel(sps)
        assertNotNull(pl)
        assertEquals(100, pl!!.first)
        assertEquals(41, pl.second)
    }

    @Test
    fun extractsParameterSets() {
        // Access unit containing SPS, PPS and IDR slice
        val full = byteArrayOf(
            0, 0, 0, 1, 0x67, 0x42, 0x00, 0x1F, // SPS
            0, 0, 0, 1, 0x68, 0xCE.toByte(),     // PPS
            0, 0, 0, 1, 0x65, 0x12, 0x34        // IDR
        )
        val csd = H264.extractParameterSets(full, full.size)
        assertNotNull(csd)

        val expectedCsd = byteArrayOf(
            0, 0, 0, 1, 0x67, 0x42, 0x00, 0x1F,
            0, 0, 0, 1, 0x68, 0xCE.toByte()
        )
        assertArrayEquals(expectedCsd, csd)

        // Without PPS returns null
        val noPps = byteArrayOf(0, 0, 0, 1, 0x67, 0x42, 0x00, 0x1F)
        assertNull(H264.extractParameterSets(noPps, noPps.size))
    }
}
