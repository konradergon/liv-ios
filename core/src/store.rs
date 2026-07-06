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
