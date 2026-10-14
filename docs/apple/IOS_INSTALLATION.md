# CastSprint for iOS — Installation & Sideloading Guide

**Target Devices:** iPhone and iPad running iOS 15.0+ / iPadOS 15.0+  
**Recommended Devices:** iPhone 11 or newer (A13 Bionic+) for locked 60 FPS hardware encoding  
**Companion App Needed?** Yes for Wi-Fi streaming to Windows/Mac. (No app needed for USB mirroring to Mac).

---

## 1. Installation Method A: Apple TestFlight (Public Beta)

During the public beta phase, CastSprint is distributed through Apple TestFlight:

1. Install the official **Apple TestFlight** app from the App Store on your iPhone or iPad.
2. Open the CastSprint TestFlight Public Beta Invitation Link:
   `https://testflight.apple.com/join/CastSprintBeta` *(Updated on GitHub Releases)*.
3. Tap **Accept** and then tap **Install**.
4. Launch **CastSprint** from your home screen.

---

## 2. Installation Method B: Developer Sideloading via Xcode

Developers and power users can compile and install CastSprint directly onto an iPhone or iPad using a free or paid Apple Developer account:

### Prerequisites:
- Mac computer running macOS 14 (Sonoma) or macOS 15 (Sequoia).
- Xcode 15 or Xcode 16 installed from the Mac App Store.
- Lightning or USB-C cable to connect your iPhone to your Mac.

### Step-by-Step Instructions:
1. **Clone the Repository:**
   ```bash
   git clone https://github.com/CastSprint/CastSprint.git
   cd CastSprint
   ```

2. **Open the Project in Xcode:**
   Open `apps/ios` or open the Xcode workspace in Xcode.

3. **Configure Code Signing (Personal Team):**
   * In Xcode, select the **CastSprintIOS** project in the left navigator.
   * Under **Signing & Capabilities**, select your personal Apple ID team.
   * Ensure the **App Group** (`group.com.castsprint.ios`) is assigned to your development team identifier (e.g. `group.com.yourname.castsprint.ios`).
   * Repeat the signing selection for the **LegacyBroadcastExtension** target.

4. **Select Your Device and Run:**
   * Connect your iPhone via USB cable.
   * Select your physical iPhone as the run destination in the top toolbar.
   * Click the **Run** button (or press `Cmd+R`).
   * Xcode will compile `CastSprintIOSCore`, sign the application with your personal profile, and install it on your device.

5. **Trust Developer Certificate (iOS 15 / 16 / 17 / 18):**
   * On your iPhone, open **Settings** -> **General** -> **VPN & Device Management**.
   * Under **Developer App**, tap your Apple ID and tap **Trust**.
   * On iOS 16+, enable Developer Mode in **Settings** -> **Privacy & Security** -> **Developer Mode** and reboot when prompted.

---

## 3. Wi-Fi Setup & Mirroring Instructions

1. **Local Network Checklist:**
   * Put both your iPhone and your Windows PC or Mac on the same **5 GHz Wi-Fi network**.
   * Disable "AP Isolation" or "Guest Network Isolation" on your Wi-Fi router.
2. **Launch Desktop Receiver:**
   * On Mac: Open **CastSprint Mac**.
   * On Windows: Open **CastSprint Windows**. Note the 4-digit pairing PIN.
3. **Launch iOS App:**
   * Open **CastSprint** on iPhone.
   * When prompted: *"CastSprint would like to find and connect to devices on your local network"*, tap **Allow**.
   * Your computer will appear in the **Discovered Computers** list. Tap it to select.
4. **Start Mirroring:**
   * Tap **"Launch Broadcast Picker"**.
   * In the Apple system modal, select **CastSprint** and tap **Start Broadcast**.
   * After the 3-second countdown, switch to your mobile game and enjoy low-latency, watermark-free mirroring!
