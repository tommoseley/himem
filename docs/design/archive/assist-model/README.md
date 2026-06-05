# archive · assist-model

Retired **June 5 2026** when the **Capture · Connect · Create** pricing
direction superseded the assist-quota framing. The assist-quota model
metered AI usage as discrete "assists" with starter allotments, monthly
caps, exhausted states, and pack purchases. It was replaced by an
outcome-named tier model (Free / Plus / Studio) where the seam is
"manual + on-device vs. automatic + frontier" — no counters, no
exhausted state, no pack-purchase flow.

## Live replacements

- **Pricing direction:** `../../Pricing model · Capture-Connect-Create.md`
- **Pricing canvas:** `../../HiMem · Pricing.html` (+ `pricing-screens.jsx`,
  `pricing-screens-lifecycle.jsx`, `pricing-screens-upgrade.jsx`)
- **AI Organize:** `../../AI Organize · spec.md` — Honest-Label rules
  unchanged; tiering rewritten around manual/on-device (Free) vs.
  automatic/frontier (Plus).

## Files archived here

| File | Was | Notes |
|---|---|---|
| `Open work · pricing flow.md` | Open-questions doc for the assist-quota model. | Superseded by §7 of the new `Pricing model · Capture-Connect-Create.md`. |
| `pricing-screens-free-flow.jsx` | Free-tier flow with starter assists + paywall transitions. | Free is now uncapped on-device; no paywall surface. |
| `pricing-screens-memory-detail.jsx` | Memory Detail with assist-counter chrome. | Replaced by the chip-as-review-state model in `pricing-screens-lifecycle.jsx`. |
| `pricing-screens-modals.jsx` | Exhausted-state modals, pack-purchase sheets. | Exhausted state doesn't exist in the new model; pack-purchase retired. |
| `pricing-screens-reorganize.jsx` | Reorganize flow with assist debit. | Reorganize is now free + manual on Free, automatic on Plus. |
| `pricing-screens-settings.jsx` | Tier/Settings with monthly-used counters, pack balance, Founders tile. | Counters retired; tier UI rewritten in the new pricing canvas. |
| `pricing-screens-tier-states.jsx` | Tier-aware state variants (starter / monthly / exhausted). | Variant axis collapsed — no metered states in the new model. |

## Why kept

Historical reference and prior-art audit. Some component patterns
(modal shells, settings rows, tier-tile typography) may still be reused.
Voice and copy in these files reflect the retired metered framing —
**do not copy strings**; refer to the live canvas and the new pricing
doc instead.

**Do not load any file from this folder in a live design canvas.**
