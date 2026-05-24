# HiMem Pricing Model

**Status:** Locked 2026-05-15
**Owner:** Tom

## Philosophy

HiMem is trust-first. Free is a real product, not a trial. Memories belong to the user, regardless of tier. AI is an organizational helper, not the product itself. Subscription pressure is calibrated to natural usage growth, not artificial gates.

## Tiers

### Free — Save & Organize
- Unlimited memory capture (text, voice, photo, watch)
- Unlimited local + CloudKit storage
- Manual organization
- Watch companion included
- **3 starter AI assists** (one-time grant on first use, never refills)
- **1 project**
- Can purchase AI Packs

Free is the proper product. Users who never subscribe should still find HiMem useful for life.

### Plus — Add AI Organization & More Projects
- **$4.99/month** or **$39.99/year**
- Everything in Free, plus:
- **50 AI assists/month** (resets monthly)
- **Unlimited projects**
- AI-powered memory organization (auto-runs; magic-by-default)
- Future Plus features as they ship
- Can purchase AI Packs on top of monthly allowance

**Copy rule:** never describe Plus as just "features." Use *"Plus AI and unlimited projects"* or *"Future Plus features"*. "Features" alone is vague and erodes trust.

### Studio — Create (post-MVP)
- Multi-memory synthesis
- Advanced Project tools
- Higher monthly AI allowance (TBD, target ~150–200/month)
- Pricing TBD

### Founders Lifetime — Early Supporter
- **$99 one-time** · hard cap **250 users**
- Includes HiMem Plus for life
- **50 AI assists/month** (same as Plus)
- **+100 AI assist bonus at purchase** (one-time, grants into pack balance, never expires)
- **TestFlight access** — builds before they ship
- **Selected early-access feature flags** — Founders get to try selected experimental features before general release (not every experiment, and not forever)
- Can purchase AI Packs
- Studio NOT included

**Copy rule:** the perk is *"Selected early-access feature flags,"* not *"early-access feature flags."* The word *selected* keeps the door open for some experiments to stay internal or go to broader beta without Founders feeling promised.

### Supporter — Voluntary Sustain
- **$2.99/month** or **$29.99/year** (two months free, matches Plus yearly pattern)
- No feature unlocks
- Surfaces only after 1 month of use + ≥10 memories saved
- Never appears in onboarding or upgrade flow — Settings-only link
- Single price (not a tier ladder) — the amount is private; all Supporters get the same small heart in Settings

### AI Packs (Consumable)
- **20 assists — $4.99** ($0.25/assist)
- **100 assists — $19.99** ($0.20/assist, 20% bulk discount)
- Never expire
- Stack on top of any tier's monthly allowance
- Drawn from after monthly allowance exhausted

## Effective Rates

| Path | Cost | $/assist |
|---|---|---|
| AI Pack 20 | $4.99 | $0.25 |
| AI Pack 100 | $19.99 | $0.20 |
| **Plus monthly** | $4.99 + 50 | **$0.10** |
| Plus yearly | $39.99 + 600 | $0.067 |

Plus subscription is **2.5× better per-assist** than the 20-pack at the same monthly price. Forcing function: anyone who buys two 20-packs should obviously be on Plus.

## Fair-Use

The monthly allowance IS the fair-use limit for included AI. There is no hidden ceiling above it. Once monthly assists are exhausted, the user buys Packs or waits for the monthly reset.

**Soft warning** at 75% of monthly:
> You've used 38 of your 50 AI assists this month. Resets [date].

**Hard message** at 100%:
> Your monthly AI organization included with Plus has been used. You can wait until [date] for it to reset, or add more if you want HiMem to keep helping right now.
> [Add 20 assists — $4.99] [Add 100 assists — $19.99]

Framed as "more than included," not "additional payment."

## Storage Architecture

### AI Assist Counter — CloudKit private DB

- **Record type:** `AssistBalance`
- **Fields:**
  - `monthlyUsed: Int` (resets on `monthlyResetDate`)
  - `packBalance: Int` (Pack purchases + Founders bonus, never expires)
  - `monthlyResetDate: Date`
  - `lastUpdated: Date`
- **Reconciliation on launch:** if `monthlyResetDate < now`, reset `monthlyUsed = 0` and roll the date forward
- **StoreKit reconciliation:** total Pack assists purchased (from StoreKit history) minus total used = current Pack balance. Rebuild path for users who reinstall after data loss.
- **Family sharing (when added):** per-seat. Each family member's Apple ID has its own private DB record and own 50/month allowance. Pooled sharing would require shared CloudKit zones + conflict resolution — defer.

### Project Counter

Project count is derived from Core Data (number of `Project` entities owned by user). The Free 1-project cap is enforced at project creation, not stored separately.

## Behavior by Tier

| Tier | Free starter | Monthly | Pack | Projects | AI mode |
|---|---|---|---|---|---|
| Free | 3 (one-time) | 0 | yes | 1 cap | button-driven (each consume tap explicit) |
| Plus | granted but moot | 50 | yes | unlimited | auto-run (magic by default) |
| Founders | granted but moot | 50 | yes + 100 bonus | unlimited | auto-run |
| Studio | granted but moot | TBD | yes | unlimited | auto-run |

The 3 starter assists for Free users go into `packBalance` on first launch (granted once, persisted in CloudKit, no refill).

## Upgrade Prompt Trigger

> 3 starter assists used AND ≥5 memories saved

When both conditions met, surface a one-time upgrade prompt. **There is no free trial of Plus.** AI economics don't support granting 50 assists to non-paying users — Plus would lose money on every trial. Instead the prompt offers two paid paths so the user picks their commitment level:

- **Continue with a 20-pack — $4.99** (low-friction, keep using AI without subscribing)
- **Subscribe to Plus — $4.99/mo or $39.99/yr** (50 assists/mo + unlimited projects + auto-org)

Decline → user keeps Free as-is, can buy Packs anytime from Settings. Prompt fires once per install; not nagged repeatedly.

## SKUs at Launch

App Store Connect products:

| ID | Type | Group |
|---|---|---|
| `plus_monthly` | Auto-renewable subscription | Plus |
| `plus_yearly` | Auto-renewable subscription | Plus |
| `founders_lifetime` | Non-consumable (hard-capped at 250) | — |
| `supporter_monthly` | Auto-renewable subscription | Supporter |
| `supporter_yearly` | Auto-renewable subscription | Supporter |
| `assist_pack_20` | Consumable | — |
| `assist_pack_100` | Consumable | — |

Seven products at launch. Studio added post-MVP into the Plus subscription group as an upgrade.

## Founders Cap Enforcement

Hard cap of 250 cannot be enforced purely client-side. Options:
- CloudKit public DB counter incremented atomically per purchase (preferred — no infra)
- Server-side counter with App Store Server Notifications webhook (more robust, more infra)

Recommendation: CloudKit public DB with `FoundersCounter` record + StoreKit purchase validation. If counter ≥ 250 at validation time, offer refund + suggest Plus subscription instead.

## Surfacing Rules

- **Onboarding:** Free is default. No upgrade ask.
- **Upgrade prompt:** appears once when trigger fires (3 starter assists used + 5 memories). Offers 20-pack or Plus subscription. No free trial.
- **Upgrade flow (Settings):** Plus monthly/yearly + Founders Lifetime (while cap holds) + AI Packs.
- **Supporter:** never in onboarding or upgrade. Only via Settings → "Support HiMem" link, surfaced post-trust (1 month + 10 memories).
- **AI Pack offer surfaces:** at fair-use hit screen + Settings → "Add AI assists."
- **Project cap message** (Free user trying to create 2nd project):
  > Free includes 1 project. Plus includes unlimited projects.
  > [Upgrade to Plus] [Maybe later]

## Trust Positioning

- "Your memories are always yours" — never gated
- Free is genuinely usable forever, not a trial
- Cancel = AI org features lapse, capture/storage continue, project list compresses back to 1 active (oldest preserved, newer projects become read-only views)
- No advertising. Ever. Anywhere.

## Open / Deferred

- Studio feature set + pricing
- Family sharing assist-pooling model (per-seat for v1)
- Cancel-Plus → re-Free transition UX (project read-only view design)
- Watch complication settings (out of pricing scope)
