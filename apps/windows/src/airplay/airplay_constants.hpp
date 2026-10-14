#pragma once
#include <cstdint>
#include <string_view>

namespace castsprint::windows::airplay {

// Default Network Ports
constexpr uint16_t kDefaultRtspPort = 7000;
constexpr uint16_t kDefaultVideoRtpPort = 7010;
constexpr uint16_t kDefaultVideoRtcpPort = 7011;
constexpr uint16_t kDefaultAudioRtpPort = 7012;
constexpr uint16_t kDefaultAudioRtcpPort = 7013;
constexpr uint16_t kDefaultAudioSyncPort = 7014;
constexpr uint16_t kDefaultMdnsPort = 5353;

// Default Identifiers
constexpr std::string_view kDefaultReceiverName = "CastSprint Desktop";
constexpr std::string_view kAirPlayModel = "AppleTV3,2";
constexpr std::string_view kAirPlaySrcVers = "220.68";
constexpr std::string_view kServerHeader = "AirTunes/220.68";

// AirPlay Feature Flags:
// 0x5A7FFFF7, 0x1E:
// bit 0: video, bit 1: photo, bit 2: slideshow, bit 3: screen mirroring,
// bit 7: audio, bit 9: audio meta, bit 11: audio redundancy,
// bit 14: FPS, bit 15: authentication, bit 18: HK pairing, bit 26: audio scream.
constexpr std::string_view kAirPlayFeatures = "0x5A7FFFF7,0x1E";

// Apple Hotspot USB Default Subnet Prefix
constexpr std::string_view kAppleHotspotSubnetPrefix = "172.20.10.";
constexpr std::string_view kAppleHotspotGatewayIp = "172.20.10.1";

} // namespace castsprint::windows::airplay
