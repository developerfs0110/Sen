# Accessibility (a11y) Release Checklist

> **Applicability:** Run this checklist for all projects with a user interface (web apps, mobile apps, desktop UI, interactive HTML widgets, or CLI output meant for human readers). If the project is a headless backend/library with no UI, mark `PASS (N/A)`.
>
> **Severity Key:** Unmet `[BLOCK]` items prevent keyboard or assistive-technology users from completing core flows and must mark the domain `BLOCK`. Unmet `[WARN]` items mark the domain `WARN`.

## Checklist Items

- [ ] **[BLOCK] Full Keyboard Navigation for Core Flows:** Every interactive control (links, buttons, forms, dialogs, menus) in primary user flows can be reached and operated using only the keyboard (`Tab`, `Shift+Tab`, `Enter`, `Space`, `Escape`) with no keyboard traps.
- [ ] **[BLOCK] Accessible Names & Form Labels:** All form inputs (`<input>`, `<select>`, `<textarea>`) have programmatic labels (`<label for="...">`, `aria-label`, or `aria-labelledby`), and icon-only buttons have descriptive accessible names.
- [ ] **[BLOCK] Meaningful Alt Text on Informative Images:** All non-decorative `<img>`, `<svg>`, and canvas elements convey equivalent meaning via `alt` or ARIA attributes, while purely decorative graphics use `alt=""` or `aria-hidden="true"`.
- [ ] **[BLOCK] Sufficient Text Color Contrast:** Body text and essential interactive controls meet WCAG AA minimum contrast ratios (`4.5:1` for normal text, `3:1` for large text and UI components) in both light and dark modes.
- [ ] **[BLOCK] Visible Focus Indicators:** Interactive elements display a clear, visible focus outline (`:focus-visible`) that is never suppressed with `outline: none` unless replaced by an equally visible indicator.
- [ ] **[WARN] Semantic HTML Landmarks & Heading Hierarchy:** Pages use semantic landmarks (`<main>`, `<nav>`, `<header>`, `<footer>`) and a logical heading hierarchy (`<h1>` through `<h6>`) without skipping levels arbitrarily.
- [ ] **[WARN] Modal & Dialog Focus Management:** Opening a dialog/modal moves focus inside the modal, traps focus while open, closes on `Escape`, and restores focus to the triggering element on close.
- [ ] **[WARN] Accessible Error & Status Announcements:** Form validation errors and asynchronous status updates are linked to inputs (`aria-describedby`, `aria-invalid`) or announced via live regions (`role="alert"`, `aria-live="polite"`), not communicated by color alone.
- [ ] **[WARN] Respect Reduced Motion & Text Zoom:** Animations respect `prefers-reduced-motion: reduce`, and layouts remain usable without horizontal scrolling or overlapping text when zoomed to `200%`.
- [ ] **[WARN] Touch Target Size on Mobile / Responsive Views:** Interactive touch targets are at least `44x44` CSS pixels (or `24x24` minimum with adequate spacing) to prevent accidental taps.
