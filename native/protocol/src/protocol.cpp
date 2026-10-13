// CastSprint Protocol v1 codec implementation.
#include "castsprint/protocol/protocol.hpp"

#include <iterator>
#include <type_traits>

namespace castsprint::protocol {
namespace {

class Writer {
public:
    explicit Writer(std::vector<std::uint8_t>& out) : out_(out) {}
    void U8(std::uint8_t v) { out_.push_back(v); }
    void U16(std::uint16_t v) {
        out_.push_back(static_cast<std::uint8_t>(v >> 8));
        out_.push_back(static_cast<std::uint8_t>(v));
    }
    void U32(std::uint32_t v) {
        U16(static_cast<std::uint16_t>(v >> 16));
        U16(static_cast<std::uint16_t>(v));
    }
    void U64(std::uint64_t v) {
        U32(static_cast<std::uint32_t>(v >> 32));
        U32(static_cast<std::uint32_t>(v));
    }
    void Bytes(std::span<const std::uint8_t> b) { out_.insert(out_.end(), b.begin(), b.end()); }
    void Str(const std::string& s) {
        U16(static_cast<std::uint16_t>(s.size()));
        out_.insert(out_.end(), s.begin(), s.end());
    }

private:
    std::vector<std::uint8_t>& out_;
};

class Reader {
public:
    explicit Reader(std::span<const std::uint8_t> in) : in_(in) {}
    bool Ok() const noexcept { return ok_; }
    std::size_t Remaining() const noexcept { return in_.size() - pos_; }

    std::uint8_t U8() {
        if (!Need(1)) return 0;
        return in_[pos_++];
    }
    std::uint16_t U16() {
        if (!Need(2)) return 0;
        auto v = static_cast<std::uint16_t>((in_[pos_] << 8) | in_[pos_ + 1]);
        pos_ += 2;
        return v;
    }
    std::uint32_t U32() {
        std::uint32_t hi = U16();
        std::uint32_t lo = U16();
        return (hi << 16) | lo;
    }
    std::uint64_t U64() {
        std::uint64_t hi = U32();
        std::uint64_t lo = U32();
        return (hi << 32) | lo;
    }
    bool Bytes(std::size_t n, std::vector<std::uint8_t>& out) {
        if (!Need(n)) return false;
        out.assign(in_.begin() + static_cast<std::ptrdiff_t>(pos_),
                   in_.begin() + static_cast<std::ptrdiff_t>(pos_ + n));
        pos_ += n;
        return true;
    }
    // Returns DecodeError::None, StringTooLong or Truncated.
    DecodeError Str(std::string& out) {
        std::uint16_t len = U16();
        if (!ok_) return DecodeError::Truncated;
        if (len > kMaxStringBytes) return DecodeError::StringTooLong;
        if (!Need(len)) return DecodeError::Truncated;
        out.assign(reinterpret_cast<const char*>(in_.data() + pos_), len);
        pos_ += len;
        return DecodeError::None;
    }

private:
    bool Need(std::size_t n) {
        if (!ok_ || Remaining() < n) {
            ok_ = false;
            return false;
        }
        return true;
    }
    std::span<const std::uint8_t> in_;
    std::size_t pos_ = 0;
    bool ok_ = true;
};

bool ValidRotation(std::uint8_t r) { return r <= 3; }

// ---- payload encoders: return false on limit violations ----

bool Enc(Writer& w, const Hello& m) {
    if (m.deviceName.size() > kMaxStringBytes || m.deviceModel.size() > kMaxStringBytes) return false;
    if (m.minVersion == 0 || m.minVersion > m.maxVersion) return false;
    w.U8(m.minVersion); w.U8(m.maxVersion); w.U16(0);
    w.U32(m.capabilities);
    w.U16(m.androidApiLevel); w.U16(m.screenWidth); w.U16(m.screenHeight); w.U16(m.densityDpi);
    w.Str(m.deviceName); w.Str(m.deviceModel);
    return true;
}
bool Enc(Writer& w, const HelloAck& m) {
    w.U8(static_cast<std::uint8_t>(m.status)); w.U8(m.acceptedVersion); w.U16(0);
    w.U32(m.assignedSessionId); w.U32(m.maxPayloadSize);
    return true;
}
bool Enc(Writer& w, const VideoConfig& m) {
    if (m.codecConfig.size() > kMaxCodecConfigBytes || m.width == 0 || m.height == 0) return false;
    w.U32(m.configId);
    w.U8(static_cast<std::uint8_t>(m.codec)); w.U8(m.profile); w.U8(m.level);
    w.U8(static_cast<std::uint8_t>(m.rotation));
    w.U16(m.width); w.U16(m.height); w.U16(m.frameRate); w.U16(0);
    w.U32(m.bitrate);
    w.U32(static_cast<std::uint32_t>(m.codecConfig.size()));
    w.Bytes(m.codecConfig);
    return true;
}
bool Enc(Writer& w, const VideoFrame& m) {
    if ((m.frameFlags & ~kFrameFlagsMask) != 0) return false;
    if (m.data.empty() && !(m.frameFlags & kFrameEndOfStream)) return false;
    w.U32(m.configId); w.U32(m.frameFlags); w.U64(m.ptsMicros);
    w.Bytes(m.data);
    return true;
}
bool Enc(Writer& w, const AudioConfig& m) {
    if (m.codecConfig.size() > kMaxCodecConfigBytes || m.channels == 0 || m.sampleRate == 0) return false;
    w.U8(static_cast<std::uint8_t>(m.codec)); w.U8(m.channels); w.U16(0);
    w.U32(m.sampleRate);
    w.U32(static_cast<std::uint32_t>(m.codecConfig.size()));
    w.Bytes(m.codecConfig);
    return true;
}
bool Enc(Writer& w, const AudioFrame& m) {
    if (m.data.empty()) return false;
    w.U64(m.ptsMicros); w.Bytes(m.data);
    return true;
}
bool Enc(Writer& w, const DisplayChanged& m) {
    if (m.width == 0 || m.height == 0) return false;
    w.U16(m.width); w.U16(m.height);
    w.U8(static_cast<std::uint8_t>(m.rotation)); w.U8(0); w.U16(0);
    w.U32(m.nextConfigId);
    return true;
}
bool Enc(Writer& w, const Heartbeat& m) {
    w.U64(m.timestampMicros); w.U64(m.echoTimestampMicros);
    return true;
}
bool Enc(Writer& w, const Status& m) {
    if (m.message.size() > kMaxStringBytes) return false;
    w.U16(m.code); w.Str(m.message);
    return true;
}
bool Enc(Writer& w, const Disconnect& m) {
    if (m.message.size() > kMaxStringBytes) return false;
    w.U16(static_cast<std::uint16_t>(m.reason)); w.Str(m.message);
    return true;
}
bool Enc(Writer& w, const ErrorMessage& m) {
    if (m.message.size() > kMaxStringBytes) return false;
    w.U16(m.code); w.U8(m.fatal ? 1 : 0); w.U8(0); w.Str(m.message);
    return true;
}

// ---- payload decoders ----

DecodeError Finish(const Reader& r) {
    if (!r.Ok()) return DecodeError::Truncated;
    if (r.Remaining() != 0) return DecodeError::TrailingBytes;
    return DecodeError::None;
}

DecodeError DecodePayload(MessageType type, std::span<const std::uint8_t> p, Payload& out) {
    Reader r(p);
    switch (type) {
    case MessageType::Hello: {
        Hello m;
        m.minVersion = r.U8(); m.maxVersion = r.U8();
        if (r.U16() != 0 && r.Ok()) return DecodeError::ReservedNotZero;
        m.capabilities = r.U32();
        m.androidApiLevel = r.U16(); m.screenWidth = r.U16(); m.screenHeight = r.U16(); m.densityDpi = r.U16();
        if (!r.Ok()) return DecodeError::Truncated;
        if (m.minVersion == 0 || m.minVersion > m.maxVersion) return DecodeError::InvalidField;
        if (auto e = r.Str(m.deviceName); e != DecodeError::None) return e;
        if (auto e = r.Str(m.deviceModel); e != DecodeError::None) return e;
        if (auto e = Finish(r); e != DecodeError::None) return e;
        out = std::move(m);
        return DecodeError::None;
    }
    case MessageType::HelloAck: {
        HelloAck m;
        auto status = r.U8(); m.acceptedVersion = r.U8();
        auto reserved = r.U16();
        m.assignedSessionId = r.U32(); m.maxPayloadSize = r.U32();
        if (auto e = Finish(r); e != DecodeError::None) return e;
        if (reserved != 0) return DecodeError::ReservedNotZero;
        if (status > 3 || m.maxPayloadSize > kMaxPayloadSize) return DecodeError::InvalidField;
        m.status = static_cast<HelloStatus>(status);
        out = m;
        return DecodeError::None;
    }
    case MessageType::VideoConfig: {
        VideoConfig m;
        m.configId = r.U32();
        auto codec = r.U8(); m.profile = r.U8(); m.level = r.U8(); auto rot = r.U8();
        m.width = r.U16(); m.height = r.U16(); m.frameRate = r.U16();
        auto reserved = r.U16();
        m.bitrate = r.U32();
        auto csdLen = r.U32();
        if (!r.Ok()) return DecodeError::Truncated;
        if (reserved != 0) return DecodeError::ReservedNotZero;
        if ((codec != 1 && codec != 2) || !ValidRotation(rot) || m.width == 0 || m.height == 0)
            return DecodeError::InvalidField;
        if (csdLen > kMaxCodecConfigBytes) return DecodeError::InvalidField;
        if (!r.Bytes(csdLen, m.codecConfig)) return DecodeError::Truncated;
        if (auto e = Finish(r); e != DecodeError::None) return e;
        m.codec = static_cast<VideoCodec>(codec);
        m.rotation = static_cast<Rotation>(rot);
        out = std::move(m);
        return DecodeError::None;
    }
    case MessageType::VideoFrame: {
        VideoFrame m;
        m.configId = r.U32(); m.frameFlags = r.U32(); m.ptsMicros = r.U64();
        if (!r.Ok()) return DecodeError::Truncated;
        if ((m.frameFlags & ~kFrameFlagsMask) != 0) return DecodeError::InvalidField;
        r.Bytes(r.Remaining(), m.data);
        if (m.data.empty() && !(m.frameFlags & kFrameEndOfStream)) return DecodeError::InvalidField;
        out = std::move(m);
        return DecodeError::None;
    }
    case MessageType::AudioConfig: {
        AudioConfig m;
        auto codec = r.U8(); m.channels = r.U8();
        auto reserved = r.U16();
        m.sampleRate = r.U32();
        auto csdLen = r.U32();
        if (!r.Ok()) return DecodeError::Truncated;
        if (reserved != 0) return DecodeError::ReservedNotZero;
        if (codec < 1 || codec > 3 || m.channels == 0 || m.channels > 8 || m.sampleRate == 0 ||
            csdLen > kMaxCodecConfigBytes)
            return DecodeError::InvalidField;
        if (!r.Bytes(csdLen, m.codecConfig)) return DecodeError::Truncated;
        if (auto e = Finish(r); e != DecodeError::None) return e;
        m.codec = static_cast<AudioCodec>(codec);
        out = std::move(m);
        return DecodeError::None;
    }
    case MessageType::AudioFrame: {
        AudioFrame m;
        m.ptsMicros = r.U64();
        if (!r.Ok()) return DecodeError::Truncated;
        r.Bytes(r.Remaining(), m.data);
        if (m.data.empty()) return DecodeError::InvalidField;
        out = std::move(m);
        return DecodeError::None;
    }
    case MessageType::DisplayChanged: {
        DisplayChanged m;
        m.width = r.U16(); m.height = r.U16();
        auto rot = r.U8(); auto r1 = r.U8(); auto r2 = r.U16();
        m.nextConfigId = r.U32();
        if (auto e = Finish(r); e != DecodeError::None) return e;
        if (r1 != 0 || r2 != 0) return DecodeError::ReservedNotZero;
        if (!ValidRotation(rot) || m.width == 0 || m.height == 0) return DecodeError::InvalidField;
        m.rotation = static_cast<Rotation>(rot);
        out = m;
        return DecodeError::None;
    }
    case MessageType::Heartbeat: {
        Heartbeat m;
        m.timestampMicros = r.U64(); m.echoTimestampMicros = r.U64();
        if (auto e = Finish(r); e != DecodeError::None) return e;
        out = m;
        return DecodeError::None;
    }
    case MessageType::Status: {
        Status m;
        m.code = r.U16();
        if (auto e = r.Str(m.message); e != DecodeError::None) return e;
        if (auto e = Finish(r); e != DecodeError::None) return e;
        out = std::move(m);
        return DecodeError::None;
    }
    case MessageType::Disconnect: {
        Disconnect m;
        auto reason = r.U16();
        if (auto e = r.Str(m.message); e != DecodeError::None) return e;
        if (auto e = Finish(r); e != DecodeError::None) return e;
        if (reason < 1 || reason > 5) return DecodeError::InvalidField;
        m.reason = static_cast<DisconnectReason>(reason);
        out = std::move(m);
        return DecodeError::None;
    }
    case MessageType::Error: {
        ErrorMessage m;
        m.code = r.U16();
        auto fatal = r.U8(); auto reserved = r.U8();
        if (!r.Ok()) return DecodeError::Truncated;
        if (reserved != 0) return DecodeError::ReservedNotZero;
        if (fatal > 1) return DecodeError::InvalidField;
        m.fatal = fatal == 1;
        if (auto e = r.Str(m.message); e != DecodeError::None) return e;
        if (auto e = Finish(r); e != DecodeError::None) return e;
        out = std::move(m);
        return DecodeError::None;
    }
    }
    return DecodeError::UnknownType;
}

}  // namespace

std::string_view ToString(DecodeError e) noexcept {
    switch (e) {
    case DecodeError::None: return "None";
    case DecodeError::NeedMoreData: return "NeedMoreData";
    case DecodeError::BadMagic: return "BadMagic";
    case DecodeError::UnsupportedVersion: return "UnsupportedVersion";
    case DecodeError::UnknownType: return "UnknownType";
    case DecodeError::ReservedNotZero: return "ReservedNotZero";
    case DecodeError::PayloadTooLarge: return "PayloadTooLarge";
    case DecodeError::Truncated: return "Truncated";
    case DecodeError::TrailingBytes: return "TrailingBytes";
    case DecodeError::InvalidField: return "InvalidField";
    case DecodeError::StringTooLong: return "StringTooLong";
    }
    return "Unknown";
}

bool IsKnownType(std::uint8_t raw) noexcept {
    switch (static_cast<MessageType>(raw)) {
    case MessageType::Hello: case MessageType::HelloAck:
    case MessageType::VideoConfig: case MessageType::VideoFrame:
    case MessageType::AudioConfig: case MessageType::AudioFrame:
    case MessageType::DisplayChanged: case MessageType::Heartbeat:
    case MessageType::Status: case MessageType::Disconnect: case MessageType::Error:
        return true;
    }
    return false;
}

std::uint32_t MaxPayloadFor(MessageType type) noexcept {
    switch (type) {
    case MessageType::VideoFrame:
    case MessageType::AudioFrame:
        return kMaxPayloadSize;
    default:
        return kMaxControlPayloadSize;
    }
}

DecodeError DecodeHeader(std::span<const std::uint8_t> bytes, Header& out) noexcept {
    if (bytes.size() < kHeaderSize) return DecodeError::NeedMoreData;
    Reader r(bytes.first(kHeaderSize));
    if (r.U32() != kMagic) return DecodeError::BadMagic;
    out.version = r.U8();
    if (out.version != kVersion) return DecodeError::UnsupportedVersion;
    auto type = r.U8();
    if (!IsKnownType(type)) return DecodeError::UnknownType;
    out.type = static_cast<MessageType>(type);
    out.flags = r.U16();
    out.sessionId = r.U32();
    out.sequence = r.U32();
    out.payloadLength = r.U32();
    auto reserved = r.U32();
    if ((out.flags & ~kHeaderFlagsMask) != 0 || reserved != 0) return DecodeError::ReservedNotZero;
    if (out.payloadLength > MaxPayloadFor(out.type)) return DecodeError::PayloadTooLarge;
    return DecodeError::None;
}

DecodeError DecodeMessage(std::span<const std::uint8_t> bytes, Message& out, std::size_t& consumed) {
    consumed = 0;
    Header h;
    if (auto e = DecodeHeader(bytes, h); e != DecodeError::None) return e;
    const std::size_t total = kHeaderSize + h.payloadLength;
    if (bytes.size() < total) return DecodeError::NeedMoreData;
    Payload p;
    if (auto e = DecodePayload(h.type, bytes.subspan(kHeaderSize, h.payloadLength), p); e != DecodeError::None)
        return e;
    out.header = h;
    out.payload = std::move(p);
    consumed = total;
    return DecodeError::None;
}

MessageType TypeOf(const Payload& payload) noexcept {
    static constexpr MessageType kTypes[] = {
        MessageType::Hello,       MessageType::HelloAck,   MessageType::VideoConfig,
        MessageType::VideoFrame,  MessageType::AudioConfig, MessageType::AudioFrame,
        MessageType::DisplayChanged, MessageType::Heartbeat, MessageType::Status,
        MessageType::Disconnect,  MessageType::Error,
    };
    static_assert(std::size(kTypes) == std::variant_size_v<Payload>);
    return kTypes[payload.index()];
}

bool EncodeMessage(std::uint32_t sessionId, std::uint32_t sequence, const Payload& payload,
                   std::vector<std::uint8_t>& out) {
    const std::size_t start = out.size();
    const MessageType type = TypeOf(payload);
    Writer w(out);
    w.U32(kMagic); w.U8(kVersion); w.U8(static_cast<std::uint8_t>(type)); w.U16(0);
    w.U32(sessionId); w.U32(sequence);
    w.U32(0);  // payload length placeholder
    w.U32(0);  // reserved

    const bool ok = std::visit([&](const auto& m) { return Enc(w, m); }, payload);
    const std::size_t len = out.size() - start - kHeaderSize;
    if (!ok || len > MaxPayloadFor(type)) {
        out.resize(start);
        return false;
    }
    const auto l = static_cast<std::uint32_t>(len);
    out[start + 16] = static_cast<std::uint8_t>(l >> 24);
    out[start + 17] = static_cast<std::uint8_t>(l >> 16);
    out[start + 18] = static_cast<std::uint8_t>(l >> 8);
    out[start + 19] = static_cast<std::uint8_t>(l);
    return true;
}

}  // namespace castsprint::protocol
