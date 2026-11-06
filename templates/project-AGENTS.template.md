# Project Verification Gates and Rules

This file defines project-specific constraints and verification gates for `{{PROJECT_NAME}}`. Agents working within this directory must adhere to these instructions in addition to workspace rules.

## Verification Gates for Delivery (Tier 2 and Tier 3)

Before declaring any Tier 2 or Tier 3 task complete or preparing a delivery report, the agent must run the required verification gates declared below.

### 1. Default Quality Gates
- **Tests & Build:** All automated tests must pass; build commands must succeed without error.
- **Verification Before Completion:** Invoke `verification-before-completion` to verify concrete evidence before claiming completion.

### 2. Security Gate (via `security-audit`)
- **Required:** {{ENABLE_SECURITY_GATE}}
- **Instructions:** Invoke the `security-audit` skill before releasing code changes. Verify that dependencies are free from known critical vulnerabilities, secret leaks, and insecure data handling.

### 3. Legal & Compliance Gate (via `vn-law-check`)
- **Required:** {{ENABLE_LEGAL_GATE}}
- **Instructions:** Check regulatory compliance and statutory requirements using `vn-law-check`.
  - If `vn-law-check` is installed: invoke it to review licensing, privacy notices, or required legal terms.
  - If `vn-law-check` is not installed: notify the user that legal checks cannot be automated yet and recommend installing the skill if compliance verification is needed.

### 4. Custom Project Gates
- **Custom Checks:**
  - Linting: Ensure code conforms to project styling rules.
  - Type Check: Ensure strict type checking passes where applicable.
  - Smoke / Scenario Tests: Execute user-facing acceptance flows.
