#include "airplay_rtsp_codec.hpp"
#include "airplay_constants.hpp"

#include <sstream>
#include <iostream>
#include <algorithm>
#include <cstring>

namespace castsprint::windows::airplay {

std::string RtspMessage::GetHeader(const std::string& key) const {
    for (const auto& [k, v] : headers) {
        if (k.size() == key.size() &&
            std::equal(k.begin(), k.end(), key.begin(), [](char a, char b) {
                return std::tolower(static_cast<unsigned char>(a)) == std::tolower(static_cast<unsigned char>(b));
            })) {
            return v;
        }
    }
    return "";
}

void RtspMessage::SetHeader(const std::string& key, const std::string& value) {
    headers[key] = value;
}

bool RtspCodec::Parse(std::string_view raw, RtspMessage& outMsg) {
    outMsg.headers.clear();
    outMsg.body.clear();
    outMsg.isResponse = false;

    if (raw.empty()) return false;

    std::string text(raw);
    std::istringstream stream(text);
    std::string firstLine;
    if (!std::getline(stream, firstLine) || firstLine.empty()) {
        return false;
    }
    if (!firstLine.empty() && firstLine.back() == '\r') firstLine.pop_back();

    std::istringstream lineStream(firstLine);
    std::string token1, token2, token3;
    lineStream >> token1 >> token2 >> token3;

    if (token1.find("RTSP/") == 0) {
        // Response: RTSP/1.0 200 OK
        outMsg.isResponse = true;
        outMsg.protocol = token1;
        outMsg.statusCode = token2.empty() ? 200 : std::stoi(token2);
        outMsg.statusText = token3.empty() ? "OK" : token3;
    } else {
        // Request: OPTIONS * RTSP/1.0
        outMsg.isResponse = false;
        outMsg.method = token1;
        outMsg.uri = token2;
        outMsg.protocol = token3.empty() ? "RTSP/1.0" : token3;
    }

    std::string line;
    while (std::getline(stream, line) && !line.empty()) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        if (line.empty()) break; // End of headers

        auto colon = line.find(':');
        if (colon != std::string::npos) {
            std::string k = line.substr(0, colon);
            std::string v = line.substr(colon + 1);
            v.erase(0, v.find_first_not_of(" \t"));
            outMsg.SetHeader(k, v);
        }
    }

    std::string clStr = outMsg.GetHeader("Content-Length");
    if (!clStr.empty()) {
        size_t contentLength = static_cast<size_t>(std::stoul(clStr));
        std::vector<char> buf(contentLength);
        stream.read(buf.data(), static_cast<std::streamsize>(contentLength));
        outMsg.body.assign(buf.begin(), buf.end());
    }

    return true;
}

std::string RtspCodec::Serialize(const RtspMessage& msg) {
    std::ostringstream ss;
    if (msg.isResponse) {
        ss << (msg.protocol.empty() ? "RTSP/1.0" : msg.protocol) << " "
           << msg.statusCode << " " << msg.statusText << "\r\n";
    } else {
        ss << msg.method << " " << msg.uri << " "
           << (msg.protocol.empty() ? "RTSP/1.0" : msg.protocol) << "\r\n";
    }

    for (const auto& [k, v] : msg.headers) {
        ss << k << ": " << v << "\r\n";
    }

    if (!msg.body.empty() && msg.GetHeader("Content-Length").empty()) {
        ss << "Content-Length: " << msg.body.size() << "\r\n";
    }
    ss << "\r\n";

    if (!msg.body.empty()) {
        ss.write(reinterpret_cast<const char*>(msg.body.data()), static_cast<std::streamsize>(msg.body.size()));
    }
    return ss.str();
}

RtspMessage RtspCodec::CreateResponse(const RtspMessage& req, int statusCode, std::string_view statusText) {
    RtspMessage resp;
    resp.isResponse = true;
    resp.protocol = req.protocol.empty() ? "RTSP/1.0" : req.protocol;
    resp.statusCode = statusCode;
    resp.statusText = statusText;

    std::string cseq = req.GetHeader("CSeq");
    if (!cseq.empty()) {
        resp.SetHeader("CSeq", cseq);
    }
    resp.SetHeader("Server", std::string(kServerHeader));
    return resp;
}

bool RtspCodec::ParseSdp(std::string_view sdpText, SdpVideoInfo& outVideo, SdpAudioInfo& outAudio) {
    outVideo = SdpVideoInfo{};
    outAudio = SdpAudioInfo{};

    std::string text(sdpText);
    std::istringstream stream(text);
    std::string line;

    bool inVideo = false;
    bool inAudio = false;

    while (std::getline(stream, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();

        if (line.rfind("m=video", 0) == 0) {
            inVideo = true;
            inAudio = false;
            outVideo.hasVideo = true;
        } else if (line.rfind("m=audio", 0) == 0) {
            inAudio = true;
            inVideo = false;
            outAudio.hasAudio = true;
        } else if (line.rfind("a=rtpmap:", 0) == 0) {
            std::string sub = line.substr(9);
            if (inVideo && sub.find("H264") != std::string::npos) {
                outVideo.codec = "H264";
            } else if (inAudio) {
                if (sub.find("AAC-ELD") != std::string::npos || sub.find("mpeg4-generic") != std::string::npos) {
                    outAudio.codec = "AAC-ELD";
                }
            }
        } else if (line.find("fairplay") != std::string::npos || line.find("kFairPlayKey") != std::string::npos) {
            if (inVideo) {
                outVideo.isNonDrmMirror = false; // Encumbered with commercial DRM
            }
        }
    }

    return outVideo.hasVideo || outAudio.hasAudio;
}

// -------------------------------------------------------------------------------------------------
// RtpVideoDepacketizer Implementation
// -------------------------------------------------------------------------------------------------

RtpVideoDepacketizer::RtpVideoDepacketizer(FrameReadyCallback onFrame)
    : onFrame_(std::move(onFrame)) {}

void RtpVideoDepacketizer::Reset() {
    fuAssemblyBuffer_.clear();
    inFuA_ = false;
    lastTimestamp_ = 0;
}

bool RtpVideoDepacketizer::ProcessRtpPacket(std::span<const uint8_t> packet) {
    if (packet.size() < 12) return false;

    // Byte 0: Version (2 bits), Padding (1 bit), Extension (1 bit), CSRC count (4 bits)
    uint8_t b0 = packet[0];
    uint8_t version = (b0 >> 6) & 0x03;
    if (version != 2) return false;

    bool hasPadding = (b0 & 0x20) != 0;
    bool hasExtension = (b0 & 0x10) != 0;
    uint8_t csrcCount = b0 & 0x0F;

    // Timestamp: bytes 4..7 (big endian)
    uint32_t timestamp = (static_cast<uint32_t>(packet[4]) << 24) |
                         (static_cast<uint32_t>(packet[5]) << 16) |
                         (static_cast<uint32_t>(packet[6]) << 8) |
                         static_cast<uint32_t>(packet[7]);

    size_t headerSize = 12 + (csrcCount * 4);
    if (packet.size() < headerSize) return false;

    if (hasExtension) {
        if (packet.size() < headerSize + 4) return false;
        const uint16_t extLenWords = static_cast<uint16_t>(
            (static_cast<uint16_t>(packet[headerSize + 2]) << 8U) |
            static_cast<uint16_t>(packet[headerSize + 3]));
        headerSize += 4 + (extLenWords * 4);
        if (packet.size() < headerSize) return false;
    }

    size_t payloadSize = packet.size() - headerSize;
    if (hasPadding && payloadSize > 0) {
        uint8_t padLen = packet.back();
        if (padLen <= payloadSize) {
            payloadSize -= padLen;
        }
    }

    if (payloadSize == 0) return true; // Empty heartbeat/keepalive packet

    const uint8_t* payload = packet.data() + headerSize;
    uint8_t nalHeader = payload[0];
    uint8_t nalType = nalHeader & 0x1F;

    uint64_t ptsMicros = (static_cast<uint64_t>(timestamp) * 1000000ULL) / 90000ULL;

    // Single NAL unit packet (types 1 to 23)
    if (nalType >= 1 && nalType <= 23) {
        std::vector<uint8_t> frame;
        frame.reserve(4 + payloadSize);
        // Prepend Annex-B start code
        frame.push_back(0x00);
        frame.push_back(0x00);
        frame.push_back(0x00);
        frame.push_back(0x01);
        frame.insert(frame.end(), payload, payload + payloadSize);

        if (onFrame_) {
            onFrame_(frame, ptsMicros);
        }
        return true;
    }

    // Fragmentation Unit A (FU-A, type 28)
    if (nalType == 28) {
        if (payloadSize < 2) return false;
        uint8_t fuIndicator = payload[0];
        uint8_t fuHeader = payload[1];
        bool isStart = (fuHeader & 0x80) != 0;
        bool isEnd = (fuHeader & 0x40) != 0;
        uint8_t reconstructedNalType = fuHeader & 0x1F;
        uint8_t reconstructedNalHeader = (fuIndicator & 0xE0) | reconstructedNalType;

        if (isStart) {
            fuAssemblyBuffer_.clear();
            // Annex-B start code
            fuAssemblyBuffer_.push_back(0x00);
            fuAssemblyBuffer_.push_back(0x00);
            fuAssemblyBuffer_.push_back(0x00);
            fuAssemblyBuffer_.push_back(0x01);
            fuAssemblyBuffer_.push_back(reconstructedNalHeader);
            fuAssemblyBuffer_.insert(fuAssemblyBuffer_.end(), payload + 2, payload + payloadSize);
            inFuA_ = true;
            lastTimestamp_ = timestamp;
        } else if (inFuA_ && timestamp == lastTimestamp_) {
            fuAssemblyBuffer_.insert(fuAssemblyBuffer_.end(), payload + 2, payload + payloadSize);
        }

        if (isEnd && inFuA_) {
            if (onFrame_) {
                onFrame_(fuAssemblyBuffer_, ptsMicros);
            }
            fuAssemblyBuffer_.clear();
            inFuA_ = false;
        }
        return true;
    }

    return true;
}

} // namespace castsprint::windows::airplay
