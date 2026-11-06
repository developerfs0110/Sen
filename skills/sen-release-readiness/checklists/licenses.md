# Open-Source Licenses & Third-Party Attribution Checklist

> **Applicability:** Run this checklist for all software projects that ship source code, binaries, containers, or client bundles, or that integrate third-party packages.
>
> **Severity Key:** Unmet `[BLOCK]` items create legal/copyleft or redistribution violations and must mark the domain `BLOCK`. Unmet `[WARN]` items mark the domain `WARN`.

## Checklist Items

- [ ] **[BLOCK] Project License File Present:** If the repository or package is distributed externally, a root `LICENSE` file exists with the exact license text, copyright year, and copyright holder approved by the project owner.
- [ ] **[BLOCK] No Incompatible Copyleft Dependencies:** Direct and transitive dependencies (in `package.json`, `requirements.txt`, `pyproject.toml`, `Cargo.toml`, `go.mod`, etc.) do not include restrictive copyleft licenses (`GPL`, `AGPL`, `SSPL`, `CC-BY-NC`, `Commons Clause`) that conflict with the project's distribution model.
- [ ] **[BLOCK] Commercial / Proprietary SDK Licensing Verified:** Any proprietary SDKs, fonts, icons, or media assets included in the repository have valid redistribution or commercial licenses covering production deployment.
- [ ] **[BLOCK] Copied or Vendored Third-Party Code Retains Headers:** Any third-party files, snippets, or skills vendored or adapted into the repository preserve their original license files and copyright headers as required by MIT/Apache-2.0/BSD terms.
- [ ] **[BLOCK] Apache-2.0 `NOTICE` File Compliance:** If the project redistributes dependencies licensed under Apache-2.0 that include a `NOTICE` file, those attributions are preserved in distribution artifacts or third-party notices.
- [ ] **[WARN] Third-Party Attribution / `THIRD_PARTY_NOTICES`:** Client-shipped applications (mobile apps, desktop apps, frontend bundles, or CLI binaries) include an up-to-date third-party attribution list or `README` credits section acknowledging key upstream packages and their licenses.
- [ ] **[WARN] Package Manifest License Metadata Matches `LICENSE`:** The `license` field in `package.json`, `plugin.json`, `pyproject.toml`, or equivalent manifest matches the root `LICENSE` file (and is not left as a default mismatch).
- [ ] **[WARN] Lockfile Integrity & Known License Audit:** Dependency lockfiles are committed and synchronized with manifests so no unreviewed transitive packages with unknown (`UNLICENSED` or missing) licenses are pulled during release builds.
- [ ] **[WARN] AI / Dataset / Media Asset Usage Rights:** Sample data, illustrations, logos, and audio/video files shipped with the release are free of third-party trademark infringement or unlicensed copyrighted material.
