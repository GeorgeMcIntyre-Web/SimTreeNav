# User Acceptance Testing (UAT) Plan

## Overview
Comprehensive user acceptance testing to validate the navigation tree against Siemens Process Simulate application.

---

## Test Objectives

1. **Verify completeness**: All expected nodes present
2. **Verify structure**: Parent-child relationships correct
3. **Verify icons**: Icons match Siemens app (automated coverage + spot check)
4. **Verify ordering**: Nodes appear in correct SEQ_NUMBER order
5. **Verify usability**: Tree is intuitive and performant
6. **Verify data accuracy**: Names, IDs, and metadata correct

---

## Test Environment

**Prerequisites:**
- Siemens Process Simulate application installed
- Access to DESIGN12 schema, FORD_DEARBORN project
- Generated navigation tree HTML file
- Both applications showing same project/data

---

## Test Categories

### 1. Structural Completeness Tests

#### Test 1.1: Root Level Comparison
**Procedure:**
1. Open Siemens Process Simulate → FORD_DEARBORN project
2. Note all top-level items in tree
3. Open generated HTML tree
4. Compare root-level children

**Expected:**
- All root-level items from Siemens app present in HTML
- Order matches (by SEQ_NUMBER)
- Icons match

**Checklist:**
- [ ] Same number of root children
- [ ] Same node names
- [ ] Same icons
- [ ] Same order

**Results:**
```
Siemens App Root Children:        HTML Tree Root Children:
1. _______________                 1. _______________
2. _______________                 2. _______________
3. _______________                 3. _______________
...                                ...

Match: ✅ YES / ❌ NO
```

#### Test 1.2: Critical Path Verification
**Procedure:**
Test the paths documented in `verify-critical-paths.ps1`:

**Path 1:** FORD_DEARBORN → PartLibrary → P702 → 01 → CC → COWL_SILL_SIDE
**Path 2:** FORD_DEARBORN → PartInstanceLibrary → P702 → 01 → CC → COWL_SILL_SIDE

**For each path:**
1. Navigate in Siemens app
2. Navigate in HTML tree
3. Verify each level exists and matches

**Expected:**
- All intermediate nodes present
- Final node accessible
- All 4 children under PartInstanceLibrary path visible

**Checklist:**
- [ ] Path 1 complete
- [ ] Path 2 complete
- [ ] All 4 children visible: COWL_SILL_SIDE_F, COWL_SILL_SIDE_L, COWL_SILL_SIDE_R, COWL_SILL_SIDE_SOP

**Results:**
```
Path 1: ✅ PASS / ❌ FAIL
Path 2: ✅ PASS / ❌ FAIL
Children: ✅ ALL PRESENT / ❌ MISSING: ___________
```

#### Test 1.3: Deep Node Verification
**Procedure:**
1. In Siemens app, navigate to a deeply nested node (5+ levels)
2. Note the complete path
3. Navigate to same node in HTML tree
4. Verify path and node details match

**Example paths to test:**
- Process flow nodes
- Nested part instances
- Study configurations
- Device hierarchies

**Checklist:**
- [ ] Deep node found in HTML
- [ ] Path matches Siemens app
- [ ] Node details correct

**Results:**
```
Test Path: (see screenshots)
Depth: 12 levels (HTML)
Found in HTML: YES (HTML)
Details match: DEFERRED (Siemens comparison pending)
```

---

### 2. Icon Verification Tests

**Best practice:** Do not attempt to manually verify all 221 icons. Use automated coverage from generation logs and a small, representative spot check in the UI.

#### Test 2.1: Automated Icon Coverage (Log-Based)
**Procedure:**
1. Generate the HTML tree and open the console output or HTML log section.
2. Confirm icon summary indicates all class-to-icon mappings are present.
3. Confirm representative icon loads for root libraries (e.g., FORD_DEARBORN, PartLibrary, PartInstanceLibrary, MfgLibrary, EngineeringResourceLibrary, DES_Studies).

**Expected:**
- All mappings present (no missing TYPE_IDs)
- Representative icon loads recorded for key root/library nodes

**Checklist:**
- [ ] Icon summary shows all class-to-icon mappings found
- [ ] No missing TYPE_IDs reported
- [ ] Icon load lines present for root/library nodes

**Results:**
```
Log evidence:
- ICON SUMMARY present: YES
- Missing TYPE_IDs: NONE
- Root/library icon loads: YES

Overall: PASS
```

#### Test 2.2: Targeted Icon Spot Check (UI)
**Procedure:**
1. In Siemens app, pick a small set of representative nodes across types.
2. Compare those icons in the HTML tree.
3. If any mismatch is found, expand the sample set.

**Suggested sample (8-12 nodes):**
- Project root
- Libraries (PartLibrary, ResourceLibrary, MfgLibrary)
- Part instance node
- Resource node (robot or station)
- Study node (RobcadStudy)
- Device node (fixture or gun)

**Expected:**
- Sampled icons match Siemens app
- Inherited/derived icons appear correctly in the sample

**Checklist:**
- [x] Sampled icons match Siemens app
- [x] Derived type icon (e.g., RobcadStudy) correct
- [x] No broken images in sample

**Results:**
```
Sample size: 8
Matches: 8
Mismatches: N/A
Issues found: None
```

---
### 3. Data Accuracy Tests

#### Test 3.1: Node Names
**Procedure:**
1. Select 20 random nodes from different levels
2. Compare names between Siemens app and HTML tree

**Expected:**
- Names match exactly
- Special characters display correctly
- German umlauts preserved

**Checklist:**
- [ ] Names match
- [ ] Special characters correct
- [ ] Umlauts display properly
- [ ] No encoding issues

**Results:**
```
Nodes tested: 0 (deferred)
Exact matches: N/A
Mismatches: N/A

Issues: Deferred - too many nodes to verify manually; sampling pending
```

#### Test 3.2: Node Ordering (SEQ_NUMBER)
**Procedure:**
1. Select a parent with multiple children (10+ children)
2. Note order in Siemens app
3. Compare with HTML tree order

**Expected:**
- Order matches exactly
- SEQ_NUMBER sorting working

**Checklist:**
- [ ] Order matches Siemens app
- [ ] Alphabetical within same SEQ_NUMBER
- [ ] No random ordering

**Results:**
```
Test Parent: N/A (deferred)
Child count: N/A
Order matches: DEFERRED (manual comparison pending)
```

#### Test 3.3: External IDs
**Procedure:**
1. Find nodes with external IDs visible in Siemens app
2. Check if external IDs present in HTML tree (hover or properties)

**Expected:**
- External IDs preserved in data
- Visible in node details (if implemented)

**Checklist:**
- [ ] External IDs in data
- [ ] Can view external IDs
- [ ] IDs match Siemens app

**Results:**
```
External IDs working: DEFERRED
```

---

### 4. User Activity Tests

#### Test 4.1: Checked Out Items
**Procedure:**
1. Check out several items in Siemens Process Simulate
2. Regenerate HTML tree
3. Verify checked-out status shown

**Expected:**
- Checked-out items highlighted (if implemented)
- User name shown (if implemented)
- Status accurate

**Checklist:**
- [ ] Checked-out items identified
- [ ] User names shown
- [ ] Status accurate

**Results:**
```
Checked-out items: ___
Correctly identified: ___
User activity working: ✅ YES / ⚠️ PARTIAL / ❌ NO
```

---

### 5. Usability Tests

#### Test 5.1: Navigation Efficiency
**Procedure:**
1. User tries to find specific nodes using tree
2. Time how long it takes
3. Compare with Siemens app

**Example tasks:**
- Find a specific part: "COWL_SILL_SIDE_R"
- Find a robot: "Robot_01" (if exists)
- Find a study: "[Study name]"

**Expected:**
- Can find nodes quickly
- Search helps (if used)
- Expand/collapse smooth

**Checklist:**
- [ ] Can find nodes easily
- [ ] Search is helpful
- [ ] Tree is responsive
- [ ] No lag when expanding

**Results:**
```
Task 1 - Find Part: ___ seconds (✅ FAST / ⚠️ SLOW)
Task 2 - Find Robot: ___ seconds (✅ FAST / ⚠️ SLOW)
Task 3 - Find Study: ___ seconds (✅ FAST / ⚠️ SLOW)

Overall usability: ✅ EXCELLENT / ✓ GOOD / ⚠️ FAIR / ❌ POOR
```

#### Test 5.2: Visual Clarity
**Procedure:**
1. User reviews tree visual design
2. Compares with Siemens app

**Expected:**
- Icons clear and recognizable
- Text readable
- Hierarchy clear (indentation)
- Colors appropriate

**Checklist:**
- [ ] Icons clear
- [ ] Text readable
- [ ] Hierarchy obvious
- [ ] Professional appearance

**Results:**
```
Visual design: ✅ EXCELLENT / ✓ GOOD / ⚠️ NEEDS WORK
Feedback: _______________
```

#### Test 5.3: Browser Performance
**Procedure:**
1. User interacts with tree for 10 minutes
2. Note any lag, freezes, or issues

**Expected:**
- Smooth interaction
- No memory leaks
- Fast expand/collapse
- Fast search

**Checklist:**
- [ ] No lag when expanding nodes
- [ ] Search is fast (<3s)
- [ ] No browser freezes
- [ ] Memory stable

**Results:**
```
Performance: ✅ EXCELLENT / ✓ GOOD / ⚠️ SOME LAG / ❌ SLOW

Issues: Deferred - too many nodes to verify manually; sampling pending
```

---

### 6. Missing Node Investigation

#### Test 6.1: Random Sampling
**Procedure:**
1. Select 10 random nodes from different branches in Siemens app
2. Search for each in HTML tree
3. Document any missing nodes

**Expected:**
- All nodes found
- If missing, investigate why

**Checklist:**
```
Node 1: _______________ - ✅ FOUND / ❌ MISSING
Node 2: _______________ - ✅ FOUND / ❌ MISSING
Node 3: _______________ - ✅ FOUND / ❌ MISSING
Node 4: _______________ - ✅ FOUND / ❌ MISSING
Node 5: _______________ - ✅ FOUND / ❌ MISSING
Node 6: _______________ - ✅ FOUND / ❌ MISSING
Node 7: _______________ - ✅ FOUND / ❌ MISSING
Node 8: _______________ - ✅ FOUND / ❌ MISSING
Node 9: _______________ - ✅ FOUND / ❌ MISSING
Node 10: ______________ - ✅ FOUND / ❌ MISSING

Missing count: ___
```

**Results:**
```
All nodes found: DEFERRED (sampling pending)

If missing, details:
- Node name: _______________
- Expected path: _______________
- Possible reason: Deferred - sampling pending
```

---

## UAT Sign-Off

### Test Summary

**Date:** _______________
**Tester:** _______________
**Environment:** Siemens Process Simulate + HTML Tree
**Database:** DESIGN12 / FORD_DEARBORN

### Results Overview

| Category | Tests | Passed | Failed | Issues |
|----------|-------|--------|--------|--------|
| Structural Completeness | 3 | ___ | ___ | ___ |
| Icon Verification | 2 | ___ | ___ | ___ |
| Data Accuracy | 3 | ___ | ___ | ___ |
| User Activity | 1 | ___ | ___ | ___ |
| Usability | 3 | ___ | ___ | ___ |
| Missing Nodes | 1 | ___ | ___ | ___ |
| **TOTAL** | **13** | **___** | **___** | **___** |

### Critical Issues Found
1. _______________
2. _______________
3. _______________

### Minor Issues Found
1. _______________
2. _______________
3. _______________

### Recommendations
1. _______________
2. _______________
3. _______________

### Overall Assessment

**Tree Completeness:** ✅ COMPLETE / ⚠️ MOSTLY COMPLETE / ❌ INCOMPLETE

**Data Accuracy:** ✅ ACCURATE / ⚠️ MINOR ISSUES / ❌ MAJOR ISSUES

**Performance:** ✅ EXCELLENT / ✓ GOOD / ⚠️ ACCEPTABLE / ❌ POOR

**Usability:** ✅ EXCELLENT / ✓ GOOD / ⚠️ ACCEPTABLE / ❌ POOR

### Final Verdict

**Status:** WIP - not signed; remaining checks deferred due to scale

**Signatures:**

Tester: _______________ Date: _______________

Approver: _______________ Date: _______________

---

## Notes and Observations

- Verified MfgLibrary weld points now visible in HTML (DESIGN12 / FORD_CX727_MEXICO), e.g., 90007-01-L_T2.
- DESIGN1 root '?' placeholders now render with correct names/icons after metadata merge.

---

**Next Steps After UAT:**
1. Address any critical issues found
2. Prioritize minor issues for future improvements
3. Update STATUS.md with UAT results
4. Document in production-ready state (if approved)

---
Date: 2026-01-20
Status: WIP - partial execution; icon verification complete; remaining checks deferred due to scale
