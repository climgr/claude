---
name: UI/UX conventions
description: Designer-level UI/UX standards for web, desktop, mobile, and TUI — theme system, accessibility, layout, interaction
type: user
---

## Designer Mindset

Every UI surface — web, desktop, mobile, TUI — must be built with designer-level intent. "It works" is not enough. Aim for clarity, consistency, and delight. When implementing any UI:

- Think in user flows, not in code paths
- Every state must be handled: loading, empty, error, success
- Copy matters — no "Error occurred", no "Feature 1, Feature 2", no placeholder text
- Spacing, alignment, and hierarchy are not optional polish

---

## Theme System (all surfaces)

**Default: dark. Always.**

Every UI must support three modes:

| Mode | Behaviour |
|------|-----------|
| `dark` | Dark background, light text — the default |
| `light` | Light background, dark text |
| `auto` | Follows the OS/system preference (`prefers-color-scheme`) |

**Rules:**
- Ship dark mode first; light mode is not an afterthought
- `auto` must react to live OS preference changes without reload (web: pure CSS `@media (prefers-color-scheme: …)` — no JS listener needed; desktop: `dark-light` crate or equivalent; mobile: system API)
- User override is always respected and persisted (theme cookie for web — the server reads it and renders the theme class on `<html>`, so the correct theme paints on first byte with no flash and no JS; config file or OS keystore for desktop/mobile)
- Never hardcode colors inline — use CSS custom properties (web), a shared theme struct (desktop/TUI), or a design token system

---

## Design Token System

All colors **must** come from this token set. Never hardcode hex values in component styles. Every combination listed in the contrast table below has been pre-checked; only use token pairings from that table.

### Token reference

#### Surface tokens

| Token | Dark | Light | Purpose |
|-------|------|-------|---------|
| `--bg` | `#282a36` | `#ffffff` | Page / app background |
| `--bg-subtle` | `#21222c` | `#f6f8fa` | Sidebar, input fill, table stripe |
| `--bg-elevated` | `#2b2d3a` | `#ffffff` | Card, modal, dialog (use `box-shadow` for elevation on light) |
| `--bg-overlay` | `#343746` | `#ffffff` | Tooltip, dropdown, popover (use `box-shadow` for depth on light) |
| `--bg-inset` | `#1e1f29` | `#eaeef2` | Code block, terminal, inset well |

#### Text tokens

| Token | Dark | Light | Contrast on `--bg` | Use |
|-------|------|-------|-------------------|-----|
| `--fg` | `#f8f8f2` | `#1f2328` | 13:1 / 17:1 | Primary body text, headings, labels |
| `--fg-muted` | `#a3a9cc` | `#636c76` | 6.2:1 / 5.5:1 | Secondary text, descriptions, metadata |
| `--fg-subtle` | `#7b83ad` | `#818b98` | 3.9:1 / 3.5:1 | Timestamps, placeholders, de-emphasized labels *(large text / UI text only — ≥18px or ≥14px bold)* |
| `--fg-disabled` | `#565f89` | `#adb5c0` | 2.3:1 / 2.2:1 | Disabled controls — intentionally below AA to signal non-interactivity |
| `--fg-on-accent` | `#282a36` | `#ffffff` | 5.9:1 on `--accent` (dark) / 5.7:1 on `--accent` (light) | Text and icons drawn on top of an accent-colored background |
| `--fg-link` | `#bd93f9` | `#0969da` | 5.9:1 / 5.7:1 | Hyperlinks; always underlined or icon-paired |

> **Rule:** `--fg-subtle` and `--fg-disabled` must **never** be used for critical information, error messages, or any text that is the sole conveyor of meaning. If in doubt, step up to `--fg-muted`.

#### Border tokens

| Token | Dark | Light | Purpose |
|-------|------|-------|---------|
| `--border-subtle` | `#2b2d3a` | `#eaeef2` | Dividers, hairlines — visual separation only |
| `--border` | `#44475a` | `#d0d7de` | Input borders, card outlines, table borders |
| `--border-strong` | `#a3a9cc` | `#636c76` | High-emphasis borders, active input, focused non-accent element |

#### Accent / interactive tokens

| Token | Dark | Light | Purpose |
|-------|------|-------|---------|
| `--accent` | `#bd93f9` | `#0969da` | Primary interactive purple — buttons, links, focus rings |
| `--accent-hover` | `#caa9fa` | `#0860ca` | Hover state of an accent element |
| `--accent-pressed` | `#a679f2` | `#0550ae` | Active / pressed state |
| `--accent-subtle` | `#3d3a5c` | `#ddf4ff` | Tinted selection background, highlighted row, tag fill |
| `--accent-fg` | `#bd93f9` | `#0969da` | Accent-colored text or icon on a surface (not on accent bg) |

#### Status / semantic tokens

Each status group has three sub-tokens: `fg` (text/icon color), `bg` (tinted fill), `border` (outline).

| Token | Dark fg | Dark bg | Dark border | Light fg | Light bg | Light border |
|-------|---------|---------|-------------|----------|----------|--------------|
| `--color-success-fg` | `#50fa7b` | — | — | `#1a7f37` | — | — |
| `--color-success-bg` | — | `#16281d` | — | — | `#dafbe1` | — |
| `--color-success-border` | — | — | `#2fa855` | — | — | `#82cfb0` |
| `--color-warning-fg` | `#ffb86c` | — | — | `#9a6700` | — | — |
| `--color-warning-bg` | — | `#2e2113` | — | — | `#fff8c5` | — |
| `--color-warning-border` | — | — | `#d68f3e` | — | — | `#d4a72c` |
| `--color-error-fg` | `#ff5555` | — | — | `#d1242f` | — | — |
| `--color-error-bg` | — | `#2e1616` | — | — | `#ffebe9` | — |
| `--color-error-border` | — | — | `#d63f3f` | — | — | `#cf222e` |
| `--color-info-fg` | `#8be9fd` | — | — | `#0969da` | — | — |
| `--color-info-bg` | — | `#16282a` | — | — | `#ddf4ff` | — |
| `--color-info-border` | — | — | `#4fc4dc` | — | — | `#54aeff` |

Status fg contrast on `--bg`: success 10.4:1 / warning 8.4:1 / error 4.5:1 / info 10.3:1 — all WCAG AA ✓

> **Icons:** use the same fg token as adjacent text — `--fg` for primary icons, `--fg-muted` for decorative or secondary icons, `--accent-fg` for interactive icons, status fg tokens for status icons. No independent icon color tokens.

### Pre-checked contrast table

Only use these foreground / background pairings. Any combination not in this table must be contrast-checked before use.

| Foreground | Background | Ratio | Passes |
|------------|------------|-------|--------|
| `--fg` | `--bg` | 13:1 / 17:1 | AA + AAA ✓ |
| `--fg` | `--bg-subtle` | 15:1 / 15:1 | AA + AAA ✓ |
| `--fg` | `--bg-elevated` | 13:1 / 17:1 | AA + AAA ✓ |
| `--fg` | `--bg-overlay` | 11:1 / 17:1 | AA + AAA ✓ |
| `--fg` | `--accent-subtle` | 10:1 / 14:1 | AA + AAA ✓ |
| `--fg-muted` | `--bg` | 6.2:1 / 5.5:1 | AA ✓ |
| `--fg-muted` | `--bg-subtle` | 6.9:1 / 5.0:1 | AA ✓ |
| `--fg-muted` | `--bg-elevated` | 5.9:1 / 5.5:1 | AA ✓ |
| `--fg-subtle` | `--bg` | 3.9:1 / 3.5:1 | AA (large/UI) ✓ |
| `--fg-on-accent` | `--accent` | 5.9:1 / 5.7:1 | AA ✓ |
| `--fg-link` | `--bg` | 5.9:1 / 5.7:1 | AA ✓ |
| `--color-success-fg` | `--bg` | 10.4:1 / 5.4:1 | AA ✓ |
| `--color-warning-fg` | `--bg` | 8.4:1 / 5.6:1 | AA ✓ |
| `--color-error-fg` | `--bg` | 4.5:1 / 5.2:1 | AA ✓ |
| `--color-info-fg` | `--bg` | 10.3:1 / 5.7:1 | AA ✓ |
| `--color-success-fg` | `--color-success-bg` | 11.3:1 / 7:1 | AA ✓ |
| `--color-warning-fg` | `--color-warning-bg` | 9.2:1 / 8:1 | AA ✓ |
| `--color-error-fg` | `--color-error-bg` | 5.4:1 / 6:1 | AA ✓ |
| `--color-info-fg` | `--color-info-bg` | 11.1:1 / 7:1 | AA ✓ |

### Full CSS variable block (web)

```css
/* ── Dark theme ─────────────────────────────────────────────────── */
:root[data-theme="dark"] {
  /* Surface */
  --bg:           #282a36;
  --bg-subtle:    #21222c;
  --bg-elevated:  #2b2d3a;
  --bg-overlay:   #343746;
  --bg-inset:     #1e1f29;

  /* Text */
  --fg:           #f8f8f2;
  --fg-muted:     #a3a9cc;
  --fg-subtle:    #7b83ad;
  --fg-disabled:  #565f89;
  --fg-on-accent: #282a36;
  --fg-link:      #bd93f9;

  /* Border */
  --border-subtle: #2b2d3a;
  --border:        #44475a;
  --border-strong: #a3a9cc;

  /* Accent */
  --accent:        #bd93f9;
  --accent-hover:  #caa9fa;
  --accent-pressed:#a679f2;
  --accent-subtle: #3d3a5c;
  --accent-fg:     #bd93f9;

  /* Status */
  --color-success-fg:     #50fa7b;
  --color-success-bg:     #16281d;
  --color-success-border: #2fa855;

  --color-warning-fg:     #ffb86c;
  --color-warning-bg:     #2e2113;
  --color-warning-border: #d68f3e;

  --color-error-fg:       #ff5555;
  --color-error-bg:       #2e1616;
  --color-error-border:   #d63f3f;

  --color-info-fg:        #8be9fd;
  --color-info-bg:        #16282a;
  --color-info-border:    #4fc4dc;
}

/* ── Light theme ────────────────────────────────────────────────── */
:root[data-theme="light"] {
  /* Surface */
  --bg:           #ffffff;
  --bg-subtle:    #f6f8fa;
  --bg-elevated:  #ffffff;
  --bg-overlay:   #ffffff;
  --bg-inset:     #eaeef2;

  /* Text */
  --fg:           #1f2328;
  --fg-muted:     #636c76;
  --fg-subtle:    #818b98;
  --fg-disabled:  #adb5c0;
  --fg-on-accent: #ffffff;
  --fg-link:      #0969da;

  /* Border */
  --border-subtle: #eaeef2;
  --border:        #d0d7de;
  --border-strong: #636c76;

  /* Accent */
  --accent:        #0969da;
  --accent-hover:  #0860ca;
  --accent-pressed:#0550ae;
  --accent-subtle: #ddf4ff;
  --accent-fg:     #0969da;

  /* Status */
  --color-success-fg:     #1a7f37;
  --color-success-bg:     #dafbe1;
  --color-success-border: #82cfb0;

  --color-warning-fg:     #9a6700;
  --color-warning-bg:     #fff8c5;
  --color-warning-border: #d4a72c;

  --color-error-fg:       #d1242f;
  --color-error-bg:       #ffebe9;
  --color-error-border:   #cf222e;

  --color-info-fg:        #0969da;
  --color-info-bg:        #ddf4ff;
  --color-info-border:    #54aeff;
}

/* ── Auto (no JS / no data-theme attribute) ─────────────────────── */
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #282a36; --bg-subtle: #21222c; --bg-elevated: #2b2d3a;
    --bg-overlay: #343746; --bg-inset: #1e1f29;
    --fg: #f8f8f2; --fg-muted: #a3a9cc; --fg-subtle: #7b83ad;
    --fg-disabled: #565f89; --fg-on-accent: #282a36; --fg-link: #bd93f9;
    --border-subtle: #2b2d3a; --border: #44475a; --border-strong: #a3a9cc;
    --accent: #bd93f9; --accent-hover: #caa9fa; --accent-pressed: #a679f2;
    --accent-subtle: #3d3a5c; --accent-fg: #bd93f9;
    --color-success-fg: #50fa7b; --color-success-bg: #16281d; --color-success-border: #2fa855;
    --color-warning-fg: #ffb86c; --color-warning-bg: #2e2113; --color-warning-border: #d68f3e;
    --color-error-fg:   #ff5555; --color-error-bg:   #2e1616; --color-error-border:   #d63f3f;
    --color-info-fg:    #8be9fd; --color-info-bg:    #16282a; --color-info-border:    #4fc4dc;
  }
}
@media (prefers-color-scheme: light) {
  :root {
    --bg: #ffffff; --bg-subtle: #f6f8fa; --bg-elevated: #ffffff;
    --bg-overlay: #ffffff; --bg-inset: #eaeef2;
    --fg: #1f2328; --fg-muted: #636c76; --fg-subtle: #818b98;
    --fg-disabled: #adb5c0; --fg-on-accent: #ffffff; --fg-link: #0969da;
    --border-subtle: #eaeef2; --border: #d0d7de; --border-strong: #636c76;
    --accent: #0969da; --accent-hover: #0860ca; --accent-pressed: #0550ae;
    --accent-subtle: #ddf4ff; --accent-fg: #0969da;
    --color-success-fg: #1a7f37; --color-success-bg: #dafbe1; --color-success-border: #82cfb0;
    --color-warning-fg: #9a6700; --color-warning-bg: #fff8c5; --color-warning-border: #d4a72c;
    --color-error-fg:   #d1242f; --color-error-bg:   #ffebe9; --color-error-border:   #cf222e;
    --color-info-fg:    #0969da; --color-info-bg:    #ddf4ff; --color-info-border:    #54aeff;
  }
}
```

### Desktop / TUI token mapping (Rust)

```rust
pub struct Theme {
    // Surface
    pub bg: Color, pub bg_subtle: Color, pub bg_elevated: Color,
    pub bg_overlay: Color, pub bg_inset: Color,
    // Text
    pub fg: Color, pub fg_muted: Color, pub fg_subtle: Color,
    pub fg_disabled: Color, pub fg_on_accent: Color, pub fg_link: Color,
    // Border
    pub border_subtle: Color, pub border: Color, pub border_strong: Color,
    // Accent
    pub accent: Color, pub accent_hover: Color, pub accent_pressed: Color,
    pub accent_subtle: Color, pub accent_fg: Color,
    // Status
    pub success: StatusColors, pub warning: StatusColors,
    pub error: StatusColors,   pub info: StatusColors,
}
pub struct StatusColors { pub fg: Color, pub bg: Color, pub border: Color }
```

Pass the active `Theme` instance through your widget/component tree; never read `dark-light` in individual widgets.

### TUI ANSI fallback mapping

When true-color is unavailable (16-color or 8-color terminal), map tokens to the nearest ANSI color:

| Token | Dark ANSI | Light ANSI |
|-------|-----------|------------|
| `--fg` | `BrightWhite` | `Black` |
| `--fg-muted` | `White` | `DarkGray` |
| `--fg-subtle` | `BrightBlack` (gray) | `BrightBlack` |
| `--fg-disabled` | `BrightBlack` | `BrightBlack` |
| `--fg-on-accent` | `Black` | `White` |
| `--accent` / `--accent-fg` | `BrightMagenta` | `Blue` |
| `--color-success-fg` | `BrightGreen` | `Green` |
| `--color-warning-fg` | `BrightYellow` | `Yellow` |
| `--color-error-fg` | `BrightRed` | `Red` |
| `--color-info-fg` | `BrightBlue` | `Blue` |

Respect `NO_COLOR` — strip all color tokens when set; render plain text only.

### Mobile equivalents

| CSS token | iOS (SwiftUI) | Android (Material You) |
|-----------|---------------|------------------------|
| `--bg` | `.systemBackground` | `colorSurface` |
| `--bg-subtle` | `.secondarySystemBackground` | `colorSurfaceVariant` |
| `--bg-elevated` | `.tertiarySystemBackground` | `colorSurfaceContainer` |
| `--fg` | `.label` | `colorOnSurface` |
| `--fg-muted` | `.secondaryLabel` | `colorOnSurfaceVariant` |
| `--fg-disabled` | `.tertiaryLabel` | `colorOutline` |
| `--accent` | `.tintColor` / `AccentColor` | `colorPrimary` |
| `--color-error-fg` | `.systemRed` | `colorError` |
| `--color-success-fg` | `.systemGreen` | custom `colorSuccess` |
| `--color-warning-fg` | `.systemOrange` | custom `colorWarning` |

Use semantic system colors where available — they automatically adapt to dark/light/high-contrast modes without custom logic.

---

## Web UI

### Rendering
- Server-side rendering only (Go templates, Jinja2, ERB, etc.) — never React/Vue/Angular for core content
- Progressive enhancement: every page works without JavaScript
- No client-side routing (SPAs); no business logic in JS
- No inline CSS or JavaScript; no `<style>` blocks in templates; no inline event handler attributes (`onclick`, `onchange`, `onsubmit`, …) — CSP blocks them; use a native HTML mechanism first, external-JS `addEventListener` only as enhancement
- No JavaScript `alert()` / `confirm()` — confirmations use native `<dialog>` with `<form method="dialog">` (close/cancel buttons need no JS); status messages use toast notifications
- Prefer native elements over JS re-implementations: `<details>/<summary>` for accordions; `:hover`/`:focus-within`, `popover`, or `title` for dropdowns and tooltips; `loading="lazy"` for image lazy loading; CSS `scroll-behavior: smooth` (with a `prefers-reduced-motion` override) for smooth scroll and back-to-top `<a href="#top">` links; `position: sticky` for sticky headers; `<progress>` for progress bars; `<button type="reset">` for form reset
- Form validation: HTML5 `required`/`pattern`/`type=` first; style invalid state with CSS `:user-invalid`; JS only mirrors `validationMessage` text as an enhancement — never blur-handler styling

### Import/Export
Applies to every feature that exports or imports data (audit logs, data
exports, config/settings export, generated lists, etc.) — a generic rule,
not a spec for one named feature.
- **Export** — a plain `<a href="...">` link or `<form method="get">`, no JavaScript required. The server sets `Content-Type` and `Content-Disposition: attachment; filename="..."` so the browser's native save flow handles the download. Never JS `Blob` + `URL.createObjectURL()` + a synthetic clicked `<a download>`, and never make the File System Access API (`showSaveFilePicker()`) the only path — both require JavaScript and fail in Text Browsers or with JS disabled.
- **Import** — a plain `<input type="file">` inside `<form method="post" enctype="multipart/form-data">`, the browser's native file picker, no JavaScript required to select or submit. Server-side validation is always authoritative. Never hide the native `<input type="file">` behind a custom-styled JS trigger — the feature breaks with JavaScript disabled.
- **Styling** — every element in the flow (trigger, form, label, input, status/progress/error text) is fully styled, reusing existing classes/tokens before writing new CSS (Reuse before creating, `~/.claude/CLAUDE.md`); "no-JS" governs markup/mechanism only, not appearance.

### Layout — mobile-first
- Write CSS for mobile first; expand with media queries
- Never desktop-first CSS

**Breakpoints:**

| Target | Media query |
|--------|-------------|
| Mobile (base) | none |
| Tablet | `@media (min-width: 768px)` |
| Desktop | `@media (min-width: 1024px)` |
| Wide | `@media (min-width: 1440px)` |

### Accessibility — WCAG 2.1 AA minimum
- Semantic HTML — headings in order, landmarks (`<main>`, `<nav>`, `<aside>`), buttons are `<button>`
- All images have `alt` text; decorative images use `alt=""`
- Touch targets minimum **44×44 px**
- Keyboard navigable — every interactive element reachable and operable by keyboard
- Focus indicators always visible — never `outline: none` without a custom replacement
- Color is never the only differentiator (always pair with icon, label, or pattern)
- Sufficient contrast: 4.5:1 for normal text, 3:1 for large text (WCAG AA)
- `lang` attribute on `<html>`; `dir` attribute when supporting RTL

### Long strings (REQUIRED CSS)
```css
.long-string, .ip-address, .onion-address, .api-token, .hash, .uuid {
  word-break: break-all;
  overflow-wrap: break-word;
  font-family: monospace;
}
```
Apply to: IPv6, onion addresses, API tokens, hashes, UUIDs, Base64 blobs.

### Footer — standard layout (all web UIs)

Every web UI footer uses this exact row order, centered, top to bottom:

1. **Onion address** (only when Tor is enabled and running): 🧅 icon + the full `.onion` address in a monospace code pill + copy-to-clipboard button with visible "Copied!" feedback
2. **Page links**: About • Privacy • Contact • Help
3. **Branding**: Made with ❤️ • {project_version} — "Made with" links to `{PLATFORM_REPO_URL}` with `target="_blank"`
4. **Build stamp**: `Last update: {build_datetime}` in human-readable format `%B %-d, %Y at %H:%M:%S %Z` (e.g. `December 4, 2025 at 13:05:13 EST`), linked to the health endpoint

Rules:
- **No `<br />` spacers between rows** — rows are consecutive `<p>` elements; vertical rhythm comes from CSS, kept tight:
```css
footer p {
  margin: 0.25rem 0;
}
```
- A disabled feature drops its row entirely (Tor off → no onion row, no leftover gap)
- The onion address uses the Long strings CSS above (`.onion-address`) so it never overflows on mobile

### Theme implementation (web)
Use the full CSS variable block from the **Design Token System** section above — copy it verbatim into your project's root stylesheet. Do not use the old three-token stub.

- Theme preference lives in a `theme` cookie; the server reads it and renders `data-theme` on `<html>` — correct theme on first paint, no flash, works with JS disabled
- `auto` (no cookie or `theme=auto`): no `data-theme` attribute — the `@media (prefers-color-scheme: …)` blocks in the token CSS handle it in pure CSS, including live OS preference changes
- Theme toggle: a POST form works without JS; external JS may intercept the click to set the cookie and swap `data-theme` in place (no page reload) as an enhancement
- Never use localStorage for theme — the server benefits from reading the value, so it belongs in a cookie; localStorage is only for optional JS convenience copies (e.g. a resource-owner token whose load-bearing copy is an HttpOnly cookie) or pure client-only state — never load-bearing

### Server vs client responsibility
| Task | Where |
|------|-------|
| Validation | Server — server is authoritative |
| HTML rendering | Server — works without JS |
| Business logic | Server — security and consistency |
| Theme persistence | Server — `theme` cookie rendered as `data-theme` on `<html>` |
| Theme toggle click | Client JS enhancement — swap `data-theme` without reload |
| Copy to clipboard | Client JS — browser API |
| Form feedback | Client JS — UX enhancement only |

### Viewport, drawer navigation, accent and consent

- **Never bare `100vh`** — use `min-height: 100dvh` (or `height: 100dvh`) so mobile browser bars do not clip content; add `env(safe-area-inset-*)` padding on anything touching a screen edge (drawer, toast, banner, bottom actions)
- **No-JS hamburger/drawer** — a checkbox (`.nav-checkbox`) toggles the drawer; hamburger below 768px, inline links from 768px; drawer `height: 100dvh; width: min(280px, 85vw)`; the scrim `<label>` closes it; while open, `body:has(.nav-checkbox:checked) { overflow: hidden }`; JavaScript (overflow detection, Esc, focus handling) is an enhancement only
- **Single accent** — one brand color `web.ui.accent` (`#RRGGBB`) in `{config_dir}/yaml.d/branding.yml` drives the primary interactive color (the template names it `--color-primary`; this file's `--accent` family is the equivalent token set)
- **Cookie-consent banner** — non-essential cookies and tracking are opt-in only: nothing non-essential runs until the visitor accepts; there is no opt-out mode

---

## Desktop UI (native)

### Surface priority (auto-detect at runtime)
1. **GUI** — preferred when a display server is available and the invocation is interactive
2. **TUI** — fallback for capable terminals without a display server
3. **CLI** — non-interactive or when `NO_COLOR`/plain-output is requested

### Display backends (Linux/BSD) — both required
- X11 and Wayland are first-class; neither is a fallback of the other
- Preferred Rust crates: `x11rb` or `x11-dl` for X11; `wayland-client` with `dlopen` for Wayland
- GUI toolkit: `egui`, `iced`, `slint`, `floem`, or `dioxus` (native renderer mode) — all pure Rust
- TUI: `ratatui` + `crossterm`
- Theme detection: `dark-light` crate (pure Rust, no C libs)

### Assets
- All assets embedded at build time — fonts, icons, theme data, default config, schemas, locales
- User is never required to install support files separately
- No CDN or network fetch on first run

### Accessibility (desktop)
- Keyboard-only navigation required; mouse is an enhancement
- Touch targets minimum 44×44 px (for touch-capable devices)
- High-contrast mode support where the toolkit allows
- Screen reader compatibility where the toolkit exposes accessibility APIs

### Theme implementation (desktop/TUI)
- Detect at startup via `dark-light` crate or OS API
- React to live changes without restart where the OS API supports it
- User override stored in config file, takes precedence over detection
- TUI: respect `NO_COLOR` — strip all ANSI color when set

---

## Mobile apps

### Layout
- Mobile-first is native — design for the smallest screen first
- Use platform layout primitives (SwiftUI `VStack`/`HStack`, Jetpack Compose `Column`/`Row`, Flutter `Column`/`Row`)
- Respect safe areas (notch, home indicator, system bars)
- Minimum touch target: **44×44 pt/dp**

### Theme implementation (mobile)
- iOS: `@Environment(\.colorScheme)` + `Color(uiColor: .systemBackground)` semantic colors
- Android: Material You / Dynamic Color + `isSystemInDarkTheme()`; the persisted theme choice always wins over the system setting, and `auto` follows the system dark-mode setting live with no restart
- Flutter: `ThemeData` with `brightness` from `MediaQuery.platformBrightness`
- User override: explicit dark/light setting in app preferences, persisted via platform storage

### Accessibility (mobile)
- VoiceOver (iOS) and TalkBack (Android) labels on all interactive elements
- Dynamic Type / font scaling respected — no hardcoded font sizes
- Sufficient color contrast (WCAG AA minimum)
- No color-only indicators

---

## TUI

- Use alternate screen buffer — restores terminal cleanly on exit
- Keyboard-only navigation; mouse support is an enhancement
- Respect `NO_COLOR` — if set, strip all ANSI colors and use plain text rendering
- Minimum readable width: 80 columns; gracefully degrade at narrower widths
- Show a spinner or progress indicator for operations >300 ms
- Escape / `q` always exits a view; `?` always shows help

---

## Universal rules (all surfaces)

- **No placeholder content** — every page/screen ships with real, functional content; no "coming soon", "Feature 1", or empty states without a meaningful message
- **Every state handled** — loading, empty, error, success each have a distinct, informative UI
- **i18n-ready** — no hardcoded user-visible strings; use a translation key from the first commit
- **No feature gating** — GUI, TUI, and CLI surfaces expose the same core capabilities
- **Feedback for every action** — button press, form submit, background task — user always knows something happened
- **Copy buttons MUST show visible "Copied!" feedback** — on success swap to a checkmark plus the translated "Copied!" label (i18n key `copied`, rendered server-side into `data-copied-label`) for 2 s via a `.copied` class; success colors come from CSS custom properties; announce via `aria-live="polite"`; icon-only buttons swap their own content and carry `aria-live="polite"` on the button itself
- **Consistent spacing** — use a spacing scale (e.g. 4 px base unit: 4, 8, 12, 16, 24, 32, 48); never arbitrary pixel values
- **Anything user-facing MUST use `%B %-d, %Y at %H:%M:%S %Z`** — (e.g. `December 4, 2025 at 13:05:13 EST`); use `%Y-%m-%dT%H:%M:%S%:z` (RFC 3339) only where machine-readability matters (API responses, logs, health endpoints, data exports)
- **Derive, don't re-prompt** — when a config/setup flow (install wizard, settings form, onboarding, CLI prompts) configures multiple components that share the same underlying value, ask for that value once and derive the rest; don't make the user re-enter the same intent under different labels. Example: a setup flow that provisions both a primary service and a dependent one sharing a domain, hostname, or base path — ask for the shared value once, pre-fill/derive the dependent one from it, and only surface a separate field when that component's value can legitimately diverge (a different port, a subdomain override, a distinct external endpoint). **Apply with caution — this is about redundant prompts for one intent, not about hiding real configuration:** if two fields are both plausible values a user might independently want to set (e.g. an admin contact email vs. a support contact email — related, but not the same fact), keep them separate; when it's genuinely unclear whether two values are "the same intent" or "coincidentally similar," default to asking separately — a redundant prompt is a minor annoyance, a wrongly-merged field silently misconfigures the divergent case.

---

## Dynamic Interaction (all surfaces)

### Gestures

- **Tap** — primary action on an element; must have a visible pressed/active state
- **Long-press** — reveals contextual options (context menu, drag handle, selection mode); always show a visual affordance (highlight, scale, or haptic) to confirm recognition
- **Swipe (horizontal)** — navigation between peers (tabs, pages, cards) or destructive/action reveal on list rows; always provide a snap point and a cancel path (release before threshold = no action)
- **Swipe (vertical)** — scroll; pull-to-refresh when at the top of a scrollable list; dismiss a modal when at the top of the sheet
- **Pinch / spread** — zoom in/out on zoomable content only; never hijack pinch on non-zoomable surfaces
- **Edge swipe** — reserved for OS-level navigation (back, app switcher); never override or intercept edge gestures
- **Drag** — reorder, move, or resize; always show a drag indicator (handle icon or elevated state); snap to valid drop zones; animate to final position on release
- **Two-finger tap / three-finger tap** — reserved for accessibility (zoom, undo); never bind custom actions to these
- Gesture conflicts must be resolved with a clear priority order: scroll > swipe-action > long-press > tap; never let two gestures silently compete
- Every gesture must have a non-gesture equivalent (button, menu item, keyboard shortcut) — gestures are an enhancement, not the only path

### Haptics

- Use haptics only on touch-capable hardware; never assume haptic availability — always check at runtime and degrade gracefully
- **Selection / light** — item selection, toggle, radio button, segmented control change
- **Impact / medium** — completing a drag-and-drop, snapping to a grid, confirming a reorder
- **Impact / heavy** — destructive action confirmation (delete, archive), pull-to-refresh trigger point
- **Notification / success** — task completed successfully
- **Notification / warning** — recoverable error, validation failure
- **Notification / error** — unrecoverable error, rejected action
- Never fire haptics on passive scroll or hover — only on deliberate, discrete user actions
- Never chain haptics back-to-back faster than 100ms; multiple rapid haptics feel like a glitch
- Respect system accessibility settings — if the user has disabled haptics or vibration, honor it

### Animations & Transitions

- **Duration scale** (all surfaces):

  | Type | Duration |
  |------|----------|
  | Micro (state change, toggle) | 100–150ms |
  | Standard (element enter/exit) | 200–300ms |
  | Emphasis (modal, page) | 300–400ms |
  | Complex (shared element, hero) | 400–500ms |

- **Easing**:
  - Enter: ease-out (fast start, gentle settle)
  - Exit: ease-in (gentle start, fast exit)
  - Repositioning / reorder: ease-in-out
  - Never use linear for UI transitions — it reads as mechanical
- **Enter** — elements slide or fade in from their natural origin; never pop in from nowhere
- **Exit** — elements fade or slide toward their origin; never disappear instantly
- **Shared element / hero** — when an element is the subject of a navigation (e.g. tapping a thumbnail to open detail), it must animate continuously from source to destination; no cut
- Respect `prefers-reduced-motion` (web) and the system reduced-motion accessibility flag (mobile/desktop) — when set, replace motion with instant transitions or simple opacity fades; never disable all feedback, just reduce motion
- Never animate layout-affecting properties (width, height, top, left) on the web — animate `transform` and `opacity` only; these are GPU-composited and do not cause reflow
- Skeleton screens replace spinners for content that has a known shape; spinners are for indeterminate-duration operations only

### Custom Keyboards & Input Extensions

- The input area (keyboard + toolbar) must never obscure focused input fields — reflow the layout when the keyboard is visible; use the platform's keyboard-avoidance primitive rather than hardcoding offsets
- Keyboard height is dynamic — it changes with language, orientation, hardware keyboard attachment, and accessibility settings; always read it from the platform notification/event, never hardcode it
- The accessory / autocomplete bar above the keyboard is part of the keyboard height — account for it in layout math
- Custom keyboard extensions must respect the same safe area and inset rules as the host app
- Dismiss behavior: tapping outside an input, pressing a hardware `Escape` or `Back`, or swiping down on a sheet that contains an input must dismiss the keyboard first, then (on a second gesture if needed) dismiss the sheet
- Custom keyboards must support all system text traits: autocorrect, autocapitalize, secure text (password), numeric, email, URL — never assume the default traits are correct for all fields
- Input accessory toolbars (formatting bar, emoji button, attachment picker) must be keyboard-height-aware on every orientation change
- If a custom keyboard has a `Done` / `Return` action, it must be wired to the form's primary submit action — never a no-op

### Dynamic Layout Adaptation

- **Orientation** — all layouts must be tested in portrait and landscape; neither is the "real" layout; content must reflow, not just rescale
- **Split-screen / multi-window** — assume the app can run at any width from ~320 pt to full screen simultaneously; use relative units and flexible containers, never fixed-width columns that only work full-screen
- **Foldables** — if a fold crease runs through the content area, shift content to avoid the hinge; never place interactive elements on the crease
- **Keyboard-up reflow** — when the software keyboard appears, the visible content area shrinks; scroll the focused field into view within the reduced area; do not zoom or scale the layout
- **Dynamic Type / font scaling** — all text must scale with the system font size setting; no hardcoded `px`/`pt`/`sp` font sizes; test at minimum and maximum scale factors
- **Display density** — use density-independent units everywhere (`dp`, `pt`, `rem`, `em`); never raw pixels except for single-pixel hairlines
- **Notch / punch-hole / safe areas** — all content and interactive elements must respect the safe area insets on all four sides; backgrounds may extend behind system bars (edge-to-edge), but tappable targets must not

### Scroll Behavior

- **Momentum** — scroll must have natural deceleration; never snap-stop on release unless snapping to a defined snap point
- **Snap points** — use snap points only when content is paged (carousels, full-screen cards, tab pagers); never on a plain list
- **Sticky headers** — section headers may stick to the top of a scroll container; they must not obscure the top-most visible item when sticky; unstick when scrolling back past their natural position
- **Parallax** — decorative only; hero images may scroll at 0.5× the content speed; interactive elements must never be inside a parallax layer
- **Pull-to-refresh** — only valid at scroll position = 0 (top); trigger point must have a clear visual threshold indicator; show a spinner/progress indicator while refreshing; dismiss the indicator when data is loaded, not when the request is sent
- **Infinite scroll** — load the next page when the user is within 2–3 screen-heights of the end; show a loading indicator at the bottom while fetching; show an end-of-list message when no more pages exist; never silently stop loading
- **Overscroll** — rubber-band (iOS-style) or glow (Android-style) at both ends of a scrollable list; never a hard stop with no visual feedback
- Scroll containers must not be nested in the same axis — horizontal list inside horizontal scroll, or vertical inside vertical, causes gesture conflicts and is prohibited

### Context Menus & Drag-and-Drop

- **Context menu trigger** — long-press on mobile; right-click on desktop; `⋮` / `…` menu button always present as a non-gesture fallback
- Context menus must show only actions relevant to the specific item — never a generic global menu
- Destructive actions (delete, remove, archive) must be visually distinct in the menu (red label or warning icon) and must be the last item
- **Drag-and-drop**:
  - Show a drag preview (a "ghost" of the item) attached to the pointer/finger during drag
  - Valid drop zones highlight on hover; invalid zones show no highlight (never a red X)
  - Drop snaps to the closest valid position; animate the item into its final slot
  - If the drag is cancelled (released outside a valid zone, `Escape` pressed), the item animates back to its origin
  - Multi-select drag: all selected items travel together in a stacked preview with a count badge
- Drag handles on reorderable lists must be visible (not hidden behind a long-press); an explicit handle icon is required when the list has both tap-to-open and drag-to-reorder behaviors on the same row

### State Persistence Across Interruptions

- **Background / app switch** — save all unsaved user input (forms, compose views, search queries) to a draft store before the app leaves the foreground; restore on return
- **Phone call / system overlay** — treat the same as backgrounding; never discard in-progress state because of a transient overlay
- **Rotation / resize** — UI state (scroll position, selected item, expanded/collapsed sections, modal open/closed) must survive orientation changes and window resizes without resetting to defaults
- **Process kill / crash recovery** — any user-authored content (typed text, drawn content, partially filled form) must be auto-saved at least every 30 seconds to a recoverable draft; on next launch, offer to restore
- **Network interruption** — in-flight actions (form submit, file upload, send message) must be queued and retried automatically; user must see a clear status: sending → queued → sent/failed; never silently drop
- **Session expiry** — if authentication expires mid-session, preserve all unsaved state, redirect to login, then restore state after re-authentication; never discard work

### Focus Management

- Every modal, dialog, drawer, and sheet must trap focus — keyboard/tab navigation must not escape to content behind the overlay while it is open (web: use native `<dialog>` via `showModal()` — focus trap, `Escape`, and `::backdrop` come free; never hand-roll a JS focus trap or a `:target` modal)
- On open: move focus to the first interactive element inside the overlay, or the close button if no other primary action exists
- On close: return focus to the element that triggered the open
- Tab order must follow visual reading order (top-left → bottom-right for LTR; mirrored for RTL); never rely on render/DOM order alone
- Auto-focus rules: auto-focus the primary input in a form-only view; never auto-focus in a mixed-content view — it disrupts screen readers and scroll position
- Focus indicators must always be visible; style them to match the design system (never just suppress the default without a custom replacement)
- Web: provide a "skip to main content" link as the first focusable element on every page

### Toast / Snackbar / Banner

- **Toast / Snackbar** — transient, non-blocking; appears at bottom of screen (mobile) or bottom-center / top-right (desktop/web); auto-dismisses on a timer
- Duration: informational = 3s; with an action button = 5s; error = persistent until explicitly dismissed
- Maximum one toast visible at a time; queue additional toasts; never stack them simultaneously
- A toast may carry one action button (e.g. "Undo", "Retry") — never two
- Tapping outside a toast does not dismiss it; only the timer, action button, or an explicit × does
- Never use a toast for an error that requires user action — use a dialog or banner instead
- **Banner** — persistent, full-width; sits below the top bar or above the content area; used for offline state, degraded-mode warnings, or required-action notices; always has a dismiss or action path
- **Severity tiers** (apply to both toast and banner):

  | Tier | Color | Icon |
  |------|-------|------|
  | Info | neutral | none required |
  | Success | green | checkmark |
  | Warning | amber | warning triangle |
  | Error | red | error circle |

### Bottom Sheets & Modal Presentation

- **Bottom sheet** — slides up from the bottom edge; used for contextual actions, pickers, and filter panels; not a replacement for full-page navigation
- Drag handle (pill indicator) is required on all draggable sheets; centered at the top of the sheet
- Snap points: minimum two — a "peek" height (~40% screen) and "full" height (near full screen, safe area respected); releasing below the lowest snap point dismisses
- Dismiss threshold: sheet released below 40% of its open height, or downward velocity > 800 unit/s = dismiss; otherwise snap to nearest point
- Scrim behind the sheet: tap dismisses; scrim opacity scales with sheet position (0 at closed → 0.5 at full open)
- Sheet stacking: underlying sheet scales down and shifts back (card-stack effect); maximum two sheets deep; never three
- **Modal dialogs** — centered overlay; used for decisions that block proceeding; always provide both a confirm and a cancel path
- Dialogs for consequential actions (destructive, data loss) must not be dismissable by tapping the scrim — only explicit buttons
- Full-screen modals: use for complex flows requiring full attention; always provide a clear back/close affordance in the top bar

### Popovers & Tooltips

- **Tooltip** — appears on hover (desktop/web) or long-press (mobile); shows a short label for an unlabeled control; auto-dismisses on pointer-out or tap-elsewhere
- Tooltip delay: 300–500ms on hover; immediate on long-press (haptic provides the trigger confirmation)
- Never put interactive content (buttons, links) inside a tooltip — use a popover instead
- **Popover** — anchored overlay containing interactive content; arrow/caret points to the trigger element
- Positioning priority: below → above → right → left; flip automatically when the preferred position would clip outside the viewport
- Dismiss on: tap/click outside, `Escape` key, or an explicit close button inside; never auto-dismiss on a timer
- A popover must never open another popover — use a menu or sheet instead
- On small screens (mobile), a popover wider than ~80% of the screen width should become a bottom sheet instead
- Arrow/caret must always point to the exact trigger element even after the popover has been repositioned to avoid clipping

### Selection Mode & Multi-select

- Selection mode is entered by: long-press on an item (mobile), checkbox click (desktop/web), or an explicit "Select" button
- On entry: show a selection toolbar (top or bottom); show checkboxes or selection indicators on all items; hide non-selection actions
- On exit (cancel or complete): restore all items to default state; hide toolbar; return focus to the last interacted item
- "Select all / Deselect all" must always be available in the selection toolbar when a list has 2+ items
- Count badge in the toolbar updates in real time as items are selected/deselected
- **Batch action toolbar** — fixed position (does not scroll with the list); shows only actions valid for the entire current selection; destructive actions are last and visually distinct
- Tapping an already-selected item deselects it — it does not open it
- Long-press on a second item selects the range between first and second on ordered lists; shift-click is the desktop equivalent
- Swipe-to-action on rows is suspended while selection mode is active — swiping instead selects/deselects

### Undo & Redo

- Any reversible user action must support undo: text edits, moves, deletes, archives, sends (within a grace window)
- Undo trigger: shake gesture (mobile — respect system setting; if disabled, do not implement), `Cmd+Z` / `Ctrl+Z` (desktop/web), or the action button on the confirmation toast
- Redo trigger: `Cmd+Shift+Z` / `Ctrl+Y` (desktop/web); no standard mobile gesture — expose via an Edit menu or toolbar button
- Undo history depth: minimum 20 steps for text editing; minimum 1 step for destructive actions
- When an action is undoable, show a toast immediately: "[Action] — Undo" with a 5s timer; the toast is the primary undo path on mobile
- Actions that cannot be undone must say so explicitly before confirmation — never silently non-undoable
- Undo/redo state must survive rotation and backgrounding; it does not need to survive process kill

### Offline & Network-aware UI

- **Offline indicator** — a persistent banner or status bar tint when the device has no network; must appear within 2s of connectivity loss; must disappear within 2s of reconnection
- Never hide network state — if an action failed due to connectivity, say so explicitly ("Saved locally — will sync when online")
- **Queued actions** — any action taken offline must be queued and shown as pending in the UI (e.g. a message shown with a clock icon, not a checkmark); auto-retry with exponential backoff when connectivity returns
- **Degraded mode** — if the service is reachable but slow or partially unavailable, show a non-blocking warning banner; do not block the entire UI
- Never disable the UI entirely when offline — allow read-only access to cached data; disable only actions that require a network round-trip, with a clear disabled reason shown on hover/press
- Retry UX: offer a manual "Retry" button for failed actions alongside automatic retry; show retry count only after two or more failures
- Data freshness: show a "Last updated X ago" label once cached data exceeds its staleness threshold — live/real-time data (chat, prices, status feeds): 30s; frequently-changing data (feeds, dashboards): 5 min; slow-changing data (settings, profiles): 1 hour; static/reference data: 24h. A project MAY override these in its IDEA.md/SPEC.md. Never silently serve stale data as current

### Pointer & Hover Adaptation

- **Hover states** — required on all interactive elements on pointer-capable devices; hover must never be the only path to an action — every hover-revealed action must also be reachable via tap or keyboard
- Hover transition: 100–150ms ease; never instant (jarring) and never >200ms (sluggish)
- **Cursor shapes** — use the correct cursor for context:

  | Cursor | When |
  |--------|------|
  | Default arrow | non-interactive areas |
  | Pointer (hand) | links, buttons, clickable cards |
  | Text (I-beam) | text inputs, selectable text |
  | Grab / grabbing | draggable elements (open at rest, closed while dragging) |
  | Resize (directional) | resize handles |
  | Wait / progress | UI blocked on an operation |
  | Not-allowed | disabled interactive elements — always pair with a tooltip explaining why |

- **Touch + mouse hybrid devices** — detect input type at event time, not at startup; users may switch between touch and mouse mid-session; hover states must appear and disappear reactively
- On touch, hover styles must never get "stuck" after a tap — clear hover state on pointer-up / touch-end
- Minimum touch target (44×44 px) still applies even when a mouse is connected — never shrink targets on mouse-only assumptions
- Right-click on desktop and long-press on mobile must produce the same context menu for the same element

### Voice Input

- Voice input states must be visually distinct across all surfaces: idle → listening → processing → result committed; never leave the mic active without a clear visible indicator
- Listening indicator: animated waveform or pulsing mic icon; visible in the top bar or inline in the input field
- Interim transcription (words appearing while speaking) must be visually distinct from committed text (e.g. dimmed or italic) until finalized
- Silence timeout: stop listening after 2–3s of silence; give a visual countdown in the final second
- Cancel: tapping outside the voice input or pressing the mic button again cancels cleanly; never leave the mic active in the background
- Errors (no speech detected, service unavailable): show an inline message below the field; never a blocking dialog; fall back to keyboard/text input automatically
- Voice input must be opt-in per field — never auto-activate on field focus

### Stylus & Pen Input

- Detect stylus/pen hover (proximity) separately from finger touch; show a precision crosshair cursor on stylus hover
- Respect palm rejection — ignore touch contacts within a defined margin around an active stylus stroke
- Pressure sensitivity: map to stroke weight, opacity, or tool size in drawing/annotation contexts; in standard UI contexts treat all pressure levels as a normal tap
- Tilt/rotation: use for tool angle in drawing contexts; ignore in standard UI interactions
- Barrel button (first): context menu / right-click equivalent; barrel button (second, if present): undo — never reassign these without explicit user configuration
- Stylus proximity hover is for precision cursor display only — do not use it to reveal hidden actions (a finger user would never see them)
- Mobile: palm rejection must be active whenever a stylus event is in progress; desktop (drawing tablets): same rule applies

### Biometric Authentication Overlay

- Biometric prompts (fingerprint, face, iris, PIN fallback) are system-owned overlays — never simulate or replicate them in-app
- When a biometric prompt appears: pause all timers, animations, and auto-logout countdowns; resume on dismissal (success or failure)
- On success: proceed directly to the gated action without an additional in-app confirmation step
- On max-attempt failure: hand off to the platform's PIN/password fallback automatically — never show a custom fallback before the system fallback
- Never trigger biometric auth automatically on app foreground — only trigger when the user initiates a protected action
- The UI behind the biometric overlay must be obscured (blurred or replaced with a placeholder) to prevent shoulder-surfing of sensitive content
- Mobile: Face ID, Touch ID, Android fingerprint/face. Desktop: Windows Hello, macOS Touch ID — same rules apply on both
