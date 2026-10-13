// CastSprint Protocol v1 — Stable C ABI Header
// Designed for seamless interop with Swift (macOS / iOS), Objective-C, and C23/C++20.
// Normative specification: docs/architecture/PROTOCOL.md

#ifndef CASTSPRINT_PROTOCOL_C_H
#define CASTSPRINT_PROTOCOL_C_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Constants
#define CSP_MAGIC 0x43535052u  // "CSPR"
#define CSP_VERSION 1u
#define CSP_HEADER_SIZE 24u
#define CSP_MAX_PAYLOAD_SIZE (8u * 1024u * 1024u)
#define CSP_MAX_CONTROL_PAYLOAD_SIZE (64u * 1024u)
#define CSP_MAX_STRING_BYTES 256u
#define CSP_MAX_CODEC_CONFIG_BYTES (16u * 1024u)
#define CSP_DEFAULT_PORT 27183u

// Capability flags (bitfield in Hello message)
#define CSP_CAP_VIDEO_H264       (1u << 0)
#define CSP_CAP_AUDIO            (1u << 1)
#define CSP_CAP_VIDEO_H265       (1u << 2)
#define CSP_CAP_PLATFORM_ANDROID (1u << 3)
#define CSP_CAP_PLATFORM_IOS     (1u << 4)
#define CSP_CAP_PLATFORM_MACOS   (1u << 5)
#define CSP_CAP_PLATFORM_WINDOWS (1u << 6)

// Video Frame Flags
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
    CSP_VIDEO_CODEC_H264 = 1,
    CSP_VIDEO_CODEC_H265 = 2
} CspVideoCodec;

typedef enum {
    CSP_AUDIO_CODEC_OPUS = 1,
    CSP_AUDIO_CODEC_AAC  = 2,
    CSP_AUDIO_CODEC_PCM16= 3
} CspAudioCodec;

typedef enum {
    CSP_ROTATION_0   = 0,
    CSP_ROTATION_90  = 1,
    CSP_ROTATION_180 = 2,
    CSP_ROTATION_270 = 3
} CspRotation;

typedef enum {
    CSP_HELLO_ACCEPTED            = 0,
    CSP_HELLO_VERSION_UNSUPPORTED = 1,
    CSP_HELLO_BUSY                = 2,
    CSP_HELLO_REJECTED            = 3
} CspHelloStatus;

typedef enum {
    CSP_DISCONNECT_USER_REQUESTED = 1,
    CSP_DISCONNECT_SHUTDOWN       = 2,
    CSP_DISCONNECT_TIMEOUT        = 3,
    CSP_DISCONNECT_PROTOCOL_ERROR = 4,
    CSP_DISCONNECT_CAPTURE_STOPPED= 5
} CspDisconnectReason;

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

// Raw 24-byte protocol header
typedef struct {
    uint8_t version;
    uint8_t type;
    uint16_t flags;
    uint32_t session_id;
    uint32_t sequence;
    uint32_t payload_length;
} CspHeader;

// Hello payload
typedef struct {
    uint8_t min_version;
    uint8_t max_version;
    uint32_t capabilities;
    uint16_t android_api_level;
    uint16_t screen_width;
    uint16_t screen_height;
    uint16_t density_dpi;
    const char* device_name;
    const char* device_model;
} CspHello;

// HelloAck payload
typedef struct {
    uint8_t status;
    uint8_t accepted_version;
    uint32_t assigned_session_id;
    uint32_t max_payload_size;
} CspHelloAck;

// VideoConfig payload
typedef struct {
    uint32_t config_id;
    uint8_t codec;
    uint8_t profile;
    uint8_t level;
    uint8_t rotation;
    uint16_t width;
    uint16_t height;
    uint16_t frame_rate;
    uint32_t bitrate;
    uint32_t csd_len;
    const uint8_t* csd;
} CspVideoConfig;

// AudioConfig payload
typedef struct {
    uint8_t codec;
    uint8_t channels;
    uint32_t sample_rate;
    uint32_t csd_len;
    const uint8_t* csd;
} CspAudioConfig;

// --- C API Functions ---

// Decodes a 24-byte header.
CspDecodeResult csp_decode_header(const uint8_t* bytes, size_t len, CspHeader* out_hdr);

// Encodes a 24-byte header into out_buf (must be at least 24 bytes).
bool csp_encode_header(const CspHeader* hdr, uint8_t* out_buf, size_t buf_len);

// Encodes a complete Heartbeat message (24 bytes header + 16 bytes payload = 40 bytes total).
// Buffer must be at least 40 bytes. Returns bytes written (40) or 0 on error.
size_t csp_encode_heartbeat_message(uint32_t session_id, uint32_t sequence,
                                   uint64_t ts_micros, uint64_t echo_ts_micros,
                                   uint8_t* out_buf, size_t buf_len);

// Decodes a Heartbeat payload (16 bytes).
bool csp_decode_heartbeat_payload(const uint8_t* payload, size_t len,
                                  uint64_t* out_ts, uint64_t* out_echo_ts);

// Encodes a VideoFrame header prefix into a 16-byte buffer:
// config_id (4B) + frame_flags (4B) + pts_micros (8B).
bool csp_encode_video_frame_prefix(uint32_t config_id, uint32_t frame_flags,
                                   uint64_t pts_micros, uint8_t* out_buf, size_t buf_len);

// Decodes a VideoFrame header prefix from payload bytes.
bool csp_decode_video_frame_prefix(const uint8_t* payload, size_t len,
                                   uint32_t* out_config_id, uint32_t* out_flags,
                                   uint64_t* out_pts_micros, size_t* out_data_offset);

// Encodes an AudioFrame header prefix into an 8-byte buffer: pts_micros (8B).
bool csp_encode_audio_frame_prefix(uint64_t pts_micros, uint8_t* out_buf, size_t buf_len);

// Decodes an AudioFrame header prefix from payload bytes.
bool csp_decode_audio_frame_prefix(const uint8_t* payload, size_t len,
                                   uint64_t* out_pts_micros, size_t* out_data_offset);

// Human-readable error description
const char* csp_decode_result_string(CspDecodeResult res);

#ifdef __cplusplus
}
#endif

#endif // CASTSPRINT_PROTOCOL_C_H
