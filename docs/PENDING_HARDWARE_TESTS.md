# CastSprint Pending Hardware Verification & Community QA Checklist

**Document ID:** CSR-QA-PENDING-01  
**Classification:** Quality Assurance & Public Beta Verification Protocol  
**Author:** Principal QA Lead  
**Date:** 2026-10-14  

---

## 1. Overview

While primary representative hardware devices (Pixel 7, Galaxy S23, iPhone 13 Pro, iPhone 15 Pro Max, iPad Pro M2) have successfully passed 100% of end-to-end streaming benchmarks, this document outlines the **secondary hardware permutations** and edge-case configurations scheduled for ongoing verification across the public beta cycle.

---

## 2. Pending Secondary Hardware Permutations

| # | Target Hardware / Platform | Configuration | Planned Evaluation | Current Beta Status |
|---|---|---|---|:---:|
| **1** | **Legacy iPhone (Lightning / iOS 15)** | iPhone 8 / iPhone X / iPhone SE (2nd Gen) running iOS 15.8 | Validate ScreenCaptureKit fallback to Legacy Broadcast Extension on A11 Bionic SoC | `NOT TESTED (Queued for Beta Cohort A)` |
| **2** | **Budget Android (MediaTek SoC)** | Xiaomi Redmi Note 12 / Samsung Galaxy A14 (MediaTek Helio / Dimensity) | Validate MediaCodec hardware H.264 profile negotiation on low-end encoders | `NOT TESTED (Queued for Beta Cohort B)` |
| **3** | **Dual SIM / eSIM iPhones** | iPhone 14/15 with active Dual SIM / eSIM | Verify that toggling USB Personal Hotspot binds cleanly to `172.20.10.x` regardless of primary data line | `NOT TESTED (Queued for Beta Cohort A)` |
| **4** | **Enterprise / Mesh Wi-Fi (802.1X)** | Corporate Cisco / Ubiquiti APs with Client Isolation | Verify fallback behavior when local mDNS multicast is suppressed by enterprise routers | `NOT TESTED (Queued for Beta Cohort C)` |
| **5** | **Windows N Editions (Media Feature Pack)**| Windows 11 Home N / Pro N without default media codecs | Verify that user receives clear warning dialog prompting Media Feature Pack installation | `NOT TESTED (Queued for Beta Cohort B)` |
| **6** | **Dual Monitor / High-DPI Windows** | Multi-monitor mixed DPI (4K 150% + 1080p 100%) | Verify Direct3D 11 swapchain resizing and OBS Window Capture across monitor transitions | `NOT TESTED (Queued for Beta Cohort A)` |

---

## 3. Community Beta Verification Instructions

If you are a beta tester validating one of the hardware setups above:
1. Connect your device using your chosen connection method.
2. Note your exact OS build and device model.
3. Stream an active mobile game for at least 30 minutes.
4. Record observed FPS, glass-to-glass latency, and audio lip-sync.
5. In CastSprint Windows or macOS, go to **Settings > Export Diagnostic Log** to save session telemetry.
6. Submit your report to the CastSprint GitHub issue tracker with tag `[Hardware-Report]`.
