# Secure Local Wi-Fi Connection Guide

CastSprint supports cable-free screen and game audio mirroring over your local wireless network (LAN) with end-to-end TLS encryption and SHA-256 certificate fingerprint pinning.

---

## Security Model

Unlike cloud mirroring applications that route video through external remote servers, CastSprint operates entirely inside your local area network (LAN):
- **Local TLS 1.2/1.3**: The desktop receiver generates a local self-signed X.509 certificate on launch.
- **Certificate Pinning**: The Android client validates the server's certificate strictly against its pinned SHA-256 fingerprint. No public certificate authority (CA) or Internet connection is required.
- **Connection-Scoped PIN**: A 6-digit random session token is regenerated on each desktop launch. Unauthorized connections without the correct PIN are immediately rejected.
- **No Internet Port Forwarding**: Operates exclusively across your local subnet. Never configure UPnP or WAN port forwarding.

---

## 1. Prerequisites
- Android phone and Windows PC connected to the **same local network subnet**.
- **5 GHz Wi-Fi** or **Wi-Fi 6 (802.11ax)** strongly recommended for mobile gaming (2.4 GHz has higher congestion and packet jitter).
- If your PC has an Ethernet port, connecting the PC via Gigabit Ethernet to the same router while the phone is on 5 GHz Wi-Fi provides the lowest latency and highest stability.

---

## 2. One-Tap Pairing via mDNS Discovery

CastSprint advertises a local DNS-SD service (`_castsprint._tcp`) containing its TLS fingerprint in the TXT record.

1. Launch **CastSprint Receiver** on your Windows PC.
2. Note the 6-digit **Session PIN** displayed on the title bar and Home screen (e.g., `123456`).
3. Open **CastSprint** on your Android device.
4. Under **Connection / Transport**, select **Secure Wi-Fi (LAN)**.
5. Tap **Configure / Discover PC**.
6. The dialog will automatically list discovered desktop receivers on your network (e.g. `Gaming-PC (192.168.1.100:27183)`).
7. Tap your PC in the list. The IP address, port, and SHA-256 fingerprint will be automatically filled in.
8. Enter the 6-digit **Session PIN** from your PC and tap **Save**.
9. Tap **Start Mirroring** and approve the system screen capture prompt.

---

## 3. Manual IP Fallback Configuration

If your router blocks multicast DNS (mDNS) discovery:
1. On your Windows PC, open Command Prompt and run `ipconfig` to locate your IPv4 address (e.g., `192.168.1.50`).
2. In CastSprint Android, tap **Configure / Discover PC**.
3. Manually enter:
   - **Receiver IP**: Your PC's local IP address.
   - **Port**: `27183` (default).
   - **Session PIN**: The 6-digit PIN shown on your PC.
   - **SHA-256 Fingerprint**: The fingerprint string shown on your PC.
4. Tap **Save**, then tap **Start Mirroring**.

---

## 4. Windows Firewall Configuration

Windows Defender Firewall may prompt to allow network access the first time you run CastSprint Receiver.

If connections fail:
1. Open **Windows Defender Firewall with Advanced Security**.
2. Click **Inbound Rules > New Rule**.
3. Select **Port > TCP**.
4. Specific local ports: `27183`.
5. Select **Allow the connection**.
6. Check **Private** (recommended for home networks).
7. Name the rule `CastSprint Receiver`.

---

## 5. Troubleshooting Wi-Fi Streaming

| Symptom | Cause | Solution |
|---|---|---|
| Discovered list is empty | Router has mDNS / Multicast isolation enabled | Use the **Manual Configuration** fallback by entering your PC's IP and PIN directly. |
| Connection times out | Windows Firewall blocking port 27183 | Add an inbound firewall rule for TCP port 27183 on Private networks. |
| "Session PIN mismatch / Rejected" | Incorrect PIN entered on phone | Check the PC title bar and re-enter the exact 6-digit PIN. |
| Packet loss or stuttering | 2.4 GHz channel congestion | Switch phone to a 5 GHz or 6 GHz Wi-Fi SSID; connect PC via Ethernet. |
| Guest Wi-Fi isolation | Router AP Client Isolation active | Ensure phone is not connected to a Guest Wi-Fi network that prevents device-to-device communication. |
