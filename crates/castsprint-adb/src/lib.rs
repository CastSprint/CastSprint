//! Native Cross-Platform ADB Discovery and Reverse Port Forwarding for CastSprint.
//! Automates `adb reverse tcp:27183 tcp:27183` for zero-latency Android USB gaming mirroring.

use std::env;
use std::io::{self, Error, ErrorKind};
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AdbDevice {
    pub serial: String,
    pub model: String,
    pub is_authorized: bool,
}

#[derive(Debug, Clone, Default)]
pub struct AdbManager {
    adb_path: Option<PathBuf>,
}

impl AdbManager {
    pub fn new() -> Self {
        let adb_path = Self::locate_adb();
        Self { adb_path }
    }

    pub fn with_path<P: AsRef<Path>>(path: P) -> Self {
        Self {
            adb_path: Some(path.as_ref().to_path_buf()),
        }
    }

    pub fn adb_path(&self) -> Option<&Path> {
        self.adb_path.as_deref()
    }

    /// Finds adb in system PATH or standard Android SDK platform-tools locations.
    pub fn locate_adb() -> Option<PathBuf> {
        // 1. Check system PATH
        if let Ok(path_var) = env::var("PATH") {
            let separator = if cfg!(windows) { ';' } else { ':' };
            let adb_name = if cfg!(windows) { "adb.exe" } else { "adb" };
            for dir in path_var.split(separator) {
                let candidate = Path::new(dir).join(adb_name);
                if candidate.is_file() {
                    return Some(candidate);
                }
            }
        }

        // 2. Check ANDROID_HOME / ANDROID_SDK_ROOT
        if let Ok(sdk_root) = env::var("ANDROID_HOME").or_else(|_| env::var("ANDROID_SDK_ROOT")) {
            let adb_name = if cfg!(windows) { "adb.exe" } else { "adb" };
            let candidate = Path::new(&sdk_root).join("platform-tools").join(adb_name);
            if candidate.is_file() {
                return Some(candidate);
            }
        }

        // 3. Platform specific standard directories
        #[cfg(target_os = "windows")]
        {
            if let Ok(local_appdata) = env::var("LOCALAPPDATA") {
                let candidate = Path::new(&local_appdata)
                    .join("Android")
                    .join("Sdk")
                    .join("platform-tools")
                    .join("adb.exe");
                if candidate.is_file() {
                    return Some(candidate);
                }
            }
            if let Ok(prog_files) = env::var("ProgramFiles") {
                let candidate = Path::new(&prog_files)
                    .join("Android")
                    .join("platform-tools")
                    .join("adb.exe");
                if candidate.is_file() {
                    return Some(candidate);
                }
            }
        }

        #[cfg(target_os = "macos")]
        {
            if let Ok(home) = env::var("HOME") {
                let candidate = Path::new(&home)
                    .join("Library")
                    .join("Android")
                    .join("sdk")
                    .join("platform-tools")
                    .join("adb");
                if candidate.is_file() {
                    return Some(candidate);
                }
            }
            let standard_paths = [
                "/opt/homebrew/bin/adb",
                "/usr/local/bin/adb",
                "/opt/local/bin/adb",
            ];
            for p in &standard_paths {
                let candidate = Path::new(p);
                if candidate.is_file() {
                    return Some(candidate.to_path_buf());
                }
            }
        }

        #[cfg(target_os = "linux")]
        {
            if let Ok(home) = env::var("HOME") {
                let candidate = Path::new(&home)
                    .join("Android")
                    .join("Sdk")
                    .join("platform-tools")
                    .join("adb");
                if candidate.is_file() {
                    return Some(candidate);
                }
            }
            let standard_paths = ["/usr/bin/adb", "/usr/local/bin/adb", "/snap/bin/adb"];
            for p in &standard_paths {
                let candidate = Path::new(p);
                if candidate.is_file() {
                    return Some(candidate.to_path_buf());
                }
            }
        }

        None
    }

    /// Queries connected Android devices via `adb devices -l`
    pub fn list_devices(&self) -> io::Result<Vec<AdbDevice>> {
        let adb = self.adb_path.as_ref().ok_or_else(|| {
            Error::new(ErrorKind::NotFound, "adb binary not found on this system")
        })?;

        let output = Command::new(adb).arg("devices").arg("-l").output()?;
        if !output.status.success() {
            return Err(Error::new(
                ErrorKind::Other,
                format!("adb devices failed with code {:?}", output.status.code()),
            ));
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        Ok(Self::parse_devices_output(&stdout))
    }

    /// Parses the raw output of `adb devices -l`.
    pub fn parse_devices_output(output: &str) -> Vec<AdbDevice> {
        let mut devices = Vec::new();
        for line in output.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with("List of devices") || line.starts_with('*') {
                continue;
            }

            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 2 {
                let serial = parts[0].to_string();
                let state = parts[1];
                let is_authorized = state == "device";

                let mut model = "Android Device".to_string();
                for part in &parts[2..] {
                    if let Some(m) = part.strip_prefix("model:") {
                        model = m.replace('_', " ");
                        break;
                    }
                }

                devices.push(AdbDevice {
                    serial,
                    model,
                    is_authorized,
                });
            }
        }
        devices
    }

    /// Sets up `adb reverse tcp:<port> tcp:<port>` for USB gaming mirroring.
    pub fn setup_reverse_tunnel(&self, serial: Option<&str>, port: u16) -> io::Result<()> {
        let adb = self.adb_path.as_ref().ok_or_else(|| {
            Error::new(ErrorKind::NotFound, "adb binary not found on this system")
        })?;

        let mut cmd = Command::new(adb);
        if let Some(s) = serial {
            cmd.arg("-s").arg(s);
        }
        cmd.arg("reverse")
            .arg(format!("tcp:{}", port))
            .arg(format!("tcp:{}", port));

        let output = cmd.output()?;
        if !output.status.success() {
            let err = String::from_utf8_lossy(&output.stderr);
            return Err(Error::new(
                ErrorKind::Other,
                format!("adb reverse failed: {}", err.trim()),
            ));
        }

        Ok(())
    }

    /// Removes reverse tunnel forwarding.
    pub fn remove_reverse_tunnel(&self, serial: Option<&str>, port: u16) -> io::Result<()> {
        let adb = self.adb_path.as_ref().ok_or_else(|| {
            Error::new(ErrorKind::NotFound, "adb binary not found on this system")
        })?;

        let mut cmd = Command::new(adb);
        if let Some(s) = serial {
            cmd.arg("-s").arg(s);
        }
        cmd.arg("reverse")
            .arg("--remove")
            .arg(format!("tcp:{}", port));

        let _ = cmd.output();
        Ok(())
    }

    /// Launches CastSprint Android companion app directly over USB.
    pub fn launch_companion_app(&self, serial: Option<&str>) -> io::Result<()> {
        let adb = self.adb_path.as_ref().ok_or_else(|| {
            Error::new(ErrorKind::NotFound, "adb binary not found on this system")
        })?;

        let mut cmd = Command::new(adb);
        if let Some(s) = serial {
            cmd.arg("-s").arg(s);
        }
        cmd.arg("shell")
            .arg("am")
            .arg("start")
            .arg("-n")
            .arg("com.castsprint.android/.MainActivity");

        let output = cmd.output()?;
        if !output.status.success() {
            let err = String::from_utf8_lossy(&output.stderr);
            return Err(Error::new(
                ErrorKind::Other,
                format!("Failed to launch companion app: {}", err.trim()),
            ));
        }

        Ok(())
    }

    /// Toggles Thermal Cooling Mode on Android (dims screen brightness to 1 to save battery and stop overheating).
    pub fn set_screen_cooling_mode(&self, serial: Option<&str>, enable: bool) -> io::Result<()> {
        let adb = self.adb_path.as_ref().ok_or_else(|| {
            Error::new(ErrorKind::NotFound, "adb binary not found on this system")
        })?;

        let mut cmd = Command::new(adb);
        if let Some(s) = serial {
            cmd.arg("-s").arg(s);
        }
        cmd.arg("shell");

        if enable {
            cmd.arg("settings put system screen_brightness_mode 0 && settings put system screen_brightness 1");
        } else {
            cmd.arg("settings put system screen_brightness_mode 1 && settings put system screen_brightness 128");
        }

        let _ = cmd.output();
        Ok(())
    }

    /// Simulates touch tap at normalized or absolute (x, y) coordinates on phone screen.
    pub fn send_touch_tap(&self, serial: Option<&str>, x: u32, y: u32) -> io::Result<()> {
        let adb = self.adb_path.as_ref().ok_or_else(|| {
            Error::new(ErrorKind::NotFound, "adb binary not found on this system")
        })?;

        let mut cmd = Command::new(adb);
        if let Some(s) = serial {
            cmd.arg("-s").arg(s);
        }
        cmd.arg("shell")
            .arg("input")
            .arg("tap")
            .arg(x.to_string())
            .arg(y.to_string());

        let _ = cmd.output();
        Ok(())
    }

    /// Simulates touch swipe / drag from (x1, y1) to (x2, y2).
    pub fn send_touch_swipe(
        &self,
        serial: Option<&str>,
        x1: u32,
        y1: u32,
        x2: u32,
        y2: u32,
        duration_ms: u32,
    ) -> io::Result<()> {
        let adb = self.adb_path.as_ref().ok_or_else(|| {
            Error::new(ErrorKind::NotFound, "adb binary not found on this system")
        })?;

        let mut cmd = Command::new(adb);
        if let Some(s) = serial {
            cmd.arg("-s").arg(s);
        }
        cmd.arg("shell")
            .arg("input")
            .arg("swipe")
            .arg(x1.to_string())
            .arg(y1.to_string())
            .arg(x2.to_string())
            .arg(y2.to_string())
            .arg(duration_ms.to_string());

        let _ = cmd.output();
        Ok(())
    }

    /// Sends Android keyevent (e.g. Back = 4, Home = 3, Power = 26).
    pub fn send_keyevent(&self, serial: Option<&str>, keycode: u32) -> io::Result<()> {
        let adb = self.adb_path.as_ref().ok_or_else(|| {
            Error::new(ErrorKind::NotFound, "adb binary not found on this system")
        })?;

        let mut cmd = Command::new(adb);
        if let Some(s) = serial {
            cmd.arg("-s").arg(s);
        }
        cmd.arg("shell")
            .arg("input")
            .arg("keyevent")
            .arg(keycode.to_string());

        let _ = cmd.output();
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_devices_output() {
        let sample = "List of devices attached\n\
                      RF8N123456          device product:shiba model:Pixel_8 device:shiba transport_id:1\n\
                      emulator-5554       unauthorized transport_id:2\n\
                      192.168.1.100:5555  device product:starqlte model:Galaxy_S9 transport_id:3\n";

        let devices = AdbManager::parse_devices_output(sample);
        assert_eq!(devices.len(), 3);

        assert_eq!(devices[0].serial, "RF8N123456");
        assert_eq!(devices[0].model, "Pixel 8");
        assert!(devices[0].is_authorized);

        assert_eq!(devices[1].serial, "emulator-5554");
        assert_eq!(devices[1].model, "Android Device");
        assert!(!devices[1].is_authorized);

        assert_eq!(devices[2].serial, "192.168.1.100:5555");
        assert_eq!(devices[2].model, "Galaxy S9");
        assert!(devices[2].is_authorized);
    }
}
