use std::fmt::Write as _;
use std::sync::OnceLock;
use std::sync::RwLock;
use std::time::{SystemTime, UNIX_EPOCH};

use crate::frb_generated::StreamSink;

use tracing::field::{Field, Visit};
use tracing::{Event, Level, Subscriber};
use tracing_subscriber::Layer;
use tracing_subscriber::layer::Context;
use tracing_subscriber::prelude::*;

/// A single tracing event forwarded from Rust to Dart.
pub struct LogEntry {
    /// Milliseconds since the Unix epoch.
    pub time_millis: i64,
    /// Log level: 0=Trace, 1=Debug, 2=Info, 3=Warn, 4=Error.
    pub level: i32,
    /// Event source (typically the module path).
    pub target: String,
    /// Rendered message (the `message` field plus any additional fields).
    pub message: String,
}

fn level_to_i32(level: &Level) -> i32 {
    match *level {
        Level::TRACE => 0,
        Level::DEBUG => 1,
        Level::INFO => 2,
        Level::WARN => 3,
        Level::ERROR => 4,
    }
}

// Globally unique log sink that delivers log entries to the Dart side.
// Initialized once when Dart calls `create_log_stream`.
static LOG_SINK: OnceLock<RwLock<Option<StreamSink<LogEntry>>>> = OnceLock::new();

fn sink_cell() -> &'static RwLock<Option<StreamSink<LogEntry>>> {
    LOG_SINK.get_or_init(|| RwLock::new(None))
}

// Collects the `message` field and additional fields into a single string.
struct MessageVisitor {
    message: String,
}

impl Visit for MessageVisitor {
    fn record_str(&mut self, field: &Field, value: &str) {
        if field.name() == "message" {
            if self.message.is_empty() {
                self.message = value.to_owned();
            } else {
                self.message = format!("{value} {}", self.message);
            }
        } else {
            let _ = write!(self.message, " {}={value}", field.name());
        }
    }

    fn record_debug(&mut self, field: &Field, value: &dyn std::fmt::Debug) {
        if field.name() == "message" {
            let rendered = format!("{value:?}");
            if self.message.is_empty() {
                self.message = rendered;
            } else {
                self.message = format!("{rendered} {}", self.message);
            }
        } else {
            let _ = write!(self.message, " {}={value:?}", field.name());
        }
    }
}

struct DartSinkLayer;

impl<S: Subscriber> Layer<S> for DartSinkLayer {
    fn on_event(&self, event: &Event<'_>, _ctx: Context<'_, S>) {
        let guard = match sink_cell().read() {
            Ok(g) => g,
            Err(_) => return,
        };
        let Some(sink) = guard.as_ref() else {
            return;
        };

        let mut visitor = MessageVisitor {
            message: String::new(),
        };
        event.record(&mut visitor);

        let meta = event.metadata();
        let entry = LogEntry {
            time_millis: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|d| d.as_millis() as i64)
                .unwrap_or(0),
            level: level_to_i32(meta.level()),
            target: meta.target().to_string(),
            message: visitor.message,
        };

        // Ignore send errors (e.g. the Dart side has closed the stream).
        let _ = sink.add(entry);
    }
}

static INIT: OnceLock<()> = OnceLock::new();

/// Opens a stream from Rust `tracing` events to Dart.
///
/// The tracing subscriber is installed on the first call; subsequent calls only replace the active sink.
/// The subscriber captures all levels (TRACE..ERROR); level filtering is done on the Dart side
/// so users can adjust it in real time.
pub fn create_log_stream(sink: StreamSink<LogEntry>) {
    {
        let mut guard = sink_cell().write().expect("log sink lock poisoned");
        *guard = Some(sink);
    }

    INIT.get_or_init(|| {
        // Capture all levels; the Dart side handles display filtering.
        let subscriber = tracing_subscriber::registry().with(DartSinkLayer);
        // If a global subscriber already exists, `set_global_default` will fail; this is expected.
        let _ = tracing::subscriber::set_global_default(subscriber);
    });

    tracing::info!("https://github.com/mcitem/lnuElytra");
}
