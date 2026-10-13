// CastSprint Protocol v1 — Stable C ABI Implementation
// Implements protocol_c.h bridging to castsprint::protocol.

#include "castsprint/protocol/protocol_c.h"
#include "castsprint/protocol/protocol.hpp"

#include <cstring>
#include <span>

using namespace castsprint::protocol;

static CspDecodeResult MapError(DecodeError err) {
    switch (err) {
        case DecodeError::None: return CSP_DECODE_OK;
        case DecodeError::NeedMoreData: return CSP_DECODE_NEED_MORE_DATA;
        case DecodeError::BadMagic: return CSP_DECODE_BAD_MAGIC;
        case DecodeError::UnsupportedVersion: return CSP_DECODE_UNSUPPORTED_VERSION;
        case DecodeError::UnknownType: return CSP_DECODE_UNKNOWN_TYPE;
        case DecodeError::ReservedNotZero: return CSP_DECODE_RESERVED_NOT_ZERO;
        case DecodeError::PayloadTooLarge: return CSP_DECODE_PAYLOAD_TOO_LARGE;
        case DecodeError::Truncated: return CSP_DECODE_TRUNCATED;
        case DecodeError::TrailingBytes: return CSP_DECODE_TRAILING_BYTES;
        case DecodeError::InvalidField: return CSP_DECODE_INVALID_FIELD;
        case DecodeError::StringTooLong: return CSP_DECODE_STRING_TOO_LONG;
    }
    return CSP_DECODE_INVALID_FIELD;
}

extern "C" {

CspDecodeResult csp_decode_header(const uint8_t* bytes, size_t len, CspHeader* out_hdr) {
    if (!bytes || !out_hdr) return CSP_DECODE_INVALID_FIELD;
    if (len < kHeaderSize) return CSP_DECODE_NEED_MORE_DATA;

    Header h;
    auto err = DecodeHeader(std::span<const uint8_t>(bytes, len), h);
    if (err != DecodeError::None) {
        return MapError(err);
    }

    out_hdr->version = h.version;
    out_hdr->type = static_cast<uint8_t>(h.type);
    out_hdr->flags = h.flags;
    out_hdr->session_id = h.sessionId;
    out_hdr->sequence = h.sequence;
    out_hdr->payload_length = h.payloadLength;
    return CSP_DECODE_OK;
}

bool csp_encode_header(const CspHeader* hdr, uint8_t* out_buf, size_t buf_len) {
    if (!hdr || !out_buf || buf_len < kHeaderSize) return false;

    // Big-endian serialization
    out_buf[0] = static_cast<uint8_t>((kMagic >> 24) & 0xFF);
    out_buf[1] = static_cast<uint8_t>((kMagic >> 16) & 0xFF);
    out_buf[2] = static_cast<uint8_t>((kMagic >> 8) & 0xFF);
    out_buf[3] = static_cast<uint8_t>(kMagic & 0xFF);

    out_buf[4] = hdr->version;
    out_buf[5] = hdr->type;

    out_buf[6] = static_cast<uint8_t>((hdr->flags >> 8) & 0xFF);
    out_buf[7] = static_cast<uint8_t>(hdr->flags & 0xFF);

    out_buf[8]  = static_cast<uint8_t>((hdr->session_id >> 24) & 0xFF);
    out_buf[9]  = static_cast<uint8_t>((hdr->session_id >> 16) & 0xFF);
    out_buf[10] = static_cast<uint8_t>((hdr->session_id >> 8) & 0xFF);
    out_buf[11] = static_cast<uint8_t>(hdr->session_id & 0xFF);

    out_buf[12] = static_cast<uint8_t>((hdr->sequence >> 24) & 0xFF);
    out_buf[13] = static_cast<uint8_t>((hdr->sequence >> 16) & 0xFF);
    out_buf[14] = static_cast<uint8_t>((hdr->sequence >> 8) & 0xFF);
    out_buf[15] = static_cast<uint8_t>(hdr->sequence & 0xFF);

    out_buf[16] = static_cast<uint8_t>((hdr->payload_length >> 24) & 0xFF);
    out_buf[17] = static_cast<uint8_t>((hdr->payload_length >> 16) & 0xFF);
    out_buf[18] = static_cast<uint8_t>((hdr->payload_length >> 8) & 0xFF);
    out_buf[19] = static_cast<uint8_t>(hdr->payload_length & 0xFF);

    out_buf[20] = 0;
    out_buf[21] = 0;
    out_buf[22] = 0;
    out_buf[23] = 0;

    return true;
}

size_t csp_encode_heartbeat_message(uint32_t session_id, uint32_t sequence,
                                   uint64_t ts_micros, uint64_t echo_ts_micros,
                                   uint8_t* out_buf, size_t buf_len) {
    if (!out_buf || buf_len < (kHeaderSize + 16)) return 0;

    CspHeader hdr;
    hdr.version = kVersion;
    hdr.type = static_cast<uint8_t>(MessageType::Heartbeat);
    hdr.flags = 0;
    hdr.session_id = session_id;
    hdr.sequence = sequence;
    hdr.payload_length = 16;

    if (!csp_encode_header(&hdr, out_buf, buf_len)) return 0;

    // Heartbeat payload (16 bytes: 8B ts_micros + 8B echo_ts_micros)
    uint8_t* p = out_buf + kHeaderSize;
    for (int i = 7; i >= 0; --i) {
        p[7 - i] = static_cast<uint8_t>((ts_micros >> (i * 8)) & 0xFF);
    }
    p += 8;
    for (int i = 7; i >= 0; --i) {
        p[7 - i] = static_cast<uint8_t>((echo_ts_micros >> (i * 8)) & 0xFF);
    }

    return kHeaderSize + 16;
}

bool csp_decode_heartbeat_payload(const uint8_t* payload, size_t len,
                                  uint64_t* out_ts, uint64_t* out_echo_ts) {
    if (!payload || len != 16 || !out_ts || !out_echo_ts) return false;

    uint64_t ts = 0;
    for (size_t i = 0; i < 8; ++i) {
        ts = (ts << 8) | payload[i];
    }
    uint64_t echo = 0;
    for (size_t i = 8; i < 16; ++i) {
        echo = (echo << 8) | payload[i];
    }

    *out_ts = ts;
    *out_echo_ts = echo;
    return true;
}

bool csp_encode_video_frame_prefix(uint32_t config_id, uint32_t frame_flags,
                                   uint64_t pts_micros, uint8_t* out_buf, size_t buf_len) {
    if (!out_buf || buf_len < 16) return false;

    out_buf[0] = static_cast<uint8_t>((config_id >> 24) & 0xFF);
    out_buf[1] = static_cast<uint8_t>((config_id >> 16) & 0xFF);
    out_buf[2] = static_cast<uint8_t>((config_id >> 8) & 0xFF);
    out_buf[3] = static_cast<uint8_t>(config_id & 0xFF);

    out_buf[4] = static_cast<uint8_t>((frame_flags >> 24) & 0xFF);
    out_buf[5] = static_cast<uint8_t>((frame_flags >> 16) & 0xFF);
    out_buf[6] = static_cast<uint8_t>((frame_flags >> 8) & 0xFF);
    out_buf[7] = static_cast<uint8_t>(frame_flags & 0xFF);

    for (int i = 7; i >= 0; --i) {
        out_buf[8 + (7 - i)] = static_cast<uint8_t>((pts_micros >> (i * 8)) & 0xFF);
    }
    return true;
}

bool csp_decode_video_frame_prefix(const uint8_t* payload, size_t len,
                                   uint32_t* out_config_id, uint32_t* out_flags,
                                   uint64_t* out_pts_micros, size_t* out_data_offset) {
    if (!payload || len < 16 || !out_config_id || !out_flags || !out_pts_micros || !out_data_offset) {
        return false;
    }

    *out_config_id = (static_cast<uint32_t>(payload[0]) << 24) |
                     (static_cast<uint32_t>(payload[1]) << 16) |
                     (static_cast<uint32_t>(payload[2]) << 8)  |
                      static_cast<uint32_t>(payload[3]);

    *out_flags = (static_cast<uint32_t>(payload[4]) << 24) |
                 (static_cast<uint32_t>(payload[5]) << 16) |
                 (static_cast<uint32_t>(payload[6]) << 8)  |
                  static_cast<uint32_t>(payload[7]);

    uint64_t pts = 0;
    for (size_t i = 8; i < 16; ++i) {
        pts = (pts << 8) | payload[i];
    }
    *out_pts_micros = pts;
    *out_data_offset = 16;
    return true;
}

bool csp_encode_audio_frame_prefix(uint64_t pts_micros, uint8_t* out_buf, size_t buf_len) {
    if (!out_buf || buf_len < 8) return false;
    for (int i = 7; i >= 0; --i) {
        out_buf[7 - i] = static_cast<uint8_t>((pts_micros >> (i * 8)) & 0xFF);
    }
    return true;
}

bool csp_decode_audio_frame_prefix(const uint8_t* payload, size_t len,
                                   uint64_t* out_pts_micros, size_t* out_data_offset) {
    if (!payload || len < 8 || !out_pts_micros || !out_data_offset) return false;
    uint64_t pts = 0;
    for (size_t i = 0; i < 8; ++i) {
        pts = (pts << 8) | payload[i];
    }
    *out_pts_micros = pts;
    *out_data_offset = 8;
    return true;
}

const char* csp_decode_result_string(CspDecodeResult res) {
    switch (res) {
        case CSP_DECODE_OK: return "OK";
        case CSP_DECODE_NEED_MORE_DATA: return "NeedMoreData";
        case CSP_DECODE_BAD_MAGIC: return "BadMagic";
        case CSP_DECODE_UNSUPPORTED_VERSION: return "UnsupportedVersion";
        case CSP_DECODE_UNKNOWN_TYPE: return "UnknownType";
        case CSP_DECODE_RESERVED_NOT_ZERO: return "ReservedNotZero";
        case CSP_DECODE_PAYLOAD_TOO_LARGE: return "PayloadTooLarge";
        case CSP_DECODE_TRUNCATED: return "Truncated";
        case CSP_DECODE_TRAILING_BYTES: return "TrailingBytes";
        case CSP_DECODE_INVALID_FIELD: return "InvalidField";
        case CSP_DECODE_STRING_TOO_LONG: return "StringTooLong";
    }
    return "UnknownError";
}

} // extern "C"
