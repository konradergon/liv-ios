//! Files, by reference — and the separation `core/` does not make.
//!
//! **A path is where; a hash is what.** `core/`'s `FileRef` carries both
//! in one value, in the log. `core.md` §14 records that as a model bug and
//! `op-format.md` §6 repeats it: a device-local path does not survive a
//! device boundary, so a file synced from a laptop arrives on a phone
//! carrying a path that resolves to nothing and looks perfectly valid.
//!
//! So they are two things here. The hash is a `Value::Blob` cell and
//! travels with everything else; the path is a row in a device-local
//! table that is not in the log, not in the digest, and not rebuilt by
//! replay — because nothing in the log could rebuild it. A file that
//! arrived by sync has a hash and no path on this device, and `path_of`
//! saying `None` is the honest answer to "where is it".
//!
//! **Nothing here copies or moves a file.** It is read to hash it and
//! otherwise left where it was put (`feature-map`: the librarian, not the
//! warehouse). The phone puts what it is handed in the box's own folder,
//! `files/<uuid>/<name>`, because iOS hands an app a copy, not a place —
//! and a path inside that folder is remembered RELATIVE to it, because
//! reinstalling the app moves the folder and every whole path with it.
//!
//! **A file that holds text is opened as a note** (owner, 2026-10-01).
//! `text_of` decides what holds text; `file_into_note` (`content.rs`)
//! makes the change, and the file itself is never written.

use sha2::{Digest, Sha256};
use std::io::Read;
use std::path::{Component, Path};

use crate::engine::Engine;
use crate::id::EntityId;
use crate::log::LogError;
use crate::model::{kind, prop};
use crate::op::{Author, Op, Value};
use crate::write::action;

/// What re-hashing a file's path found.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Resync {
    /// The bytes are unchanged; the stored hash still holds.
    Unchanged,
    /// The bytes changed, and the cell now carries the new hash. **This is
    /// the whole integration** — it is how Liv learns Word saved a file.
    Changed([u8; 32]),
    /// The path no longer resolves, this device never had one, or the
    /// thing is not a file. A broken reference, which is not a change.
    Broken,
}

#[derive(Debug)]
pub enum FileError {
    /// The path could not be read. An unreadable file is an error, never a
    /// phantom entity with a hash of nothing.
    Unreadable(std::io::Error),
    Log(LogError),
}

impl std::fmt::Display for FileError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            FileError::Unreadable(e) => write!(f, "cannot read that file: {e}"),
            FileError::Log(e) => write!(f, "{e}"),
        }
    }
}

impl std::error::Error for FileError {}

impl From<LogError> for FileError {
    fn from(e: LogError) -> FileError {
        FileError::Log(e)
    }
}

impl From<crate::write::WriteError> for FileError {
    fn from(e: crate::write::WriteError) -> FileError {
        match e {
            crate::write::WriteError::Log(l) => FileError::Log(l),
            other => FileError::Log(LogError::Sqlite(other.to_string())),
        }
    }
}

/// SHA-256 over the bytes, streamed.
///
/// **Vetted, not hand-rolled**, and that is a decision this tree already
/// recorded once — `services/Cargo.toml` says so beside its own `sha2`:
/// *"A changed hash is the whole integration, so the digest must be
/// vetted, not hand-rolled."* It is the reason this crate has a second
/// dependency at all.
///
/// Streamed rather than read whole: a large PDF should not become a
/// large allocation.
pub fn hash_file(path: &str) -> std::io::Result<[u8; 32]> {
    let mut file = std::fs::File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buf = [0u8; 64 * 1024];
    loop {
        let read = file.read(&mut buf)?;
        if read == 0 {
            break;
        }
        hasher.update(&buf[..read]);
    }
    Ok(hasher.finalize().into())
}

/// The most a file may hold and still be opened as a note: half a
/// megabyte, a long book's worth of words. Anything larger is not
/// something a person edits on a phone.
pub const TEXT_CAP: u64 = 512 * 1024;

/// The words in a file, if it holds words — `None` when it does not.
///
/// **The one judge of "this file is text"** (owner, 2026-10-01: a file is
/// opened if it contains text, which is edited as a note). Text is UTF-8
/// with no NUL in it, at most `TEXT_CAP` bytes. No encoding is guessed:
/// a guess would put mangled words in someone's note, and refusing leaves
/// the file to the app that made it.
///
/// Read at most one byte past the cap, so a file that grows while it is
/// read is still turned down rather than read whole. A leading byte
/// order mark is dropped and every line ending becomes `\n` — those are
/// how the bytes were saved, not words.
pub fn text_of(path: &str) -> std::io::Result<Option<String>> {
    let file = std::fs::File::open(path)?;
    let ext = extension(path);
    if NOT_NOTES.contains(&ext.as_str()) || file.metadata()?.len() > TEXT_CAP {
        return Ok(None);
    }
    let mut bytes = Vec::new();
    file.take(TEXT_CAP + 1).read_to_end(&mut bytes)?;
    if bytes.len() as u64 > TEXT_CAP {
        return Ok(None);
    }
    let bytes = bytes.strip_prefix(b"\xEF\xBB\xBF").unwrap_or(&bytes);
    if bytes.contains(&0) {
        return Ok(None);
    }
    // An empty file is a note only when its name says plain words: an
    // empty .docx is a document nobody has written yet.
    if bytes.is_empty() && !PLAIN.contains(&ext.as_str()) {
        return Ok(None);
    }
    let Ok(text) = std::str::from_utf8(bytes) else { return Ok(None) };
    Ok(Some(text.replace("\r\n", "\n").replace('\r', "\n")))
}

/// WORDS IN ANOTHER APP'S MARKUP are not a note, though they are UTF-8: an
/// RTF letter, a spreadsheet's CSV, a drawing's SVG, a web page. As notes
/// they arrived as raw markup, and the file itself was gone (review,
/// 2026-10-02). They stay files, and open in the app they belong to.
const NOT_NOTES: &[&str] = &[
    "rtf", "csv", "tsv", "svg", "html", "htm", "xhtml", "xml", "ics", "vcf", "eml", "pdf",
    "ps", "eps",
];

/// The names that say a file holds plain words.
const PLAIN: &[&str] = &["", "txt", "text", "md", "markdown"];

/// A file's extension, lowercased; "" when it has none.
fn extension(path: &str) -> String {
    Path::new(path).extension().and_then(|e| e.to_str()).unwrap_or("").to_lowercase()
}

/// What a note made from a file is called: its name without the last
/// extension. `.bashrc` is all name; a name with nothing else is kept.
/// A whole path works too — only its last part counts.
///
/// An extension is short, has no spaces and has a letter in it: "Version
/// 2.0 notes", "Dr. Who quotes" and "Release 2.0" are names with a dot in
/// them, not names with an extension (review, 2026-10-02).
pub fn note_name(file_name: &str) -> String {
    let last = Path::new(file_name).file_name().and_then(|s| s.to_str()).unwrap_or(file_name);
    match last.rsplit_once('.') {
        Some((stem, ext))
            if !stem.is_empty()
                && !ext.is_empty()
                && ext.len() <= 8
                && ext.chars().all(|c| c.is_ascii_alphanumeric())
                && ext.chars().any(|c| c.is_ascii_alphabetic()) =>
        {
            stem.to_owned()
        }
        _ => last.to_owned(),
    }
}

impl Engine {
    /// Take a file into the box, by reference.
    ///
    /// One action: the entity, its kind, the filename as its name, the
    /// hash, and the format. The path is remembered separately, on this
    /// device only — relative to the box's folder when the file is in it.
    pub fn add_file(&mut self, path: &str, now_ms: u64) -> Result<EntityId, FileError> {
        let hash = hash_file(path).map_err(FileError::Unreadable)?;
        let p = std::path::Path::new(path);
        let filename = p.file_name().and_then(|s| s.to_str()).unwrap_or(path).to_owned();
        // Lowercased: a format is a kind of thing, and `.PDF` and `.pdf`
        // are the same kind of thing.
        let format = p
            .extension()
            .and_then(|s| s.to_str())
            .map(str::to_lowercase)
            .filter(|s| !s.is_empty());

        let id = self.mint(now_ms);
        let mut ops = vec![
            Op::CreateEntity { entity: id },
            Op::SetCell { entity: id, prop: prop::KIND, value: Value::Ref(kind::FILE), replaces: vec![] },
            Op::SetCell { entity: id, prop: prop::NAME, value: Value::Text(filename), replaces: vec![] },
            Op::SetCell { entity: id, prop: prop::FILE, value: Value::Blob(hash), replaces: vec![] },
        ];
        if let Some(format) = format {
            // No cell at all when there is no extension. An empty format
            // is a claim about the file, and we have none to make.
            ops.push(Op::SetCell {
                entity: id,
                prop: prop::FORMAT,
                value: Value::Text(format),
                replaces: vec![],
            });
        }
        self.commit(ops, action::CREATE, Author::User, now_ms)?;
        self.remember_path(id, path)?;
        Ok(id)
    }

    /// Re-hash what this file points at on THIS device.
    ///
    /// A changed hash is replaced in one action, so the change is one undo
    /// step. Called when a file is opened, never on a timer.
    pub fn resync_file(&mut self, id: EntityId, now_ms: u64) -> Result<Resync, LogError> {
        let Some(Value::Blob(stored)) = self.one(id, prop::FILE)? else {
            return Ok(Resync::Broken);
        };
        let Some(path) = self.path_of(id)? else {
            // A file that arrived by sync. Not broken in the sense of
            // "gone" — this device simply has no copy — but there is
            // nothing here to re-hash, and both answers are the same to a
            // caller deciding whether to refresh.
            return Ok(Resync::Broken);
        };
        let Ok(fresh) = hash_file(&path) else {
            return Ok(Resync::Broken);
        };
        if fresh == stored {
            return Ok(Resync::Unchanged);
        }
        let replaces = self.cell(id, prop::FILE)?.into_iter().map(|(d, _)| d).collect();
        self.commit(
            vec![Op::SetCell {
                entity: id,
                prop: prop::FILE,
                value: Value::Blob(fresh),
                replaces,
            }],
            action::SET,
            Author::User,
            now_ms,
        )?;
        // The same file, in the same place, holding different bytes.
        self.remember_path(id, &path)?;
        Ok(Resync::Changed(fresh))
    }

    /// Where this device keeps that file, if it keeps it at all — always
    /// a whole path when the box is on disk.
    ///
    /// **The one reader of `places`.** A relative row is joined to the
    /// box's folder as it is NOW, which is how a moved box or a
    /// reinstalled app still finds its files. A whole row — anything
    /// outside the box's folder, and every row written before places went
    /// relative — is handed back as written.
    pub fn path_of(&self, id: EntityId) -> Result<Option<String>, LogError> {
        let Some(Value::Blob(hash)) = self.one(id, prop::FILE)? else {
            return Ok(None);
        };
        let Some(stored) = crate::view::path_of(self.conn(), &hash)? else {
            return Ok(None);
        };
        Ok(Some(match self.home() {
            Some(home) if Path::new(&stored).is_relative() => {
                home.join(&stored).to_string_lossy().into_owned()
            }
            _ => stored,
        }))
    }

    /// Say where a file is on this device — what `add_file` does, and what
    /// a shell does after finding a synced file the user has pointed it at.
    ///
    /// Keyed by the HASH, not the entity: two entities holding the same
    /// bytes are the same file, and the path answers "what", not "which".
    pub fn remember_path(&self, id: EntityId, path: &str) -> Result<(), LogError> {
        let Some(Value::Blob(hash)) = self.one(id, prop::FILE)? else {
            return Ok(());
        };
        crate::view::remember_path(self.conn(), &hash, &self.place(path))?;
        Ok(())
    }

    /// How a path is written into `places`: relative to the box's folder
    /// when the file is inside it, whole otherwise.
    ///
    /// Made whole first, against the current directory — where `hash_file`
    /// just read it from — so the CLI's `liv file ./x.pdf` means the file
    /// it hashed. A remainder that climbs out with `..` is not inside,
    /// whatever its spelling starts with.
    fn place(&self, path: &str) -> String {
        let Ok(whole) = std::path::absolute(path) else { return path.to_owned() };
        if let Some(rest) = self.home().and_then(|home| whole.strip_prefix(home).ok()) {
            let parts: Vec<_> = rest.components().collect();
            if !parts.is_empty() && !parts.contains(&Component::ParentDir) {
                // `/` on every platform, so the row reads the same
                // wherever the box is opened.
                return parts
                    .iter()
                    .map(|c| c.as_os_str().to_string_lossy())
                    .collect::<Vec<_>>()
                    .join("/");
            }
        }
        whole.to_string_lossy().into_owned()
    }
}
