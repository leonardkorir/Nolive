use std::collections::{HashMap, VecDeque};
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

pub struct DanmakuMask {
    window_ms: u64,
    burst_limit: usize,
    buckets: HashMap<String, VecDeque<u64>>,
}

impl DanmakuMask {
    fn new(window_ms: u64, burst_limit: usize) -> Self {
        Self {
            window_ms,
            burst_limit: burst_limit.max(1),
            buckets: HashMap::new(),
        }
    }

    fn evict(&mut self, threshold: u64) {
        self.buckets.retain(|_, queue| {
            while matches!(queue.front(), Some(value) if *value < threshold) {
                queue.pop_front();
            }
            !queue.is_empty()
        });
    }

    fn allow(&mut self, value: &str, now_ms: u64) -> bool {
        let key = normalize(value);
        if key.is_empty() {
          return true;
        }
        let threshold = now_ms.saturating_sub(self.window_ms);
        let queue = self.buckets.entry(key).or_default();
        while matches!(queue.front(), Some(ts) if *ts < threshold) {
            queue.pop_front();
        }
        if queue.len() >= self.burst_limit {
            return false;
        }
        queue.push_back(now_ms);
        true
    }
}

fn normalize(raw: &str) -> String {
    raw.chars()
        .filter(|ch| !ch.is_whitespace())
        .flat_map(|ch| ch.to_lowercase())
        .collect()
}

#[no_mangle]
pub extern "C" fn nolive_danmaku_mask_create(
    window_ms: u64,
    burst_limit: u32,
) -> *mut DanmakuMask {
    Box::into_raw(Box::new(DanmakuMask::new(window_ms, burst_limit as usize)))
}

#[no_mangle]
pub unsafe extern "C" fn nolive_danmaku_mask_filter(
    mask: *mut DanmakuMask,
    now_ms: u64,
    payload: *const c_char,
) -> *mut c_char {
    if mask.is_null() || payload.is_null() {
        return std::ptr::null_mut();
    }

    let mask = &mut *mask;
    let payload = match CStr::from_ptr(payload).to_str() {
        Ok(value) => value,
        Err(_) => return std::ptr::null_mut(),
    };
    let items = match serde_json::from_str::<Vec<Option<String>>>(payload) {
        Ok(value) => value,
        Err(_) => return std::ptr::null_mut(),
    };

    mask.evict(now_ms.saturating_sub(mask.window_ms));

    let allow_list: Vec<bool> = items
        .into_iter()
        .map(|value| match value {
            Some(text) => mask.allow(&text, now_ms),
            None => true,
        })
        .collect();

    let encoded = match serde_json::to_string(&allow_list) {
        Ok(value) => value,
        Err(_) => return std::ptr::null_mut(),
    };
    match CString::new(encoded) {
        Ok(value) => value.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn nolive_danmaku_mask_free_string(value: *mut c_char) {
    if value.is_null() {
        return;
    }
    let _ = CString::from_raw(value);
}

#[no_mangle]
pub unsafe extern "C" fn nolive_danmaku_mask_destroy(mask: *mut DanmakuMask) {
    if mask.is_null() {
        return;
    }
    let _ = Box::from_raw(mask);
}
