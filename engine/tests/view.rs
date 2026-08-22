//! The replay gate, and the merge rule underneath it.
//!
//! > Drop every derived table, replay the log from zero, and the view
//! > comes back identical.
//!
//! `core-plan.md` makes this the gate for everything after Phase 4, and
//! says plainly: if it cannot be made to pass, the design is wrong and the
//! work should stop. It is what makes a bug in the fold repairable rather
//! than permanent — which is one of the three reasons `core.md` §1 gives
//! for the log existing at all.

use liv_engine::*;

fn dev(n: u8) -> DeviceId {
    DeviceId([n; 8])
}

fn ent(n: u8) -> EntityId {
    EntityId([n; 16])
}

const NAME: EntityId = EntityId([0xf1; 16]);
const DUE: EntityId = EntityId([0xf2; 16]);
const TAGS: EntityId = EntityId([0xf3; 16]);

fn engine() -> Engine {
    Engine::open_in_memory(dev(1)).unwrap()
}

#[test]
fn a_write_lands_in_the_view() {
    let mut e = engine();
    let id = e.mint(1_787_391_635_000);
    e.commit(
        vec![
            Op::CreateEntity { entity: id },
            Op::SetCell {
                entity: id,
                prop: NAME,
                value: Value::Text("Roof project".into()),
                replaces: vec![],
            },
        ],
        1,
        Author::User,
        1_787_391_635_000,
    )
    .unwrap();

    assert_eq!(e.entity_count().unwrap(), 1);
    let cell = e.cell(id, NAME).unwrap();
    assert_eq!(cell.len(), 1, "one live value");
    assert_eq!(cell[0].1, Value::Text("Roof project".into()));
}

#[test]
fn replay_rebuilds_the_view_exactly() {
    // THE GATE. Everything after Phase 4 rests on this.
    let mut e = engine();
    let mut ids = Vec::new();
    for i in 0..200u64 {
        let id = e.mint(1_787_391_635_000 + i);
        ids.push(id);
        e.commit(
            vec![
                Op::CreateEntity { entity: id },
                Op::SetCell {
                    entity: id,
                    prop: NAME,
                    value: Value::Text(format!("note {i}")),
                    replaces: vec![],
                },
                Op::AddToSet { entity: id, prop: TAGS, value: Value::Ref(ent(7)) },
            ],
            1,
            Author::User,
            1_787_391_635_000 + i,
        )
        .unwrap();
    }
    // Overwrite some of them, so the log contains retirements as well as
    // additions — a replay that only ever adds is not a replay.
    for (n, id) in ids.iter().take(50).enumerate() {
        let live = e.cell(*id, NAME).unwrap();
        let replaces: Vec<Dot> = live.iter().map(|(d, _)| *d).collect();
        e.commit(
            vec![Op::SetCell {
                entity: *id,
                prop: NAME,
                value: Value::Text(format!("renamed {n}")),
                replaces,
            }],
            2,
            Author::User,
            1_787_391_700_000 + n as u64,
        )
        .unwrap();
    }

    let before = e.digest().unwrap();
    let entities = e.entity_count().unwrap();
    assert_eq!(entities, 200);

    e.replay().unwrap();

    assert_eq!(e.digest().unwrap(), before, "the view did not come back the same");
    assert_eq!(e.entity_count().unwrap(), entities);
}

#[test]
fn replay_is_idempotent() {
    // Running it twice must not drift. A rebuild button nobody trusts is
    // not a rebuild button.
    let mut e = engine();
    let id = e.mint(1_000);
    e.commit(
        vec![
            Op::CreateEntity { entity: id },
            Op::SetCell { entity: id, prop: DUE, value: Value::Date(DateSpec::Day(20_688)), replaces: vec![] },
        ],
        1,
        Author::User,
        1_000,
    )
    .unwrap();

    e.replay().unwrap();
    let once = e.digest().unwrap();
    e.replay().unwrap();
    assert_eq!(e.digest().unwrap(), once);
}

#[test]
fn two_boxes_fed_the_same_ops_agree() {
    // The digest is also how two devices would notice drift, which
    // core.md §11 calls the only mitigation for a quiet merge bug. If it
    // cannot tell two identical boxes apart from two different ones, it
    // is not worth having.
    let mut a = Engine::open_in_memory(dev(1)).unwrap();
    let mut b = Engine::open_in_memory(dev(2)).unwrap();

    let mut source = Engine::open_in_memory(dev(9)).unwrap();
    let mut groups = Vec::new();
    for i in 0..25u64 {
        let id = source.mint(1_000 + i);
        source
            .commit(
                vec![
                    Op::CreateEntity { entity: id },
                    Op::SetCell { entity: id, prop: NAME, value: Value::Text(format!("n{i}")), replaces: vec![] },
                ],
                1,
                Author::User,
                1_000 + i,
            )
            .unwrap();
    }
    groups.extend(source.groups().unwrap());

    for g in &groups {
        a.receive(g.clone()).unwrap();
    }
    // B gets them in a different arrival order — the hold buffer puts
    // them back in sequence.
    for g in groups.iter().rev() {
        b.receive(g.clone()).unwrap();
    }

    assert_eq!(b.held(), 0, "everything was released");
    assert_eq!(a.digest().unwrap(), b.digest().unwrap(), "arrival order changed the view");
}

#[test]
fn a_concurrent_write_leaves_the_cell_contended_rather_than_picking() {
    // The register rule, and P3: nothing silently wins. Two devices set
    // the same property without seeing each other, so neither names the
    // other's dot in `replaces` — and both values stay live.
    let mut e = Engine::open_in_memory(dev(1)).unwrap();
    let id = ent(3);

    let from_phone = Group {
        device: dev(1),
        first_seq: 0,
        hlc: Hlc { wall_ms: 1_000, ctr: 0 },
        author: Author::User,
        action: 1,
        reverses: None,
        ops: vec![Op::SetCell {
            entity: id,
            prop: DUE,
            value: Value::Text("friday".into()),
            replaces: vec![],
        }],
    };
    let from_laptop = Group {
        device: dev(2),
        first_seq: 0,
        hlc: Hlc { wall_ms: 1_001, ctr: 0 },
        author: Author::User,
        action: 1,
        reverses: None,
        ops: vec![Op::SetCell {
            entity: id,
            prop: DUE,
            value: Value::Text("monday".into()),
            replaces: vec![],
        }],
    };

    e.receive(from_phone).unwrap();
    e.receive(from_laptop).unwrap();

    let live = e.cell(id, DUE).unwrap();
    assert_eq!(live.len(), 2, "a concurrent write must leave BOTH values live");
    let values: Vec<&Value> = live.iter().map(|(_, v)| v).collect();
    assert!(values.contains(&&Value::Text("friday".into())));
    assert!(values.contains(&&Value::Text("monday".into())));
}

#[test]
fn a_write_that_saw_the_other_one_replaces_it() {
    // The other half: a writer that DID see the previous value names its
    // dot, and the cell settles back to one live value. Contention is a
    // consequence of concurrency, not a permanent state.
    let mut e = engine();
    let id = e.mint(1_000);
    e.commit(
        vec![Op::SetCell { entity: id, prop: DUE, value: Value::Text("friday".into()), replaces: vec![] }],
        1,
        Author::User,
        1_000,
    )
    .unwrap();

    let seen: Vec<Dot> = e.cell(id, DUE).unwrap().iter().map(|(d, _)| *d).collect();
    e.commit(
        vec![Op::SetCell { entity: id, prop: DUE, value: Value::Text("monday".into()), replaces: seen }],
        1,
        Author::User,
        1_001,
    )
    .unwrap();

    let live = e.cell(id, DUE).unwrap();
    assert_eq!(live.len(), 1, "a write that saw the last one replaces it");
    assert_eq!(live[0].1, Value::Text("monday".into()));
}

#[test]
fn a_set_keeps_every_member_and_removes_only_what_was_seen() {
    let mut e = engine();
    let id = e.mint(1_000);
    for tag in 1..=3u8 {
        e.commit(
            vec![Op::AddToSet { entity: id, prop: TAGS, value: Value::Ref(ent(tag)) }],
            1,
            Author::User,
            1_000 + tag as u64,
        )
        .unwrap();
    }
    assert_eq!(e.cell(id, TAGS).unwrap().len(), 3, "three members");

    // Remove exactly the add for tag 2.
    let target = e
        .cell(id, TAGS)
        .unwrap()
        .into_iter()
        .find(|(_, v)| *v == Value::Ref(ent(2)))
        .map(|(d, _)| d)
        .unwrap();
    e.commit(
        vec![Op::RemoveFromSet {
            entity: id,
            prop: TAGS,
            value: Value::Ref(ent(2)),
            replaces: vec![target],
        }],
        1,
        Author::User,
        2_000,
    )
    .unwrap();

    let live = e.cell(id, TAGS).unwrap();
    assert_eq!(live.len(), 2, "only the named add went");
    assert!(!live.iter().any(|(_, v)| *v == Value::Ref(ent(2))));
}

#[test]
fn a_cell_arriving_before_its_create_still_lands() {
    // Sync delivers ONE device's stream in order, not the whole mesh's,
    // so a cell can arrive before the create that made its entity. The
    // row is built from the id, which carries its own timestamp — nothing
    // is invented.
    let mut e = Engine::open_in_memory(dev(1)).unwrap();
    let id = ent(42);
    e.receive(Group {
        device: dev(2),
        first_seq: 0,
        hlc: Hlc { wall_ms: 5, ctr: 0 },
        author: Author::User,
        action: 1,
        reverses: None,
        ops: vec![Op::SetCell { entity: id, prop: NAME, value: Value::Text("orphan".into()), replaces: vec![] }],
    })
    .unwrap();

    assert_eq!(e.entity_count().unwrap(), 1);
    assert_eq!(e.cell(id, NAME).unwrap().len(), 1);
}

#[test]
fn the_view_survives_a_restart_and_still_matches_its_log() {
    let dir = std::env::temp_dir().join("liv_engine_view_restart");
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("box.db");

    let before = {
        let mut e = Engine::open(&path, dev(1)).unwrap();
        for i in 0..20u64 {
            let id = e.mint(1_000 + i);
            e.commit(
                vec![
                    Op::CreateEntity { entity: id },
                    Op::SetCell { entity: id, prop: NAME, value: Value::Text(format!("n{i}")), replaces: vec![] },
                ],
                1,
                Author::User,
                1_000 + i,
            )
            .unwrap();
        }
        e.digest().unwrap()
    };

    let mut e = Engine::open(&path, dev(1)).unwrap();
    assert_eq!(e.digest().unwrap(), before, "the view came back as it was left");
    e.replay().unwrap();
    assert_eq!(e.digest().unwrap(), before, "and the log still implies it");
    let _ = std::fs::remove_dir_all(&dir);
}
