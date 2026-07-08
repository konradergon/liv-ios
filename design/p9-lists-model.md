# P9 Lists Model — a list is an entity of `type=list` whose ordered `related` cells ARE its members; membership is tagging; the one genuine gap is an add-ONE / remove-ONE-cell seam

Building on the shipped tree (`services/src/{lib,content,search}.rs`,
`ffi/src/lib.rs`, `shell/macos/Sources/{Window,Chrome,Spaces}.swift`) and the
substrate P1–P8 laid down. **A (manual) list is an ordinary entity of a new
`type=list` whose multi-valued `related` reference cells, in log order, ARE its
members.** That model needs almost nothing new: `related` is already seeded
(`lib.rs:372`), reference cells are already multi-valued and already carry
`refTarget` in the snapshot (`Window.swift:29`), and the birth/lens/open
plumbing is a direct twin of P8's task work. **Membership is tagging** — an
object can be in many lists; removing a member emits one `RemoveCell` and
**never deletes the object**. Adding a member is one `AddCell`. There is
**exactly one genuine core gap**: the seam has no *add-one* / *remove-one*
verb. `lotus_set_at`→`set_property` does **replace-all** (`content.rs:401-412`:
maps every existing cell to `RemoveCell`, then one `AddCell`) and
`lotus_unset_at`→`unset_property` does **remove-all** (`content.rs:349-356`).
Neither can add a member without wiping the rest, nor remove one specific
member. P9 adds a thin service pair (`add_member` = one `AddCell(related,
Reference)`; `remove_member` = one `RemoveCell(related, Reference)`) and two FFI
verbs. **No new command variants, no new snapshot field, no core model change.**

Liv's Lists (liv-ui-map §2.16) are heavier — a first-class collection with
`templateMode` (fill/overwrite/tag-only) that **stamps metadata onto joining
members**, `memberIds[]` in insertion order, saved as `.base` + mirrored `.md`
files, rendered in the Files tab bar, workspace-scoped. lotus keeps the **one
durable idea** — an ordered manual collection that tags rather than contains —
and **drops the rest**: template-mode stamping becomes a **deferred clerk
proposal on join** (severable, §8); `.base`/`.md` mirrors are dropped;
`memberIds[]` becomes `related` cells in log order; the collection is
**vault-wide** for v1, exactly as Tasks and Library ship vault-wide.

## 1 · The load-bearing decisions

1. **A manual list is an entity of `type=list`; its `related` cells ARE the
   members.** No list store, no `memberIds` array, no `.base` file. Birth is
   `Create` + `type=→list` + `name` + `created` — a twin of `create_workspace`
   (name at birth, `content.rs:306`) rather than `create_note` (nameless),
   because a list wants a name from the first frame (you name it *before* you
   add to it). Adding member `x` is `AddCell(related, Reference(x))`; the log
   appends in order, so **log order = insertion order = display order**.
   Removing `x` is one `RemoveCell(related, Reference(x))` — the object `x`
   survives untouched. This is the whole membership model.

2. **`related` is already the substrate — no new property.** `lib.rs:372`
   seeds `related` as a `reference` property, and reference cells are
   multi-valued (`entity.all(prop)` yields every cell in log order). P9 adds
   **no property**. It adds one **type** (`list`) so lists are a
   distinguishable kind the lens can filter on and `create_list` can stamp.

3. **THE ONE GENUINE SEAM GAP: neither `set_at` nor `unset_at` touches ONE
   cell of a multi-valued property.** `set_property` is replace-all
   (`content.rs:401-412`); `unset_property` is remove-all (`content.rs:349-356`).
   Using `set_at` to add a member would **wipe every existing member**; using
   `unset_at` to remove a member would **wipe them all**. So P9 authors two
   thin services emitting a **single** command each, and two FFI verbs. The
   remove-one primitive already exists at the command layer — `set_property`
   and `unset_property` already build `Command::RemoveCell{entity, cell:{property,
   value}}` per cell (`content.rs:404`); the new service just emits **one** of
   them. Each service is ~10 lines; no new `Command` variant.

4. **The native surface is a structural copy of P8, not new UI.** A `lists`
   case on `Surface` (`Chrome.swift:12`) routes a `ListsView` modeled on
   `LibraryView`/`TasksView` (`Window.swift:2248`, `:2310`) — filter
   `$0.kinds.contains("list")`, quick-add via `createList`, `EntityLine` rows.
   A `ListDetailView` renders the selected list's `row.cells.filter {
   $0.property == "related" }` as `EntityLine` members in array (log) order,
   each with `open(refTarget)` and a hover-✕ calling `remove_member`. A sidebar
   **Lists section** (mirroring the Boards group at `Spaces.swift:283-295`)
   lists the lists with a **+ New list** affordance. The add-to-list gesture is
   an **"Add to list…"** menu on any entity — Liv's `AddToListMenu` **minus**
   the template stamping.

5. **Query-lists are the same surface, a different backing — and severable.**
   A manual list reads members from its `related` cells; a query list would run
   a saved DSL string (a `props::QUERY` text cell → `search::parse` →
   `search::run`, feature-map #28). The lens/sidebar rendering is identical;
   only the member *source* differs. For P9, **ship manual lists fully** and
   treat query-lists as **9c or a deferred fold** (§7), since #28 (saved
   searches) may ship as its own slice.

## 2 · The list-entity model (data-model first)

A manual list, e.g. `Reading queue`:

```
Create #7200
name     = "Reading queue"            (props::NAME, text; named at birth)
type     = →list                      (props::TYPE, reference to the seeded "list" type)
created  = 2026-07-08 …               (props::CREATED)
related  = →#4012                      (props::… "related", reference — member 1)
related  = →#4103                      (a second related cell — member 2)
related  = →#3990                      (member 3)
```

`type`, `name`, `created` are written at birth (§4). Members are added **after
birth**, one `AddCell(related, Reference(member))` each (§3), in the order the
user adds them. `entity.all(related)` returns them in log order — that ordered
list IS the membership, and the snapshot already carries each as a `CellRow`
with `property == "related"` and `refTarget == member id` (`Window.swift:21-29`).

A **query list** (deferred/severable, §7) would instead carry:

```
type  = →list
name  = "Overdue tasks"
query = "type:task status:todo due:<today"   (props::QUERY, text — a saved DSL string)
```

and no `related` cells; its members are `search::run(store, &search::parse(q))`
computed at read time. One `type=list`, two backings.

## 3 · The membership seam — the one genuine Rust addition

### 3.1 Services — `add_member` / `remove_member` (`services/src/content.rs`)

Two thin services beside `set_property`/`unset_property`, each emitting a
**single** command. Both resolve `related` by name (never a hardcoded id, per
the seed law) and validate the member entity exists:

```rust
/// Add ONE member to a list: a single AddCell(related, Reference(member)).
/// Membership is tagging — the member entity is not touched, and it may
/// belong to many lists. `set_property` cannot do this (it replaces ALL
/// cells of `related`); this is the add-one primitive lists need. Adding a
/// member already present is a silent no-op (log-order membership stays a
/// set), matching Liv's AddToListMenu, and keeps the log from appending a
/// second identical Reference.
pub fn add_member(session: &mut Session, list: Id, member: Id) -> Result<(), String> {
    let store = session.store();
    let list = store.resolve(list);
    let member = store.resolve(member);
    let entity = store.get(list).ok_or(format!("no list #{list}"))?;
    if store.get(member).is_none() {
        return Err(format!("no entity #{member}"));
    }
    let related =
        property_id(store, "related").ok_or("no property named related")?;
    let value = Value::Reference(member);
    if entity.has(related, &value) {
        return Ok(()); // already a member — silent no-op
    }
    session
        .commit(
            vec![Command::AddCell { entity: list, cell: Cell { property: related, value } }],
            "add to list",
            Author::User,
        )
        .map_err(|e| e.to_string())?;
    Ok(())
}

/// Remove ONE member from a list: a single RemoveCell(related,
/// Reference(member)). Removing membership NEVER deletes the member
/// (the core law: "Deletion never cascades") — the object survives,
/// merely un-tagged. `unset_property` cannot do this (it removes EVERY
/// `related` cell); this removes exactly the one matching member.
pub fn remove_member(session: &mut Session, list: Id, member: Id) -> Result<(), String> {
    let store = session.store();
    let list = store.resolve(list);
    let member = store.resolve(member);
    let entity = store.get(list).ok_or(format!("no list #{list}"))?;
    let related =
        property_id(store, "related").ok_or("no property named related")?;
    let value = Value::Reference(member);
    if !entity.has(related, &value) {
        return Ok(()); // not a member — no-op, not an error
    }
    session
        .commit(
            vec![Command::RemoveCell { entity: list, cell: Cell { property: related, value } }],
            "remove from list",
            Author::User,
        )
        .map_err(|e| e.to_string())?;
    Ok(())
}
```

`entity.has(property, &value)` already exists (`core/src/entity.rs:47`), so the
dedup/no-op guards are free.

**Naming / altitude — resolving the open question.** The verbs are named
`add_member` / `remove_member` (list-domain vocabulary), but their **body is
generic** — a single AddCell / RemoveCell of one `{property, value}`. I
recommend the **FFI** be the *generic* primitive
`lotus_add_cell_at(path, id, property, value)` /
`lotus_remove_cell_at(path, id, property, value)` (mirroring `lotus_set_at`'s
signature exactly), because (a) it is the honest shape of the operation, (b) it
also serves any future multi-valued property (tags, people) without another
FFI round, and (c) the Swift side already speaks `(id, property, value)` via
`model.set`. The list-specific `add_member`/`remove_member` **services** stay
(they carry the dedup guard and the domain name); the FFI is the one generic
add/remove-cell pair those services could even share. If the owner prefers
narrow-and-honest at the FFI too, ship `lotus_add_related_at` /
lotus_remove_related_at` (member id, no property string) — smaller, but a
second verb the day tags need the same thing. **Recommendation: generic
`lotus_add_cell_at` / `lotus_remove_cell_at`**, value parsed by the property's
kind exactly as `set_at` does (a `related` value arrives as `#id` and
`parse_value`'s reference branch trims `#` and validates existence,
`content.rs` reference parse).

### 3.2 FFI — `lotus_add_cell_at` / `lotus_remove_cell_at` (`ffi/src/lib.rs`)

Slot beside `lotus_set_at` (`:861`) using the same `open_swept` + `is_ok() as
i32` shape:

```rust
/// Add ONE cell to a multi-valued property (list membership: property
/// "related", value "#<member-id>"). Unlike lotus_set_at (replace-all) and
/// lotus_unset_at (remove-all), this touches exactly one cell. Returns 1,
/// or 0 on busy/parse/no-entity. Adding a value already present is a
/// no-op that still returns 1.
#[no_mangle]
pub unsafe extern "C" fn lotus_add_cell_at(
    path: *const c_char, id: u64,
    property: *const c_char, value: *const c_char,
) -> i32 { /* CStr guards → open_swept → content::add_member-style dispatch */ }

/// Remove ONE cell of a multi-valued property (un-tag a list member).
/// Never deletes the referenced entity. Returns 1, or 0 on busy/failure.
#[no_mangle]
pub unsafe extern "C" fn lotus_remove_cell_at(
    path: *const c_char, id: u64,
    property: *const c_char, value: *const c_char,
) -> i32 { /* mirror; removes one matching cell */ }
```

For a generic FFI, back it with a generic service that parses `value` by kind
(reusing `set_property`'s `parse_value`) and then does the single Add/Remove;
`add_member`/`remove_member` become the reference-typed callers of it, or the
FFI calls the generic path directly. **Declare both in the hand-maintained
header** `shell/macos/lotus.h` next to `lotus_set_at` (`:61`) — the Swift side
links against this header, not a generated one; an export without the matching
`.h` line leaves the call unresolved.

### 3.3 Shell — `BoxModel.addMember` / `removeMember`

Twins of `model.set` (`Window.swift:262`), through the boolean `act` helper:

```swift
func addMember(_ list: UInt64, _ member: UInt64, done: @escaping (Bool) -> Void = { _ in }) {
    act(done) { lotus_add_cell_at(self.path, list, "related", "#\(member)") == 1 }
}
func removeMember(_ list: UInt64, _ member: UInt64, done: @escaping (Bool) -> Void = { _ in }) {
    act(done) { lotus_remove_cell_at(self.path, list, "related", "#\(member)") == 1 }
}
```

## 4 · Seeding `type=list` + the `create_list` birth verb

### 4.1 Seed the `list` type — additive, idempotent

`seed_starter_library` returns early when `due` exists (`lib.rs:349`), so an
edit *inside* it never runs on an already-shipped box. Two honest options:

- **(a) Add `("list", &[])` to the expectations tuple** (`lib.rs:393`) for
  **new** boxes, **and** add a separately-guarded additive pass (its own
  `if find_type(store, "list").is_none()` gate, run after
  `seed_starter_library`, mirroring P8's `seed_priority` and the P7
  "older box gains it on open" contract) so **existing** boxes gain the type on
  open. This is the P8-proven pattern and I recommend it.
- (b) Only the additive pass (skip the tuple edit) — simpler but new boxes then
  also get `list` from the pass rather than the library; fine, but splits where
  the type is born.

**Recommendation: (a).** The type is `("list", &[])` — **`related` is NOT an
expected cell.** Leaving membership unexpected keeps `related` generic (it is
not a "field of a list", it is the tagging property any entity can carry) and
avoids the inspector/clerk treating an empty list as a box with an unfilled
slot. (This resolves the "should list expect `related`?" open question:
**no** — offered by the surface, not expected by the type.)

### 4.2 Service — `content::create_list` (a `create_workspace` twin, named at birth)

```rust
/// Birth of a list: Create + type=list + name + created, one transaction.
/// Named at birth (unlike create_note/create_task, which are nameless) —
/// a list is named BEFORE members are added, mirroring create_workspace.
/// Members are added later via add_member, never at birth.
pub fn create_list(session: &mut Session, name: &str, created: DateTime) -> Result<Id, PersistError> {
    let store = session.store();
    let list_type = find_type(store, "list");
    let id = session.allocate_id();
    let mut commands = vec![Command::Create { entity: id }];
    let mut add = |property: Id, value: Value| {
        commands.push(Command::AddCell { entity: id, cell: Cell { property, value } });
    };
    add(props::NAME, Value::text(name));
    add(props::CREATED, Value::DateTime(created));
    if let Some(t) = list_type { add(props::TYPE, Value::Reference(t)); }
    session.commit(commands, "new list", Author::User)?;
    Ok(id)
}
```

### 4.3 FFI — `lotus_create_list_at(path, name)`

Mirror `lotus_create_workspace_at` (`ffi/src/lib.rs:991`, which takes a `name`
string), returning the new id or 0. Declare in `lotus.h` beside
`lotus_create_workspace_at` (`:111`). Shell: `BoxModel.createList(name:)`, a
twin of `createWorkspace` (`Window.swift:330`).

## 5 · Reading a list's ordered members (no new snapshot field)

The snapshot already carries every member. For the selected list `row`:

```swift
let memberIds = row.cells
    .filter { $0.property == "related" }     // log order preserved
    .compactMap { $0.refTarget }             // each member's id
let members = memberIds.compactMap { model.entity($0) }   // resolve to rows
```

`model.entity(id)` (`Window.swift:170`) resolves each to an `EntityRow`; render
each as an `EntityLine`. Log order is array order — **insertion order for
free**, no order cell, no sort. (Reordering by drag is deferred, §8; v1 is
insertion order, and reordering without an order-cell means a remove+re-add
sequence — flagged, not built.)

## 6 · The native shell (assembly of existing primitives)

### 6.1 Surface + router
Add `case lists` to `Surface` (`Chrome.swift:12`): `label "Lists"`, `symbol
"list.bullet"`, `isGlobalTool == true` (it is `!= .notes`, so full-bleed
vault-wide like Tasks/Library). Add a `case .lists: ListsView(...)` arm to the
center router (`Window.swift:922`) beside `.tasks`/`.library`.

### 6.2 `ListsView` — the list of lists (a `LibraryView` twin)
Filter `model.rows(...).filter { $0.kinds.contains("list") }`; `LensHeader`
("Lists", live count); a **+ New list** affordance (an `InlineInput` →
`model.createList(name:)`, mirroring the Boards new-workspace input at
`Spaces.swift:296-313`); `EntityLine` rows whose tap **selects the active
list** (drives the detail pane) rather than opening a tab (a list *contains*, it
is not primarily an editable note). Empty state on the LibraryView pattern.

### 6.3 `ListDetailView` — the ordered members (a read-only lens, then ✕)
Given the selected list row, render §5's `members` as `EntityLine` rows in log
order, each `open(refTarget)` → `openEntityTab` (`Window.swift:1074`;
list members open exactly as any entity — a member with a `file` cell opens as a
file, else a note, no special-casing). A **hover-✕** on each row calls
`model.removeMember(list, member)`. Empty state: "No members yet — add from any
entity's ⋯ menu." (9a ships this **read-only** — members render, no ✕; the ✕ and
the add gesture land in 9b.)

### 6.4 Sidebar Lists section
A **Lists group** in the sidebar, mirroring the Boards group
(`Spaces.swift:283-295`): a `groupHeader("Lists")`, one flat row per
`type=list` entity (selecting it switches to the `.lists` surface with that list
active), and a **+ New list** button at the foot (like "New workspace",
`Spaces.swift:330`). This is the durable Liv affordance (lists live in the
navigation chrome) minus the Files-tab-bar rendering.

### 6.5 The "Add to list…" gesture — `AddToListMenu` minus stamping
A menu action on any entity (the row context-menu / the ⋯ affordance, and a
command-palette entry acting on the current selection). It presents a
filter-and-pick popover over `type=list` entities; picking `L` calls
`model.addMember(L, focusedEntity)`. This is Liv's `AddToListMenu.pick`
(`AddToListMenu.tsx:74-92`) **stripped of `applyListTemplate` /
`applyMetadataToKind`** — lotus keeps only "append the member" and **drops the
metadata stamping entirely** (that is the deferred clerk proposal, §8). A "＋
New list" row at the foot of the popover creates-then-adds. The inspector's
`related` cell stays **read-only** (`Window.swift:2537-2549` — the reference
picker is still deferred); membership is edited through this gesture and the
detail-pane ✕, not the inspector.

## 7 · Slice plan (each an independent commit: build → tests → review → fix)

- **9a — the substrate + a read-only Lists surface.** *Rust/FFI:* seed
  `type=list` (tuple edit + its own idempotent additive pass, §4.1);
  `content::create_list` (§4.2); `content::add_member` / `content::remove_member`
  (§3.1); `lotus_create_list_at` + `lotus_add_cell_at` + `lotus_remove_cell_at`
  + their three `lotus.h` decls (§3.2, §4.3); `BoxModel.createList` /
  `addMember` / `removeMember` (§3.3, §4.3). *Shell:* `case lists` on `Surface`
  + router arm; `ListsView` (list of lists, +New list) + `ListDetailView`
  (**read-only** ordered members) modeled on LibraryView; the sidebar Lists
  section (§6.4). *Tests:* the seed creates exactly one `list` type, is
  idempotent across two opens, **and lands on a box that already has `due`**
  (the guard-bypass is the load-bearing assertion, as in P8); `create_list`
  makes one `type=list` entity named-at-birth with **no `related`** cell;
  `add_member` appends exactly one `related` cell (and is a silent no-op when
  the member is already present — assert the log does not grow); `remove_member`
  removes exactly that one cell **and the member entity still exists**
  (tagging-not-containment); FFI round-trip (`lotus_create_list_at` →
  `lotus_add_cell_at` ×2 → snapshot shows a `list`-kind entity whose two
  `related` cells carry the members' `refTarget` in insertion order).

- **9b — the add-to-list gesture, the remove-✕, create-list UI polish.**
  *Shell only, no Rust:* the "Add to list…" menu on entities (filter-and-pick
  popover, +New-list-and-add row, §6.5), stripped of any template stamping;
  wire the command-palette entry acting on the current selection; the hover-✕ on
  detail-pane member rows → `removeMember`; confirm the sidebar/ListsView
  +New-list inline input round-trips. *Tests* (shell/manual + a Rust round-trip
  for the writes): adding entity `E` to list `L` shows `E` in `L`'s detail pane
  and `E` still opens/edits normally elsewhere (not consumed); adding `E` twice
  is a no-op (one member row); the ✕ removes `E` from `L` and `E` survives in
  Everything; a list with members in a known insertion order renders them in
  that order.

- **9c — query-lists (feature-map #28) OR fold/defer.** A `type=list` entity
  carrying a `props::QUERY` text cell instead of `related` cells; `ListDetailView`
  detects the QUERY cell and renders `search::run(store, &search::parse(q))` as
  its (live, read-only) members; a "New saved search" birth path. **This slice
  is severable** — if #28 ships on its own track, fold query-lists into it and
  P9 ends at 9b with manual lists complete; the lens/sidebar already handle both
  because only the member *source* differs (`related` cells vs `run(query)`).

## 8 · Deferred (named, not built in P9)

Liv's **template-mode member stamping** (fill / overwrite / tag-only over
area/project/tier/calendar + union tags/people, `lists.ts:419-451`) — in lotus
this becomes a **clerk PROPOSAL on join** (a member joining a list *proposes*
the list's metadata onto itself, quarantined, never a silent fold), **severable
and deferred** · `.base` files and mirrored `.md` derived files · the 3-way
List/Keep/Base member view and Bases-scan-from-vault · **member reordering by
drag** (v1 = insertion/log order; reordering needs either a per-membership order
cell — heavier — or a remove+re-add sequence, flagged in §5) · the inspector's
**reference/entity picker** for `related` (still deferred, `Window.swift:2537`)
· **workspace-scoping** of lists (Liv's `getWorkspaceLists`; lotus v1 is
vault-wide like Tasks/Library) · Data-view / Kanban list **renderers** · **query
lists** if #28 ships as its own slice (§7, 9c).