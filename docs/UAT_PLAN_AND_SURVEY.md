# UAT Plan & Survey

**Goal**: Confirm Phase 2 Readiness with key stakeholders.
**Dates**: Feb 4 - Feb 6, 2026.

## Sessions

### Session 1: Executive / High-Level (30 mins)
- **Who**: Project Sponsor.
- **Goal**: "Does this look professional and accurate?"
- **Tasks**:
  1. Open Dashboard. Check "Top Level KPI".
  2. Navigate to a specific Plant Node in the Tree.
- **Success**: No confusion on navigation.

### Session 2: PM / Power User (60 mins)
- **Who**: Product Manager.
- **Goal**: Data verification and feature check.
- **Tasks**:
  1. Compare "At Risk" count on Dashboard vs Source System.
  2. Verify "Drill-down" links work for all 5 test cases.
  3. Validate "Search" functionality finds specific assets.
- **Success**: Data matches within 1% tolerance (timing diff).

### Session 3: Engineering / Support (60 mins)
- **Who**: Lead Engineer / Support Rep.
- **Goal**: Usability and Performance.
- **Tasks**:
  1. Load large tree (Fast loading check).
  2. Simulate "Offline" mode (check for graceful error or cached view).
- **Success**: No crashes, performance feels "snappy".

## UAT Survey

**Please rate on 1-5 Scale (1=Poor, 5=Excellent):**

1.  **Visual Appeal**: How professional does the dashboard look? [ ]
2.  **Navigation Speed**: How fast can you find what you need? [ ]
3.  **Data Trust**: Do you trust the numbers shown? [ ]
4.  **Ease of Use**: Was it intuitive without training? [ ]

**Qualitative Questions:**
- What is the ONE thing that confused you?
- What is the ONE feature you'd miss if we took it away?
- Any critical bugs found? (Describe)

## Scoring Rubric
- **Go**: Average Score > 4.0, No Critical Bugs.
- **Caution**: Average Score > 3.0, Non-Critical Bugs (Fix in Phase 2.1).
- **Stop**: Average Score < 3.0 OR Critical Data Error.
