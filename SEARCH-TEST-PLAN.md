# Search Functionality Test Plan

## Overview
Comprehensive test plan for verifying search functionality with 632K nodes and 310K unique nodes.

---

## Test Categories

### 1. Basic Search Tests

#### Test 1.1: Simple Word Search
**Test:** Search for common node name (e.g., "Robot", "Station", "Part")
**Expected:**
- Results highlighted in yellow
- Parent nodes expanded to show results
- Multiple matches visible
- Search is case-insensitive

**Pass Criteria:**
- ✅ All matching nodes highlighted
- ✅ Parents expanded automatically
- ✅ No performance lag (<2 seconds)

#### Test 1.2: Numeric Search
**Test:** Search for object ID or number (e.g., "18140190", "123")
**Expected:**
- Nodes with matching numbers in name highlighted
- Works with External IDs
- Works with sequence numbers

**Pass Criteria:**
- ✅ Numeric matches found
- ✅ No errors in console

#### Test 1.3: Partial Match Search
**Test:** Search for partial word (e.g., "Rob" should find "Robot", "Robotic")
**Expected:**
- All nodes containing substring highlighted
- Case-insensitive matching

**Pass Criteria:**
- ✅ Partial matches work
- ✅ Highlighting accurate

#### Test 1.4: Empty Search
**Test:** Clear search box (empty string)
**Expected:**
- All highlights removed
- Tree returns to previous state
- No expanded nodes collapse

**Pass Criteria:**
- ✅ Highlights cleared
- ✅ No errors

---

### 2. Special Character Tests

#### Test 2.1: German Umlauts (ä, ö, ü, ß)
**Test:** Search for German characters commonly used in Siemens data
**Examples:**
- "Tür" (door)
- "Förder" (conveyor)
- "Prüf" (test)
- "Straße" (street)

**Expected:**
- Unicode characters match correctly
- Case-insensitive (ä matches Ä)
- No encoding issues

**Pass Criteria:**
- ✅ Umlauts found correctly
- ✅ No garbled text
- ✅ Diacritics work

#### Test 2.2: Special Characters in Names
**Test:** Search for nodes with special characters
**Examples:**
- Underscores: "PART_001"
- Dashes: "Robot-01"
- Parentheses: "Station (Main)"
- Brackets: "[Optional]"

**Expected:**
- Special characters treated as literal
- No regex errors

**Pass Criteria:**
- ✅ Special chars match
- ✅ No JavaScript errors

#### Test 2.3: Accented Characters (é, è, ñ, etc.)
**Test:** Search for accented characters
**Examples:**
- "Exposé"
- "Café"
- "Año"

**Expected:**
- Accents match correctly
- Unicode support working

**Pass Criteria:**
- ✅ Accents work
- ✅ No encoding issues

---

### 3. Performance Tests

#### Test 3.1: Search Performance with Many Results
**Test:** Search for common term that appears in 1000+ nodes (e.g., "Resource", "Object")
**Expected:**
- Search completes in <3 seconds
- Browser remains responsive
- All results highlighted
- No memory spikes

**Pass Criteria:**
- ✅ Completes in <3 seconds
- ✅ No browser freeze
- ✅ Memory stable

**How to measure:**
1. Open browser DevTools (F12)
2. Go to Console tab
3. Type: `console.time('search'); searchTree('Resource'); console.timeEnd('search');`
4. Check execution time

#### Test 3.2: Rapid Search (Type Fast)
**Test:** Type quickly in search box, changing query rapidly
**Expected:**
- Each keystroke triggers search
- No lag accumulation
- Final result matches final query

**Pass Criteria:**
- ✅ Responsive to fast typing
- ✅ No queued searches
- ✅ Correct final result

#### Test 3.3: Search with Lazy-Loaded Nodes
**Test:** Search for node that hasn't been rendered yet (deep in tree)
**Expected:**
- Search only finds rendered nodes
- OR search triggers rendering (if implemented)
- No errors for unrendered nodes

**Pass Criteria:**
- ✅ No JavaScript errors
- ✅ Search works on visible nodes
- ✅ (Optional) Can find deep nodes

---

### 4. Edge Cases

#### Test 4.1: Very Long Search Query
**Test:** Paste 100+ character string
**Expected:**
- No crashes
- Search completes (even with 0 results)
- No input truncation

**Pass Criteria:**
- ✅ Handles long input
- ✅ No errors

#### Test 4.2: Search with Regex Special Chars
**Test:** Search for: `.*+?[](){}^$|\\`
**Expected:**
- Treated as literal characters (not regex)
- No errors
- Finds exact match if exists

**Pass Criteria:**
- ✅ No regex interpretation
- ✅ No errors

#### Test 4.3: Search with Leading/Trailing Spaces
**Test:** Search for " Robot " (with spaces)
**Expected:**
- Spaces handled correctly
- Trimmed or matched literally

**Pass Criteria:**
- ✅ Consistent behavior
- ✅ No errors

#### Test 4.4: Case Sensitivity
**Test:** Search for "ROBOT", "robot", "Robot", "rObOt"
**Expected:**
- All return same results
- Case-insensitive matching

**Pass Criteria:**
- ✅ Case-insensitive
- ✅ All variants match

---

### 5. Visual Verification

#### Test 5.1: Highlight Visibility
**Test:** Search and verify highlighting
**Expected:**
- Highlighted nodes clearly visible (yellow background)
- Text remains readable
- Highlight removed when search cleared

**Pass Criteria:**
- ✅ Highlight visible
- ✅ Text readable
- ✅ Highlight clears properly

#### Test 5.2: Parent Expansion
**Test:** Search for deeply nested node
**Expected:**
- All parent nodes expand to show result
- Expand arrows updated correctly
- Scroll position shows result (if possible)

**Pass Criteria:**
- ✅ Parents expand
- ✅ Result visible
- ✅ Tree structure maintained

#### Test 5.3: Multiple Results
**Test:** Search with 5-10 results visible
**Expected:**
- All results highlighted
- Can see multiple matches in different branches
- Highlights don't overlap incorrectly

**Pass Criteria:**
- ✅ Multiple highlights work
- ✅ All visible

---

## Test Execution

### Manual Testing Checklist

Open the generated tree and test each category:

```powershell
# Generate fresh tree
.\src\powershell\main\tree-viewer-launcher.ps1

# Tree opens in browser
# Open DevTools (F12) -> Console tab
```

**Test Order:**
1. ✅ Basic Search Tests (5 min)
2. ✅ Special Character Tests (5 min)
3. ✅ Performance Tests (10 min)
4. ✅ Edge Cases (5 min)
5. ✅ Visual Verification (5 min)

**Total Time:** ~30 minutes

---

## Automated Testing (Optional)

### JavaScript Console Tests

Paste into browser console:

```javascript
// Test 1: Basic search
console.log('Test 1: Basic Search');
console.time('basicSearch');
searchTree('Robot');
console.timeEnd('basicSearch');
const basicResults = document.querySelectorAll('.highlight').length;
console.log(`Found ${basicResults} results`);

// Test 2: Clear search
console.log('\nTest 2: Clear Search');
searchTree('');
const clearedResults = document.querySelectorAll('.highlight').length;
console.log(`Highlights after clear: ${clearedResults} (should be 0)`);

// Test 3: Special characters
console.log('\nTest 3: German Umlauts');
searchTree('ü');
const umlautResults = document.querySelectorAll('.highlight').length;
console.log(`Found ${umlautResults} results with umlauts`);
searchTree('');

// Test 4: Performance with common term
console.log('\nTest 4: Performance Test');
console.time('performanceSearch');
searchTree('Resource');
console.timeEnd('performanceSearch');
const perfResults = document.querySelectorAll('.highlight').length;
console.log(`Found ${perfResults} results (should complete in <3s)`);
searchTree('');

// Test 5: Case insensitivity
console.log('\nTest 5: Case Insensitivity');
searchTree('robot');
const lowerResults = document.querySelectorAll('.highlight').length;
searchTree('ROBOT');
const upperResults = document.querySelectorAll('.highlight').length;
console.log(`Lowercase: ${lowerResults}, Uppercase: ${upperResults} (should match)`);
searchTree('');

console.log('\n✅ Automated tests complete!');
```

---

## Known Issues to Check

### Issue 1: Search Only Checks Rendered Nodes
**Current Behavior:** Search uses `document.querySelectorAll('.tree-label')` which only finds rendered DOM nodes.

**Impact:** With lazy loading (level < 1), search won't find nodes that haven't been expanded yet.

**Fix (if needed):** Implement search that:
1. Searches in-memory data structure (rootNode)
2. Auto-expands path to found nodes
3. Renders nodes as needed

**Priority:** Medium (most important nodes are already expanded at root + level 1)

### Issue 2: No Search Result Count
**Current Behavior:** Search highlights matches but doesn't show count.

**Impact:** User doesn't know how many results found.

**Fix (if needed):** Add result counter: "Found 47 matches for 'Robot'"

**Priority:** Low (nice-to-have)

### Issue 3: No "Jump to Next Result"
**Current Behavior:** All results highlighted, but no navigation between them.

**Impact:** With many results, hard to see all matches.

**Fix (if needed):** Add "Next" / "Previous" buttons to cycle through results.

**Priority:** Low (can manually scroll)

---

## Success Criteria

Search functionality is considered **VERIFIED** if:

1. ✅ Basic search works (finds nodes, highlights correctly)
2. ✅ Special characters work (umlauts, accents)
3. ✅ Performance is acceptable (<3s for common terms)
4. ✅ No JavaScript errors in console
5. ✅ Parent expansion works correctly
6. ✅ Clear search removes highlights
7. ✅ Case-insensitive matching works

---

## Test Results Template

```markdown
## Search Functionality Test Results

**Date:** 2026-01-19
**Tester:** [Name]
**Browser:** [Chrome/Edge/Firefox + version]
**Tree Size:** 632,669 lines, 310,203 nodes

### Basic Search Tests
- [ ] Test 1.1: Simple Word Search - ✅ PASS / ❌ FAIL
- [ ] Test 1.2: Numeric Search - ✅ PASS / ❌ FAIL
- [ ] Test 1.3: Partial Match Search - ✅ PASS / ❌ FAIL
- [ ] Test 1.4: Empty Search - ✅ PASS / ❌ FAIL

### Special Character Tests
- [ ] Test 2.1: German Umlauts - ✅ PASS / ❌ FAIL
- [ ] Test 2.2: Special Characters - ✅ PASS / ❌ FAIL
- [ ] Test 2.3: Accented Characters - ✅ PASS / ❌ FAIL

### Performance Tests
- [ ] Test 3.1: Many Results - ✅ PASS / ❌ FAIL (Time: ___s)
- [ ] Test 3.2: Rapid Search - ✅ PASS / ❌ FAIL
- [ ] Test 3.3: Lazy-Loaded Nodes - ✅ PASS / ❌ FAIL

### Edge Cases
- [ ] Test 4.1: Long Query - ✅ PASS / ❌ FAIL
- [ ] Test 4.2: Regex Chars - ✅ PASS / ❌ FAIL
- [ ] Test 4.3: Spaces - ✅ PASS / ❌ FAIL
- [ ] Test 4.4: Case Sensitivity - ✅ PASS / ❌ FAIL

### Visual Verification
- [ ] Test 5.1: Highlight Visibility - ✅ PASS / ❌ FAIL
- [ ] Test 5.2: Parent Expansion - ✅ PASS / ❌ FAIL
- [ ] Test 5.3: Multiple Results - ✅ PASS / ❌ FAIL

### Issues Found
1. [Describe any issues]
2. ...

### Overall Result
✅ VERIFIED / ⚠️ ISSUES FOUND / ❌ FAILED

**Notes:**
[Any additional observations]
```

---

**Next Steps:**
1. Run manual tests following this plan
2. Document results in test results template
3. Fix any issues found
4. Mark search functionality as verified in STATUS.md

---
Date: 2026-01-19
Status: 📋 Test plan ready - awaiting execution
