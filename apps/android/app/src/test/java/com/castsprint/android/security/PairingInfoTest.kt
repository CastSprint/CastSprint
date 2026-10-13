package com.castsprint.android.security

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PairingInfoTest {

    @Test
    fun testParseCsvFormat() {
        val csv = "192.168.1.100,27183,e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855,123456,Gaming-PC"
        val info = PairingInfo.parse(csv)
        assertNotNull(info)
        assertEquals("192.168.1.100", info!!.host)
        assertEquals(27183, info.port)
        assertEquals("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", info.fingerprintSha256)
        assertEquals("123456", info.sessionToken)
        assertEquals("Gaming-PC", info.receiverName)
    }

    @Test
    fun testParseCsvDefaultName() {
        val csv = "192.168.1.50, 27183, abcdef, 654321"
        val info = PairingInfo.parse(csv)
        assertNotNull(info)
        assertEquals("192.168.1.50", info!!.host)
        assertEquals(27183, info.port)
        assertEquals("abcdef", info.fingerprintSha256)
        assertEquals("654321", info.sessionToken)
        assertEquals("Windows PC", info.receiverName)
    }

    @Test
    fun testParseInvalidInputs() {
        assertNull(PairingInfo.parse(""))
        assertNull(PairingInfo.parse("   "))
        assertNull(PairingInfo.parse("invalid_input_without_csv_or_uri"))
        assertNull(PairingInfo.parse("host,port")) // insufficient fields
    }

    @Test
    fun testFingerprintNormalization() {
        val rawFp = "E3:B0:C4:42:98:FC:1C:14:9A:FB:F4:C8:99:6F:B9:24:27:AE:41:E4:64:9B:93:4C:A4:95:99:1B:78:52:B8:55"
        val normalized = TlsPinningSocketFactory.normalizeFingerprint(rawFp)
        assertEquals("E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855", normalized)
    }
}
