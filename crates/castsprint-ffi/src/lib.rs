//! CastSprint C-ABI & Swift Bridge.
//! Provides stable C linkage for Swift (macOS / iOS), Android JNI, and native embedding.

use std::ffi::{c_char, c_void, CStr};
use std::ptr;
use std::slice;

use castsprint_core::protocol::*;
use castsprint_core::session::*;
use castsprint_core::sync::*;

#[repr(C)]
#[derive(Debug, Copy, Clone)]
pub struct CspHeader {
    pub version: u8,
    pub msg_type: u8,
    pub flags: u16,
    pub session_id: u32,
    pub sequence: u32,
    pub payload_length: u32,
}

#[repr(C)]
#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub enum CspDecodeResult {
    Ok = 0,
    NeedMoreData = 1,
    BadMagic = 2,
    UnsupportedVersion = 3,
    UnknownType = 4,
    ReservedNotZero = 5,
    PayloadTooLarge = 6,
    Truncated = 7,
    TrailingBytes = 8,
    InvalidField = 9,
    StringTooLong = 10,
}

impl From<DecodeError> for CspDecodeResult {
    fn from(err: DecodeError) -> Self {
        match err {
            DecodeError::NeedMoreData => CspDecodeResult::NeedMoreData,
            DecodeError::BadMagic => CspDecodeResult::BadMagic,
            DecodeError::UnsupportedVersion => CspDecodeResult::UnsupportedVersion,
            DecodeError::UnknownType => CspDecodeResult::UnknownType,
            DecodeError::ReservedNotZero => CspDecodeResult::ReservedNotZero,
            DecodeError::PayloadTooLarge => CspDecodeResult::PayloadTooLarge,
            DecodeError::Truncated => CspDecodeResult::Truncated,
            DecodeError::TrailingBytes => CspDecodeResult::TrailingBytes,
            DecodeError::InvalidField => CspDecodeResult::InvalidField,
            DecodeError::StringTooLong => CspDecodeResult::StringTooLong,
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn csp_decode_header(
    bytes: *const u8,
    len: usize,
    out_hdr: *mut CspHeader,
) -> CspDecodeResult {
    if bytes.is_null() || out_hdr.is_null() {
        return CspDecodeResult::InvalidField;
    }
    let slice = slice::from_raw_parts(bytes, len);
    match decode_header(slice) {
        Ok(h) => {
            (*out_hdr).version = h.version;
            (*out_hdr).msg_type = h.msg_type as u8;
            (*out_hdr).flags = h.flags;
            (*out_hdr).session_id = h.session_id;
            (*out_hdr).sequence = h.sequence;
            (*out_hdr).payload_length = h.payload_length;
            CspDecodeResult::Ok
        }
        Err(e) => e.into(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn csp_encode_header(
    hdr: *const CspHeader,
    out_buf: *mut u8,
    buf_len: usize,
) -> bool {
    if hdr.is_null() || out_buf.is_null() || buf_len < HEADER_SIZE {
        return false;
    }
    let h = &*hdr;
    let slice = slice::from_raw_parts_mut(out_buf, buf_len);
    slice[0..4].copy_from_slice(&MAGIC.to_be_bytes());
    slice[4] = h.version;
    slice[5] = h.msg_type;
    slice[6..8].copy_from_slice(&h.flags.to_be_bytes());
    slice[8..12].copy_from_slice(&h.session_id.to_be_bytes());
    slice[12..16].copy_from_slice(&h.sequence.to_be_bytes());
    slice[16..20].copy_from_slice(&h.payload_length.to_be_bytes());
    slice[20..24].copy_from_slice(&0u32.to_be_bytes());
    true
}

#[no_mangle]
pub unsafe extern "C" fn csp_encode_heartbeat_message(
    session_id: u32,
    sequence: u32,
    ts_micros: u64,
    echo_ts_micros: u64,
    out_buf: *mut u8,
    buf_len: usize,
) -> usize {
    if out_buf.is_null() || buf_len < 40 {
        return 0;
    }
    let hb = Heartbeat {
        timestamp_micros: ts_micros,
        echo_timestamp_micros: echo_ts_micros,
    };
    let mut vec = Vec::with_capacity(40);
    if encode_message(session_id, sequence, &Payload::Heartbeat(hb), &mut vec).is_err() {
        return 0;
    }
    if vec.len() > buf_len {
        return 0;
    }
    ptr::copy_nonoverlapping(vec.as_ptr(), out_buf, vec.len());
    vec.len()
}

#[no_mangle]
pub unsafe extern "C" fn csp_decode_heartbeat_payload(
    payload: *const u8,
    len: usize,
    out_ts: *mut u64,
    out_echo_ts: *mut u64,
) -> bool {
    if payload.is_null() || len != 16 || out_ts.is_null() || out_echo_ts.is_null() {
        return false;
    }
    let slice = slice::from_raw_parts(payload, len);
    let mut ts_bytes = [0u8; 8];
    let mut echo_bytes = [0u8; 8];
    ts_bytes.copy_from_slice(&slice[0..8]);
    echo_bytes.copy_from_slice(&slice[8..16]);
    *out_ts = u64::from_be_bytes(ts_bytes);
    *out_echo_ts = u64::from_be_bytes(echo_bytes);
    true
}

#[no_mangle]
pub unsafe extern "C" fn csp_encode_video_frame_prefix(
    config_id: u32,
    frame_flags: u32,
    pts_micros: u64,
    out_buf: *mut u8,
    buf_len: usize,
) -> bool {
    if out_buf.is_null() || buf_len < 16 {
        return false;
    }
    let slice = slice::from_raw_parts_mut(out_buf, buf_len);
    slice[0..4].copy_from_slice(&config_id.to_be_bytes());
    slice[4..8].copy_from_slice(&frame_flags.to_be_bytes());
    slice[8..16].copy_from_slice(&pts_micros.to_be_bytes());
    true
}

#[no_mangle]
pub unsafe extern "C" fn csp_decode_video_frame_prefix(
    payload: *const u8,
    len: usize,
    out_config_id: *mut u32,
    out_flags: *mut u32,
    out_pts_micros: *mut u64,
    out_data_offset: *mut usize,
) -> bool {
    if payload.is_null() || len < 16 {
        return false;
    }
    let slice = slice::from_raw_parts(payload, len);
    let mut cid = [0u8; 4];
    let mut flg = [0u8; 4];
    let mut pts = [0u8; 8];
    cid.copy_from_slice(&slice[0..4]);
    flg.copy_from_slice(&slice[4..8]);
    pts.copy_from_slice(&slice[8..16]);

    if !out_config_id.is_null() {
        *out_config_id = u32::from_be_bytes(cid);
    }
    if !out_flags.is_null() {
        *out_flags = u32::from_be_bytes(flg);
    }
    if !out_pts_micros.is_null() {
        *out_pts_micros = u64::from_be_bytes(pts);
    }
    if !out_data_offset.is_null() {
        *out_data_offset = 16;
    }
    true
}

#[no_mangle]
pub unsafe extern "C" fn csp_encode_audio_frame_prefix(
    pts_micros: u64,
    out_buf: *mut u8,
    buf_len: usize,
) -> bool {
    if out_buf.is_null() || buf_len < 8 {
        return false;
    }
    let slice = slice::from_raw_parts_mut(out_buf, buf_len);
    slice[0..8].copy_from_slice(&pts_micros.to_be_bytes());
    true
}

#[no_mangle]
pub unsafe extern "C" fn csp_decode_audio_frame_prefix(
    payload: *const u8,
    len: usize,
    out_pts_micros: *mut u64,
    out_data_offset: *mut usize,
) -> bool {
    if payload.is_null() || len < 8 {
        return false;
    }
    let slice = slice::from_raw_parts(payload, len);
    let mut pts = [0u8; 8];
    pts.copy_from_slice(&slice[0..8]);
    if !out_pts_micros.is_null() {
        *out_pts_micros = u64::from_be_bytes(pts);
    }
    if !out_data_offset.is_null() {
        *out_data_offset = 8;
    }
    true
}

#[no_mangle]
pub unsafe extern "C" fn csp_encode_hello_ack_message(
    session_id: u32,
    sequence: u32,
    status: u8,
    accepted_version: u8,
    max_payload_size: u32,
    out_buf: *mut u8,
    buf_len: usize,
) -> usize {
    if out_buf.is_null() || buf_len < (HEADER_SIZE + 12) {
        return 0;
    }
    let ack = HelloAck {
        status: HelloStatus::from_u8(status).unwrap_or(HelloStatus::Rejected),
        accepted_version,
        assigned_session_id: session_id,
        max_payload_size,
    };
    let mut vec = Vec::with_capacity(HEADER_SIZE + 12);
    if encode_message(session_id, sequence, &Payload::HelloAck(ack), &mut vec).is_err() {
        return 0;
    }
    if vec.len() > buf_len {
        return 0;
    }
    ptr::copy_nonoverlapping(vec.as_ptr(), out_buf, vec.len());
    vec.len()
}

#[no_mangle]
pub unsafe extern "C" fn csp_decode_hello_payload(
    payload: *const u8,
    len: usize,
    out_min_ver: *mut u8,
    out_max_ver: *mut u8,
    out_caps: *mut u32,
    out_api_level: *mut u16,
    out_width: *mut u16,
    out_height: *mut u16,
    out_dpi: *mut u16,
    out_name: *mut c_char,
    name_buf_len: usize,
    out_model: *mut c_char,
    model_buf_len: usize,
) -> bool {
    if payload.is_null() || len < 16 {
        return false;
    }
    let slice = slice::from_raw_parts(payload, len);
    if !out_min_ver.is_null() {
        *out_min_ver = slice[0];
    }
    if !out_max_ver.is_null() {
        *out_max_ver = slice[1];
    }
    if !out_caps.is_null() {
        let mut b = [0u8; 4];
        b.copy_from_slice(&slice[4..8]);
        *out_caps = u32::from_be_bytes(b);
    }
    if !out_api_level.is_null() {
        let mut b = [0u8; 2];
        b.copy_from_slice(&slice[8..10]);
        *out_api_level = u16::from_be_bytes(b);
    }
    if !out_width.is_null() {
        let mut b = [0u8; 2];
        b.copy_from_slice(&slice[10..12]);
        *out_width = u16::from_be_bytes(b);
    }
    if !out_height.is_null() {
        let mut b = [0u8; 2];
        b.copy_from_slice(&slice[12..14]);
        *out_height = u16::from_be_bytes(b);
    }
    if !out_dpi.is_null() {
        let mut b = [0u8; 2];
        b.copy_from_slice(&slice[14..16]);
        *out_dpi = u16::from_be_bytes(b);
    }

    let mut offset = 16;
    if offset + 2 <= len {
        let name_len = u16::from_be_bytes([slice[offset], slice[offset + 1]]) as usize;
        offset += 2;
        if offset + name_len <= len && !out_name.is_null() && name_buf_len > 0 {
            let copy_len = name_len.min(name_buf_len - 1);
            ptr::copy_nonoverlapping(slice[offset..].as_ptr(), out_name as *mut u8, copy_len);
            *out_name.add(copy_len) = 0;
        }
        offset += name_len;
    }

    if offset + 2 <= len {
        let model_len = u16::from_be_bytes([slice[offset], slice[offset + 1]]) as usize;
        offset += 2;
        if offset + model_len <= len && !out_model.is_null() && model_buf_len > 0 {
            let copy_len = model_len.min(model_buf_len - 1);
            ptr::copy_nonoverlapping(slice[offset..].as_ptr(), out_model as *mut u8, copy_len);
            *out_model.add(copy_len) = 0;
        }
    }

    true
}

#[no_mangle]
pub unsafe extern "C" fn csp_decode_video_config_payload(
    payload: *const u8,
    len: usize,
    out_config_id: *mut u32,
    out_codec: *mut u8,
    out_rotation: *mut u8,
    out_width: *mut u16,
    out_height: *mut u16,
    out_fps: *mut u16,
    out_bitrate: *mut u32,
    out_csd_offset: *mut usize,
    out_csd_len: *mut usize,
) -> bool {
    if payload.is_null() || len < 24 {
        return false;
    }
    let slice = slice::from_raw_parts(payload, len);
    if !out_config_id.is_null() {
        let mut b = [0u8; 4];
        b.copy_from_slice(&slice[0..4]);
        *out_config_id = u32::from_be_bytes(b);
    }
    if !out_codec.is_null() {
        *out_codec = slice[4];
    }
    if !out_rotation.is_null() {
        *out_rotation = slice[7];
    }
    if !out_width.is_null() {
        let mut b = [0u8; 2];
        b.copy_from_slice(&slice[8..10]);
        *out_width = u16::from_be_bytes(b);
    }
    if !out_height.is_null() {
        let mut b = [0u8; 2];
        b.copy_from_slice(&slice[10..12]);
        *out_height = u16::from_be_bytes(b);
    }
    if !out_fps.is_null() {
        let mut b = [0u8; 2];
        b.copy_from_slice(&slice[12..14]);
        *out_fps = u16::from_be_bytes(b);
    }
    if !out_bitrate.is_null() {
        let mut b = [0u8; 4];
        b.copy_from_slice(&slice[16..20]);
        *out_bitrate = u32::from_be_bytes(b);
    }
    let mut b = [0u8; 4];
    b.copy_from_slice(&slice[20..24]);
    let csd_len = u32::from_be_bytes(b) as usize;
    if !out_csd_len.is_null() {
        *out_csd_len = csd_len;
    }
    if !out_csd_offset.is_null() {
        *out_csd_offset = 24;
    }

    24 + csd_len <= len
}

#[no_mangle]
pub unsafe extern "C" fn csp_decode_audio_config_payload(
    payload: *const u8,
    len: usize,
    out_codec: *mut u8,
    out_channels: *mut u8,
    out_sample_rate: *mut u32,
    out_csd_offset: *mut usize,
    out_csd_len: *mut usize,
) -> bool {
    if payload.is_null() || len < 12 {
        return false;
    }
    let slice = slice::from_raw_parts(payload, len);
    if !out_codec.is_null() {
        *out_codec = slice[0];
    }
    if !out_channels.is_null() {
        *out_channels = slice[1];
    }
    if !out_sample_rate.is_null() {
        let mut b = [0u8; 4];
        b.copy_from_slice(&slice[4..8]);
        *out_sample_rate = u32::from_be_bytes(b);
    }
    let mut b = [0u8; 4];
    b.copy_from_slice(&slice[8..12]);
    let csd_len = u32::from_be_bytes(b) as usize;
    if !out_csd_len.is_null() {
        *out_csd_len = csd_len;
    }
    if !out_csd_offset.is_null() {
        *out_csd_offset = 12;
    }

    12 + csd_len <= len
}

#[no_mangle]
pub extern "C" fn csp_decode_result_string(res: CspDecodeResult) -> *const c_char {
    let s: &'static [u8] = match res {
        CspDecodeResult::Ok => b"OK\0",
        CspDecodeResult::NeedMoreData => b"NeedMoreData\0",
        CspDecodeResult::BadMagic => b"BadMagic\0",
        CspDecodeResult::UnsupportedVersion => b"UnsupportedVersion\0",
        CspDecodeResult::UnknownType => b"UnknownType\0",
        CspDecodeResult::ReservedNotZero => b"ReservedNotZero\0",
        CspDecodeResult::PayloadTooLarge => b"PayloadTooLarge\0",
        CspDecodeResult::Truncated => b"Truncated\0",
        CspDecodeResult::TrailingBytes => b"TrailingBytes\0",
        CspDecodeResult::InvalidField => b"InvalidField\0",
        CspDecodeResult::StringTooLong => b"StringTooLong\0",
    };
    s.as_ptr() as *const c_char
}

// ----------------- AV Sync C-ABI -----------------

#[repr(C)]
#[derive(Debug, Copy, Clone)]
pub struct CspSyncDecision {
    pub action: u8, // 0 = PresentNow, 1 = Wait, 2 = DropLate
    pub wait_micros: i64,
    pub skew_micros: i64,
}

#[no_mangle]
pub extern "C" fn csp_sync_create(preset: u8) -> *mut c_void {
    let p = match preset {
        0 => SyncPreset::LowLatency,
        1 => SyncPreset::Balanced,
        2 => SyncPreset::HighQuality,
        _ => SyncPreset::Balanced,
    };
    let sync = Box::new(AvSynchronizer::new(p));
    Box::into_raw(sync) as *mut c_void
}

#[no_mangle]
pub unsafe extern "C" fn csp_sync_on_audio_rendered(
    sync_ptr: *mut c_void,
    audio_pts: u64,
    host_time: u64,
) {
    if !sync_ptr.is_null() {
        let sync = &mut *(sync_ptr as *mut AvSynchronizer);
        sync.on_audio_rendered(audio_pts, host_time);
    }
}

#[no_mangle]
pub unsafe extern "C" fn csp_sync_evaluate_video(
    sync_ptr: *mut c_void,
    video_pts: u64,
    host_time: u64,
    out_decision: *mut CspSyncDecision,
) {
    if !sync_ptr.is_null() && !out_decision.is_null() {
        let sync = &mut *(sync_ptr as *mut AvSynchronizer);
        let d = sync.evaluate_video_frame(video_pts, host_time);
        (*out_decision).action = d.action as u8;
        (*out_decision).wait_micros = d.wait_micros;
        (*out_decision).skew_micros = d.skew_micros;
    }
}

#[no_mangle]
pub unsafe extern "C" fn csp_sync_reset(sync_ptr: *mut c_void) {
    if !sync_ptr.is_null() {
        let sync = &mut *(sync_ptr as *mut AvSynchronizer);
        sync.reset();
    }
}

#[no_mangle]
pub unsafe extern "C" fn csp_sync_destroy(sync_ptr: *mut c_void) {
    if !sync_ptr.is_null() {
        drop(Box::from_raw(sync_ptr as *mut AvSynchronizer));
    }
}

// ----------------- Session Manager C-ABI -----------------

#[repr(C)]
#[derive(Debug, Copy, Clone)]
pub struct CspSessionStats {
    pub total_bytes_received: u64,
    pub video_frames_received: u32,
    pub audio_frames_received: u32,
    pub keyframes_received: u32,
    pub dropped_frames: u32,
    pub current_fps: f64,
    pub current_bitrate_mbps: f64,
    pub last_rtt_micros: u64,
    pub estimated_clock_offset_micros: i64,
}

#[no_mangle]
pub extern "C" fn csp_session_create() -> *mut c_void {
    let session = Box::new(SessionManager::new());
    Box::into_raw(session) as *mut c_void
}

#[no_mangle]
pub unsafe extern "C" fn csp_session_init_pairing(
    session_ptr: *mut c_void,
    cert_fp: *const c_char,
    pin: *const c_char,
) {
    if !session_ptr.is_null() {
        let sm = &mut *(session_ptr as *mut SessionManager);
        let fp_str = if !cert_fp.is_null() {
            CStr::from_ptr(cert_fp).to_str().unwrap_or("")
        } else {
            ""
        };
        let pin_str = if !pin.is_null() {
            Some(CStr::from_ptr(pin).to_str().unwrap_or(""))
        } else {
            None
        };
        sm.initialize_pairing(fp_str, pin_str);
    }
}

#[no_mangle]
pub unsafe extern "C" fn csp_session_get_pin(
    session_ptr: *mut c_void,
    out_buf: *mut c_char,
    max_len: usize,
) -> bool {
    if session_ptr.is_null() || out_buf.is_null() || max_len < 7 {
        return false;
    }
    let sm = &*(session_ptr as *mut SessionManager);
    let pin = sm.session_pin();
    let bytes = pin.as_bytes();
    if bytes.len() >= max_len {
        return false;
    }
    ptr::copy_nonoverlapping(bytes.as_ptr(), out_buf as *mut u8, bytes.len());
    *out_buf.add(bytes.len()) = 0;
    true
}

#[no_mangle]
pub unsafe extern "C" fn csp_session_get_stats(
    session_ptr: *mut c_void,
    out_stats: *mut CspSessionStats,
) {
    if !session_ptr.is_null() && !out_stats.is_null() {
        let sm = &*(session_ptr as *mut SessionManager);
        let s = sm.stats();
        (*out_stats).total_bytes_received = s.total_bytes_received;
        (*out_stats).video_frames_received = s.video_frames_received;
        (*out_stats).audio_frames_received = s.audio_frames_received;
        (*out_stats).keyframes_received = s.keyframes_received;
        (*out_stats).dropped_frames = s.dropped_frames;
        (*out_stats).current_fps = s.current_fps;
        (*out_stats).current_bitrate_mbps = s.current_bitrate_mbps;
        (*out_stats).last_rtt_micros = s.last_rtt_micros;
        (*out_stats).estimated_clock_offset_micros = s.estimated_clock_offset_micros;
    }
}

#[no_mangle]
pub unsafe extern "C" fn csp_session_destroy(session_ptr: *mut c_void) {
    if !session_ptr.is_null() {
        drop(Box::from_raw(session_ptr as *mut SessionManager));
    }
}

// ----------------- Android JNI Bridge -----------------

#[no_mangle]
pub extern "system" fn Java_com_castsprint_android_protocol_ProtocolCodec_nativeGetVersion(
    _env: *mut c_void,
    _class: *mut c_void,
) -> i32 {
    VERSION as i32
}

#[no_mangle]
pub extern "system" fn Java_com_castsprint_android_protocol_ProtocolCodec_nativeGetHeaderSize(
    _env: *mut c_void,
    _class: *mut c_void,
) -> i32 {
    HEADER_SIZE as i32
}

#[no_mangle]
pub unsafe extern "system" fn Java_com_castsprint_android_protocol_ProtocolCodec_nativeEncodeHeartbeat(
    _env: *mut c_void,
    _class: *mut c_void,
    session_id: i32,
    sequence: i32,
    ts_micros: i64,
    echo_ts_micros: i64,
    out_buf: *mut u8,
    buf_len: usize,
) -> i32 {
    csp_encode_heartbeat_message(
        session_id as u32,
        sequence as u32,
        ts_micros as u64,
        echo_ts_micros as u64,
        out_buf,
        buf_len,
    ) as i32
}
