//! CastSprint Protocol v1 — wire format definitions and codec.
//! Normative specification: `docs/architecture/PROTOCOL.md`
//! All multi-byte integers are big-endian (network byte order).

pub const MAGIC: u32 = 0x43535052; // "CSPR"
pub const VERSION: u8 = 1;
pub const HEADER_SIZE: usize = 24;
pub const MAX_PAYLOAD_SIZE: usize = 8 * 1024 * 1024; // 8 MiB (media packets)
pub const MAX_CONTROL_PAYLOAD_SIZE: usize = 64 * 1024; // 64 KiB (non-media packets)
pub const MAX_STRING_BYTES: usize = 256;
pub const MAX_CODEC_CONFIG_BYTES: usize = 16 * 1024; // 16 KiB
pub const DEFAULT_PORT: u16 = 27183;

// Capability flags (bitfield in Hello message)
pub const CAP_VIDEO_H264: u32 = 1 << 0;
pub const CAP_AUDIO: u32 = 1 << 1;
pub const CAP_VIDEO_H265: u32 = 1 << 2;
pub const CAP_PLATFORM_ANDROID: u32 = 1 << 3;
pub const CAP_PLATFORM_IOS: u32 = 1 << 4;
pub const CAP_PLATFORM_MACOS: u32 = 1 << 5;
pub const CAP_PLATFORM_WINDOWS: u32 = 1 << 6;

// Video frame flags
pub const FRAME_KEYFRAME: u32 = 1 << 0;
pub const FRAME_DISCONTINUITY: u32 = 1 << 1;
pub const FRAME_END_OF_STREAM: u32 = 1 << 2;
pub const FRAME_FLAGS_MASK: u32 = 0x7;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[repr(u8)]
pub enum MessageType {
    Hello = 0x01,
    HelloAck = 0x02,
    VideoConfig = 0x10,
    VideoFrame = 0x11,
    AudioConfig = 0x20,
    AudioFrame = 0x21,
    DisplayChanged = 0x30,
    Heartbeat = 0x40,
    Status = 0x41,
    Disconnect = 0x50,
    Error = 0x51,
}

impl MessageType {
    pub fn from_u8(v: u8) -> Option<Self> {
        match v {
            0x01 => Some(Self::Hello),
            0x02 => Some(Self::HelloAck),
            0x10 => Some(Self::VideoConfig),
            0x11 => Some(Self::VideoFrame),
            0x20 => Some(Self::AudioConfig),
            0x21 => Some(Self::AudioFrame),
            0x30 => Some(Self::DisplayChanged),
            0x40 => Some(Self::Heartbeat),
            0x41 => Some(Self::Status),
            0x50 => Some(Self::Disconnect),
            0x51 => Some(Self::Error),
            _ => None,
        }
    }

    pub fn max_payload_size(self) -> usize {
        match self {
            Self::VideoFrame | Self::AudioFrame => MAX_PAYLOAD_SIZE,
            _ => MAX_CONTROL_PAYLOAD_SIZE,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum VideoCodec {
    H264 = 1,
    H265 = 2,
}

impl VideoCodec {
    pub fn from_u8(v: u8) -> Option<Self> {
        match v {
            1 => Some(Self::H264),
            2 => Some(Self::H265),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum AudioCodec {
    Opus = 1,
    Aac = 2,
    Pcm16 = 3,
}

impl AudioCodec {
    pub fn from_u8(v: u8) -> Option<Self> {
        match v {
            1 => Some(Self::Opus),
            2 => Some(Self::Aac),
            3 => Some(Self::Pcm16),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
#[repr(u8)]
pub enum Rotation {
    #[default]
    R0 = 0,
    R90 = 1,
    R180 = 2,
    R270 = 3,
}

impl Rotation {
    pub fn from_u8(v: u8) -> Option<Self> {
        match v {
            0 => Some(Self::R0),
            1 => Some(Self::R90),
            2 => Some(Self::R180),
            3 => Some(Self::R270),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum HelloStatus {
    Accepted = 0,
    VersionUnsupported = 1,
    Busy = 2,
    Rejected = 3,
}

impl HelloStatus {
    pub fn from_u8(v: u8) -> Option<Self> {
        match v {
            0 => Some(Self::Accepted),
            1 => Some(Self::VersionUnsupported),
            2 => Some(Self::Busy),
            3 => Some(Self::Rejected),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u16)]
pub enum DisconnectReason {
    UserRequested = 1,
    Shutdown = 2,
    Timeout = 3,
    ProtocolError = 4,
    CaptureStopped = 5,
}

impl DisconnectReason {
    pub fn from_u16(v: u16) -> Option<Self> {
        match v {
            1 => Some(Self::UserRequested),
            2 => Some(Self::Shutdown),
            3 => Some(Self::Timeout),
            4 => Some(Self::ProtocolError),
            5 => Some(Self::CaptureStopped),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DecodeError {
    NeedMoreData,
    BadMagic,
    UnsupportedVersion,
    UnknownType,
    ReservedNotZero,
    PayloadTooLarge,
    Truncated,
    TrailingBytes,
    InvalidField,
    StringTooLong,
}

impl std::fmt::Display for DecodeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{:?}", self)
    }
}

impl std::error::Error for DecodeError {}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EncodeError {
    StringTooLong,
    InvalidField,
    PayloadTooLarge,
}

impl std::fmt::Display for EncodeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{:?}", self)
    }
}

impl std::error::Error for EncodeError {}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Header {
    pub version: u8,
    pub msg_type: MessageType,
    pub flags: u16,
    pub session_id: u32,
    pub sequence: u32,
    pub payload_length: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Hello {
    pub min_version: u8,
    pub max_version: u8,
    pub capabilities: u32,
    pub android_api_level: u16,
    pub screen_width: u16,
    pub screen_height: u16,
    pub density_dpi: u16,
    pub device_name: String,
    pub device_model: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HelloAck {
    pub status: HelloStatus,
    pub accepted_version: u8,
    pub assigned_session_id: u32,
    pub max_payload_size: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VideoConfig {
    pub config_id: u32,
    pub codec: VideoCodec,
    pub profile: u8,
    pub level: u8,
    pub rotation: Rotation,
    pub width: u16,
    pub height: u16,
    pub frame_rate: u16,
    pub bitrate: u32,
    pub codec_config: Vec<u8>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VideoFrame {
    pub config_id: u32,
    pub frame_flags: u32,
    pub pts_micros: u64,
    pub data: Vec<u8>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AudioConfig {
    pub codec: AudioCodec,
    pub channels: u8,
    pub sample_rate: u32,
    pub codec_config: Vec<u8>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AudioFrame {
    pub pts_micros: u64,
    pub data: Vec<u8>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DisplayChanged {
    pub width: u16,
    pub height: u16,
    pub rotation: Rotation,
    pub next_config_id: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Heartbeat {
    pub timestamp_micros: u64,
    pub echo_timestamp_micros: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Status {
    pub code: u16,
    pub message: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Disconnect {
    pub reason: DisconnectReason,
    pub message: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ErrorMessage {
    pub code: u16,
    pub fatal: bool,
    pub message: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Payload {
    Hello(Hello),
    HelloAck(HelloAck),
    VideoConfig(VideoConfig),
    VideoFrame(VideoFrame),
    AudioConfig(AudioConfig),
    AudioFrame(AudioFrame),
    DisplayChanged(DisplayChanged),
    Heartbeat(Heartbeat),
    Status(Status),
    Disconnect(Disconnect),
    Error(ErrorMessage),
}

impl Payload {
    pub fn msg_type(&self) -> MessageType {
        match self {
            Self::Hello(_) => MessageType::Hello,
            Self::HelloAck(_) => MessageType::HelloAck,
            Self::VideoConfig(_) => MessageType::VideoConfig,
            Self::VideoFrame(_) => MessageType::VideoFrame,
            Self::AudioConfig(_) => MessageType::AudioConfig,
            Self::AudioFrame(_) => MessageType::AudioFrame,
            Self::DisplayChanged(_) => MessageType::DisplayChanged,
            Self::Heartbeat(_) => MessageType::Heartbeat,
            Self::Status(_) => MessageType::Status,
            Self::Disconnect(_) => MessageType::Disconnect,
            Self::Error(_) => MessageType::Error,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Message {
    pub header: Header,
    pub payload: Payload,
}

// ----------------- Codec Implementation -----------------

struct Writer<'a> {
    out: &'a mut Vec<u8>,
}

impl<'a> Writer<'a> {
    fn new(out: &'a mut Vec<u8>) -> Self {
        Self { out }
    }

    fn u8(&mut self, v: u8) {
        self.out.push(v);
    }

    fn u16(&mut self, v: u16) {
        self.out.extend_from_slice(&v.to_be_bytes());
    }

    fn u32(&mut self, v: u32) {
        self.out.extend_from_slice(&v.to_be_bytes());
    }

    fn u64(&mut self, v: u64) {
        self.out.extend_from_slice(&v.to_be_bytes());
    }

    fn bytes(&mut self, b: &[u8]) {
        self.out.extend_from_slice(b);
    }

    fn string(&mut self, s: &str) -> Result<(), EncodeError> {
        let b = s.as_bytes();
        if b.len() > MAX_STRING_BYTES {
            return Err(EncodeError::StringTooLong);
        }
        self.u16(b.len() as u16);
        self.bytes(b);
        Ok(())
    }
}

struct Reader<'a> {
    slice: &'a [u8],
    pos: usize,
}

impl<'a> Reader<'a> {
    fn new(slice: &'a [u8]) -> Self {
        Self { slice, pos: 0 }
    }

    fn remaining(&self) -> usize {
        self.slice.len().saturating_sub(self.pos)
    }

    fn has(&self, n: usize) -> bool {
        self.remaining() >= n
    }

    fn read_u8(&mut self) -> Result<u8, DecodeError> {
        if !self.has(1) {
            return Err(DecodeError::Truncated);
        }
        let v = self.slice[self.pos];
        self.pos += 1;
        Ok(v)
    }

    fn read_u16(&mut self) -> Result<u16, DecodeError> {
        if !self.has(2) {
            return Err(DecodeError::Truncated);
        }
        let v = u16::from_be_bytes([self.slice[self.pos], self.slice[self.pos + 1]]);
        self.pos += 2;
        Ok(v)
    }

    fn read_u32(&mut self) -> Result<u32, DecodeError> {
        if !self.has(4) {
            return Err(DecodeError::Truncated);
        }
        let arr = [
            self.slice[self.pos],
            self.slice[self.pos + 1],
            self.slice[self.pos + 2],
            self.slice[self.pos + 3],
        ];
        self.pos += 4;
        Ok(u32::from_be_bytes(arr))
    }

    fn read_u64(&mut self) -> Result<u64, DecodeError> {
        if !self.has(8) {
            return Err(DecodeError::Truncated);
        }
        let mut arr = [0u8; 8];
        arr.copy_from_slice(&self.slice[self.pos..self.pos + 8]);
        self.pos += 8;
        Ok(u64::from_be_bytes(arr))
    }

    fn read_bytes(&mut self, n: usize) -> Result<Vec<u8>, DecodeError> {
        if !self.has(n) {
            return Err(DecodeError::Truncated);
        }
        let b = self.slice[self.pos..self.pos + n].to_vec();
        self.pos += n;
        Ok(b)
    }

    fn read_string(&mut self) -> Result<String, DecodeError> {
        let len = self.read_u16()? as usize;
        if len > MAX_STRING_BYTES {
            return Err(DecodeError::StringTooLong);
        }
        if !self.has(len) {
            return Err(DecodeError::Truncated);
        }
        let str_bytes = &self.slice[self.pos..self.pos + len];
        let s = std::str::from_utf8(str_bytes).map_err(|_| DecodeError::InvalidField)?;
        self.pos += len;
        Ok(s.to_string())
    }

    fn finish(&self) -> Result<(), DecodeError> {
        if self.remaining() > 0 {
            Err(DecodeError::TrailingBytes)
        } else {
            Ok(())
        }
    }
}

/// Parses and validates a 24-byte header.
pub fn decode_header(bytes: &[u8]) -> Result<Header, DecodeError> {
    if bytes.len() < HEADER_SIZE {
        return Err(DecodeError::NeedMoreData);
    }
    let mut r = Reader::new(&bytes[..HEADER_SIZE]);
    let magic = r.read_u32()?;
    if magic != MAGIC {
        return Err(DecodeError::BadMagic);
    }
    let version = r.read_u8()?;
    if version != VERSION {
        return Err(DecodeError::UnsupportedVersion);
    }
    let raw_type = r.read_u8()?;
    let msg_type = MessageType::from_u8(raw_type).ok_or(DecodeError::UnknownType)?;
    let flags = r.read_u16()?;
    if flags != 0 {
        return Err(DecodeError::ReservedNotZero);
    }
    let session_id = r.read_u32()?;
    let sequence = r.read_u32()?;
    let payload_length = r.read_u32()?;
    let reserved = r.read_u32()?;
    if reserved != 0 {
        return Err(DecodeError::ReservedNotZero);
    }

    if payload_length as usize > msg_type.max_payload_size() {
        return Err(DecodeError::PayloadTooLarge);
    }

    Ok(Header {
        version,
        msg_type,
        flags,
        session_id,
        sequence,
        payload_length,
    })
}

/// Decodes a full message (header + payload).
/// Returns `(Message, bytes_consumed)`.
pub fn decode_message(bytes: &[u8]) -> Result<(Message, usize), DecodeError> {
    let header = decode_header(bytes)?;
    let total_size = HEADER_SIZE + header.payload_length as usize;
    if bytes.len() < total_size {
        return Err(DecodeError::NeedMoreData);
    }

    let payload_slice = &bytes[HEADER_SIZE..total_size];
    let payload = decode_payload(header.msg_type, payload_slice)?;

    Ok((Message { header, payload }, total_size))
}

fn decode_payload(msg_type: MessageType, p: &[u8]) -> Result<Payload, DecodeError> {
    let mut r = Reader::new(p);
    let payload = match msg_type {
        MessageType::Hello => {
            let min_version = r.read_u8()?;
            let max_version = r.read_u8()?;
            let reserved = r.read_u16()?;
            if reserved != 0 {
                return Err(DecodeError::ReservedNotZero);
            }
            if min_version == 0 || min_version > max_version {
                return Err(DecodeError::InvalidField);
            }
            let capabilities = r.read_u32()?;
            let android_api_level = r.read_u16()?;
            let screen_width = r.read_u16()?;
            let screen_height = r.read_u16()?;
            let density_dpi = r.read_u16()?;
            let device_name = r.read_string()?;
            let device_model = r.read_string()?;
            r.finish()?;
            Payload::Hello(Hello {
                min_version,
                max_version,
                capabilities,
                android_api_level,
                screen_width,
                screen_height,
                density_dpi,
                device_name,
                device_model,
            })
        }
        MessageType::HelloAck => {
            let status_raw = r.read_u8()?;
            let status = HelloStatus::from_u8(status_raw).ok_or(DecodeError::InvalidField)?;
            let accepted_version = r.read_u8()?;
            let reserved = r.read_u16()?;
            if reserved != 0 {
                return Err(DecodeError::ReservedNotZero);
            }
            let assigned_session_id = r.read_u32()?;
            let max_payload_size = r.read_u32()?;
            if max_payload_size as usize > MAX_PAYLOAD_SIZE {
                return Err(DecodeError::InvalidField);
            }
            r.finish()?;
            Payload::HelloAck(HelloAck {
                status,
                accepted_version,
                assigned_session_id,
                max_payload_size,
            })
        }
        MessageType::VideoConfig => {
            let config_id = r.read_u32()?;
            let codec_raw = r.read_u8()?;
            let codec = VideoCodec::from_u8(codec_raw).ok_or(DecodeError::InvalidField)?;
            let profile = r.read_u8()?;
            let level = r.read_u8()?;
            let rot_raw = r.read_u8()?;
            let rotation = Rotation::from_u8(rot_raw).ok_or(DecodeError::InvalidField)?;
            let width = r.read_u16()?;
            let height = r.read_u16()?;
            if width == 0 || height == 0 {
                return Err(DecodeError::InvalidField);
            }
            let frame_rate = r.read_u16()?;
            let reserved = r.read_u16()?;
            if reserved != 0 {
                return Err(DecodeError::ReservedNotZero);
            }
            let bitrate = r.read_u32()?;
            let csd_len = r.read_u32()? as usize;
            if csd_len > MAX_CODEC_CONFIG_BYTES {
                return Err(DecodeError::InvalidField);
            }
            let codec_config = r.read_bytes(csd_len)?;
            r.finish()?;
            Payload::VideoConfig(VideoConfig {
                config_id,
                codec,
                profile,
                level,
                rotation,
                width,
                height,
                frame_rate,
                bitrate,
                codec_config,
            })
        }
        MessageType::VideoFrame => {
            let config_id = r.read_u32()?;
            let frame_flags = r.read_u32()?;
            if (frame_flags & !FRAME_FLAGS_MASK) != 0 {
                return Err(DecodeError::InvalidField);
            }
            let pts_micros = r.read_u64()?;
            let rem = r.remaining();
            let data = r.read_bytes(rem)?;
            if data.is_empty() && (frame_flags & FRAME_END_OF_STREAM) == 0 {
                return Err(DecodeError::InvalidField);
            }
            Payload::VideoFrame(VideoFrame {
                config_id,
                frame_flags,
                pts_micros,
                data,
            })
        }
        MessageType::AudioConfig => {
            let codec_raw = r.read_u8()?;
            let codec = AudioCodec::from_u8(codec_raw).ok_or(DecodeError::InvalidField)?;
            let channels = r.read_u8()?;
            if channels == 0 || channels > 8 {
                return Err(DecodeError::InvalidField);
            }
            let reserved = r.read_u16()?;
            if reserved != 0 {
                return Err(DecodeError::ReservedNotZero);
            }
            let sample_rate = r.read_u32()?;
            if sample_rate == 0 {
                return Err(DecodeError::InvalidField);
            }
            let csd_len = r.read_u32()? as usize;
            if csd_len > MAX_CODEC_CONFIG_BYTES {
                return Err(DecodeError::InvalidField);
            }
            let codec_config = r.read_bytes(csd_len)?;
            r.finish()?;
            Payload::AudioConfig(AudioConfig {
                codec,
                channels,
                sample_rate,
                codec_config,
            })
        }
        MessageType::AudioFrame => {
            let pts_micros = r.read_u64()?;
            let rem = r.remaining();
            if rem == 0 {
                return Err(DecodeError::InvalidField);
            }
            let data = r.read_bytes(rem)?;
            Payload::AudioFrame(AudioFrame { pts_micros, data })
        }
        MessageType::DisplayChanged => {
            let width = r.read_u16()?;
            let height = r.read_u16()?;
            if width == 0 || height == 0 {
                return Err(DecodeError::InvalidField);
            }
            let rot_raw = r.read_u8()?;
            let rotation = Rotation::from_u8(rot_raw).ok_or(DecodeError::InvalidField)?;
            let reserved_u8 = r.read_u8()?;
            let reserved_u16 = r.read_u16()?;
            if reserved_u8 != 0 || reserved_u16 != 0 {
                return Err(DecodeError::ReservedNotZero);
            }
            let next_config_id = r.read_u32()?;
            r.finish()?;
            Payload::DisplayChanged(DisplayChanged {
                width,
                height,
                rotation,
                next_config_id,
            })
        }
        MessageType::Heartbeat => {
            let timestamp_micros = r.read_u64()?;
            let echo_timestamp_micros = r.read_u64()?;
            r.finish()?;
            Payload::Heartbeat(Heartbeat {
                timestamp_micros,
                echo_timestamp_micros,
            })
        }
        MessageType::Status => {
            let code = r.read_u16()?;
            let message = r.read_string()?;
            r.finish()?;
            Payload::Status(Status { code, message })
        }
        MessageType::Disconnect => {
            let reason_raw = r.read_u16()?;
            let reason = DisconnectReason::from_u16(reason_raw).ok_or(DecodeError::InvalidField)?;
            let message = r.read_string()?;
            r.finish()?;
            Payload::Disconnect(Disconnect { reason, message })
        }
        MessageType::Error => {
            let code = r.read_u16()?;
            let fatal_raw = r.read_u8()?;
            let reserved = r.read_u8()?;
            if reserved != 0 {
                return Err(DecodeError::ReservedNotZero);
            }
            let fatal = match fatal_raw {
                0 => false,
                1 => true,
                _ => return Err(DecodeError::InvalidField),
            };
            let message = r.read_string()?;
            r.finish()?;
            Payload::Error(ErrorMessage {
                code,
                fatal,
                message,
            })
        }
    };
    Ok(payload)
}

/// Encodes a full CastSprint Protocol message into the provided buffer.
pub fn encode_message(
    session_id: u32,
    sequence: u32,
    payload: &Payload,
    out: &mut Vec<u8>,
) -> Result<(), EncodeError> {
    let msg_type = payload.msg_type();
    let header_start = out.len();

    // Reserve 24 bytes for header
    out.resize(header_start + HEADER_SIZE, 0);

    let payload_start = out.len();
    let mut w = Writer::new(out);

    match payload {
        Payload::Hello(m) => {
            if m.device_name.len() > MAX_STRING_BYTES || m.device_model.len() > MAX_STRING_BYTES {
                return Err(EncodeError::StringTooLong);
            }
            if m.min_version == 0 || m.min_version > m.max_version {
                return Err(EncodeError::InvalidField);
            }
            w.u8(m.min_version);
            w.u8(m.max_version);
            w.u16(0); // reserved
            w.u32(m.capabilities);
            w.u16(m.android_api_level);
            w.u16(m.screen_width);
            w.u16(m.screen_height);
            w.u16(m.density_dpi);
            w.string(&m.device_name)?;
            w.string(&m.device_model)?;
        }
        Payload::HelloAck(m) => {
            w.u8(m.status as u8);
            w.u8(m.accepted_version);
            w.u16(0); // reserved
            w.u32(m.assigned_session_id);
            w.u32(m.max_payload_size);
        }
        Payload::VideoConfig(m) => {
            if m.codec_config.len() > MAX_CODEC_CONFIG_BYTES || m.width == 0 || m.height == 0 {
                return Err(EncodeError::InvalidField);
            }
            w.u32(m.config_id);
            w.u8(m.codec as u8);
            w.u8(m.profile);
            w.u8(m.level);
            w.u8(m.rotation as u8);
            w.u16(m.width);
            w.u16(m.height);
            w.u16(m.frame_rate);
            w.u16(0); // reserved
            w.u32(m.bitrate);
            w.u32(m.codec_config.len() as u32);
            w.bytes(&m.codec_config);
        }
        Payload::VideoFrame(m) => {
            if (m.frame_flags & !FRAME_FLAGS_MASK) != 0 {
                return Err(EncodeError::InvalidField);
            }
            if m.data.is_empty() && (m.frame_flags & FRAME_END_OF_STREAM) == 0 {
                return Err(EncodeError::InvalidField);
            }
            w.u32(m.config_id);
            w.u32(m.frame_flags);
            w.u64(m.pts_micros);
            w.bytes(&m.data);
        }
        Payload::AudioConfig(m) => {
            if m.codec_config.len() > MAX_CODEC_CONFIG_BYTES
                || m.channels == 0
                || m.channels > 8
                || m.sample_rate == 0
            {
                return Err(EncodeError::InvalidField);
            }
            w.u8(m.codec as u8);
            w.u8(m.channels);
            w.u16(0); // reserved
            w.u32(m.sample_rate);
            w.u32(m.codec_config.len() as u32);
            w.bytes(&m.codec_config);
        }
        Payload::AudioFrame(m) => {
            if m.data.is_empty() {
                return Err(EncodeError::InvalidField);
            }
            w.u64(m.pts_micros);
            w.bytes(&m.data);
        }
        Payload::DisplayChanged(m) => {
            if m.width == 0 || m.height == 0 {
                return Err(EncodeError::InvalidField);
            }
            w.u16(m.width);
            w.u16(m.height);
            w.u8(m.rotation as u8);
            w.u8(0); // reserved
            w.u16(0); // reserved
            w.u32(m.next_config_id);
        }
        Payload::Heartbeat(m) => {
            w.u64(m.timestamp_micros);
            w.u64(m.echo_timestamp_micros);
        }
        Payload::Status(m) => {
            if m.message.len() > MAX_STRING_BYTES {
                return Err(EncodeError::StringTooLong);
            }
            w.u16(m.code);
            w.string(&m.message)?;
        }
        Payload::Disconnect(m) => {
            if m.message.len() > MAX_STRING_BYTES {
                return Err(EncodeError::StringTooLong);
            }
            w.u16(m.reason as u16);
            w.string(&m.message)?;
        }
        Payload::Error(m) => {
            if m.message.len() > MAX_STRING_BYTES {
                return Err(EncodeError::StringTooLong);
            }
            w.u16(m.code);
            w.u8(if m.fatal { 1 } else { 0 });
            w.u8(0); // reserved
            w.string(&m.message)?;
        }
    }

    let payload_len = out.len() - payload_start;
    if payload_len > msg_type.max_payload_size() {
        return Err(EncodeError::PayloadTooLarge);
    }

    // Write header bytes
    let header_bytes = &mut out[header_start..header_start + HEADER_SIZE];
    header_bytes[0..4].copy_from_slice(&MAGIC.to_be_bytes());
    header_bytes[4] = VERSION;
    header_bytes[5] = msg_type as u8;
    header_bytes[6..8].copy_from_slice(&0u16.to_be_bytes());
    header_bytes[8..12].copy_from_slice(&session_id.to_be_bytes());
    header_bytes[12..16].copy_from_slice(&sequence.to_be_bytes());
    header_bytes[16..20].copy_from_slice(&(payload_len as u32).to_be_bytes());
    header_bytes[20..24].copy_from_slice(&0u32.to_be_bytes());

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_golden_heartbeat() {
        // Golden vector shared with Android ProtocolCodecTest and C++ protocol_tests.cpp
        let hb = Heartbeat {
            timestamp_micros: 0x0102030405060708,
            echo_timestamp_micros: 0x1112131415161718,
        };
        let mut buf = Vec::new();
        encode_message(0x00000001, 0x00000002, &Payload::Heartbeat(hb.clone()), &mut buf).unwrap();

        let expected: &[u8] = &[
            0x43, 0x53, 0x50, 0x52, 0x01, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
            0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00, 0x00,
            0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
            0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18,
        ];

        assert_eq!(buf.as_slice(), expected);

        let (msg, consumed) = decode_message(&buf).unwrap();
        assert_eq!(consumed, expected.len());
        assert_eq!(msg.header.session_id, 1);
        assert_eq!(msg.header.sequence, 2);
        assert_eq!(msg.payload, Payload::Heartbeat(hb));
    }

    #[test]
    fn test_roundtrips() {
        // Hello
        let hello = Hello {
            min_version: 1,
            max_version: 1,
            capabilities: CAP_VIDEO_H264 | CAP_AUDIO,
            android_api_level: 34,
            screen_width: 1080,
            screen_height: 2400,
            density_dpi: 420,
            device_name: "Pixel 8".to_string(),
            device_model: "shiba".to_string(),
        };
        let mut buf = Vec::new();
        encode_message(42, 1, &Payload::Hello(hello.clone()), &mut buf).unwrap();
        let (msg, consumed) = decode_message(&buf).unwrap();
        assert_eq!(consumed, buf.len());
        assert_eq!(msg.payload, Payload::Hello(hello));

        // VideoConfig
        let vc = VideoConfig {
            config_id: 3,
            codec: VideoCodec::H264,
            profile: 100,
            level: 42,
            rotation: Rotation::R90,
            width: 1920,
            height: 1080,
            frame_rate: 60,
            bitrate: 12_000_000,
            codec_config: vec![0, 0, 0, 1, 0x67, 0x64, 0, 0, 0, 1, 0x68],
        };
        buf.clear();
        encode_message(42, 2, &Payload::VideoConfig(vc.clone()), &mut buf).unwrap();
        let (msg, consumed) = decode_message(&buf).unwrap();
        assert_eq!(consumed, buf.len());
        assert_eq!(msg.payload, Payload::VideoConfig(vc));

        // VideoFrame
        let vf = VideoFrame {
            config_id: 3,
            frame_flags: FRAME_KEYFRAME,
            pts_micros: 123456789012,
            data: vec![0xAB; 5000],
        };
        buf.clear();
        encode_message(42, 3, &Payload::VideoFrame(vf.clone()), &mut buf).unwrap();
        let (msg, consumed) = decode_message(&buf).unwrap();
        assert_eq!(consumed, buf.len());
        assert_eq!(msg.payload, Payload::VideoFrame(vf));

        // AudioConfig & Frame
        let ac = AudioConfig {
            codec: AudioCodec::Opus,
            channels: 2,
            sample_rate: 48000,
            codec_config: vec![1, 2, 3],
        };
        buf.clear();
        encode_message(42, 4, &Payload::AudioConfig(ac.clone()), &mut buf).unwrap();
        let (msg, _) = decode_message(&buf).unwrap();
        assert_eq!(msg.payload, Payload::AudioConfig(ac));

        let af = AudioFrame {
            pts_micros: 99,
            data: vec![9, 9, 9],
        };
        buf.clear();
        encode_message(42, 5, &Payload::AudioFrame(af.clone()), &mut buf).unwrap();
        let (msg, _) = decode_message(&buf).unwrap();
        assert_eq!(msg.payload, Payload::AudioFrame(af));

        // DisplayChanged
        let dc = DisplayChanged {
            width: 2400,
            height: 1080,
            rotation: Rotation::R270,
            next_config_id: 4,
        };
        buf.clear();
        encode_message(42, 6, &Payload::DisplayChanged(dc.clone()), &mut buf).unwrap();
        let (msg, _) = decode_message(&buf).unwrap();
        assert_eq!(msg.payload, Payload::DisplayChanged(dc));

        // Status, Disconnect, Error
        let st = Status { code: 5, message: "encoder ready".to_string() };
        buf.clear();
        encode_message(42, 7, &Payload::Status(st.clone()), &mut buf).unwrap();
        let (msg, _) = decode_message(&buf).unwrap();
        assert_eq!(msg.payload, Payload::Status(st));

        let disc = Disconnect { reason: DisconnectReason::Timeout, message: "bye".to_string() };
        buf.clear();
        encode_message(42, 8, &Payload::Disconnect(disc.clone()), &mut buf).unwrap();
        let (msg, _) = decode_message(&buf).unwrap();
        assert_eq!(msg.payload, Payload::Disconnect(disc));

        let err = ErrorMessage { code: 17, fatal: true, message: "decoder failed".to_string() };
        buf.clear();
        encode_message(42, 9, &Payload::Error(err.clone()), &mut buf).unwrap();
        let (msg, _) = decode_message(&buf).unwrap();
        assert_eq!(msg.payload, Payload::Error(err));
    }
}
