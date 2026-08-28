use std::collections::HashMap;
use std::time::{SystemTime, UNIX_EPOCH};

use crate::command::{Author, Command, Proposal, Transaction};
use crate::entity::{props, Cell, Entity};
use crate::value::{Id, NONE};

/// Who points, through which property (or richtext span).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Backlink {
    pub source: Id,
    pub property: Id,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum StoreError {
    NoSuchEntity(Id),
    AlreadyExists(Id),
    AlreadyTrashed(Id),
    NotTrashed(Id),
    NoSuchCell { entity: Id, property: Id },
    RedirectMismatch { entity: Id, expected: Id },
    MergeWithSelf(Id),
    NothingToUndo,
    NothingToRedo,
    NoSuchProposal(usize),
}

impl std::fmt::Display for StoreError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{self:?}")
    }
}

impl std::error::Error for StoreError {}

/// Materialized state. On disk this will be a replay of the log
/// (milestone 2); in memory it is the log's consequence.
#[derive(Debug, Default)]
pub struct Store {
    entities: HashMap<Id, Entity>,
    /// Merged-away id -> survivor; chased at read time.
    redirects: HashMap<Id, Id>,
    next_id: Id,

    /// Derived — rebuildable from truth at any time.
    backlinks: HashMap<Id, Vec<Backlink>>,
    /// Who carries a NAME cell with exactly this text — derived, like
    /// backlinks. Name lookup used to be a full-store query; with ~197
    /// resolution sites above the core, that shape made the snapshot
    /// quadratic twice before this index existed (T1, owner 2026-08-09).
    /// Unfiltered on purpose: trash and plumbing are read-time concerns.
    names: HashMap<String, Vec<Id>>,
    /// The same index keyed by a LOWERCASED name.
    ///
    /// `named` answers "who claims this name, exactly" and several callers
    /// depend on that being exact. But a person typing `Area:Work` into a
    /// workspace query means the property called `area`, and an exact map
    /// answered nothing — the token silently demoted to free text and the
    /// screen emptied with no error anywhere (owner, 2026-08-27). A second
    /// index costs one map entry per named entity and keeps the lookup
    /// O(1); scanning every entity on a miss would put a full pass on the
    /// read path, which standing rule 2 exists to stop.
    folded: HashMap<String, Vec<Id>>,
    /// The last transaction to touch each entity — derived, like the three
    /// above, and maintained on append for the same reason (T3, owner
    /// 2026-08-22). It was recomputed by walking the whole history on
    /// every call, and `search` calls it once per query: 99 ms per
    /// search at 500,000 entities, identical every time.
    recency: HashMap<Id, u64>,

    /// The disk truth (milestone 2 makes this the append-only log on disk).
    /// Private, so the only way it grows is `commit`: append-only is a fact,
    /// not a rule. Read it through `history()`.
    history: Vec<Transaction>,
    /// An agent's drafts, quarantined beside history. Private so nothing
    /// lands except through `accept`. Read it through `pending()`.
    pending: Vec<Proposal>,
    /// Refusals, remembered beside the queue: proposers drop duplicates of
    /// anything pending or declined, so nothing asks again. In memory until
    /// milestone 7 persists the queue.
    declined: Vec<Proposal>,

    undo_stack: Vec<u64>,
    redo_stack: Vec<u64>,
}

impl Store {
    pub fn new() -> Self {
        Store {
            next_id: props::FIRST_USER_ID,
            ..Store::default()
        }
    }

    /// Reconstruct a store by replaying the log — the disk truth made live.
    /// Entities, next_id, redirects and backlinks all fall out of folding
    /// `apply` over the commands; the undo/redo cursors are rebuilt from the
    /// shape of the history, so undo survives a restart.
    ///
    /// The transactions must arrive in log order. A command that fails to
    /// apply means the log is inconsistent with itself — a corrupt log, not
    /// a normal outcome — so replay is fallible.
    pub fn replay(transactions: Vec<Transaction>) -> Result<Store, StoreError> {
        let mut store = Store::new();
        for tx in transactions {
            for command in &tx.commands {
                store.apply(command)?;
            }
            let commands = tx.commands.clone();
            store.note_recency(&commands, tx.seq);
            // Mirror the cursor bookkeeping that commit/undo/redo perform live.
            match tx.reverses {
                None => {
                    store.undo_stack.push(tx.seq);
                    store.redo_stack.clear();
                }
                Some(target) => {
                    if store.undo_stack.last() == Some(&target) {
                        store.undo_stack.pop();
                        store.redo_stack.push(tx.seq);
                    } else if store.redo_stack.last() == Some(&target) {
                        store.redo_stack.pop();
                        store.undo_stack.push(tx.seq);
                    }
                    // A reverse whose target is at neither cursor cannot occur
                    // in a log this store wrote; leave the cursors untouched.
                }
            }
            store.history.push(tx);
        }
        Ok(store)
    }

    /// Monotonic, never reused — even when the draft holding it is discarded.
    pub fn allocate_id(&mut self) -> Id {
        let id = self.next_id;
        self.next_id += 1;
        id
    }

    /// Chase redirects until an identifier that stands for itself.
    /// Permanent means identifiers always resolve.
    pub fn resolve(&self, id: Id) -> Id {
        let mut current = id;
        let mut steps = 0;
        while let Some(&next) = self.redirects.get(&current) {
            current = next;
            steps += 1;
            if steps > self.redirects.len() {
                break; // a cycle would be a bug, but reads never hang
            }
        }
        current
    }

    pub fn get(&self, id: Id) -> Option<&Entity> {
        self.entities.get(&self.resolve(id))
    }

    /// Read-only iteration over every entity, in no particular order.
    /// The query layer above filters and sorts; an index replaces this
    /// scan only when a measured query hurts.
    pub fn entities(&self) -> impl Iterator<Item = &Entity> {
        self.entities.values()
    }

    /// The entities a USER can see: not trashed, not plumbing. Almost
    /// every projection wants exactly this, and each used to write the
    /// two filters by hand — forgetting the plumbing one once let the
    /// starter types leak into Everything as ordinary rows and damaged
    /// 9 of the owner's 20 early boxes (T4, 2026-08-09). Projections
    /// that genuinely want plumbing say so by using `entities()`.
    pub fn user_entities(&self) -> impl Iterator<Item = &Entity> {
        self.entities.values().filter(|e| {
            !e.trashed && !e.has(props::WORKING, &crate::value::Value::Bool(true))
        })
    }

    /// Every entity carrying a NAME cell with exactly this text.
    /// Unfiltered: the caller decides about trash, plumbing and kinds —
    /// the index only answers "who claims this name", in id order.
    pub fn named(&self, name: &str) -> &[Id] {
        self.names.get(name).map(Vec::as_slice).unwrap_or(&[])
    }

    /// Every entity whose NAME matches this text ignoring case. Use it
    /// where a PERSON typed the name — a query, a picker — and `named`
    /// where the app did.
    pub fn named_folded(&self, name: &str) -> &[Id] {
        self.folded.get(&name.to_lowercase()).map(Vec::as_slice).unwrap_or(&[])
    }

    /// Everything pointing at this entity, through any property or span —
    /// including references that arrive via redirects.
    pub fn backlinks(&self, target: Id) -> Vec<Backlink> {
        let resolved = self.resolve(target);
        let mut result = Vec::new();
        if let Some(links) = self.backlinks.get(&resolved) {
            result.extend_from_slice(links);
        }
        for &from in self.redirects.keys() {
            if from != resolved && self.resolve(from) == resolved {
                if let Some(links) = self.backlinks.get(&from) {
                    result.extend_from_slice(links);
                }
            }
        }
        result
    }

    /// The timestamp of the last transaction that touched the entity,
    /// read from history, never written as a cell.
    pub fn modified(&self, id: Id) -> Option<i64> {
        let resolved = self.resolve(id);
        self.history
            .iter()
            .rev()
            .find(|tx| {
                tx.commands
                    .iter()
                    .any(|c| self.resolve(c.entity()) == resolved)
            })
            .map(|tx| tx.time)
    }

    /// A monotonic recency key per entity: the seq of the newest transaction
    /// that touched it, in one O(history) pass. The empty-query recents sort
    /// (bp3 a10, "jump back to where you were") needs a monotonic signal —
    /// wall-clock `modified` ties across rapid edits. Later transactions
    /// overwrite earlier ones for the same (redirect-resolved) entity.
    pub fn recency(&self) -> &HashMap<Id, u64> {
        &self.recency
    }

    /// Fold one landed transaction into `recency`. Called from the two
    /// places a transaction joins history — `commit_with` and `replay` —
    /// and nowhere else.
    ///
    /// Resolved AFTER the commands are applied, which is what the old
    /// read-time walk did for the transaction that created a redirect.
    /// A merge trashes the loser before redirecting it, and every reader
    /// of this map filters trashed entities, so the loser's own older
    /// entry is unreachable rather than wrong.
    fn note_recency(&mut self, commands: &[Command], seq: u64) {
        // A REDIRECT MOVES AN ENTITY'S PAST WITH IT. The walk this
        // replaces resolved at READ time, so every entry an id had ever
        // collected followed it to its target. Maintained, that has to
        // happen once, here — otherwise a merged-away id keeps a stale
        // entry and the two disagree. Undoing the redirect converges
        // again, because the undo transaction touches both ids and is by
        // definition the newest thing that did.
        for command in commands {
            if let Command::Redirect { entity, .. } = command {
                if let Some(had) = self.recency.remove(entity) {
                    let target = self.resolve(*entity);
                    if target != *entity {
                        let slot = self.recency.entry(target).or_insert(0);
                        *slot = (*slot).max(had);
                    }
                }
            }
        }
        for command in commands {
            let id = self.resolve(command.entity());
            self.recency.insert(id, seq);
        }
    }

    /// The append-only log, read-only. Provenance and undo history live here.
    pub fn history(&self) -> &[Transaction] {
        &self.history
    }

    /// The proposal queue, read-only. Accept or reject to act on it.
    pub fn pending(&self) -> &[Proposal] {
        &self.pending
    }

    /// Every refusal, read-only. Fed to proposers with the gazetteer.
    pub fn declined(&self) -> &[Proposal] {
        &self.declined
    }

    /// Reload remembered refusals at open — persistence's door, not a
    /// user action. Refusals are user intent: unlike pending proposals
    /// they cannot be re-derived, so they ride a sidecar, not the sweep.
    pub(crate) fn restore_declined(&mut self, proposals: Vec<Proposal>) {
        self.declined.extend(proposals);
    }

    /// One user action, one undo step, one author.
    pub fn commit(
        &mut self,
        commands: Vec<Command>,
        label: impl Into<String>,
        author: Author,
    ) -> Result<u64, StoreError> {
        let seq = self.commit_with(commands, label.into(), author, None)?;
        self.undo_stack.push(seq);
        self.redo_stack.clear();
        Ok(seq)
    }

    /// Undo appends. Reversing a transaction writes its inverse;
    /// the truth is never rewritten, and history shows both.
    pub fn undo(&mut self, author: Author) -> Result<u64, StoreError> {
        let target = self.undo_stack.pop().ok_or(StoreError::NothingToUndo)?;
        match self.append_inverse(target, author) {
            Ok(seq) => {
                self.redo_stack.push(seq);
                Ok(seq)
            }
            Err(e) => {
                self.undo_stack.push(target);
                Err(e)
            }
        }
    }

    /// The inverse of the inverse, appended again.
    pub fn redo(&mut self, author: Author) -> Result<u64, StoreError> {
        let target = self.redo_stack.pop().ok_or(StoreError::NothingToRedo)?;
        match self.append_inverse(target, author) {
            Ok(seq) => {
                self.undo_stack.push(seq);
                Ok(seq)
            }
            Err(e) => {
                self.redo_stack.push(target);
                Err(e)
            }
        }
    }

    /// Proposals gate entry: automation never mutates without confirmation.
    pub fn propose(&mut self, proposal: Proposal) {
        self.pending.push(proposal);
    }

    /// One keystroke of consent. The transaction records the proposer
    /// as its author, so history answers for it forever.
    pub fn accept(&mut self, index: usize) -> Result<u64, StoreError> {
        if index >= self.pending.len() {
            return Err(StoreError::NoSuchProposal(index));
        }
        let proposal = self.pending.remove(index);
        match self.commit(proposal.commands.clone(), proposal.label.clone(), proposal.author.clone())
        {
            Ok(seq) => Ok(seq),
            Err(e) => {
                self.pending.insert(index, proposal);
                Err(e)
            }
        }
    }

    /// Declining is not forgetting: the refusal moves beside the queue so
    /// proposers can drop duplicates of it. Nothing asks again.
    pub fn reject(&mut self, index: usize) -> Result<&Proposal, StoreError> {
        if index >= self.pending.len() {
            return Err(StoreError::NoSuchProposal(index));
        }
        let refused = self.pending.remove(index);
        self.declined.push(refused);
        Ok(self.declined.last().expect("just pushed"))
    }

    /// Retracting is the system noticing its own proposal went stale —
    /// not the user declining it. The proposal vanishes without a refusal
    /// record, so a proposer is free to re-derive a fresh one.
    pub fn retract(&mut self, index: usize) -> Result<Proposal, StoreError> {
        if index >= self.pending.len() {
            return Err(StoreError::NoSuchProposal(index));
        }
        Ok(self.pending.remove(index))
    }

    /// Merge is a first-class action, not a primitive: one transaction of
    /// ordinary commands. Never rewrites another entity — inbound references
    /// resolve through the redirect at read time.
    ///
    /// Conflict resolution is the caller's: pass the outcome as extra
    /// commands, recorded like everything else.
    pub fn merge(
        &mut self,
        survivor: Id,
        loser: Id,
        resolutions: Vec<Command>,
        author: Author,
    ) -> Result<u64, StoreError> {
        let survivor = self.resolve(survivor);
        let loser = self.resolve(loser);
        if survivor == loser {
            return Err(StoreError::MergeWithSelf(survivor));
        }
        let surviving = self
            .entities
            .get(&survivor)
            .ok_or(StoreError::NoSuchEntity(survivor))?;
        let losing = self
            .entities
            .get(&loser)
            .ok_or(StoreError::NoSuchEntity(loser))?;

        let mut commands = Vec::new();
        let mut planned: Vec<&Cell> = Vec::new();
        for cell in &losing.cells {
            let already = surviving.has(cell.property, &cell.value)
                || planned.iter().any(|c| **c == *cell);
            if !already {
                planned.push(cell);
                commands.push(Command::AddCell {
                    entity: survivor,
                    cell: cell.clone(),
                });
            }
        }
        commands.extend(resolutions);
        if !losing.trashed {
            commands.push(Command::Trash { entity: loser });
        }
        commands.push(Command::Redirect {
            entity: loser,
            to: survivor,
            before: NONE,
        });

        self.commit(commands, "merge", author)
    }

    // ---- internals ----

    fn append_inverse(&mut self, target: u64, author: Author) -> Result<u64, StoreError> {
        let tx = &self.history[target as usize];
        let label = format!("undo: {}", tx.label);
        let commands: Vec<Command> = tx.commands.iter().rev().map(Command::inverse).collect();
        self.commit_with(commands, label, author, Some(target))
    }

    fn commit_with(
        &mut self,
        commands: Vec<Command>,
        label: String,
        author: Author,
        reverses: Option<u64>,
    ) -> Result<u64, StoreError> {
        // Apply in order; on failure reverse the applied prefix,
        // so a transaction lands whole or not at all.
        let mut applied: Vec<Command> = Vec::new();
        for command in &commands {
            if let Err(e) = self.apply(command) {
                for done in applied.iter().rev() {
                    self.unapply(done);
                }
                return Err(e);
            }
            applied.push(command.clone());
        }

        let seq = self.history.len() as u64;
        self.note_recency(&commands, seq);
        self.history.push(Transaction {
            seq,
            commands,
            label,
            author,
            time: now(),
            reverses,
        });
        Ok(seq)
    }

    /// Physically revert a command from a transaction that failed to land.
    /// Different from Command::inverse: a failed transaction is not in
    /// history, so the state must be as if it never happened — a Create
    /// is removed outright, not trashed. (The allocated id stays burned;
    /// identifiers are never reused.)
    fn unapply(&mut self, command: &Command) {
        match command {
            Command::Create { entity } => {
                self.entities.remove(entity);
            }
            _ => {
                self.apply(&command.inverse())
                    .expect("reversing an applied command cannot fail");
            }
        }
    }

    fn apply(&mut self, command: &Command) -> Result<(), StoreError> {
        match command {
            Command::Create { entity } => {
                if *entity == NONE || self.entities.contains_key(entity) {
                    return Err(StoreError::AlreadyExists(*entity));
                }
                if *entity >= self.next_id {
                    self.next_id = *entity + 1;
                }
                self.entities.insert(*entity, Entity::new(*entity));
                Ok(())
            }
            Command::Trash { entity } => {
                let e = self
                    .entities
                    .get_mut(entity)
                    .ok_or(StoreError::NoSuchEntity(*entity))?;
                if e.trashed {
                    return Err(StoreError::AlreadyTrashed(*entity));
                }
                e.trashed = true;
                Ok(())
            }
            Command::Restore { entity } => {
                let e = self
                    .entities
                    .get_mut(entity)
                    .ok_or(StoreError::NoSuchEntity(*entity))?;
                if !e.trashed {
                    return Err(StoreError::NotTrashed(*entity));
                }
                e.trashed = false;
                Ok(())
            }
            Command::AddCell { entity, cell } => {
                let e = self
                    .entities
                    .get_mut(entity)
                    .ok_or(StoreError::NoSuchEntity(*entity))?;
                e.cells.push(cell.clone());
                for target in cell.value.targets() {
                    self.backlinks.entry(target).or_default().push(Backlink {
                        source: *entity,
                        property: cell.property,
                    });
                }
                if cell.property == props::NAME {
                    if let crate::value::Value::Text(name) = &cell.value {
                        self.names.entry(name.clone()).or_default().push(*entity);
                        self.folded
                            .entry(name.to_lowercase())
                            .or_default()
                            .push(*entity);
                    }
                }
                Ok(())
            }
            Command::RemoveCell { entity, cell } => {
                let e = self
                    .entities
                    .get_mut(entity)
                    .ok_or(StoreError::NoSuchEntity(*entity))?;
                // Removal depends on per-kind value equality.
                let position = e.cells.iter().position(|c| c == cell).ok_or(
                    StoreError::NoSuchCell {
                        entity: *entity,
                        property: cell.property,
                    },
                )?;
                let removed = e.cells.remove(position);
                for target in removed.value.targets() {
                    if let Some(links) = self.backlinks.get_mut(&target) {
                        let link = Backlink {
                            source: *entity,
                            property: removed.property,
                        };
                        if let Some(i) = links.iter().position(|l| *l == link) {
                            links.remove(i);
                        }
                    }
                }
                if removed.property == props::NAME {
                    if let crate::value::Value::Text(name) = &removed.value {
                        if let Some(ids) = self.names.get_mut(name) {
                            if let Some(i) = ids.iter().position(|id| id == entity) {
                                ids.remove(i);
                            }
                        }
                        if let Some(ids) = self.folded.get_mut(&name.to_lowercase()) {
                            if let Some(i) = ids.iter().position(|id| id == entity) {
                                ids.remove(i);
                            }
                        }
                    }
                }
                Ok(())
            }
            Command::Redirect { entity, to, before } => {
                let current = self.redirects.get(entity).copied().unwrap_or(NONE);
                if current != *before {
                    return Err(StoreError::RedirectMismatch {
                        entity: *entity,
                        expected: *before,
                    });
                }
                if *to == NONE {
                    self.redirects.remove(entity);
                } else {
                    self.redirects.insert(*entity, *to);
                }
                Ok(())
            }
        }
    }
}

impl Command {
    fn entity(&self) -> Id {
        match self {
            Command::Create { entity }
            | Command::Trash { entity }
            | Command::Restore { entity }
            | Command::AddCell { entity, .. }
            | Command::RemoveCell { entity, .. }
            | Command::Redirect { entity, .. } => *entity,
        }
    }
}

fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}
