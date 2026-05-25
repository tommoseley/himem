# Crucible · topic palette spec

**Status:** locked, May 2026.

This document is the **cross-platform contract** between the design-system CSS, the JSX mockups, and the iOS Swift implementation. The slug strings below are the source of truth — every implementation (CSS variables, React/JSX inline styles, Core Data attribute, CloudKit field) must use these exact strings, byte-for-byte.

## The palette (16 swatches)

Inherited from the `topicPalette` array in `Himem Design System.html`. Each swatch has a paired light value and dark value, designed to read as "the same topic" across modes while sitting legibly on its respective paper.

| Slug | Hue family | Light hex | Dark hex |
|---|---|---|---|
| `ember` | red-orange | `#A53A13` | `#E5704A` |
| `terracotta` | brown-orange | `#8A4724` | `#C97B4F` |
| `clay` | dark terracotta-red | `#7A3A1C` | `#BC6B45` |
| `amber` | gold-brown | `#8A5A0E` | `#D49846` |
| `wheat` | warm tan-gold | `#7A5A10` | `#C9A04D` |
| `sage` | muted green | `#4A6A3A` | `#8AB672` |
| `moss` | green | `#3E6A2A` | `#7AB060` |
| `pine` | deep green | `#284A1F` | `#6AA452` |
| `sea` | dark teal | `#1F5C56` | `#5DA89E` |
| `tide` | blue | `#255A7A` | `#6CACD0` |
| `indigo` | dark blue-purple | `#2E3E7C` | `#7F8FD8` |
| `violet` | purple | `#4A3577` | `#9C85D0` |
| `plum` | red-purple | `#6B3567` | `#C58BBE` |
| `rose` | rose-red | `#8A3A3A` | `#D87B7B` |
| `sand` | warm tan-gray | `#5A4A30` | `#B89E72` |
| `slate` | cool gray | `#3B4452` | `#92A0B5` |

**Picker order** (the order users see swatches in the topic-color picker, also the array order used by the auto-hash):

```
ember   terracotta clay  amber       ← row 1 · warms
wheat   sage       moss  pine        ← row 2 · yellows & greens
sea     tide       indigo violet     ← row 3 · blues
plum    rose       sand   slate      ← row 4 · purples, roses, neutrals
```

## What slugs are NOT

- Not user-facing copy. The picker labels them ("Ember", "Terracotta", etc.) but those labels are presentation, not data.
- Not localizable. The slug is the durable identifier and must round-trip identical bytes through every layer.
- Not extensible at runtime. Adding a new color = adding a new slug to this spec, deploying both ends, migrating the schema.

## Design constraints I designed against

- **Light values come from the existing design-system bundle's `fg` column** (the `topicPalette` array in `Himem Design System.html`). They're saturated, dark colors tuned to read on cream paper as dot/text.
- **Dark values are designed to read on warm near-black** at the same dot size, targeting ~5:1 contrast. Pairs share a hue family — swapping modes shouldn't make a topic feel like a different topic.
- **No collisions with system semantics.** None of the swatches sit too close to `--accent` (ochre `#C64A1C`), `--ai` (blue `#1E5C8E`), `--danger` (red `#B8311E`), or the confirmed/warn semantics. Topics are labels, not state — they must not pull rank visually.

## Auto-hash: the default color rule

Every topic must always have a color. New topics get one assigned the moment they're named — no "now pick a color" modal blocks topic creation. Users can override anytime in topic settings.

```
slug = PALETTE[ djb2(normalize(topic.name)) mod 16 ]

normalize(s) = s.trim().toLowerCase()

djb2(s):
  h := 5381
  for each UTF-16 code unit c in s:
    h := (h * 33 + c) mod 2^32     // unsigned 32-bit wrap
  return h
```

### Implementation contracts

**JavaScript** (used by JSX mockups + iOS WebView previews):

```js
const TOPIC_PALETTE = [
  'ember','terracotta','clay','amber',
  'wheat','sage','moss','pine',
  'sea','tide','indigo','violet',
  'plum','rose','sand','slate',
];
function topicSlugFor(name) {
  const s = (name || '').trim().toLowerCase();
  let h = 5381 >>> 0;
  for (let i = 0; i < s.length; i++) {
    h = (Math.imul(h, 33) + s.charCodeAt(i)) >>> 0;
  }
  return TOPIC_PALETTE[h % TOPIC_PALETTE.length];
}
```

**Swift** (used by the shipping iOS app):

```swift
func topicSlug(for name: String) -> String {
    let s = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    var h: UInt32 = 5381
    for c in s.utf16 {                              // UTF-16 code units
        h = h &* 33 &+ UInt32(c)                    // unsigned 32-bit wrap
    }
    let palette = ["ember","terracotta","clay","amber",
                   "wheat","sage","moss","pine",
                   "sea","tide","indigo","violet",
                   "plum","rose","sand","slate"]
    return palette[Int(h % UInt32(palette.count))]
}
```

These two functions **must produce identical output** for any input string. If they ever diverge, that's a bug — a single topic would draw differently on watch (Swift-rendered) versus a phone WebView preview (JS-rendered).

### Test vectors (golden values)

If either implementation doesn't match these, the implementation is wrong:

| Input | Normalized | Slug |
|---|---|---|
| `"Garden"` | `garden` | `moss` |
| `"garden"` | `garden` | `moss` |
| `"  Garden  "` | `garden` | `moss` |
| `"How We Work"` | `how we work` | `clay` |
| `"Tomatoes"` | `tomatoes` | `terracotta` |
| `"Ideas"` | `ideas` | `violet` |
| `"Travel"` | `travel` | `amber` |
| `""` | `` | `sage` |

*(Update this table by running the reference JS implementation if the palette ordering ever changes. The slug names are stable; the position-in-array determines hash output.)*

## CSS surface

Tokens are declared per theme in `crucible.css` via `light-dark()`:

```css
:root {
  --topic-ember: light-dark(#A53A13, #E5704A);
  --topic-pine:  light-dark(#284A1F, #6AA452);
  /* … 14 more */
}
```

### Chip styling — derived, not stored

Topic chips don't get three tokens per swatch (`dot`, `bg`, `border`). One value per swatch — backgrounds and borders are **derived per-instance** via `color-mix()`:

```css
.cru-topic-chip {
  background: color-mix(in oklab, var(--topic-color) 14%, var(--paper));
  border:     1px solid color-mix(in oklab, var(--topic-color) 26%, var(--paper));
  color:      var(--ink);
}
.cru-topic-chip .cru-topic-dot {
  background: var(--topic-color);
}
```

The chip's parent sets `--topic-color` for the binding:

```html
<span class="cru-topic-chip" style="--topic-color: var(--topic-pine)">
  <span class="cru-topic-dot"></span>
  Garden
</span>
```

This means **the same chip CSS adapts to mode automatically** because `--paper` and `--topic-*` both flip when `[data-theme]` flips. No JS, no remount, no per-component awareness of mode.

Browser floor: `color-mix(in oklab, …)` requires Safari 16.4+ / Chrome 111+. Within shipping iOS target.

### Why derived, not pre-baked

The previous design-system bundle stored each swatch as `{ bg, fg }` pairs — pre-baked pastel backgrounds tuned to cream paper. That approach predates `color-mix()` and required 32 values per mode (so 64 to support dark). Derivation cuts that to 16 + automatic mode adaptation, at the cost of slightly different bgs than the original pre-bakes. If we ever need to honor a specific pre-baked bg, override it inline; the rule is the default, not a law.

### Legacy `--topic-<workname>` aliases

A handful of older HTML files reference topics by working-name (`var(--topic-garden)`, `--topic-food`, `--topic-ideas`, `--topic-work`) rather than spec slug. These aliases live at the bottom of `crucible.css` and **must point each working-name to the slug that `topicSlugFor(name)` would produce for that name**, so a legacy mock and a freshly-created user topic with the same name render identically.

If you change the picker order or the hash function, recompute the aliases. The current mappings:

| Alias | Resolves to | Why |
|---|---|---|
| `--topic-garden` | `var(--topic-moss)` | `topicSlugFor("garden")` → `moss` |
| `--topic-food` | `var(--topic-rose)` | `topicSlugFor("food")` → `rose` |
| `--topic-ideas` | `var(--topic-violet)` | `topicSlugFor("ideas")` → `violet` |
| `--topic-work` | `var(--topic-sea)` | `topicSlugFor("work")` → `sea` |

New HTML / JSX should use the canonical slug directly (`var(--topic-moss)`, not `var(--topic-garden)`). The aliases exist for transition only and should be removed once no file references them.

## Swift / Core Data schema notes

When the iOS port lands (separate PR), the model changes are:

- Add `colorSlug: String?` to the `Topic` entity. Nullable in storage, but **always populated at read time** via the auto-hash if absent.
- Migration: existing topics with no slug → derive via `topicSlug(for: name)` at first read, write back. One-shot, no UI.
- CloudKit: new field `colorSlug` on the Topic record type. Schema deploy required per CLAUDE.md.
- Renderer: `Color("topic-ember")` against an asset-catalog Any/Dark entry whose values match this spec exactly.

The slug strings in the asset catalog folder names and Color literal calls must be byte-identical to this spec. A typo (`"terracota"`, `"slate-blue"`) silently maps no asset and the chip renders gray.

## When this spec changes

Any change to slug names, palette ordering, or the hash function is a **breaking change** with a migration cost on both platforms:

- Renaming a slug requires a data migration (rewrite `colorSlug` on every existing Topic).
- Reordering the palette array changes every auto-hashed assignment for unset topics — users see their colors shuffle.
- Changing the hash function does the same.

Don't change those casually. Hex values can be tuned freely; slug strings and positional order are load-bearing.
