// CCastSprintProtocol.h — C ABI for CastSprint Protocol v1 in Swift
#ifndef C_CASTSPRINT_PROTOCOL_H
#define C_CASTSPRINT_PROTOCOL_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#define CSP_MAGIC 0x43535052u  // "CSPR"
#define CSP_VERSION 1u
#define CSP_HEADER_SIZE 24u
#define CSP_MAX_PAYLOAD_SIZE (8u * 1024u * 1024u)
#define CSP_MAX_CONTROL_PAYLOAD_SIZE (64u * 1024u)
#define CSP_MAX_STRING_BYTES 256u
#define CSP_MAX_CODEC_CONFIG_BYTES (16u * 1024u)
#define CSP_DEFAULT_PORT 27183u

#define CSP_CAP_VIDEO_H264       (1u << 0)
#define CSP_CAP_AUDIO            (1u << 1)
#define CSP_CAP_VIDEO_H265       (1u << 2)
#define CSP_CAP_PLATFORM_ANDROID (1u << 3)
#define CSP_CAP_PLATFORM_IOS     (1u << 4)
#define CSP_CAP_PLATFORM_MACOS   (1u << 5)
#define CSP_CAP_PLATFORM_WINDOWS (1u << 6)

#define CSP_FRAME_KEYFRAME       (1u << 0)
#define CSP_FRAME_DISCONTINUITY  (1u << 1)
#define CSP_FRAME_END_OF_STREAM  (1u << 2)

typedef enum {
    CSP_MSG_HELLO           = 0x01,
    CSP_MSG_HELLO_ACK       = 0x02,
    CSP_MSG_VIDEO_CONFIG    = 0x10,
    CSP_MSG_VIDEO_FRAME     = 0x11,
    CSP_MSG_AUDIO_CONFIG    = 0x20,
    CSP_MSG_AUDIO_FRAME     = 0x21,
    CSP_MSG_DISPLAY_CHANGED = 0x30,
    CSP_MSG_HEARTBEAT       = 0x40,
    CSP_MSG_STATUS          = 0x41,
    CSP_MSG_DISCONNECT      = 0x50,
    CSP_MSG_ERROR           = 0x51
} CspMessageType;

typedef enum {
    CSP_DECODE_OK = 0,
    CSP_DECODE_NEED_MORE_DATA,
    CSP_DECODE_BAD_MAGIC,
    CSP_DECODE_UNSUPPORTED_VERSION,
    CSP_DECODE_UNKNOWN_TYPE,
    CSP_DECODE_RESERVED_NOT_ZERO,
    CSP_DECODE_PAYLOAD_TOO_LARGE,
    CSP_DECODE_TRUNCATED,
    CSP_DECODE_TRAILING_BYTES,
    CSP_DECODE_INVALID_FIELD,
    CSP_DECODE_STRING_TOO_LONG
} CspDecodeResult;

typedef struct {
    uint8_t version;
    uint8_t type;
    uint16_t flags;
    uint32_t session_id;
    uint32_t sequence;
    uint32_t payload_length;
} CspHeader;

CspDecodeResult csp_decode_header(const uint8_t* bytes, size_t len, CspHeader* out_hdr);
bool csp_encode_header(const CspHeader* hdr, uint8_t* out_buf, size_t buf_len);
size_t csp_encode_heartbeat_message(uint32_t session_id, uint32_t sequence,
                                   uint64_t ts_micros, uint64_t echo_ts_micros,
                                   uint8_t* out_buf, size_t buf_len);
bool csp_decode_heartbeat_payload(const uint8_t* payload, size_t len,
                                  uint64_t* out_ts, uint64_t* out_echo_ts);
bool csp_encode_video_frame_prefix(uint32_t config_id, uint32_t frame_flags,
                                   uint64_t pts_micros, uint8_t* out_buf, size_t buf_len);
bool csp_decode_video_frame_prefix(const uint8_t* payload, size_t len,
                                   uint32_t* out_config_id, uint32_t* out_flags,
                                   uint64_t* out_pts_micros, size_t* out_data_offset);
bool csp_encode_audio_frame_prefix(uint64_t pts_micros, uint8_t* out_buf, size_t buf_len);
bool csp_decode_audio_frame_prefix(const uint8_t* payload, size_t len,
                                   uint64_t* out_pts_micros, size_t* out_data_offset);
const char* csp_decode_result_string(CspDecodeResult res);

#ifdef __cplusplus
}
#endif

#endif // C_CASTSPRINT_PROTOCOL_H
