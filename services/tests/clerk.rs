//! Clerk v0: dates in text, mentions of known names, and the promise that
//! nothing asks again.

use lotus_core::*;
use lotus_services::clerk;

fn boxed(name: &str) -> (Session, std::path::PathBuf) {
    let path = std::env::temp_dir().join(format!("lotus_clerk_{name}.log"));
    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
    let mut session = Session::open(&path).unwrap();
    lotus_services::seed_if_fresh(&mut session).unwrap();
    (session, path)
}

fn capture(session: &mut Session, text: &str) -> Id {
    lotus_services::capture(session, text, DateTime::at(2026, 7, 6, 9, 0)).unwrap()
}

fn cleanup(path: &std::path::Path) {
    let _ = std::fs::remove_file(path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
}

/// An UNTYPED entity whose content's first block is a task checkbox (P16
/// promotion's candidate: the capture literally is a checkbox).
fn task_note(session: &mut Session, text: &str) -> Id {
    let id = session.allocate_id();
    session
        .commit(
            vec![
                Command::Create { entity: id },
                Command::AddCell {
                    entity: id,
                    cell: Cell {
                        property: props::CONTENT,
                        value: Value::RichText(RichText {
                            spans: vec![
                                Span::Break(Block::Task { depth: 0, done: false }),
                                Span::text(text),
                            ],
                        }),
                    },
                },
                Command::AddCell {
                    entity: id,
                    cell: Cell {
                        property: props::CREATED,
                        value: Value::DateTime(DateTime::at(2026, 7, 6, 9, 0)),
                    },
                },
            ],
            "task note",
            Author::User,
        )
        .unwrap();
    id
}

fn from(proposals: &[Proposal], proposer: &str) -> Option<Proposal> {
    proposals.iter().find(|p| p.author == Author::Proposer(proposer.into())).cloned()
}

/// A typed, named entity (+ optional extra cells) for the dedupe tests.
fn typed(session: &mut Session, type_name: &str, name: &str, extra: Vec<Cell>) -> Id {
    let ty = lotus_services::content::find_type(session.store(), type_name);
    let id = session.allocate_id();
    let mut cmds = vec![Command::Create { entity: id }];
    if let Some(ty) = ty {
        cmds.push(Command::AddCell {
            entity: id,
            cell: Cell { property: props::TYPE, value: Value::Reference(ty) },
        });
    }
    cmds.push(Command::AddCell {
        entity: id,
        cell: Cell { property: props::NAME, value: Value::text(name) },
    });
    for cell in extra {
        cmds.push(Command::AddCell { entity: id, cell });
    }
    session.commit(cmds, "e", Author::User).unwrap();
    id
}

// ---- P16 dedupe: exact-identity merge proposals ----

#[test]
fn dedupe_proposes_a_merge_for_same_type_and_name() {
    let (mut session, path) = boxed("dedupe_prop");
    let due = lotus_services::property_id(session.store(), "due").unwrap();
    let older = typed(&mut session, "note", "Meeting notes", vec![]);
    let newer = typed(
        &mut session,
        "note",
        "meeting NOTES", // casefold-equal
        vec![Cell { property: due, value: Value::DateTime(DateTime::date(2026, 7, 10)) }],
    );

    let p = from(&clerk::sweep(session.store(), MONDAY), "dedupe").expect("a dedupe proposal");
    // Survivor is the older id; the newer redirects into it.
    session.propose(p.clone()).unwrap();
    session.accept(0).unwrap();
    assert_eq!(session.store().resolve(newer), older, "loser redirects to survivor");
    // Survivor absorbed the loser's unique due cell.
    assert!(session.store().get(older).unwrap().get(due).is_some(), "survivor got the due");
    cleanup(&path);
}

#[test]
fn dedupe_is_exact_not_fuzzy() {
    let (mut session, path) = boxed("dedupe_fuzzy");
    typed(&mut session, "note", "Anna", vec![]);
    typed(&mut session, "note", "Annabel", vec![]);
    assert!(from(&clerk::sweep(session.store(), MONDAY), "dedupe").is_none());
    cleanup(&path);
}

#[test]
fn dedupe_never_copies_tier_or_private() {
    let (mut session, path) = boxed("dedupe_tier");
    // A loser carrying a private flag — the merge must not copy it.
    typed(&mut session, "note", "Dup", vec![]);
    typed(
        &mut session,
        "note",
        "Dup",
        vec![Cell { property: props::PRIVATE, value: Value::Bool(true) }],
    );
    let p = from(&clerk::sweep(session.store(), MONDAY), "dedupe").expect("still proposes");
    assert!(
        !p.commands.iter().any(|c| matches!(
            c,
            Command::AddCell { cell, .. } if cell.property == props::PRIVATE
        )),
        "the merge copied a private cell"
    );
    cleanup(&path);
}

#[test]
fn a_declined_dedupe_is_not_re_asked() {
    let (mut session, path) = boxed("dedupe_decl");
    typed(&mut session, "note", "Twice", vec![]);
    typed(&mut session, "note", "Twice", vec![]);
    let p = from(&clerk::sweep(session.store(), MONDAY), "dedupe").unwrap();
    session.propose(p.clone()).unwrap();
    session.reject(0).unwrap();
    assert!(from(&clerk::sweep(session.store(), MONDAY), "dedupe").is_none());
    cleanup(&path);
}

// ---- P16a: the priority-word proposer ----

#[test]
fn priority_word_proposes_the_matching_option() {
    let (mut session, path) = boxed("prio");
    let scrap = capture(&mut session, "URGENT: the server is down");

    let proposals = clerk::sweep(session.store(), MONDAY);
    let p = from(&proposals, "priority").expect("a priority proposal");
    assert!(p.reason.to_lowercase().contains("high"), "{}", p.reason);

    session.propose(p.clone()).unwrap();
    session.accept(0).unwrap();
    let priority = lotus_services::property_id(session.store(), "priority").unwrap();
    let high = lotus_services::content::find_option(session.store(), priority, "high").unwrap();
    assert_eq!(session.store().get(scrap).unwrap().get(priority), Some(&Value::Select(high)));

    // Once set, the proposer stays quiet.
    assert!(from(&clerk::sweep(session.store(), MONDAY), "priority").is_none());
    cleanup(&path);
}

#[test]
fn priority_is_quiet_without_a_trigger_word() {
    let (mut session, path) = boxed("noprio");
    capture(&mut session, "buy milk and eggs");
    assert!(from(&clerk::sweep(session.store(), MONDAY), "priority").is_none());
    cleanup(&path);
}

// ---- P16a: the promotion proposer (checkbox capture -> task) ----

#[test]
fn promotion_promotes_an_untyped_checkbox() {
    let (mut session, path) = boxed("promote");
    let note = task_note(&mut session, "call the dentist");

    let proposals = clerk::sweep(session.store(), MONDAY);
    let p = from(&proposals, "promotion").expect("a promotion proposal");

    session.propose(p.clone()).unwrap();
    session.accept(0).unwrap();
    let ty = lotus_services::content::find_type(session.store(), "task").unwrap();
    assert!(
        session.store().get(note).unwrap().has(props::TYPE, &Value::Reference(ty)),
        "the note became a task"
    );
    cleanup(&path);
}

#[test]
fn promotion_is_quiet_when_already_typed() {
    let (mut session, path) = boxed("typed");
    // A plain scrap (no leading task block) is never promoted.
    capture(&mut session, "just a thought");
    assert!(from(&clerk::sweep(session.store(), MONDAY), "promotion").is_none());
    cleanup(&path);
}

#[test]
fn a_declined_promotion_is_not_re_asked() {
    let (mut session, path) = boxed("declpromote");
    task_note(&mut session, "water the plants");

    let p = from(&clerk::sweep(session.store(), MONDAY), "promotion").unwrap();
    session.propose(p.clone()).unwrap();
    session.reject(0).unwrap();
    // The next sweep must not re-propose the same promotion.
    assert!(from(&clerk::sweep(session.store(), MONDAY), "promotion").is_none());
    cleanup(&path);
}

#[test]
fn the_sweep_never_proposes_tier_or_private() {
    let (mut session, path) = boxed("protected");
    capture(&mut session, "URGENT call anna friday");
    task_note(&mut session, "urgent thing");
    let private = props::PRIVATE;
    let tier = lotus_services::property_id(session.store(), "tier");
    for p in clerk::sweep(session.store(), MONDAY) {
        for c in &p.commands {
            if let Command::AddCell { cell, .. } = c {
                assert_ne!(cell.property, private, "proposed a private cell");
                if let Some(tier) = tier {
                    assert_ne!(cell.property, tier, "proposed a tier cell");
                }
            }
        }
    }
    cleanup(&path);
}

/// 2026-07-06 is a Monday.
const MONDAY: DateTime = DateTime {
    civil: 202607060000,
    date_only: true,
    end: None,
};

#[test]
fn friday_means_this_friday() {
    let (mut session, path) = boxed("friday");
    let scrap = capture(&mut session, "Call Anna about the kickoff Friday");

    let proposals = clerk::sweep(session.store(), MONDAY);
    assert_eq!(proposals.len(), 1);
    let p = &proposals[0];
    assert_eq!(p.author, Author::Proposer("dates".into()));
    assert!(p.reason.contains("2026-07-10"), "{}", p.reason);

    // Accepting lands the due cell on the scrap, authored by the clerk.
    session.propose(p.clone()).unwrap();
    session.accept(0).unwrap();
    let due = lotus_services::property_id(session.store(), "due").unwrap();
    assert!(session.store().get(scrap).unwrap().get(due).is_some());

    // Once due exists, the dates proposer stays quiet.
    assert!(clerk::sweep(session.store(), MONDAY).is_empty());

    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
}

#[test]
fn tomorrow_and_iso_dates_parse() {
    let (mut session, path) = boxed("dates");
    capture(&mut session, "renew the domain tomorrow");
    capture(&mut session, "dentist on 2026-08-03");

    let proposals = clerk::sweep(session.store(), MONDAY);
    let reasons: Vec<&str> = proposals.iter().map(|p| p.reason.as_str()).collect();
    assert_eq!(proposals.len(), 2);
    assert!(reasons.iter().any(|r| r.contains("2026-07-07")), "{reasons:?}");
    assert!(reasons.iter().any(|r| r.contains("2026-08-03")), "{reasons:?}");

    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
}

#[test]
fn known_names_are_noticed_whole_words_only() {
    let (mut session, path) = boxed("mentions");
    let anna = session.allocate_id();
    session
        .commit(
            vec![
                Command::Create { entity: anna },
                Command::AddCell {
                    entity: anna,
                    cell: Cell {
                        property: props::NAME,
                        value: Value::text("Anna"),
                    },
                },
            ],
            "a person",
            Author::User,
        )
        .unwrap();

    let scrap = capture(&mut session, "lunch with anna");
    capture(&mut session, "susanna's book"); // not a mention of Anna

    let proposals = clerk::sweep(session.store(), MONDAY);
    assert_eq!(proposals.len(), 1, "{proposals:?}");
    assert_eq!(proposals[0].author, Author::Proposer("mentions".into()));
    assert!(matches!(
        proposals[0].commands.as_slice(),
        [Command::AddCell { entity, cell }]
            if *entity == scrap && cell.value == Value::Reference(anna)
    ));

    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
}

#[test]
fn a_decline_is_remembered_across_restarts() {
    let (mut session, path) = boxed("decline");
    capture(&mut session, "maybe friday");

    let proposals = clerk::sweep(session.store(), MONDAY);
    assert_eq!(proposals.len(), 1);
    session.propose(proposals[0].clone()).unwrap();
    session.reject(0).unwrap();

    // Same process: the sweep drops the duplicate of the refusal.
    assert!(clerk::sweep(session.store(), MONDAY).is_empty());

    // New process: the refusal was persisted beside the log.
    drop(session);
    let session = Session::open(&path).unwrap();
    assert_eq!(session.store().declined().len(), 1);
    assert!(
        clerk::sweep(session.store(), MONDAY).is_empty(),
        "nothing asks again"
    );

    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
}

#[test]
fn relative_dates_anchor_to_capture_not_to_the_sweep() {
    let (mut session, path) = boxed("anchor");
    // Captured Monday; triaged days later.
    let scrap = lotus_services::capture(
        &mut session,
        "pay rent tomorrow",
        DateTime::at(2026, 7, 6, 21, 0),
    )
    .unwrap();
    let _ = scrap;

    let wednesday = DateTime::date(2026, 7, 8);
    let proposals = clerk::sweep(session.store(), wednesday);
    assert_eq!(proposals.len(), 1);
    // Tomorrow means the day after the thought: July 7, not July 9.
    assert!(proposals[0].reason.contains("2026-07-07"), "{}", proposals[0].reason);

    // And the proposal is identical no matter which day sweeps it —
    // what the inbox showed is what accept will commit.
    assert_eq!(proposals, clerk::sweep(session.store(), DateTime::date(2026, 7, 20)));

    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
}

#[test]
fn a_decline_outlives_value_drift() {
    let (mut session, path) = boxed("drift");
    capture(&mut session, "gym today");

    let proposals = clerk::sweep(session.store(), MONDAY);
    assert_eq!(proposals.len(), 1);
    session.propose(proposals[0].clone()).unwrap();
    session.reject(0).unwrap();

    // Even if a future proposer resolves to a different value, the
    // refusal binds (proposer, entity, property): quiet on every day.
    for day in [7, 8, 20] {
        assert!(
            clerk::sweep(session.store(), DateTime::date(2026, 7, day)).is_empty(),
            "asked again on day {day}"
        );
    }

    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
}

#[test]
fn an_old_box_gains_the_starter_library_on_open() {
    let path = std::env::temp_dir().join("lotus_clerk_upgrade.log");
    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));

    // A box from before the starter library: history exists, "due" does not.
    {
        let mut session = Session::open(&path).unwrap();
        let scrap = session.allocate_id();
        session
            .commit(
                vec![Command::Create { entity: scrap }],
                "old capture",
                Author::User,
            )
            .unwrap();
        assert!(lotus_services::property_id(session.store(), "due").is_none());
    }

    // Opening it through the seed path upgrades it, additively.
    let mut session = Session::open(&path).unwrap();
    lotus_services::seed_if_fresh(&mut session).unwrap();
    assert!(lotus_services::property_id(session.store(), "due").is_some());
    capture(&mut session, "dentist friday");
    assert_eq!(clerk::sweep(session.store(), MONDAY).len(), 1);

    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
}

#[test]
fn the_sweep_never_duplicates_pending() {
    let (mut session, path) = boxed("dedup");
    capture(&mut session, "ship it friday");

    for proposal in clerk::sweep(session.store(), MONDAY) {
        session.propose(proposal).unwrap();
    }
    assert_eq!(session.store().pending().len(), 1);

    // A second sweep — the startup sweep of the next open — adds nothing.
    assert!(clerk::sweep(session.store(), MONDAY).is_empty());

    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
}

// ---- P16b: grouping + severable group-accept ----

#[test]
fn alike_proposals_share_a_group_key() {
    let (mut session, path) = boxed("groupkey");
    typed(&mut session, "note", "Anna", vec![]); // a known name → a mention too
    capture(&mut session, "call Anna friday");
    let proposals = clerk::sweep(session.store(), MONDAY);
    let dates = from(&proposals, "dates").unwrap();
    let mentions = from(&proposals, "mentions").unwrap();
    assert_ne!(
        clerk::group_key(&dates),
        clerk::group_key(&mentions),
        "a date and a mention are different groups"
    );
    assert!(clerk::groups(&proposals).len() >= 2);
    cleanup(&path);
}

#[test]
fn accept_group_is_one_transaction_one_undo() {
    let (mut session, path) = boxed("acceptgroup");
    let a = capture(&mut session, "ship it friday");
    let b = capture(&mut session, "review pr monday");
    for p in clerk::sweep(session.store(), MONDAY) {
        session.propose(p).unwrap();
    }
    assert_eq!(session.store().pending().len(), 2);

    clerk::accept_group(&mut session, &[0, 1]).unwrap();
    let due = lotus_services::property_id(session.store(), "due").unwrap();
    assert!(session.store().get(a).unwrap().get(due).is_some());
    assert!(session.store().get(b).unwrap().get(due).is_some());
    assert!(session.store().pending().is_empty(), "both drained");

    // ONE undo reverts BOTH — the group committed as one transaction.
    session.undo(Author::User).unwrap();
    assert!(session.store().get(a).unwrap().get(due).is_none());
    assert!(session.store().get(b).unwrap().get(due).is_none());
    cleanup(&path);
}

#[test]
fn severing_leaves_a_member_pending() {
    let (mut session, path) = boxed("sever");
    capture(&mut session, "ship it friday");
    capture(&mut session, "review pr monday");
    for p in clerk::sweep(session.store(), MONDAY) {
        session.propose(p).unwrap();
    }
    assert_eq!(session.store().pending().len(), 2);
    clerk::accept_group(&mut session, &[0]).unwrap();
    assert_eq!(session.store().pending().len(), 1, "one severed, one remains");
    cleanup(&path);
}
