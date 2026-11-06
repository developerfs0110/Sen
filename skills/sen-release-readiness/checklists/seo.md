# SEO & Web Metadata Release Checklist

> **Applicability:** Run this checklist when the project includes public-facing web pages, landing pages, documentation sites, or web apps meant to be shared or indexed. If the project is a CLI tool, internal backend, or local plugin with no public web pages, mark this domain `PASS (N/A)`.
>
> **Severity Key:** Unmet `[BLOCK]` items prevent search indexing or break public link sharing and must mark the domain `BLOCK`. Unmet `[WARN]` items mark the domain `WARN`.

## Checklist Items

- [ ] **[BLOCK] Unique `<title>` and Meta Description on Public Pages:** Every public route renders a descriptive, non-placeholder `<title>` and `<meta name="description">` tailored to the page content.
- [ ] **[BLOCK] Production Indexing Not Blocked by Accident:** Public pages do not accidentally ship with `<meta name="robots" content="noindex">` or a `robots.txt` `Disallow: /` rule left over from staging, while private/admin routes are properly excluded from indexing.
- [ ] **[BLOCK] Valid Language & Viewport Declarations:** The root `<html lang="...">` attribute matches the page language (e.g., `vi` or `en`), and `<meta name="viewport" content="width=device-width, initial-scale=1">` is present for mobile friendliness.
- [ ] **[BLOCK] No Broken Internal Links or 404 Assets:** All internal navigation links, documentation links, and primary CTA buttons resolve to valid routes/files without dead `404` targets.
- [ ] **[WARN] Canonical URLs Configured:** Public pages specify `<link rel="canonical" href="...">` using the production domain and HTTPS scheme to prevent duplicate-content dilution.
- [ ] **[WARN] Open Graph & Social Sharing Cards (`og:*`, `twitter:*`):** Key landing pages define `og:title`, `og:description`, `og:image`, `og:url`, and `twitter:card` with an absolute production image URL so shared links render cleanly in chat and social apps.
- [ ] **[WARN] Sitemap (`sitemap.xml`) & `robots.txt` Present:** Public multi-page sites expose an accurate `sitemap.xml` and `robots.txt` referencing the sitemap URL.
- [ ] **[WARN] Semantic Heading Structure (`<h1>`):** Each indexable page contains a single clear `<h1>` matching the primary topic of the page, supported by logical `<h2>`/`<h3>` subheadings.
- [ ] **[WARN] Favicon & App Manifest Icons:** A valid favicon (`favicon.ico` / SVG / `apple-touch-icon`) is configured so browser tabs and bookmarks do not request a missing `/favicon.ico` (`404`).
- [ ] **[WARN] Structured Data (`JSON-LD`) Where Relevant:** Product, article, organization, or FAQ pages include valid Schema.org `application/ld+json` metadata where rich search snippets apply.
