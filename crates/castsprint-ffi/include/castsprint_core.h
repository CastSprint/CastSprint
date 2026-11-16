// CastSprint Protocol & Core Engine — Stable C-ABI Header
// Generated for Swift (macOS / iOS), Android JNI, and Native Embedding.
// Normative specification: docs/architecture/PROTOCOL.md and AUDIO_AND_LAN.md

#ifndef CASTSPRINT_CORE_H
#define CASTSPRINT_CORE_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#define CSP_MAGIC 0x43535052u
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
    CSP_DECODE_NEED_MORE_DATA = 1,
    CSP_DECODE_BAD_MAGIC = 2,
    CSP_DECODE_UNSUPPORTED_VERSION = 3,
    CSP_DECODE_UNKNOWN_TYPE = 4,
    CSP_DECODE_RESERVED_NOT_ZERO = 5,
    CSP_DECODE_PAYLOAD_TOO_LARGE = 6,
    CSP_DECODE_TRUNCATED = 7,
    CSP_DECODE_TRAILING_BYTES = 8,
    CSP_DECODE_INVALID_FIELD = 9,
    CSP_DECODE_STRING_TOO_LONG = 10
} CspDecodeResult;

typedef struct {
    uint8_t version;
    uint8_t type;
    uint16_t flags;
    uint32_t session_id;
    uint32_t sequence;
    uint32_t payload_length;
} CspHeader;

typedef struct {
    uint8_t action; // 0 = PresentNow, 1 = Wait, 2 = DropLate
    int64_t wait_micros;
    int64_t skew_micros;
} CspSyncDecision;

typedef struct {
    uint64_t total_bytes_received;
    uint32_t video_frames_received;
    uint32_t audio_frames_received;
    uint32_t keyframes_received;
    uint32_t dropped_frames;
    double current_fps;
    double current_bitrate_mbps;
    uint64_t last_rtt_micros;
    int64_t estimated_clock_offset_micros;
} CspSessionStats;

// --- Codec Functions ---
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
size_t csp_encode_hello_ack_message(uint32_t session_id, uint32_t sequence,
                                    uint8_t status, uint8_t accepted_version,
                                    uint32_t max_payload_size,
                                    uint8_t* out_buf, size_t buf_len);
bool csp_decode_hello_payload(const uint8_t* payload, size_t len,
                              uint8_t* out_min_ver, uint8_t* out_max_ver,
                              uint32_t* out_caps, uint16_t* out_api_level,
                              uint16_t* out_width, uint16_t* out_height,
                              uint16_t* out_dpi,
                              char* out_name, size_t name_buf_len,
                              char* out_model, size_t model_buf_len);
bool csp_decode_video_config_payload(const uint8_t* payload, size_t len,
                                     uint32_t* out_config_id, uint8_t* out_codec,
                                     uint8_t* out_rotation,
                                     uint16_t* out_width, uint16_t* out_height,
                                     uint16_t* out_fps, uint32_t* out_bitrate,
                                     size_t* out_csd_offset, size_t* out_csd_len);
bool csp_decode_audio_config_payload(const uint8_t* payload, size_t len,
                                     uint8_t* out_codec, uint8_t* out_channels,
                                     uint32_t* out_sample_rate,
                                     size_t* out_csd_offset, size_t* out_csd_len);
const char* csp_decode_result_string(CspDecodeResult res);

// --- AV Synchronizer Functions ---
void* csp_sync_create(uint8_t preset);
void csp_sync_on_audio_rendered(void* sync_ptr, uint64_t audio_pts, uint64_t host_time);
void csp_sync_evaluate_video(void* sync_ptr, uint64_t video_pts, uint64_t host_time, CspSyncDecision* out_decision);
void csp_sync_reset(void* sync_ptr);
void csp_sync_destroy(void* sync_ptr);

// --- Session Manager Functions ---
void* csp_session_create(void);
void csp_session_init_pairing(void* session_ptr, const char* cert_fp, const char* pin);
bool csp_session_get_pin(void* session_ptr, char* out_buf, size_t max_len);
void csp_session_get_stats(void* session_ptr, CspSessionStats* out_stats);
void csp_session_destroy(void* session_ptr);

#ifdef __cplusplus
}
#endif

#endif // CASTSPRINT_CORE_H
