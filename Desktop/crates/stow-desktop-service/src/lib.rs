//! UI-independent, single-writer desktop service. Call synchronous methods,
//! including shutdown, from a blocking task, never from the UI event loop.
mod dto;
pub use dto::*;

use std::{
    sync::{Arc, Condvar, Mutex, mpsc},
    thread::{self, JoinHandle},
};
use stow_core::{
    Repository, SERVICE_FIELD_LIMIT, SERVICE_TEXT_LIMIT, bounded_string as bounded,
    optional_string as optional, revision_timestamp, service_error as error,
};
use uuid::Uuid;

const QUEUE_CAPACITY: usize = 32;
const TEXT_LIMIT: usize = SERVICE_TEXT_LIMIT;
const FIELD_LIMIT: usize = SERVICE_FIELD_LIMIT;
type Job = Box<dyn FnOnce(&mut State) + Send>;
struct State {
    repository: Result<Box<dyn Repository>>,
}
struct WorkerControl {
    sender: Option<mpsc::SyncSender<Job>>,
    join: Option<JoinHandle<()>>,
    thread_id: Option<thread::ThreadId>,
    joining: bool,
    completion: Option<Result<()>>,
}
struct Worker {
    control: Mutex<WorkerControl>,
    completed: Condvar,
}
impl Drop for Worker {
    fn drop(&mut self) {
        let control = self
            .control
            .get_mut()
            .unwrap_or_else(|error| error.into_inner());
        // Disconnect and detach only. A native backend may need the main actor
        // to finish its accepted operations or destructor.
        control.sender.take();
        control.join.take();
    }
}
#[derive(Clone)]
pub struct DesktopService {
    worker: Arc<Worker>,
}
impl DesktopService {
    /// The host selects the backend once. The worker creates and owns it.
    /// Open failures remain available through status without a fallback store.
    pub fn start(factory: impl FnOnce() -> Result<Box<dyn Repository>> + Send + 'static) -> Self {
        let (sender, receiver) = mpsc::sync_channel::<Job>(QUEUE_CAPACITY);
        let join = thread::Builder::new()
            .name("stow-storage".into())
            .spawn(move || {
                let mut state = State {
                    repository: factory(),
                };
                while let Ok(job) = receiver.recv() {
                    job(&mut state);
                }
            })
            .ok();
        Self {
            worker: Arc::new(Worker {
                control: Mutex::new(WorkerControl {
                    sender: join.as_ref().map(|_| sender),
                    thread_id: join.as_ref().map(|join| join.thread().id()),
                    join,
                    joining: false,
                    completion: None,
                }),
                completed: Condvar::new(),
            }),
        }
    }

    /// Stop admissions across all clones, drain accepted work, and join.
    /// Call from a background thread other than this service's worker while
    /// the native event loop runs. Self-join requests are rejected.
    /// Concurrent callers all wait for the same completion, including panics.
    pub fn shutdown(&self) -> Result<()> {
        let mut control = self
            .worker
            .control
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if control.thread_id == Some(thread::current().id()) {
            return Err(error(
                "invalid_argument",
                "The storage worker cannot join itself.",
            ));
        }
        control.sender.take();
        loop {
            if let Some(result) = &control.completion {
                return result.clone();
            }
            if !control.joining {
                control.joining = true;
                break;
            }
            control = self
                .worker
                .completed
                .wait(control)
                .unwrap_or_else(|error| error.into_inner());
        }
        let join = control.join.take();
        drop(control);
        let result = match join {
            Some(join) => join
                .join()
                .map_err(|_| error("disconnected", "The storage worker panicked.")),
            None => Err(disconnected()),
        };
        let mut control = self
            .worker
            .control
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        control.completion = Some(result.clone());
        self.worker.completed.notify_all();
        result
    }

    fn enqueue(&self, job: Job) -> Result<()> {
        // Hold this lock through try_send. Shutdown cannot race an admission
        // through a temporary sender clone.
        self.worker
            .control
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .sender
            .as_ref()
            .ok_or_else(disconnected)?
            .try_send(job)
            .map_err(|failure| match failure {
                mpsc::TrySendError::Full(_) => error("busy", "The storage request queue is full."),
                mpsc::TrySendError::Disconnected(_) => disconnected(),
            })
    }

    fn request<T: Send + 'static>(
        &self,
        operation: impl FnOnce(&mut State) -> Result<T> + Send + 'static,
    ) -> Result<T> {
        let (sender, receiver) = mpsc::channel();
        self.enqueue(Box::new(move |state| {
            let _ = sender.send(operation(state));
        }))?;
        // No ambiguous mutation timeout: complete, or drop the response sender
        // on panic/disconnect. Response delivery never blocks the worker.
        receiver.recv().map_err(|_| disconnected())?
    }

    pub fn status(&self) -> Result<ServiceStatus> {
        self.request(|state| {
            let available = state.repository.is_ok();
            Ok(ServiceStatus {
                storage_available: available,
                message: match &state.repository {
                    Ok(_) => "Library is stored only on this device.".into(),
                    Err(error) => error.message.clone(),
                },
                platform: std::env::consts::OS.into(),
                capabilities: Capabilities {
                    local_storage: available,
                    ..Default::default()
                },
            })
        })
    }
    pub fn search(&self, mut request: SearchRequest) -> Result<Vec<ItemSummary>> {
        bounded(&request.text, 4096)?;
        optional(&request.source_app, FIELD_LIMIT)?;
        request.limit = Some(request.limit.unwrap_or(200).clamp(1, 500));
        self.request(move |state| repository(state)?.search(request))
    }
    pub fn get(&self, id: Uuid) -> Result<ItemDetail> {
        self.request(move |state| repository(state)?.get(id))
    }
    pub fn create(&self, request: CreateRequest) -> Result<ItemDetail> {
        // Reject unsupported types and invalid portable content before dispatch.
        // Backends retain their own normalization and atomic replay handling.
        request.validate_type()?;
        bounded(&request.title, FIELD_LIMIT)?;
        optional(&request.text_content, TEXT_LIMIT)?;
        optional(&request.url_string, FIELD_LIMIT)?;
        optional(&request.note, TEXT_LIMIT)?;
        optional(&request.source_app, FIELD_LIMIT)?;
        optional(&request.language, FIELD_LIMIT)?;
        request.normalized_draft()?;
        self.request(move |state| repository(state)?.create(request))
    }
    pub fn update(&self, mut request: UpdateRequest) -> Result<ItemDetail> {
        bounded(&request.edit.title, FIELD_LIMIT)?;
        optional(&request.edit.text_content, TEXT_LIMIT)?;
        optional(&request.edit.note, TEXT_LIMIT)?;
        optional(&request.edit.language, FIELD_LIMIT)?;
        request.expected_updated_at = canonical_revision(&request.expected_updated_at)?;
        self.request(move |state| repository(state)?.update(request))
    }
    pub fn apply(&self, mut request: ApplyRequest) -> Result<ItemDetail> {
        request.expected_updated_at = canonical_revision(&request.expected_updated_at)?;
        self.request(move |state| repository(state)?.apply(request))
    }
    pub fn rebuild(&self) -> Result<()> {
        self.request(|state| repository(state)?.rebuild())
    }
}
fn canonical_revision(value: &str) -> Result<String> {
    Ok(revision_timestamp(value)?.to_rfc3339_opts(chrono::SecondsFormat::Nanos, true))
}
fn disconnected() -> ServiceError {
    error("disconnected", "The storage worker is unavailable.")
}
fn repository(state: &mut State) -> Result<&mut (dyn Repository + 'static)> {
    match &mut state.repository {
        Ok(repository) => Ok(repository.as_mut()),
        Err(error) => Err(error.clone()),
    }
}

#[cfg(test)]
mod memory_tests;
#[cfg(test)]
mod tests;
