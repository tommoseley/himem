# Release Gates

Hand-tracked gates that block specific distribution milestones. Items here are not on a ticket-tracker — they're things that must be verified before the gate is opened, and they're easy to forget between milestones unless someone writes them down.

Gate list is append-only-while-open and pruned-when-closed. When a gate is satisfied, move the entry to **Closed** with the date and the commit/PR that satisfied it.

---

## Open Gates

### Production CloudKit schema deploy

Required before **every** TestFlight / App Store upload that includes a Core Data schema change. Per `CLAUDE.md` "CloudKit Schema Changes":

| # | Gate | Why |
|---|------|-----|
| 2 | After any synced-entity attribute or relationship change, deploy the schema in CloudKit Dashboard from Development → Production *before* the next archive/upload | Outbound sync silently breaks in TestFlight/Production otherwise (auto-publish only happens for Development under `#if DEBUG`) |

This gate fires on every release, not just the first.

---

## Closed Gates

| # | Gate | Closed | Resolution |
|---|------|--------|------------|
| 1 | `FragmentMigration.runIfNeeded` deferred until CloudKit initial import settles | 2026-05-09 | `LaunchScreenView` gates on `eventChangedNotification` `.import .succeeded` with 3s safety timeout fallback. Migration runs on a background context. 6/6 clean test runs. See [2026-05-09-fragment-migration-cloudkit-race.md](issues/2026-05-09-fragment-migration-cloudkit-race.md). |

---

_Gates derived from this session and from CLAUDE.md governance. Add a new row whenever a known issue is **mitigated** but **not durably fixed** and a specific milestone is what triggers the bite._
