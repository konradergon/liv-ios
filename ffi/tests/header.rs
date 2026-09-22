//! `ffi/liv.h` is the CONTRACT, and a contract nobody checks is prose.
//!
//! Standing rule 3 says a rule that matters lives in a type rather than in
//! prose, and this header is the one place in the repo where that is not
//! possible: C has to be told the signatures by hand. So the next best
//! thing is a test that notices when the hand-written side stops matching
//! the Rust — because the failure mode otherwise is a shell that declares
//! a verb that is not there, or worse, one that is there with a different
//! shape, and finds out at run time on a phone.
//!
//! This checks NAMES, not signatures. A missing verb is the drift that
//! actually happens (a verb is added and the header is forgotten); a
//! signature that disagrees is caught at link time on the shell's own
//! build. Checking names is the part a linker cannot do for us — a verb
//! absent from the header is absent from the shell, and nothing anywhere
//! complains.

use std::collections::BTreeSet;

/// Every `#[no_mangle] pub unsafe extern "C" fn` / `pub extern "C" fn` in
/// the crate's sources, by name.
fn exported() -> BTreeSet<String> {
    let mut found = BTreeSet::new();
    let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("src");
    let mut stack = vec![dir];
    while let Some(d) = stack.pop() {
        for entry in std::fs::read_dir(&d).unwrap() {
            let p = entry.unwrap().path();
            if p.is_dir() {
                stack.push(p);
                continue;
            }
            if p.extension().is_none_or(|e| e != "rs") {
                continue;
            }
            let src = std::fs::read_to_string(&p).unwrap();
            for (n, line) in src.lines().enumerate() {
                if !line.trim_start().starts_with("#[no_mangle]") {
                    continue;
                }
                // The signature is the next line that is not an attribute
                // or a blank — `#[no_mangle]` and `pub unsafe extern` are
                // conventionally adjacent, but a `#[allow]` between them
                // is legal and should not hide a verb.
                let sig = src
                    .lines()
                    .skip(n + 1)
                    .find(|l| !l.trim().is_empty() && !l.trim_start().starts_with('#'))
                    .unwrap_or("");
                if let Some(name) = sig.split("fn ").nth(1).and_then(|r| r.split('(').next()) {
                    found.insert(name.trim().to_owned());
                }
            }
        }
    }
    assert!(found.len() > 50, "the scraper found almost nothing: {}", found.len());
    found
}

/// Every `liv_*` name the header declares.
fn declared() -> BTreeSet<String> {
    let h = std::fs::read_to_string(
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("liv.h"),
    )
    .unwrap();
    let mut found = BTreeSet::new();
    for line in h.lines() {
        // A declaration, not a mention in a comment: the name is followed
        // by `(` and the line is not inside a `/* … */` block. Comments in
        // this header always open their line with `/*` or a space.
        let t = line.trim_start();
        if t.starts_with('/') || t.starts_with('*') || t.starts_with('#') {
            continue;
        }
        let Some(at) = line.find("liv_") else { continue };
        let rest = &line[at..];
        let name: String =
            rest.chars().take_while(|c| c.is_alphanumeric() || *c == '_').collect();
        if rest[name.len()..].starts_with('(') {
            found.insert(name);
        }
    }
    assert!(found.len() > 50, "the header parser found almost nothing: {}", found.len());
    found
}

#[test]
fn every_exported_verb_is_declared_in_the_header() {
    let missing: Vec<_> = exported().difference(&declared()).cloned().collect();
    assert!(
        missing.is_empty(),
        "exported from Rust and absent from ffi/liv.h — a shell cannot call these:\n  {}",
        missing.join("\n  ")
    );
}

#[test]
fn the_header_declares_nothing_that_is_not_there() {
    // The other direction, which is the one that fails at LINK time rather
    // than at run time — but only for a shell that actually calls it, so a
    // stale declaration can sit in the header for months.
    let ghosts: Vec<_> = declared().difference(&exported()).cloned().collect();
    assert!(
        ghosts.is_empty(),
        "declared in ffi/liv.h and not exported — these link-error a shell:\n  {}",
        ghosts.join("\n  ")
    );
}

