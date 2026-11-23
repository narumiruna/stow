//! Owned client for the preview-only Swift bridge. Calls must run off the main thread.
use std::{ffi::c_void, marker::PhantomData, path::Path, rc::Rc, sync::mpsc};

use serde::{Serialize, de::DeserializeOwned};
use serde_json::{Value, json};
use stow_core::Repository;
use stow_desktop_service::{
    ApplyRequest, CreateRequest, ItemDetail, ItemSummary, SearchRequest, ServiceError,
    UpdateRequest,
};
use uuid::Uuid;

type Result<T> = std::result::Result<T, ServiceError>;
const MAX_REQUEST: usize = 16 * 1024 * 1024;
const MAX_RESPONSE: usize = 64 * 1024 * 1024;
const PREVIEW_ID: &str = "dev.narumi.stow.desktop-preview";
type Completion = unsafe extern "C" fn(*mut c_void, *mut u8, isize);
type ResponseSender = mpsc::Sender<Result<Vec<u8>>>;

unsafe extern "C" {
    fn stow_bridge_abi_version() -> u32;
    fn stow_bridge_submit(
        handle: u64,
        bytes: *const u8,
        length: isize,
        context: *mut c_void,
        completion: Completion,
    );
    fn stow_bridge_free(bytes: *mut u8, length: isize);
    fn pthread_main_np() -> i32;
}

fn failure(code: &str, message: &str) -> ServiceError {
    ServiceError {
        code: code.into(),
        message: message.into(),
        retryable: matches!(code, "storage" | "busy"),
    }
}

// The bridge calls this once, after copying the request. The callback takes the
// context back, copies the owned response, and releases it through its allocator.
// It never unwinds across the C ABI or includes response contents in diagnostics.
unsafe extern "C" fn complete(context: *mut c_void, bytes: *mut u8, length: isize) {
    // SAFETY: submit passes exactly one Box<ResponseSender> to one completion.
    let sender = unsafe { Box::from_raw(context.cast::<ResponseSender>()) };
    let response =
        if length < 0 || length as usize > MAX_RESPONSE || (bytes.is_null() && length != 0) {
            Err(failure("storage", "The bridge response is invalid."))
        } else if length == 0 {
            Ok(Vec::new())
        } else {
            // SAFETY: the bridge owns a live allocation of length bytes until free.
            Ok(unsafe { std::slice::from_raw_parts(bytes, length as usize) }.to_vec())
        };
    // SAFETY: response bytes are released once, even if the receiver disconnected.
    unsafe { stow_bridge_free(bytes, length) };
    let _ = sender.send(response);
}

fn request<T: DeserializeOwned>(handle: u64, command: &str, payload: Value) -> Result<T> {
    // SAFETY: this system function has no arguments or ownership requirements.
    if unsafe { pthread_main_np() } != 0 {
        return Err(failure(
            "unavailable",
            "Bridge requests must run on the storage worker.",
        ));
    }
    let bytes = serde_json::to_vec(&json!({
        "version": 1, "command": command, "payload": payload,
    }))
    .map_err(|_| failure("invalid_argument", "The bridge request is invalid."))?;
    if bytes.len() > MAX_REQUEST {
        return Err(failure(
            "invalid_argument",
            "The bridge request is too large.",
        ));
    }
    let (sender, receiver) = mpsc::channel::<Result<Vec<u8>>>();
    let context = Box::into_raw(Box::new(sender));
    // SAFETY: input remains live until submit copies it. The context belongs to
    // complete after submission. Swift guarantees exactly one completion.
    unsafe {
        stow_bridge_submit(
            handle,
            bytes.as_ptr(),
            bytes.len() as isize,
            context.cast(),
            complete,
        );
    }
    // Accepted mutations have no timeout or automatic retry. The main run loop
    // stays active while the host drains and shuts down the storage worker.
    let bytes = receiver
        .recv()
        .map_err(|_| failure("disconnected", "The bridge disconnected."))??;
    let value: Value = serde_json::from_slice(&bytes)
        .map_err(|_| failure("storage", "The bridge response is invalid."))?;
    let object = value
        .as_object()
        .filter(|object| object.len() == 1)
        .ok_or_else(|| failure("storage", "The bridge response is invalid."))?;
    if let Some(error) = object.get("error") {
        return Err(serde_json::from_value(error.clone())
            .unwrap_or_else(|_| failure("storage", "The bridge error is invalid.")));
    }
    serde_json::from_value(
        object
            .get("ok")
            .cloned()
            .ok_or_else(|| failure("storage", "The bridge response is invalid."))?,
    )
    .map_err(|_| failure("storage", "The bridge response is invalid."))
}

/// One worker-owned Swift owner. It is deliberately neither Send nor Sync.
/// The numeric handle is not an object pointer and never crosses the web IPC.
pub struct MacRepository {
    handle: u64,
    _worker_owned: PhantomData<Rc<()>>,
}

impl MacRepository {
    pub fn open(root: &Path) -> Result<Self> {
        if !root.is_absolute() || root.file_name().is_none_or(|name| name != PREVIEW_ID) {
            return Err(failure(
                "unavailable",
                "The preview library path is invalid.",
            ));
        }
        // SAFETY: version inspection has no ownership or actor requirements.
        if unsafe { stow_bridge_abi_version() } != 1 {
            return Err(failure("unavailable", "The bridge version is unsupported."));
        }
        let root = root
            .to_str()
            .ok_or_else(|| failure("unavailable", "The preview library path is invalid."))?;
        let response: Value = request(0, "open", json!({"root": root}))?;
        let handle = response
            .get("handle")
            .and_then(Value::as_u64)
            .filter(|handle| *handle != 0)
            .ok_or_else(|| failure("storage", "The bridge handle is invalid."))?;
        Ok(Self {
            handle,
            _worker_owned: PhantomData,
        })
    }

    fn call<T: DeserializeOwned>(&self, command: &str, payload: impl Serialize) -> Result<T> {
        let payload = serde_json::to_value(payload)
            .map_err(|_| failure("invalid_argument", "The bridge request is invalid."))?;
        request(self.handle, command, payload)
    }
}

impl Drop for MacRepository {
    fn drop(&mut self) {
        // Runs on the storage worker after accepted operations drain. Host exit
        // waits off the main thread, so Swift can finish this close callback.
        let _: Result<()> = request(self.handle, "close", json!({}));
    }
}

impl Repository for MacRepository {
    fn search(&mut self, request: SearchRequest) -> Result<Vec<ItemSummary>> {
        let after = request
            .added_after
            .map(|date| date.to_rfc3339_opts(chrono::SecondsFormat::Nanos, true));
        let before = request
            .added_before
            .map(|date| date.to_rfc3339_opts(chrono::SecondsFormat::Nanos, true));
        let mut payload = serde_json::to_value(request)
            .map_err(|_| failure("invalid_argument", "The bridge request is invalid."))?;
        payload["added_after"] = json!(after);
        payload["added_before"] = json!(before);
        self.call("search", payload)
    }

    fn get(&mut self, id: Uuid) -> Result<ItemDetail> {
        self.call("get", json!({"id": id}))
    }

    fn create(&mut self, mut request: CreateRequest) -> Result<ItemDetail> {
        // Apply portable defaults before native validation. Foundation preserves
        // host case, whereas the Rust URL parser generates a lowercase title.
        let draft = request.normalized_draft()?;
        request.title = draft.title;
        request.text_content = draft.text_content;
        request.url_string = draft.url_string;
        request.note = draft.note;
        request.source_app = draft.source_app;
        request.language = draft.language;
        self.call("create", request)
    }

    fn update(&mut self, mut request: UpdateRequest) -> Result<ItemDetail> {
        request.expected_updated_at = stow_core::revision_timestamp(&request.expected_updated_at)?
            .to_rfc3339_opts(chrono::SecondsFormat::Nanos, true);
        self.call("update", request)
    }

    fn apply(&mut self, mut request: ApplyRequest) -> Result<ItemDetail> {
        request.expected_updated_at = stow_core::revision_timestamp(&request.expected_updated_at)?
            .to_rfc3339_opts(chrono::SecondsFormat::Nanos, true);
        self.call("apply", request)
    }

    fn rebuild(&mut self) -> Result<()> {
        self.call("rebuild", json!({}))
    }
}
