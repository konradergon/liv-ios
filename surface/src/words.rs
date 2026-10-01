//! Where a word starts and stops.
//!
//! **One boundary matcher, and it lives here.** The clerk's gazetteer asks
//! "is this name in this text", search's scoring asks "does this text hold
//! this word" and "does something filed here start with these letters" —
//! and standing rule 4 says a display helper, a grammar or a glyph table
//! that exists twice is a defect. A boundary rule that forks is worse than
//! most, because the two halves disagree about one thing the user typed.
//!
//! Callers lowercase both sides first. That is the convention rather than
//! a fold done here, because the caller usually has a lowercased haystack
//! already and doing it per call would allocate per name per entity — the
//! allocation the clerk's gazetteer exists to avoid.

/// The alphanumeric runs of a string.
pub fn words(text: &str) -> impl Iterator<Item = &str> {
    text.split(|c: char| !c.is_alphanumeric()).filter(|w| !w.is_empty())
}

/// Whole-word containment: "anna" is in "call anna friday", and not in
/// "susanna". A boundary at BOTH ends.
pub fn contains_word(haystack: &str, needle: &str) -> bool {
    matches(haystack, needle, true)
}

/// A word that STARTS with these letters: "test" reaches "Testjunk".
///
/// A boundary before and nothing required after — which is the whole
/// difference between the filing tier and the body tier in search. A
/// filing is a short label somebody chose and incremental typing is how
/// anyone reaches one; a body is long enough that a whole word is the
/// honest unit.
pub fn starts_word(haystack: &str, needle: &str) -> bool {
    matches(haystack, needle, false)
}

fn matches(haystack: &str, needle: &str, closed: bool) -> bool {
    if needle.is_empty() {
        return false;
    }
    let mut start = 0;
    while let Some(at) = haystack[start..].find(needle) {
        let at = start + at;
        let before = haystack[..at].chars().next_back();
        let open = before.is_none_or(|c| !c.is_alphanumeric());
        if open && (!closed || {
            let after = haystack[at + needle.len()..].chars().next();
            after.is_none_or(|c| !c.is_alphanumeric())
        }) {
            return true;
        }
        // Past this occurrence. `max(1)` because a needle cannot be empty
        // here but the compiler does not know it, and a zero step would
        // spin.
        start = at + needle.len().max(1);
        if start >= haystack.len() {
            break;
        }
    }
    false
}
