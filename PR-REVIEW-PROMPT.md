# PR Review Prompt for Other Developer

## Quick Message Version

Hey! I've created a review branch documenting the tree nodes bugs work (missing nodes & incorrect icons). There's likely useful stuff here for your work:

**Branch**: `docs/tree-nodes-bugs-review`

**Key things that might help:**
1. **Icon fallback pattern** - How to handle missing icons by using parent class icons from the database (lines 146-191 in generate-tree-html.ps1)
2. **Specialized node query template** - Reusable pattern for adding nodes from non-COLLECTION_ tables (documented in TREE-NODES-BUGS-REVIEW.md)
3. **Class hierarchy tracing SQL** - How to find parent classes with icons when a TYPE_ID doesn't have one
4. **Missing node diagnosis process** - 6-step systematic approach to find and fix missing nodes
5. **Database schema insights** - Understanding of COLLECTION_ vs specialized tables, REL_COMMON relationships

The review doc includes code references, SQL queries, and step-by-step guides. Worth a quick scan to see if any patterns/solutions apply to what you're working on.

---

## Detailed PR Description Version

### Review Request: Tree Nodes Bugs Documentation

This branch contains a comprehensive review document of the work done to fix missing nodes and incorrect icons in the tree navigation system.

#### What's Included

**TREE-NODES-BUGS-REVIEW.md** - Complete documentation covering:
- Icon fixes for StudyFolder and Study types (using parent class icons)
- Missing nodes fixes for 7 specialized node types
- Query templates and investigation processes
- Step-by-step guides for future developers

#### Key Solutions That Might Help Your Work

1. **Icon Fallback Mechanism** (`generate-tree-html.ps1` lines 146-191)
   - Pattern for handling TYPE_IDs that don't have icons in DF_ICONS_DATA
   - Traces class hierarchy to find parent class icons
   - Reusable for any missing TYPE_ID

2. **Specialized Node Query Template**
   - Pattern for adding nodes from non-COLLECTION_ tables
   - Includes project scope filtering
   - Handles level correction automatically

3. **Class Hierarchy Tracing**
   - SQL query to find parent classes with icons
   - Useful when investigating missing icons

4. **Missing Node Diagnosis Process**
   - 6-step systematic approach
   - How to identify which table stores a node
   - How to verify and add missing nodes

5. **Database Schema Understanding**
   - COLLECTION_ vs specialized tables
   - REL_COMMON relationship patterns
   - How hierarchical queries work (and their limitations)

#### Impact

- Fixed ~2,400 missing nodes (11% increase: 20,854 → 23,254 nodes)
- Fixed icons for Study-related node types
- Added 8 fallback icons

#### Files to Review

- `TREE-NODES-BUGS-REVIEW.md` - Main review document (start here)
- `ICON-FIX-SUMMARY.md` - Icon fixes details (referenced)
- `ROBCADSTUDY-CHILDREN-FIX.md` - Specific fix example (referenced)
- `SPECIALIZED-NODES-GUIDE.md` - Guide for finding specialized nodes (referenced)

#### Code References

The review document includes specific line references to:
- `src/powershell/main/generate-tree-html.ps1` (icon fallbacks, specialized queries)

Please review and let me know if any of these patterns or solutions would be useful for your work!

---

## Short Email/Slack Version

Subject: Review Request - Tree Nodes Bugs Documentation Branch

Hi [Name],

I've documented the tree nodes bugs work (missing nodes & incorrect icons) in branch `docs/tree-nodes-bugs-review`. 

There are several reusable patterns that might help your work:
- Icon fallback mechanism for missing TYPE_IDs
- Specialized node query template for non-COLLECTION_ tables  
- Class hierarchy tracing SQL
- Missing node diagnosis process

The review doc has code references, SQL queries, and step-by-step guides. Worth checking if any apply to what you're working on.

PR: [link when created]

Thanks!

---

## GitHub PR Description Template

```markdown
## Overview
Comprehensive review document of tree nodes bugs fixes (missing nodes & incorrect icons).

## What's Included
- **TREE-NODES-BUGS-REVIEW.md** - Complete documentation with code references, SQL queries, and guides

## Key Solutions That Might Help
1. **Icon Fallback Pattern** - Handle missing icons using parent class icons
2. **Specialized Node Query Template** - Reusable pattern for non-COLLECTION_ tables
3. **Class Hierarchy Tracing** - SQL to find parent classes with icons
4. **Missing Node Diagnosis** - 6-step systematic approach
5. **Database Schema Insights** - COLLECTION_ vs specialized tables understanding

## Impact
- Fixed ~2,400 missing nodes (11% increase)
- Fixed icons for Study-related types
- Added reusable patterns for future work

## Review Focus
Please check if any patterns/solutions apply to your current work. The review doc includes specific code references and step-by-step guides.
```
