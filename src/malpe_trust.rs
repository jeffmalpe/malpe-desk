//! MALPE Desk "conexão direta": computers the user chose to let in without
//! clicking "Accept" every time.
//!
//! A computer is trusted by its ID together with its hardware id (the SHA-256
//! of the machine UUID that the MALPE client sends in the login request), so
//! knowing the public ID alone is not enough to get in.
//!
//! Stored in the service config option `malpe-trusted-peers` as a JSON array of
//! `{"id", "name", "hwid"}`. The Flutter UI lists and removes entries through
//! the normal option IPC.

use hbb_common::{config::Config, log};
use serde_json::{json, Value};

pub const OPTION_KEY: &str = "malpe-trusted-peers";
const MAX_ENTRIES: usize = 200;

fn to_hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{:02x}", b)).collect()
}

fn load() -> Vec<Value> {
    serde_json::from_str::<Vec<Value>>(&Config::get_option(OPTION_KEY)).unwrap_or_default()
}

pub fn is_trusted(id: &str, hwid: &[u8]) -> bool {
    if id.is_empty() || hwid.is_empty() {
        return false;
    }
    let hwid = to_hex(hwid);
    load().iter().any(|e| {
        e.get("id").and_then(|v| v.as_str()) == Some(id)
            && e.get("hwid").and_then(|v| v.as_str()) == Some(hwid.as_str())
    })
}

/// Returns false when the peer cannot be trusted (old or non-MALPE client
/// without a hardware id).
pub fn add(id: &str, name: &str, hwid: &[u8]) -> bool {
    if id.is_empty() || hwid.is_empty() {
        log::warn!("malpe-trust: peer {} sent no hwid, not trusted", id);
        return false;
    }
    let hwid_hex = to_hex(hwid);
    let mut list: Vec<Value> = load()
        .into_iter()
        .filter(|e| e.get("id").and_then(|v| v.as_str()) != Some(id))
        .collect();
    list.push(json!({
        "id": id,
        "name": name,
        "hwid": hwid_hex,
        "added": hbb_common::get_time(),
    }));
    if list.len() > MAX_ENTRIES {
        let extra = list.len() - MAX_ENTRIES;
        list.drain(0..extra);
    }
    Config::set_option(
        OPTION_KEY.to_owned(),
        serde_json::to_string(&list).unwrap_or_default(),
    );
    log::info!("malpe-trust: peer {} is now trusted", id);
    true
}
