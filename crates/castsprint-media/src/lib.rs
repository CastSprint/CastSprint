//! CastSprint Media Pipeline: H.264 Bitstream Parser & Lossless Direct-to-Disk Recorder.
//! Normative specification: `docs/architecture/STREAMING_PIPELINE.md` and `AUDIO_AND_LAN.md`

use std::fs::{File, OpenOptions};
use std::io::{self, BufWriter, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum NalType {
    Unspecified = 0,
    NonIdr = 1,
    DataPartitionA = 2,
    DataPartitionB = 3,
    DataPartitionC = 4,
    Idr = 5,
    Sei = 6,
    Sps = 7,
    Pps = 8,
    Aud = 9,
    EndOfSequence = 10,
    EndOfStream = 11,
    FillerData = 12,
    Unknown(u8),
}

impl From<u8> for NalType {
    fn from(v: u8) -> Self {
        match v & 0x1F {
            0 => Self::Unspecified,
            1 => Self::NonIdr,
            2 => Self::DataPartitionA,
            3 => Self::DataPartitionB,
            4 => Self::DataPartitionC,
            5 => Self::Idr,
            6 => Self::Sei,
            7 => Self::Sps,
            8 => Self::Pps,
            9 => Self::Aud,
            10 => Self::EndOfSequence,
            11 => Self::EndOfStream,
            12 => Self::FillerData,
            other => Self::Unknown(other),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NalUnit<'a> {
    pub nal_type: NalType,
    pub data: &'a [u8],
}

/// Parses an Annex-B formatted byte stream into its individual NAL units.
pub fn parse_nal_units(data: &[u8]) -> Vec<NalUnit<'_>> {
    let mut units = Vec::new();
    let len = data.len();
    if len < 4 {
        return units;
    }

    let mut start_indices = Vec::new();
    let mut i = 0;
    while i + 3 <= len {
        if data[i] == 0 && data[i + 1] == 0 {
            if data[i + 2] == 1 {
                // 3-byte start code 00 00 01
                start_indices.push((i, i + 3));
                i += 3;
                continue;
            } else if i + 4 <= len && data[i + 2] == 0 && data[i + 3] == 1 {
                // 4-byte start code 00 00 00 01
                start_indices.push((i, i + 4));
                i += 4;
                continue;
            }
        }
        i += 1;
    }

    for idx in 0..start_indices.len() {
        let (start_code_pos, nal_payload_start) = start_indices[idx];
        let nal_payload_end = if idx + 1 < start_indices.len() {
            start_indices[idx + 1].0
        } else {
            len
        };

        if nal_payload_start < nal_payload_end {
            let nal_header = data[nal_payload_start];
            let nal_type = NalType::from(nal_header);
            units.push(NalUnit {
                nal_type,
                data: &data[start_code_pos..nal_payload_end],
            });
        }
    }

    units
}

/// Returns true if the Annex-B byte slice contains an IDR (Keyframe) NAL unit.
pub fn contains_idr(data: &[u8]) -> bool {
    let units = parse_nal_units(data);
    units.iter().any(|u| u.nal_type == NalType::Idr)
}

/// Returns true if the Annex-B byte slice contains SPS/PPS headers.
pub fn contains_sps_pps(data: &[u8]) -> bool {
    let units = parse_nal_units(data);
    let has_sps = units.iter().any(|u| u.nal_type == NalType::Sps);
    let has_pps = units.iter().any(|u| u.nal_type == NalType::Pps);
    has_sps && has_pps
}

// ----------------- Lossless Direct-to-Disk Recorder -----------------

pub struct StreamRecorder {
    file_path: PathBuf,
    writer: Option<BufWriter<File>>,
    is_recording: Arc<AtomicBool>,
    frames_recorded: Arc<AtomicU64>,
    bytes_written: Arc<AtomicU64>,
    start_time_micros: Option<u64>,
    last_pts_micros: u64,
}

impl StreamRecorder {
    /// Initializes a new lossless recording session writing directly to file.
    pub fn new<P: AsRef<Path>>(path: P) -> io::Result<Self> {
        let file_path = path.as_ref().to_path_buf();
        if let Some(parent) = file_path.parent() {
            std::fs::create_dir_all(parent)?;
        }

        let file = OpenOptions::new()
            .create(true)
            .write(true)
            .truncate(true)
            .open(&file_path)?;

        let writer = BufWriter::with_capacity(256 * 1024, file);

        Ok(Self {
            file_path,
            writer: Some(writer),
            is_recording: Arc::new(AtomicBool::new(true)),
            frames_recorded: Arc::new(AtomicU64::new(0)),
            bytes_written: Arc::new(AtomicU64::new(0)),
            start_time_micros: None,
            last_pts_micros: 0,
        })
    }

    pub fn is_recording(&self) -> bool {
        self.is_recording.load(Ordering::SeqCst)
    }

    pub fn frames_recorded(&self) -> u64 {
        self.frames_recorded.load(Ordering::SeqCst)
    }

    pub fn bytes_written(&self) -> u64 {
        self.bytes_written.load(Ordering::SeqCst)
    }

    pub fn file_path(&self) -> &Path {
        &self.file_path
    }

    /// Writes an Annex-B encoded H.264 video frame directly to the file.
    pub fn write_video_frame(&mut self, pts_micros: u64, data: &[u8]) -> io::Result<()> {
        if !self.is_recording.load(Ordering::SeqCst) {
            return Ok(());
        }

        if let Some(ref mut w) = self.writer {
            w.write_all(data)?;

            if self.start_time_micros.is_none() {
                self.start_time_micros = Some(pts_micros);
            }
            self.last_pts_micros = pts_micros;

            self.frames_recorded.fetch_add(1, Ordering::SeqCst);
            self.bytes_written
                .fetch_add(data.len() as u64, Ordering::SeqCst);
        }

        Ok(())
    }

    /// Flushes buffers and finalizes the recording file.
    pub fn stop(&mut self) -> io::Result<()> {
        self.is_recording.store(false, Ordering::SeqCst);
        if let Some(mut w) = self.writer.take() {
            w.flush()?;
        }
        Ok(())
    }
}

impl Drop for StreamRecorder {
    fn drop(&mut self) {
        let _ = self.stop();
    }
}

/// Saves a 32-bit 0RGB pixel buffer to a standard cross-platform 32-bit BMP image file.
/// Zero-dependency, compatible with Windows Photos, macOS Preview, Linux image viewers, and OBS.
pub fn save_bmp_screenshot<P: AsRef<Path>>(
    path: P,
    width: u32,
    height: u32,
    pixels: &[u32],
) -> io::Result<()> {
    if (width * height) as usize != pixels.len() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "Pixel slice length does not match width * height",
        ));
    }

    if let Some(parent) = path.as_ref().parent() {
        let _ = std::fs::create_dir_all(parent);
    }

    let file = File::create(path)?;
    let mut writer = BufWriter::new(file);

    let image_size = (width * height * 4) as u32;
    let file_size = 54 + image_size;

    // 14-byte BMP Header
    let mut bmp_header = [0u8; 14];
    bmp_header[0] = b'B';
    bmp_header[1] = b'M';
    bmp_header[2..6].copy_from_slice(&file_size.to_le_bytes());
    bmp_header[10..14].copy_from_slice(&54u32.to_le_bytes()); // Pixel array offset
    writer.write_all(&bmp_header)?;

    // 40-byte DIB Header (BITMAPINFOHEADER)
    let mut dib_header = [0u8; 40];
    dib_header[0..4].copy_from_slice(&40u32.to_le_bytes()); // Header size
    dib_header[4..8].copy_from_slice(&(width as i32).to_le_bytes());
    // Negative height indicates top-down bitmap (row 0 is top)
    dib_header[8..12].copy_from_slice(&(-(height as i32)).to_le_bytes());
    dib_header[12..14].copy_from_slice(&1u16.to_le_bytes()); // Color planes
    dib_header[14..16].copy_from_slice(&32u16.to_le_bytes()); // Bits per pixel (32-bit BGRA/BGRX)
    dib_header[16..20].copy_from_slice(&0u32.to_le_bytes()); // BI_RGB (uncompressed)
    dib_header[20..24].copy_from_slice(&image_size.to_le_bytes());
    dib_header[24..28].copy_from_slice(&2835u32.to_le_bytes()); // 72 DPI horizontal
    dib_header[28..32].copy_from_slice(&2835u32.to_le_bytes()); // 72 DPI vertical
    writer.write_all(&dib_header)?;

    // Pixel data: in softbuffer, 0x00RRGGBB in little-endian on x86/ARM is [BB, GG, RR, 00],
    // which exactly matches Windows/BMP 32-bit BGRA format!
    for &p in pixels {
        let b = (p & 0xFF) as u8;
        let g = ((p >> 8) & 0xFF) as u8;
        let r = ((p >> 16) & 0xFF) as u8;
        let a = 0xFFu8;
        writer.write_all(&[b, g, r, a])?;
    }

    writer.flush()?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_annex_b_parsing() {
        // Construct sample bitstream: SPS (0x67) + PPS (0x68) + IDR (0x65)
        let sample_sps = [0x00, 0x00, 0x00, 0x01, 0x67, 0x42, 0x00, 0x1E];
        let sample_pps = [0x00, 0x00, 0x01, 0x68, 0xCE, 0x3C, 0x80];
        let sample_idr = [0x00, 0x00, 0x00, 0x01, 0x65, 0x88, 0x84];

        let mut stream = Vec::new();
        stream.extend_from_slice(&sample_sps);
        stream.extend_from_slice(&sample_pps);
        stream.extend_from_slice(&sample_idr);

        let units = parse_nal_units(&stream);
        assert_eq!(units.len(), 3);
        assert_eq!(units[0].nal_type, NalType::Sps);
        assert_eq!(units[1].nal_type, NalType::Pps);
        assert_eq!(units[2].nal_type, NalType::Idr);

        assert!(contains_idr(&stream));
        assert!(contains_sps_pps(&stream));
    }

    #[test]
    fn test_stream_recorder_lifecycle() {
        let temp_dir = std::env::temp_dir();
        let test_file = temp_dir.join("castsprint_test_recording.h264");

        let mut recorder = StreamRecorder::new(&test_file).expect("Failed to create recorder");
        assert!(recorder.is_recording());

        let frame = vec![0x00, 0x00, 0x00, 0x01, 0x65, 0xAA, 0xBB, 0xCC];
        recorder.write_video_frame(100_000, &frame).unwrap();
        recorder.write_video_frame(116_666, &frame).unwrap();

        assert_eq!(recorder.frames_recorded(), 2);
        assert_eq!(recorder.bytes_written(), 16);

        recorder.stop().unwrap();
        assert!(!recorder.is_recording());

        // Verify written file size on disk
        let metadata = std::fs::metadata(&test_file).unwrap();
        assert_eq!(metadata.len(), 16);

        let _ = std::fs::remove_file(&test_file);
    }

    #[test]
    fn test_save_bmp_screenshot() {
        let temp_dir = std::env::temp_dir();
        let shot_path = temp_dir.join("castsprint_test_shot.bmp");

        let pixels = vec![0x00FF0000, 0x0000FF00, 0x000000FF, 0x00FFFFFF];
        save_bmp_screenshot(&shot_path, 2, 2, &pixels).expect("Failed to write BMP screenshot");

        let meta = std::fs::metadata(&shot_path).unwrap();
        assert_eq!(meta.len(), 54 + (2 * 2 * 4)); // 54 byte header + 16 bytes pixel data

        let _ = std::fs::remove_file(&shot_path);
    }
}
