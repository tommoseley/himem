// Crucible — design tokens
// Apple-native base · warm editorial serif moments · Swiss precision in layout.
// iOS is the source of truth. Values are opinionated and fixed.

const Crucible = {
  meta: {
    name: 'Crucible',
    version: '0.1',
    tagline: 'A design language for native apps and the web.',
  },

  // ───────── Color ─────────
  // Three neutral ramps + one accent ramp. All values opinionated and fixed.
  // "Ink" = text/foreground on light. "Paper" = backgrounds on light.
  // Dark mode gets its own mirrored ramp.
  color: {
    // Neutrals (light)
    paper:   '#F7F5F0',   // canvas — warm, not blue-white
    card:    '#FFFFFF',   // raised surface
    sunk:    '#EFECE5',   // inset / inactive / keyboard tint
    hairline:'rgba(25,20,15,0.08)',
    divider: 'rgba(25,20,15,0.12)',
    ink:     '#1A1612',   // primary text (warm near-black)
    ink2:    'rgba(26,22,18,0.64)',  // secondary text
    ink3:    'rgba(26,22,18,0.42)',  // tertiary text / placeholder
    ink4:    'rgba(26,22,18,0.22)',  // disabled / decorative

    // Neutrals (dark)
    paperD:  '#0E0C0A',
    cardD:   '#181513',
    sunkD:   '#221E1A',
    hairlineD:'rgba(255,245,235,0.09)',
    dividerD:'rgba(255,245,235,0.14)',
    inkD:    '#F5EFE6',
    inkD2:   'rgba(245,239,230,0.66)',
    inkD3:   'rgba(245,239,230,0.42)',
    inkD4:   'rgba(245,239,230,0.22)',

    // Accent — warm ember. One color, one job: primary action.
    accent:        '#C64A1C',
    accentPressed: '#A53A13',
    accentTint:    '#FBEAE0',
    accentInk:     '#FFFFFF',
    accentOnDark:  '#EC7442',

    // Semantic (used sparingly; mostly inherit neutral)
    success: '#2F7D4F',
    warning: '#B87322',
    danger:  '#B8311E',
    info:    '#1E5C8E',

    // Focus ring
    focus: 'rgba(198,74,28,0.45)',
  },

  // ───────── Typography ─────────
  // Dual-typeface system: SF (or -apple-system) for UI + body;
  // a warm serif for editorial titles, empty-state hero, quotes.
  type: {
    sans: '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif',
    sansDisplay: '-apple-system, BlinkMacSystemFont, "SF Pro Display", system-ui, sans-serif',
    serif: '"Source Serif 4", "Source Serif Pro", "Iowan Old Style", Georgia, serif',
    mono: 'ui-monospace, "SF Mono", "JetBrains Mono", Menlo, monospace',

    // Scale — opinionated Apple-ish ramp with a serif display size added.
    // { size, line, weight, letter }
    display:   { size: 48, line: 54, weight: 400, letter: -0.8, family: 'serif' },
    title1:    { size: 34, line: 41, weight: 700, letter: 0.4,  family: 'sansDisplay' },
    title2:    { size: 28, line: 34, weight: 700, letter: 0.36, family: 'sansDisplay' },
    title3:    { size: 22, line: 28, weight: 600, letter: 0.35, family: 'sansDisplay' },
    headline:  { size: 17, line: 22, weight: 600, letter: -0.43, family: 'sans' },
    body:      { size: 17, line: 22, weight: 400, letter: -0.43, family: 'sans' },
    callout:   { size: 16, line: 21, weight: 400, letter: -0.32, family: 'sans' },
    subhead:   { size: 15, line: 20, weight: 400, letter: -0.24, family: 'sans' },
    footnote:  { size: 13, line: 18, weight: 400, letter: -0.08, family: 'sans' },
    caption1:  { size: 12, line: 16, weight: 400, letter:  0,    family: 'sans' },
    caption2:  { size: 11, line: 13, weight: 500, letter:  0.07, family: 'sans' },
    // Editorial serif sizes
    serif1:    { size: 56, line: 60, weight: 400, letter: -0.8, family: 'serif' },
    serif2:    { size: 40, line: 46, weight: 400, letter: -0.6, family: 'serif' },
    serif3:    { size: 28, line: 34, weight: 400, letter: -0.3, family: 'serif' },
    // Utility
    eyebrow:   { size: 11, line: 13, weight: 700, letter: 2.0, family: 'sans' }, // uppercase label
  },

  // ───────── Space / grid ─────────
  // 4pt grid. Swiss precision: name the steps, don't improvise.
  space: {
    '0': 0, '0.5': 2, '1': 4, '1.5': 6, '2': 8, '2.5': 10, '3': 12,
    '4': 16, '5': 20, '6': 24, '7': 28, '8': 32, '10': 40, '12': 48,
    '14': 56, '16': 64, '20': 80, '24': 96,
  },

  // ───────── Radii ─────────
  radius: {
    none: 0,
    xs: 4,
    sm: 8,
    md: 12,
    lg: 16,
    xl: 22,    // default card radius on iOS
    pill: 9999,
    device: 48,
  },

  // ───────── Elevation ─────────
  // Warm shadows (orange-tinted black). Four flat levels.
  elevation: {
    0: 'none',
    1: '0 1px 2px rgba(40,25,15,0.06), 0 1px 3px rgba(40,25,15,0.04)',
    2: '0 2px 6px rgba(40,25,15,0.08), 0 6px 18px rgba(40,25,15,0.06)',
    3: '0 6px 16px rgba(40,25,15,0.10), 0 16px 48px rgba(40,25,15,0.10)',
    4: '0 20px 60px rgba(40,25,15,0.22), 0 4px 12px rgba(40,25,15,0.08)',
  },

  // ───────── Motion ─────────
  // Spring-ish eases + four durations. All UI motion uses these.
  motion: {
    fast:    120,
    base:    200,
    slow:    320,
    pageful: 520,
    ease: {
      standard: 'cubic-bezier(0.2, 0, 0, 1)',    // entering + default
      emphasized: 'cubic-bezier(0.2, 0.7, 0.2, 1)',
      exit: 'cubic-bezier(0.4, 0, 1, 1)',
      spring: 'cubic-bezier(0.2, 1.3, 0.3, 1)',  // overshoot (haptic feel)
    },
  },

  // ───────── Iconography ─────────
  // SF Symbols style: 1.5 – 2pt stroke, rounded caps/joins, 24×24 grid.
  icon: {
    size: { sm: 16, md: 20, lg: 24, xl: 32 },
    stroke: 1.6,
  },

  // ───────── Layout grid ─────────
  layout: {
    mobileGutter: 16,
    mobileMargin: 20,
    ipadGutter: 24,
    ipadMargin: 32,
    webGutter: 32,
    webMargin: 64,
    contentMax: 1200,
    readingMax: 680,
  },
};

// tiny helper — hydrate a type token into a CSS style object
function typeStyle(t, family) {
  const fam = family || t.family || 'sans';
  return {
    fontFamily: Crucible.type[fam],
    fontSize: t.size,
    lineHeight: t.line + 'px',
    fontWeight: t.weight,
    letterSpacing: t.letter + 'px',
  };
}

window.Crucible = Crucible;
window.typeStyle = typeStyle;
