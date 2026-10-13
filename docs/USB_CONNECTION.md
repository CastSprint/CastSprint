# Native USB Connection Guide

The native USB pipeline is the recommended transport for competitive mobile gaming in CastSprint, offering the lowest latency (~15ms end-to-end), maximum frame stability (locked 60 FPS), and zero Wi-Fi interference.

---

## Technical Architecture

CastSprint USB streaming relies on a framed native TCP socket mapped locally over ADB reverse port forwarding:
```
[Android MediaCodec Encoder] 
       ↓ (TCP socket on 127.0.0.1:27183)
[Android ADB Daemon (adbd)]
       ↓ (USB Type-C Cable)
[PC ADB Server]
       ↓ (TCP socket on 127.0.0.1:27183)
[CastSprint Windows D3D11 / WASAPI Receiver]
```
This guarantees zero network jitter, no router congestion, and zero dependence on cloud servers or third-party drivers.

---

## 1. Enabling USB Debugging

To allow CastSprint to communicate with your PC via USB, USB Debugging must be enabled:

### Samsung One UI
1. Go to **Settings > About phone > Software information**.
2. Tap **Build number** 7 times until you see *"Developer mode has been enabled"*.
3. Go back to **Settings > Developer options**.
4. Turn on **USB debugging**.

### Xiaomi / Redmi / POCO (MIUI / HyperOS)
1. Go to **Settings > About phone**.
2. Tap **MIUI version** or **OS version** 7 times.
3. Go to **Settings > Additional settings > Developer options**.
4. Enable **USB debugging**.
5. *(Optional)* If prompted, allow USB debugging security authorization.

### Google Pixel / Motorola / Sony (Stock Android)
1. Go to **Settings > About phone**.
2. Tap **Build number** 7 times.
3. Go to **Settings > System > Developer options**.
4. Enable **USB debugging**.

### OnePlus / OPPO / Realme (ColorOS / OxygenOS)
1. Go to **Settings > About device > Version**.
2. Tap **Build number** 7 times.
3. Go to **Settings > Additional settings > Developer options**.
4. Turn on **USB debugging**.

---

## 2. PC Setup & Port Forwarding

1. Connect your Android device to your Windows PC using a high-quality USB data cable.
2. When prompted on your phone screen with *"Allow USB debugging?"*, check **"Always allow from this computer"** and tap **Allow**.
3. On your Windows PC, ensure ADB is accessible. If ADB is installed with platform-tools:
   ```cmd
   adb devices
   ```
   *Your device should be listed as `device` (not `unauthorized` or `offline`).*
4. Run the reverse port forwarding command:
   ```cmd
   adb reverse tcp:27183 tcp:27183
   ```
5. Launch **CastSprint Receiver** on Windows.
6. Open **CastSprint** on your phone, ensure **USB (ADB reverse)** is selected, and tap **Start Mirroring**.
7. Approve the screen capture prompt on Android. The PC window will immediately switch to the real-time gaming stream.

---

## 3. Troubleshooting USB Connections

| Symptom | Root Cause | Fix |
|---|---|---|
| `adb devices` shows `unauthorized` | Device prompt was dismissed or missed | Unplug USB, reconnect, unlock phone screen, and accept the debugging RSA prompt. |
| `adb devices` shows nothing | Cable is charge-only or USB driver missing | Use a verified data cable. Install the official Google OEM USB driver via Windows Update or device manufacturer. |
| Android app says *"Waiting for receiver"* | `adb reverse` was not executed | Run `adb reverse tcp:27183 tcp:27183` in command prompt. Ensure PC receiver is running. |
| Micro-stuttering during gameplay | USB 2.0 port or hub saturation | Plug directly into a rear USB 3.0/3.1 port on the motherboard; avoid unpowered USB hubs. |
