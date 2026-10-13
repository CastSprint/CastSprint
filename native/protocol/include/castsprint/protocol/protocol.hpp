// CastSprint Protocol v1 — wire format definitions and codec.
// Normative specification: docs/architecture/PROTOCOL.md
// All multi-byte integers are big-endian (network byte order).
#pragma once

#include <cstddef>
#include <cstdint>
#include <span>
#include <string>
#include <string_view>
#include <variant>
#include <vector>

namespace castsprint::protocol {

inline constexpr std::uint32_t kMagic = 0x43535052;  // "CSPR"
inline constexpr std::uint8_t kVersion = 1;
inline constexpr std::size_t kHeaderSize = 24;
inline constexpr std::uint32_t kMaxPayloadSize = 8u * 1024u * 1024u;   // media packets
inline constexpr std::uint32_t kMaxControlPayloadSize = 64u * 1024u;   // non-media packets
inline constexpr std::size_t kMaxStringBytes = 256;
inline constexpr std::size_t kMaxCodecConfigBytes = 16u * 1024u;
inline constexpr std::uint16_t kDefaultPort = 27183;

enum class MessageType : std::uint8_t {
    Hello = 0x01,
    HelloAck = 0x02,
    VideoConfig = 0x10,
    VideoFrame = 0x11,
    AudioConfig = 0x20,
    AudioFrame = 0x21,
    DisplayChanged = 0x30,
    Heartbeat = 0x40,
    Status = 0x41,
    Disconnect = 0x50,
    Error = 0x51,
};

// Header flags (u16). Undefined bits MUST be zero in v1.
inline constexpr std::uint16_t kHeaderFlagsMask = 0x0000;

// VideoFrame flags (u32).
inline constexpr std::uint32_t kFrameKeyframe = 1u << 0;
inline constexpr std::uint32_t kFrameDiscontinuity = 1u << 1;
inline constexpr std::uint32_t kFrameEndOfStream = 1u << 2;
inline constexpr std::uint32_t kFrameFlagsMask = 0x7;

// Hello capability bits (u32).
inline constexpr std::uint32_t kCapVideoH264 = 1u << 0;
inline constexpr std::uint32_t kCapAudio = 1u << 1;
inline constexpr std::uint32_t kCapVideoH265 = 1u << 2;
inline constexpr std::uint32_t kCapPlatformAndroid = 1u << 3;
inline constexpr std::uint32_t kCapPlatformIOS = 1u << 4;
inline constexpr std::uint32_t kCapPlatformMacOS = 1u << 5;
inline constexpr std::uint32_t kCapPlatformWindows = 1u << 6;

enum class VideoCodec : std::uint8_t { H264 = 1, H265 = 2 };
enum class AudioCodec : std::uint8_t { Opus = 1, Aac = 2, Pcm16 = 3 };
enum class Rotation : std::uint8_t { R0 = 0, R90 = 1, R180 = 2, R270 = 3 };

enum class HelloStatus : std::uint8_t { Accepted = 0, VersionUnsupported = 1, Busy = 2, Rejected = 3 };

enum class DisconnectReason : std::uint16_t {
    UserRequested = 1,
    Shutdown = 2,
    Timeout = 3,
    ProtocolError = 4,
    CaptureStopped = 5,
};

struct Header {
    std::uint8_t version = kVersion;
    MessageType type = MessageType::Heartbeat;
    std::uint16_t flags = 0;
    std::uint32_t sessionId = 0;
    std::uint32_t sequence = 0;
    std::uint32_t payloadLength = 0;
};

struct Hello {
    std::uint8_t minVersion = kVersion;
    std::uint8_t maxVersion = kVersion;
    std::uint32_t capabilities = 0;
    std::uint16_t androidApiLevel = 0;
    std::uint16_t screenWidth = 0;
    std::uint16_t screenHeight = 0;
    std::uint16_t densityDpi = 0;
    std::string deviceName;   // UTF-8, <= kMaxStringBytes
    std::string deviceModel;  // UTF-8, <= kMaxStringBytes
};

struct HelloAck {
    HelloStatus status = HelloStatus::Accepted;
    std::uint8_t acceptedVersion = kVersion;
    std::uint32_t assignedSessionId = 0;
    std::uint32_t maxPayloadSize = kMaxPayloadSize;
};

struct VideoConfig {
    std::uint32_t configId = 0;
    VideoCodec codec = VideoCodec::H264;
    std::uint8_t profile = 0;
    std::uint8_t level = 0;
    Rotation rotation = Rotation::R0;
    std::uint16_t width = 0;
    std::uint16_t height = 0;
    std::uint16_t frameRate = 0;
    std::uint32_t bitrate = 0;
    std::vector<std::uint8_t> codecConfig;  // Annex-B SPS/PPS
};

struct VideoFrame {
    std::uint32_t configId = 0;
    std::uint32_t frameFlags = 0;
    std::uint64_t ptsMicros = 0;
    std::vector<std::uint8_t> data;  // one Annex-B access unit
};

struct AudioConfig {
    AudioCodec codec = AudioCodec::Opus;
    std::uint8_t channels = 0;
    std::uint32_t sampleRate = 0;
    std::vector<std::uint8_t> codecConfig;
};

struct AudioFrame {
    std::uint64_t ptsMicros = 0;
    std::vector<std::uint8_t> data;
};

struct DisplayChanged {
    std::uint16_t width = 0;
    std::uint16_t height = 0;
    Rotation rotation = Rotation::R0;
    std::uint32_t nextConfigId = 0;
};

struct Heartbeat {
    std::uint64_t timestampMicros = 0;
    std::uint64_t echoTimestampMicros = 0;
};

struct Status {
    std::uint16_t code = 0;
    std::string message;
};

struct Disconnect {
    DisconnectReason reason = DisconnectReason::UserRequested;
    std::string message;
};

struct ErrorMessage {
    std::uint16_t code = 0;
    bool fatal = false;
    std::string message;
};

using Payload = std::variant<Hello, HelloAck, VideoConfig, VideoFrame, AudioConfig, AudioFrame,
                             DisplayChanged, Heartbeat, Status, Disconnect, ErrorMessage>;

struct Message {
    Header header;
    Payload payload;
};

enum class DecodeError {
    None,
    NeedMoreData,
    BadMagic,
    UnsupportedVersion,
    UnknownType,
    ReservedNotZero,
    PayloadTooLarge,
    Truncated,
    TrailingBytes,
    InvalidField,
    StringTooLong,
};

std::string_view ToString(DecodeError e) noexcept;

// Max payload permitted for a given message type.
std::uint32_t MaxPayloadFor(MessageType type) noexcept;
bool IsKnownType(std::uint8_t raw) noexcept;

// Parses and validates a 24-byte header. Does not require the payload to be present.
DecodeError DecodeHeader(std::span<const std::uint8_t> bytes, Header& out) noexcept;

// Decodes a full message (header + payload). On success sets `consumed` to the total size.
DecodeError DecodeMessage(std::span<const std::uint8_t> bytes, Message& out, std::size_t& consumed);

// Encodes a message; header.type and header.payloadLength are derived from the payload.
// Returns false if any field violates v1 limits.
bool EncodeMessage(std::uint32_t sessionId, std::uint32_t sequence, const Payload& payload,
                   std::vector<std::uint8_t>& out);

MessageType TypeOf(const Payload& payload) noexcept;

}  // namespace castsprint::protocol
