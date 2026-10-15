#include <iostream>
#include <string>
#include <csignal>
#include <atomic>
#include <thread>
#include <chrono>

#include "lan_server.hpp"
#include "video_decoder.hpp"
#include "audio_player.hpp"
#include "log.hpp"

namespace {
std::atomic<bool> g_keepRunning{true};

void SignalHandler(int signum) {
    (void)signum;
    g_keepRunning.store(false);
}
} // namespace

int main(int argc, char* argv[]) {
    std::string arg;
    uint16_t port = 27183;

    for (int i = 1; i < argc; ++i) {
        arg = argv[i];
        if (arg == "--help" || arg == "-h") {
            std::cout << "CastSprint Native Linux Receiver v0.2.0\n"
                      << "Usage: castsprint_receiver_linux [options]\n"
                      << "Options:\n"
                      << "  --port <port>   Set listening port (default: 27183)\n"
                      << "  --smoke-test    Run initialization smoke test and exit\n"
                      << "  --version       Display version information\n"
                      << "  --help          Display this help message\n";
            return 0;
        } else if (arg == "--version" || arg == "-v") {
            std::cout << "CastSprint Native Linux Receiver v0.2.0 (C++20)\n";
            return 0;
        } else if (arg == "--smoke-test") {
            castsprint::linux_app::Log(castsprint::linux_app::LogLevel::Info,
                                       "Running Linux Receiver smoke test...");
            castsprint::linux_app::LanServer server;
            castsprint::linux_app::VideoDecoder decoder;
            castsprint::linux_app::AudioPlayer audio;
            castsprint::linux_app::Log(castsprint::linux_app::LogLevel::Info,
                                       "Smoke test passed: all subsystems initialized successfully.");
            return 0;
        } else if (arg == "--port" && i + 1 < argc) {
            port = static_cast<uint16_t>(std::stoi(argv[++i]));
        }
    }

    std::signal(SIGINT, SignalHandler);
    std::signal(SIGTERM, SignalHandler);

    castsprint::linux_app::Log(castsprint::linux_app::LogLevel::Info,
                               "Starting CastSprint Native Linux Receiver on port " + std::to_string(port));

    castsprint::linux_app::LanServer server;
    castsprint::linux_app::VideoDecoder decoder;
    castsprint::linux_app::AudioPlayer audio;

    castsprint::linux_app::LanCallbacks callbacks;
    callbacks.onVideoConfig = [&decoder](const castsprint::protocol::VideoConfig& vc) {
        decoder.Configure(vc);
    };
    callbacks.onVideoFrame = [&decoder](const castsprint::protocol::VideoFrame& vf) {
        decoder.DecodeFrame(vf, [](const castsprint::linux_app::DecodedVideoFrame&) {
            // Forward decoded YUV to Wayland/X11 surface
        });
    };
    callbacks.onAudioConfig = [&audio](const castsprint::protocol::AudioConfig& ac) {
        audio.Configure(ac);
    };
    callbacks.onAudioFrame = [&audio](const castsprint::protocol::AudioFrame& af) {
        audio.PlayFrame(af);
    };
    callbacks.onStateChanged = [](castsprint::session::ConnectionState state) {
        castsprint::linux_app::Log(castsprint::linux_app::LogLevel::Info,
                                   "Session state: " + std::to_string(static_cast<int>(state)));
    };

    if (!server.Start(port, std::move(callbacks))) {
        castsprint::linux_app::Log(castsprint::linux_app::LogLevel::Error, "Failed to start server");
        return 1;
    }

    castsprint::linux_app::Log(castsprint::linux_app::LogLevel::Info,
                               "Pairing PIN: " + std::string(server.SessionPin()));

    while (g_keepRunning.load()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(200));
    }

    castsprint::linux_app::Log(castsprint::linux_app::LogLevel::Info, "Shutting down Linux receiver...");
    server.Stop();
    return 0;
}
