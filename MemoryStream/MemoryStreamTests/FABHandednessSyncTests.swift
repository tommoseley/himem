import Testing
@testable import HiMem

/// Money tests for `FABHandednessSync.reconcile` — the pure decision that
/// mirrors the Left-Handed FAB preference between UserDefaults (local, what
/// `@AppStorage` reads) and iCloud KVS (cross-device). iCloud is the synced
/// truth, so a present remote wins; a value that exists only locally is pushed
/// up; matching values are a no-op (which is what breaks the echo loop between
/// the two observers).
struct FABHandednessSyncTests {

    private typealias Plan = FABHandednessSync.Plan

    /// Fresh install: iCloud already holds the pref, local has nothing → adopt
    /// iCloud locally, don't write remote.
    @Test func freshInstall_adoptsRemote() {
        #expect(FABHandednessSync.reconcile(localExists: false, localValue: false,
                                            remoteExists: true, remoteValue: true)
                == Plan(writeLocal: true, writeRemote: nil))
        #expect(FABHandednessSync.reconcile(localExists: false, localValue: false,
                                            remoteExists: true, remoteValue: false)
                == Plan(writeLocal: false, writeRemote: nil))
    }

    /// Both present and differing → iCloud (the synced truth) wins locally.
    @Test func conflict_remoteWins() {
        #expect(FABHandednessSync.reconcile(localExists: true, localValue: false,
                                            remoteExists: true, remoteValue: true)
                == Plan(writeLocal: true, writeRemote: nil))
        #expect(FABHandednessSync.reconcile(localExists: true, localValue: true,
                                            remoteExists: true, remoteValue: false)
                == Plan(writeLocal: false, writeRemote: nil))
    }

    /// Both present and equal → nothing to write (this no-op is the loop guard).
    @Test func equal_isNoOp() {
        #expect(FABHandednessSync.reconcile(localExists: true, localValue: true,
                                            remoteExists: true, remoteValue: true)
                == Plan(writeLocal: nil, writeRemote: nil))
        #expect(FABHandednessSync.reconcile(localExists: true, localValue: false,
                                            remoteExists: true, remoteValue: false)
                == Plan(writeLocal: nil, writeRemote: nil))
    }

    /// A value set on this device before iCloud had one → push it up so other
    /// devices adopt it.
    @Test func localOnly_pushesToRemote() {
        #expect(FABHandednessSync.reconcile(localExists: true, localValue: true,
                                            remoteExists: false, remoteValue: false)
                == Plan(writeLocal: nil, writeRemote: true))
    }

    /// Nothing anywhere → leave the app default in place.
    @Test func neither_isNoOp() {
        #expect(FABHandednessSync.reconcile(localExists: false, localValue: false,
                                            remoteExists: false, remoteValue: false)
                == Plan(writeLocal: nil, writeRemote: nil))
    }
}
