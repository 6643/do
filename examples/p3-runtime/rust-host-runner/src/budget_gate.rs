use std::sync::{Arc, Mutex};

#[derive(Debug)]
struct State {
    limit: u64,
    used: u64,
}

#[derive(Clone, Debug)]
pub struct BudgetGate {
    state: Arc<Mutex<State>>,
}

#[derive(Debug)]
pub struct BudgetPermit {
    state: Arc<Mutex<State>>,
    bytes: u64,
    active: bool,
}

impl BudgetGate {
    pub fn new(limit: u64) -> Self {
        Self {
            state: Arc::new(Mutex::new(State { limit, used: 0 })),
        }
    }

    pub fn try_acquire(&self, bytes: u64) -> Option<BudgetPermit> {
        let mut state = self.state.lock().ok()?;
        let next = state.used.checked_add(bytes)?;
        if next > state.limit {
            return None;
        }
        state.used = next;
        Some(BudgetPermit {
            state: Arc::clone(&self.state),
            bytes,
            active: true,
        })
    }

    pub fn used(&self) -> u64 {
        self.state
            .lock()
            .map(|state| state.used)
            .unwrap_or(u64::MAX)
    }
}

impl Drop for BudgetPermit {
    fn drop(&mut self) {
        if !self.active {
            return;
        }
        if let Ok(mut state) = self.state.lock() {
            assert!(state.used >= self.bytes, "budget permit release underflow");
            state.used -= self.bytes;
        }
        self.active = false;
    }
}

#[cfg(test)]
mod tests {
    use super::BudgetGate;

    #[test]
    fn rejects_over_limit_without_mutating() {
        let gate = BudgetGate::new(20);
        let permit = gate.try_acquire(20).expect("initial reservation");
        assert!(gate.try_acquire(1).is_none());
        assert_eq!(gate.used(), 20);
        drop(permit);
        assert_eq!(gate.used(), 0);
    }

    #[test]
    fn rejects_checked_add_overflow_without_mutating() {
        let gate = BudgetGate::new(u64::MAX);
        let permit = gate.try_acquire(u64::MAX).expect("maximum reservation");
        assert!(gate.try_acquire(1).is_none());
        assert_eq!(gate.used(), u64::MAX);
        drop(permit);
        assert_eq!(gate.used(), 0);
    }
}
