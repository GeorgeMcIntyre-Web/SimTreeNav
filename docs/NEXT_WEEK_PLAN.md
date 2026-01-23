# Next Week Plan: CI Hardening & Manager-Readiness

**Goal for the week:** Finish Track B properly (CI gates + artifacts + clear failure signals) and make the repo "manager-ready" without burning tokens.

## Current Status (Context)
* **Unit Test Coverage:** Currently 0% reported. SimTreeNav has custom PowerShell tests but no coverage tooling (Pester/Codecov) configured.
* **Objective:** Migrate RunStatus tests to Pester and add a CI step for coverage on `scripts/lib/*.ps1`.

## Token Rules
* **One agent = one mission** per day (no "while you're there...").
* Prompts must include: *goal, files, acceptance checks, stop conditions*.
* **Claude**: Review/Decide/Plan.
* **Codex**: Edit code/Implement.
* **Antigravity**: Docs/Polish.

---

## Monday — Lock scope + acceptance gates

**Claude Code #1 (Planner/PM, low tokens):**
* Output: `docs/ACCEPTANCE.md` (definition of "green CI") + checklist for PRs.
* Include: required jobs, artifacts, failure messaging, secret scan rules.

**Codex (Implementer, medium tokens):**
* Verify workflows are wired for PR + push to main.
* Ensure artifacts always upload even on failure.

**Antigravity (Docs polish, low tokens):**
* Update `docs/PRODUCTION_RUNBOOK.md` with "CI failure triage" (what to check first).

---

## Tuesday — CI hardening + deterministic outputs

**Claude Code #2 (QA/Failure-mode reviewer):**
* Review CI steps for brittle paths (linux vs windows paths, missing out dirs).
* Output: a short list of "likely failures" + exact fixes.

**Codex (Implementer):**
* Make CI create required folders (`out/`, `test/integration/results/`) before running tests.
* Make smoke mode deterministic: always produces `run-status.json` even on expected fail.

---

## Wednesday — Coverage *measurement* (not "more tests" yet)

**Claude Code #3 (Test strategy, low tokens):**
* Decide the **coverage boundary** (start with `scripts/lib/*.ps1` only).
* Decide metric: line coverage vs function coverage (pick one, keep it simple).

**Codex (Implementer, medium tokens):**
* Add **Pester** just for `RunStatus.ps1` + `EnvChecks.ps1`.
* Add CI step to output a coverage summary (even plain text is fine).
* Deliverable: **a real %** for the library layer (not the whole repo yet).

---

## Thursday — Secrets + operational safety gates

**Claude Code #1 (Security review, low tokens):**
* Review grep-based secret scan patterns for false positives / blind spots.
* Tighten excludes so you don't miss dangerous files.

**Codex (Implementer):**
* Improve secret scan to focus on risky file types (env, yaml, ini, conf, psd1 if used).
* Ensure it fails loudly with actionable output.

---

## Friday — Merge-ready packaging

**Antigravity (Docs, low tokens):**
* One-page "How to run locally + how to read failures" doc section.

**Claude Code #2 (Release reviewer):**
* Run through acceptance checklist and produce a merge recommendation.

**Codex (Final fixes only):**
* Address only the reviewer's top issues.
* No new features.

---

## Outcome by end of week
* CI is "boringly reliable"
* Failures are explainable (run-status + artifacts)
* **Real coverage %** available for `scripts/lib/` instead of guessing
