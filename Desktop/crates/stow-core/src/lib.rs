//! Portable domain rules. No desktop, persistence, or synchronization access.
//! DTO timestamps use RFC 3339 UTC strings; bytes use arrays; absent values use null.
//! These DTOs are not the Swift Codable or C ABI wire format.
mod capture;
mod fingerprint;
mod item;
mod representation;

pub use capture::*;
pub use fingerprint::*;
pub use item::*;
pub use representation::*;
