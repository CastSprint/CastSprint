// protocol_c.c — C ABI Implementation for CastSprint Protocol v1
#include "CCastSprintProtocol.h"
#include <string.h>

CspDecodeResult csp_decode_header(const uint8_t* bytes, size_t len, CspHeader* out_hdr) {
    if (!bytes || !out_hdr) return CSP_DECODE_INVALID_FIELD;
    if (len < CSP_HEADER_SIZE) return CSP_DECODE_NEED_MORE_DATA;

    uint32_t magic = ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) |
                     ((uint32_t)bytes[2] << 8)  |  (uint32_t)bytes[3];
    if (magic != CSP_MAGIC) return CSP_DECODE_BAD_MAGIC;

    uint8_t version = bytes[4];
    if (version != CSP_VERSION) return CSP_DECODE_UNSUPPORTED_VERSION;

    uint8_t type = bytes[5];
    uint16_t flags = ((uint16_t)bytes[6] << 8) | (uint16_t)bytes[7];
    if (flags != 0) return CSP_DECODE_RESERVED_NOT_ZERO;

    uint32_t session_id = ((uint32_t)bytes[8] << 24) | ((uint32_t)bytes[9] << 16) |
                          ((uint32_t)bytes[10] << 8) |  (uint32_t)bytes[11];
    uint32_t sequence = ((uint32_t)bytes[12] << 24) | ((uint32_t)bytes[13] << 16) |
                        ((uint32_t)bytes[14] << 8)  |  (uint32_t)bytes[15];
    uint32_t payload_len = ((uint32_t)bytes[16] << 24) | ((uint32_t)bytes[17] << 16) |
                           ((uint32_t)bytes[18] << 8)  |  (uint32_t)bytes[19];

    uint32_t reserved = ((uint32_t)bytes[20] << 24) | ((uint32_t)bytes[21] << 16) |
                        ((uint32_t)bytes[22] << 8)  |  (uint32_t)bytes[23];
    if (reserved != 0) return CSP_DECODE_RESERVED_NOT_ZERO;

    uint32_t limit = (type == CSP_MSG_VIDEO_FRAME || type == CSP_MSG_AUDIO_FRAME) ?
                     CSP_MAX_PAYLOAD_SIZE : CSP_MAX_CONTROL_PAYLOAD_SIZE;
    if (payload_len > limit) return CSP_DECODE_PAYLOAD_TOO_LARGE;

    out_hdr->version = version;
    out_hdr->type = type;
    out_hdr->flags = flags;
    out_hdr->session_id = session_id;
    out_hdr->sequence = sequence;
    out_hdr->payload_length = payload_len;
    return CSP_DECODE_OK;
}

bool csp_encode_header(const CspHeader* hdr, uint8_t* out_buf, size_t buf_len) {
    if (!hdr || !out_buf || buf_len < CSP_HEADER_SIZE) return false;

    out_buf[0] = (uint8_t)((CSP_MAGIC >> 24) & 0xFF);
    out_buf[1] = (uint8_t)((CSP_MAGIC >> 16) & 0xFF);
    out_buf[2] = (uint8_t)((CSP_MAGIC >> 8) & 0xFF);
    out_buf[3] = (uint8_t)(CSP_MAGIC & 0xFF);

    out_buf[4] = hdr->version;
    out_buf[5] = hdr->type;

    out_buf[6] = (uint8_t)((hdr->flags >> 8) & 0xFF);
    out_buf[7] = (uint8_t)(hdr->flags & 0xFF);

    out_buf[8]  = (uint8_t)((hdr->session_id >> 24) & 0xFF);
    out_buf[9]  = (uint8_t)((hdr->session_id >> 16) & 0xFF);
    out_buf[10] = (uint8_t)((hdr->session_id >> 8) & 0xFF);
    out_buf[11] = (uint8_t)(hdr->session_id & 0xFF);

    out_buf[12] = (uint8_t)((hdr->sequence >> 24) & 0xFF);
    out_buf[13] = (uint8_t)((hdr->sequence >> 16) & 0xFF);
    out_buf[14] = (uint8_t)((hdr->sequence >> 8) & 0xFF);
    out_buf[15] = (uint8_t)(hdr->sequence & 0xFF);

    out_buf[16] = (uint8_t)((hdr->payload_length >> 24) & 0xFF);
    out_buf[17] = (uint8_t)((hdr->payload_length >> 16) & 0xFF);
    out_buf[18] = (uint8_t)((hdr->payload_length >> 8) & 0xFF);
    out_buf[19] = (uint8_t)(hdr->payload_length & 0xFF);

    out_buf[20] = 0;
    out_buf[21] = 0;
    out_buf[22] = 0;
    out_buf[23] = 0;
    return true;
}

size_t csp_encode_heartbeat_message(uint32_t session_id, uint32_t sequence,
                                   uint64_t ts_micros, uint64_t echo_ts_micros,
                                   uint8_t* out_buf, size_t buf_len) {
    if (!out_buf || buf_len < (CSP_HEADER_SIZE + 16)) return 0;

    CspHeader hdr;
    hdr.version = CSP_VERSION;
    hdr.type = CSP_MSG_HEARTBEAT;
    hdr.flags = 0;
    hdr.session_id = session_id;
    hdr.sequence = sequence;
    hdr.payload_length = 16;

    if (!csp_encode_header(&hdr, out_buf, buf_len)) return 0;

    uint8_t* p = out_buf + CSP_HEADER_SIZE;
    for (int i = 7; i >= 0; --i) {
        p[7 - i] = (uint8_t)((ts_micros >> (i * 8)) & 0xFF);
    }
    p += 8;
    for (int i = 7; i >= 0; --i) {
        p[7 - i] = (uint8_t)((echo_ts_micros >> (i * 8)) & 0xFF);
    }

    return CSP_HEADER_SIZE + 16;
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

    out_buf[0] = (uint8_t)((config_id >> 24) & 0xFF);
    out_buf[1] = (uint8_t)((config_id >> 16) & 0xFF);
    out_buf[2] = (uint8_t)((config_id >> 8) & 0xFF);
    out_buf[3] = (uint8_t)(config_id & 0xFF);

    out_buf[4] = (uint8_t)((frame_flags >> 24) & 0xFF);
    out_buf[5] = (uint8_t)((frame_flags >> 16) & 0xFF);
    out_buf[6] = (uint8_t)((frame_flags >> 8) & 0xFF);
    out_buf[7] = (uint8_t)(frame_flags & 0xFF);

    for (int i = 7; i >= 0; --i) {
        out_buf[8 + (7 - i)] = (uint8_t)((pts_micros >> (i * 8)) & 0xFF);
    }
    return true;
}

bool csp_decode_video_frame_prefix(const uint8_t* payload, size_t len,
                                   uint32_t* out_config_id, uint32_t* out_flags,
                                   uint64_t* out_pts_micros, size_t* out_data_offset) {
    if (!payload || len < 16 || !out_config_id || !out_flags || !out_pts_micros || !out_data_offset) {
        return false;
    }

    *out_config_id = ((uint32_t)payload[0] << 24) | ((uint32_t)payload[1] << 16) |
                     ((uint32_t)payload[2] << 8)  |  (uint32_t)payload[3];

    *out_flags = ((uint32_t)payload[4] << 24) | ((uint32_t)payload[5] << 16) |
                 ((uint32_t)payload[6] << 8)  |  (uint32_t)payload[7];

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
        out_buf[7 - i] = (uint8_t)((pts_micros >> (i * 8)) & 0xFF);
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

size_t csp_encode_hello_ack_message(uint32_t session_id, uint32_t sequence,
                                    uint8_t status, uint8_t accepted_version,
                                    uint32_t max_payload_size,
                                    uint8_t* out_buf, size_t buf_len) {
    if (!out_buf || buf_len < (CSP_HEADER_SIZE + 12)) return 0;

    CspHeader hdr;
    hdr.version = CSP_VERSION;
    hdr.type = CSP_MSG_HELLO_ACK;
    hdr.flags = 0;
    hdr.session_id = session_id;
    hdr.sequence = sequence;
    hdr.payload_length = 12;

    if (!csp_encode_header(&hdr, out_buf, buf_len)) return 0;

    uint8_t* p = out_buf + CSP_HEADER_SIZE;
    p[0] = status;
    p[1] = accepted_version;
    p[2] = 0; // reserved
    p[3] = 0;

    p[4] = (uint8_t)((session_id >> 24) & 0xFF);
    p[5] = (uint8_t)((session_id >> 16) & 0xFF);
    p[6] = (uint8_t)((session_id >> 8) & 0xFF);
    p[7] = (uint8_t)(session_id & 0xFF);

    p[8]  = (uint8_t)((max_payload_size >> 24) & 0xFF);
    p[9]  = (uint8_t)((max_payload_size >> 16) & 0xFF);
    p[10] = (uint8_t)((max_payload_size >> 8) & 0xFF);
    p[11] = (uint8_t)(max_payload_size & 0xFF);

    return CSP_HEADER_SIZE + 12;
}

bool csp_decode_hello_payload(const uint8_t* payload, size_t len,
                              uint8_t* out_min_ver, uint8_t* out_max_ver,
                              uint32_t* out_caps, uint16_t* out_api_level,
                              uint16_t* out_width, uint16_t* out_height,
                              uint16_t* out_dpi,
                              char* out_name, size_t name_buf_len,
                              char* out_model, size_t model_buf_len) {
    if (!payload || len < 16) return false;

    if (out_min_ver) *out_min_ver = payload[0];
    if (out_max_ver) *out_max_ver = payload[1];

    if (out_caps) {
        *out_caps = ((uint32_t)payload[4] << 24) | ((uint32_t)payload[5] << 16) |
                    ((uint32_t)payload[6] << 8)  |  (uint32_t)payload[7];
    }
    if (out_api_level) {
        *out_api_level = ((uint16_t)payload[8] << 8) | (uint16_t)payload[9];
    }
    if (out_width) {
        *out_width = ((uint16_t)payload[10] << 8) | (uint16_t)payload[11];
    }
    if (out_height) {
        *out_height = ((uint16_t)payload[12] << 8) | (uint16_t)payload[13];
    }
    if (out_dpi) {
        *out_dpi = ((uint16_t)payload[14] << 8) | (uint16_t)payload[15];
    }

    size_t offset = 16;
    if (offset + 2 <= len) {
        uint16_t name_len = ((uint16_t)payload[offset] << 8) | (uint16_t)payload[offset + 1];
        offset += 2;
        if (offset + name_len <= len && out_name && name_buf_len > 0) {
            size_t copy_len = name_len < (name_buf_len - 1) ? name_len : (name_buf_len - 1);
            memcpy(out_name, payload + offset, copy_len);
            out_name[copy_len] = '\0';
        }
        offset += name_len;
    }

    if (offset + 2 <= len) {
        uint16_t model_len = ((uint16_t)payload[offset] << 8) | (uint16_t)payload[offset + 1];
        offset += 2;
        if (offset + model_len <= len && out_model && model_buf_len > 0) {
            size_t copy_len = model_len < (model_buf_len - 1) ? model_len : (model_buf_len - 1);
            memcpy(out_model, payload + offset, copy_len);
            out_model[copy_len] = '\0';
        }
    }

    return true;
}

bool csp_decode_video_config_payload(const uint8_t* payload, size_t len,
                                     uint32_t* out_config_id, uint8_t* out_codec,
                                     uint8_t* out_rotation,
                                     uint16_t* out_width, uint16_t* out_height,
                                     uint16_t* out_fps, uint32_t* out_bitrate,
                                     size_t* out_csd_offset, size_t* out_csd_len) {
    if (!payload || len < 24) return false;

    if (out_config_id) {
        *out_config_id = ((uint32_t)payload[0] << 24) | ((uint32_t)payload[1] << 16) |
                         ((uint32_t)payload[2] << 8)  |  (uint32_t)payload[3];
    }
    if (out_codec) *out_codec = payload[4];
    if (out_rotation) *out_rotation = payload[7];

    if (out_width) {
        *out_width = ((uint16_t)payload[8] << 8) | (uint16_t)payload[9];
    }
    if (out_height) {
        *out_height = ((uint16_t)payload[10] << 8) | (uint16_t)payload[11];
    }
    if (out_fps) {
        *out_fps = ((uint16_t)payload[12] << 8) | (uint16_t)payload[13];
    }
    if (out_bitrate) {
        *out_bitrate = ((uint32_t)payload[16] << 24) | ((uint32_t)payload[17] << 16) |
                       ((uint32_t)payload[18] << 8)  |  (uint32_t)payload[19];
    }

    uint32_t csd_len = ((uint32_t)payload[20] << 24) | ((uint32_t)payload[21] << 16) |
                       ((uint32_t)payload[22] << 8)  |  (uint32_t)payload[23];
    if (out_csd_len) *out_csd_len = csd_len;
    if (out_csd_offset) *out_csd_offset = 24;

    return (24 + csd_len <= len);
}

bool csp_decode_audio_config_payload(const uint8_t* payload, size_t len,
                                     uint8_t* out_codec, uint8_t* out_channels,
                                     uint32_t* out_sample_rate,
                                     size_t* out_csd_offset, size_t* out_csd_len) {
    if (!payload || len < 12) return false;

    if (out_codec) *out_codec = payload[0];
    if (out_channels) *out_channels = payload[1];
    if (out_sample_rate) {
        *out_sample_rate = ((uint32_t)payload[4] << 24) | ((uint32_t)payload[5] << 16) |
                           ((uint32_t)payload[6] << 8)  |  (uint32_t)payload[7];
    }
    uint32_t csd_len = ((uint32_t)payload[8] << 24) | ((uint32_t)payload[9] << 16) |
                       ((uint32_t)payload[10] << 8) |  (uint32_t)payload[11];
    if (out_csd_len) *out_csd_len = csd_len;
    if (out_csd_offset) *out_csd_offset = 12;

    return (12 + csd_len <= len);
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
