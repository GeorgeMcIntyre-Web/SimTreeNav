SET PAGESIZE 50000
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING OFF

-- Get full navigation tree for FORD_DEARBORN with ordering
-- Output format: LEVEL|PARENT_ID|OBJECT_ID|CAPTION|NAME|EXTERNAL_ID|SEQ_NUMBER|CLASS_NAME|NICE_NAME|TYPE_ID

-- Level 0: Root
-- Output: LEVEL|PARENT_ID|OBJECT_ID|CAPTION|NAME|EXTERNAL_ID|SEQ_NUMBER|CLASS_NAME|NICE_NAME|TYPE_ID
SELECT '0|0|18140190|FORD_DEARBORN|FORD_DEARBORN|' || NVL(c.EXTERNALID_S_, '') || '|0|' || NVL(cd.NAME, 'class PmNode') || '|' || NVL(cd.NICE_NAME, 'Unknown') || '|' || TO_CHAR(cd.TYPE_ID)
FROM DESIGN12.COLLECTION_ c
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON c.CLASS_ID = cd.TYPE_ID
WHERE c.OBJECT_ID = 18140190;

-- Level 1: Direct children (custom order matching Siemens app)
-- Output: LEVEL|PARENT_ID|OBJECT_ID|CAPTION|NAME|EXTERNAL_ID|SEQ_NUMBER|CLASS_NAME|NICE_NAME|TYPE_ID
SELECT
    '1|18140190|' || r.OBJECT_ID || '|' ||
    NVL(c.CAPTION_S_, 'Unnamed') || '|' ||
    NVL(c.CAPTION_S_, 'Unnamed') || '|' ||
    NVL(c.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class PmNode') || '|' ||
    NVL(cd.NICE_NAME, 'Unknown') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM DESIGN12.REL_COMMON r
LEFT JOIN DESIGN12.COLLECTION_ c ON r.OBJECT_ID = c.OBJECT_ID
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON c.CLASS_ID = cd.TYPE_ID
WHERE r.FORWARD_OBJECT_ID = 18140190
ORDER BY
    -- Custom ordering to match Siemens Navigation Tree
    CASE r.OBJECT_ID
        WHEN 18195357 THEN 1  -- P702
        WHEN 18195358 THEN 2  -- P736
        WHEN 18153685 THEN 3  -- EngineeringResourceLibrary
        WHEN 18143951 THEN 4  -- PartLibrary
        WHEN 18143953 THEN 5  -- PartInstanceLibrary (ghost node)
        WHEN 18143955 THEN 6  -- MfgLibrary
        WHEN 18143956 THEN 7  -- IPA
        WHEN 18144070 THEN 8  -- DES_Studies
        WHEN 18144071 THEN 9  -- Working Folders
        ELSE 999  -- Unknown nodes go last
    END;

-- Level 2+: All descendants using hierarchical query with NOCYCLE
-- Output: LEVEL|PARENT_ID|OBJECT_ID|CAPTION|NAME|EXTERNAL_ID|SEQ_NUMBER|CLASS_NAME|NICE_NAME|TYPE_ID
SELECT
    LEVEL || '|' ||
    PRIOR c.OBJECT_ID || '|' ||
    c.OBJECT_ID || '|' ||
    NVL(c.CAPTION_S_, 'Unnamed') || '|' ||
    NVL(c.CAPTION_S_, 'Unnamed') || '|' ||
    NVL(c.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class PmNode') || '|' ||
    NVL(cd.NICE_NAME, 'Unknown') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM DESIGN12.REL_COMMON r
INNER JOIN DESIGN12.COLLECTION_ c ON r.OBJECT_ID = c.OBJECT_ID
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON c.CLASS_ID = cd.TYPE_ID
START WITH r.FORWARD_OBJECT_ID = 18140190
CONNECT BY NOCYCLE PRIOR r.OBJECT_ID = r.FORWARD_OBJECT_ID
ORDER SIBLINGS BY NVL(c.MODIFICATIONDATE_DA_, TO_DATE('1900-01-01', 'YYYY-MM-DD')), c.OBJECT_ID;

-- Add StudyFolder children explicitly (these are links/shortcuts to real data)
-- StudyFolder nodes are identified by their NICE_NAME in CLASS_DEFINITIONS, not CAPTION
-- Output: LEVEL|PARENT_ID|OBJECT_ID|CAPTION|NAME|EXTERNAL_ID|SEQ_NUMBER|CLASS_NAME|NICE_NAME|TYPE_ID
SELECT
    '999|' ||  -- Use high level number, JavaScript will handle it
    r.FORWARD_OBJECT_ID || '|' ||
    r.OBJECT_ID || '|' ||
    NVL(c.CAPTION_S_, 'Unnamed') || '|' ||
    NVL(c.CAPTION_S_, 'Unnamed') || '|' ||
    NVL(c.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class PmNode') || '|' ||
    NVL(cd.NICE_NAME, 'Unknown') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM DESIGN12.REL_COMMON r
INNER JOIN DESIGN12.COLLECTION_ c_parent ON r.FORWARD_OBJECT_ID = c_parent.OBJECT_ID
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd_parent ON c_parent.CLASS_ID = cd_parent.TYPE_ID
INNER JOIN DESIGN12.COLLECTION_ c ON r.OBJECT_ID = c.OBJECT_ID
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON c.CLASS_ID = cd.TYPE_ID
WHERE cd_parent.NICE_NAME = 'StudyFolder'
  AND EXISTS (
    SELECT 1 FROM DESIGN12.REL_COMMON r2
    INNER JOIN DESIGN12.COLLECTION_ c2 ON r2.OBJECT_ID = c2.OBJECT_ID
    START WITH r2.FORWARD_OBJECT_ID = 18140190
    CONNECT BY NOCYCLE PRIOR r2.OBJECT_ID = r2.FORWARD_OBJECT_ID
    WHERE c2.OBJECT_ID = c_parent.OBJECT_ID
  )
ORDER BY r.FORWARD_OBJECT_ID, NVL(c.MODIFICATIONDATE_DA_, TO_DATE('1900-01-01', 'YYYY-MM-DD')), c.OBJECT_ID;

-- Add RobcadStudy nodes (from ROBCADSTUDY_ table)
-- These nodes are stored in a specialized table, not COLLECTION_
-- Output: LEVEL|PARENT_ID|OBJECT_ID|CAPTION|NAME|EXTERNAL_ID|SEQ_NUMBER|CLASS_NAME|NICE_NAME|TYPE_ID
SELECT
    '999|' ||  -- Use high level number, JavaScript will handle it
    r.FORWARD_OBJECT_ID || '|' ||
    r.OBJECT_ID || '|' ||
    NVL(rs.NAME_S_, 'Unnamed') || '|' ||
    NVL(rs.NAME_S_, 'Unnamed') || '|' ||
    NVL(rs.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class RobcadStudy') || '|' ||
    NVL(cd.NICE_NAME, 'RobcadStudy') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM DESIGN12.REL_COMMON r
INNER JOIN DESIGN12.ROBCADSTUDY_ rs ON r.OBJECT_ID = rs.OBJECT_ID
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON rs.CLASS_ID = cd.TYPE_ID
WHERE EXISTS (
    SELECT 1 FROM DESIGN12.REL_COMMON r2
    INNER JOIN DESIGN12.COLLECTION_ c2 ON r2.OBJECT_ID = c2.OBJECT_ID
    WHERE c2.OBJECT_ID = r.FORWARD_OBJECT_ID
      AND c2.OBJECT_ID IN (
        SELECT c3.OBJECT_ID
        FROM DESIGN12.REL_COMMON r3
        INNER JOIN DESIGN12.COLLECTION_ c3 ON r3.OBJECT_ID = c3.OBJECT_ID
        START WITH r3.FORWARD_OBJECT_ID = 18140190
        CONNECT BY NOCYCLE PRIOR r3.OBJECT_ID = r3.FORWARD_OBJECT_ID
      )
  );

-- Add LineSimulationStudy nodes (from LINESIMULATIONSTUDY_ table)
SELECT
    '999|' ||
    r.FORWARD_OBJECT_ID || '|' ||
    r.OBJECT_ID || '|' ||
    NVL(ls.NAME_S_, 'Unnamed') || '|' ||
    NVL(ls.NAME_S_, 'Unnamed') || '|' ||
    NVL(ls.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class LineSimulationStudy') || '|' ||
    NVL(cd.NICE_NAME, 'LineSimulationStudy') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM DESIGN12.REL_COMMON r
INNER JOIN DESIGN12.LINESIMULATIONSTUDY_ ls ON r.OBJECT_ID = ls.OBJECT_ID
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON ls.CLASS_ID = cd.TYPE_ID
WHERE EXISTS (
    SELECT 1 FROM DESIGN12.REL_COMMON r2
    INNER JOIN DESIGN12.COLLECTION_ c2 ON r2.OBJECT_ID = c2.OBJECT_ID
    WHERE c2.OBJECT_ID = r.FORWARD_OBJECT_ID
      AND c2.OBJECT_ID IN (
        SELECT c3.OBJECT_ID
        FROM DESIGN12.REL_COMMON r3
        INNER JOIN DESIGN12.COLLECTION_ c3 ON r3.OBJECT_ID = c3.OBJECT_ID
        START WITH r3.FORWARD_OBJECT_ID = 18140190
        CONNECT BY NOCYCLE PRIOR r3.OBJECT_ID = r3.FORWARD_OBJECT_ID
      )
  );

-- Add GanttStudy nodes (from GANTTSTUDY_ table)
SELECT
    '999|' ||
    r.FORWARD_OBJECT_ID || '|' ||
    r.OBJECT_ID || '|' ||
    NVL(gs.NAME_S_, 'Unnamed') || '|' ||
    NVL(gs.NAME_S_, 'Unnamed') || '|' ||
    NVL(gs.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class GanttStudy') || '|' ||
    NVL(cd.NICE_NAME, 'GanttStudy') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM DESIGN12.REL_COMMON r
INNER JOIN DESIGN12.GANTTSTUDY_ gs ON r.OBJECT_ID = gs.OBJECT_ID
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON gs.CLASS_ID = cd.TYPE_ID
WHERE EXISTS (
    SELECT 1 FROM DESIGN12.REL_COMMON r2
    INNER JOIN DESIGN12.COLLECTION_ c2 ON r2.OBJECT_ID = c2.OBJECT_ID
    WHERE c2.OBJECT_ID = r.FORWARD_OBJECT_ID
      AND c2.OBJECT_ID IN (
        SELECT c3.OBJECT_ID
        FROM DESIGN12.REL_COMMON r3
        INNER JOIN DESIGN12.COLLECTION_ c3 ON r3.OBJECT_ID = c3.OBJECT_ID
        START WITH r3.FORWARD_OBJECT_ID = 18140190
        CONNECT BY NOCYCLE PRIOR r3.OBJECT_ID = r3.FORWARD_OBJECT_ID
      )
  );

-- Add SimpleDetailedStudy nodes (from SIMPLEDETAILEDSTUDY_ table)
SELECT
    '999|' ||
    r.FORWARD_OBJECT_ID || '|' ||
    r.OBJECT_ID || '|' ||
    NVL(sd.NAME_S_, 'Unnamed') || '|' ||
    NVL(sd.NAME_S_, 'Unnamed') || '|' ||
    NVL(sd.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class SimpleDetailedStudy') || '|' ||
    NVL(cd.NICE_NAME, 'SimpleDetailedStudy') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM DESIGN12.REL_COMMON r
INNER JOIN DESIGN12.SIMPLEDETAILEDSTUDY_ sd ON r.OBJECT_ID = sd.OBJECT_ID
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON sd.CLASS_ID = cd.TYPE_ID
WHERE EXISTS (
    SELECT 1 FROM DESIGN12.REL_COMMON r2
    INNER JOIN DESIGN12.COLLECTION_ c2 ON r2.OBJECT_ID = c2.OBJECT_ID
    WHERE c2.OBJECT_ID = r.FORWARD_OBJECT_ID
      AND c2.OBJECT_ID IN (
        SELECT c3.OBJECT_ID
        FROM DESIGN12.REL_COMMON r3
        INNER JOIN DESIGN12.COLLECTION_ c3 ON r3.OBJECT_ID = c3.OBJECT_ID
        START WITH r3.FORWARD_OBJECT_ID = 18140190
        CONNECT BY NOCYCLE PRIOR r3.OBJECT_ID = r3.FORWARD_OBJECT_ID
      )
  );

-- Add LocationalStudy nodes (from LOCATIONALSTUDY_ table)
SELECT
    '999|' ||
    r.FORWARD_OBJECT_ID || '|' ||
    r.OBJECT_ID || '|' ||
    NVL(lc.NAME_S_, 'Unnamed') || '|' ||
    NVL(lc.NAME_S_, 'Unnamed') || '|' ||
    NVL(lc.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class LocationalStudy') || '|' ||
    NVL(cd.NICE_NAME, 'LocationalStudy') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM DESIGN12.REL_COMMON r
INNER JOIN DESIGN12.LOCATIONALSTUDY_ lc ON r.OBJECT_ID = lc.OBJECT_ID
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON lc.CLASS_ID = cd.TYPE_ID
WHERE EXISTS (
    SELECT 1 FROM DESIGN12.REL_COMMON r2
    INNER JOIN DESIGN12.COLLECTION_ c2 ON r2.OBJECT_ID = c2.OBJECT_ID
    WHERE c2.OBJECT_ID = r.FORWARD_OBJECT_ID
      AND c2.OBJECT_ID IN (
        SELECT c3.OBJECT_ID
        FROM DESIGN12.REL_COMMON r3
        INNER JOIN DESIGN12.COLLECTION_ c3 ON r3.OBJECT_ID = c3.OBJECT_ID
        START WITH r3.FORWARD_OBJECT_ID = 18140190
        CONNECT BY NOCYCLE PRIOR r3.OBJECT_ID = r3.FORWARD_OBJECT_ID
      )
  );

-- Add ToolPrototype nodes (equipment, layouts, units, etc.)
-- ToolPrototypes use REL_COMMON for parent relationships (not COLLECTIONS_VR_)
-- Output: LEVEL|PARENT_ID|OBJECT_ID|CAPTION|NAME|EXTERNAL_ID|SEQ_NUMBER|CLASS_NAME|NICE_NAME|TYPE_ID
SELECT
    '999|' ||
    r.FORWARD_OBJECT_ID || '|' ||
    tp.OBJECT_ID || '|' ||
    NVL(tp.CAPTION_S_, NVL(tp.NAME_S_, 'Unnamed Tool')) || '|' ||
    NVL(tp.NAME_S_, 'Unnamed') || '|' ||
    NVL(tp.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class ToolPrototype') || '|' ||
    NVL(cd.NICE_NAME, 'ToolPrototype') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM DESIGN12.TOOLPROTOTYPE_ tp
INNER JOIN DESIGN12.REL_COMMON r ON tp.OBJECT_ID = r.OBJECT_ID
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON tp.CLASS_ID = cd.TYPE_ID
WHERE EXISTS (
    SELECT 1 FROM DESIGN12.REL_COMMON r2
    INNER JOIN DESIGN12.COLLECTION_ c2 ON r2.OBJECT_ID = c2.OBJECT_ID
    WHERE c2.OBJECT_ID = r.FORWARD_OBJECT_ID
      AND c2.OBJECT_ID IN (
        SELECT c3.OBJECT_ID
        FROM DESIGN12.REL_COMMON r3
        INNER JOIN DESIGN12.COLLECTION_ c3 ON r3.OBJECT_ID = c3.OBJECT_ID
        START WITH r3.FORWARD_OBJECT_ID = 18140190
        CONNECT BY NOCYCLE PRIOR r3.OBJECT_ID = r3.FORWARD_OBJECT_ID
      )
  );

-- Add ToolInstanceAspect nodes (instances attached to other objects)
-- Tool instances use ATTACHEDTO_SR_ for parent relationships
-- Output: LEVEL|PARENT_ID|OBJECT_ID|CAPTION|NAME|EXTERNAL_ID|SEQ_NUMBER|CLASS_NAME|NICE_NAME|TYPE_ID
SELECT
    '999|' ||
    ti.ATTACHEDTO_SR_ || '|' ||
    ti.OBJECT_ID || '|' ||
    'Tool Instance' || '|' ||
    'Tool Instance' || '|' ||
    '' || '|' ||
    '0|' ||
    NVL(cd.NAME, 'class ToolInstanceAspect') || '|' ||
    NVL(cd.NICE_NAME, 'ToolInstanceAspect') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM DESIGN12.TOOLINSTANCEASPECT_ ti
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON ti.CLASS_ID = cd.TYPE_ID
WHERE ti.OBJECT_ID IS NOT NULL
  AND ti.ATTACHEDTO_SR_ IS NOT NULL
  AND EXISTS (
    SELECT 1 FROM DESIGN12.REL_COMMON r
    INNER JOIN DESIGN12.COLLECTION_ c ON r.OBJECT_ID = c.OBJECT_ID
    WHERE c.OBJECT_ID = ti.ATTACHEDTO_SR_
      AND c.OBJECT_ID IN (
        SELECT c2.OBJECT_ID
        FROM DESIGN12.REL_COMMON r2
        INNER JOIN DESIGN12.COLLECTION_ c2 ON r2.OBJECT_ID = c2.OBJECT_ID
        START WITH r2.FORWARD_OBJECT_ID = 18140190
        CONNECT BY NOCYCLE PRIOR r2.OBJECT_ID = r2.FORWARD_OBJECT_ID
      )
  );

-- Add Resource nodes (robots, equipment, cables, etc. - instances under CompoundResource)
-- Resources use REL_COMMON for parent relationships, same as other nodes
-- These are the actual robot/equipment instances visible in the Siemens UI
-- Output: LEVEL|PARENT_ID|OBJECT_ID|CAPTION|NAME|EXTERNAL_ID|SEQ_NUMBER|CLASS_NAME|NICE_NAME|TYPE_ID
SELECT
    '999|' ||
    r.FORWARD_OBJECT_ID || '|' ||
    res.OBJECT_ID || '|' ||
    NVL(res.CAPTION_S_, NVL(res.NAME_S_, 'Unnamed Resource')) || '|' ||
    NVL(res.NAME_S_, 'Unnamed') || '|' ||
    NVL(res.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class Resource') || '|' ||
    NVL(cd.NICE_NAME, 'Resource') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM DESIGN12.RESOURCE_ res
INNER JOIN DESIGN12.REL_COMMON r ON res.OBJECT_ID = r.OBJECT_ID
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON res.CLASS_ID = cd.TYPE_ID
WHERE EXISTS (
    SELECT 1 FROM DESIGN12.REL_COMMON r2
    INNER JOIN DESIGN12.COLLECTION_ c2 ON r2.OBJECT_ID = c2.OBJECT_ID
    WHERE c2.OBJECT_ID = r.FORWARD_OBJECT_ID
      AND c2.OBJECT_ID IN (
        SELECT c3.OBJECT_ID
        FROM DESIGN12.REL_COMMON r3
        INNER JOIN DESIGN12.COLLECTION_ c3 ON r3.OBJECT_ID = c3.OBJECT_ID
        START WITH r3.FORWARD_OBJECT_ID = 18140190
        CONNECT BY NOCYCLE PRIOR r3.OBJECT_ID = r3.FORWARD_OBJECT_ID
      )
  );

-- TODO: Add Operation nodes (manufacturing operations like MOV_HOME, COMM_PICK01, etc.)
-- ISSUE: Operations nest up to 28+ levels deep before reaching COLLECTION_ nodes
-- Current hierarchical queries timeout or take 5+ minutes to execute
-- 743,107 total operations in database, 99.7% have OPERATION_ parents (not COLLECTION_)
-- Needs optimization: temp tables, materialized views, or iterative PowerShell approach
--
-- COMMENTED OUT TEMPORARILY - Tree viewer works without operations
--
-- WITH project_collections AS (
--     SELECT c.OBJECT_ID
--     FROM DESIGN12.REL_COMMON r
--     INNER JOIN DESIGN12.COLLECTION_ c ON r.OBJECT_ID = c.OBJECT_ID
--     START WITH r.FORWARD_OBJECT_ID = 18140190
--     CONNECT BY NOCYCLE PRIOR r.OBJECT_ID = r.FORWARD_OBJECT_ID
-- ),
-- project_operations AS (
--     SELECT DISTINCT rc.OBJECT_ID
--     FROM DESIGN12.REL_COMMON rc
--     START WITH rc.FORWARD_OBJECT_ID IN (SELECT OBJECT_ID FROM project_collections)
--     CONNECT BY NOCYCLE PRIOR rc.OBJECT_ID = rc.FORWARD_OBJECT_ID
-- )
-- SELECT
--     '999|' ||
--     r.FORWARD_OBJECT_ID || '|' ||
--     op.OBJECT_ID || '|' ||
--     NVL(op.CAPTION_S_, NVL(op.NAME_S_, 'Unnamed Operation')) || '|' ||
--     NVL(op.NAME_S_, 'Unnamed') || '|' ||
--     NVL(op.EXTERNALID_S_, '') || '|' ||
--     TO_CHAR(r.SEQ_NUMBER) || '|' ||
--     NVL(cd.NAME, 'class Operation') || '|' ||
--     NVL(cd.NICE_NAME, 'Operation') || '|' ||
--     TO_CHAR(cd.TYPE_ID)
-- FROM DESIGN12.OPERATION_ op
-- INNER JOIN DESIGN12.REL_COMMON r ON op.OBJECT_ID = r.OBJECT_ID
-- LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON op.CLASS_ID = cd.TYPE_ID
-- WHERE op.OBJECT_ID IN (SELECT OBJECT_ID FROM project_operations);

-- Add children of RobcadStudy nodes from SHORTCUT_ table
-- Shortcuts are link nodes that reference other objects in the tree
-- Output: LEVEL|PARENT_ID|OBJECT_ID|CAPTION|NAME|EXTERNAL_ID|SEQ_NUMBER|CLASS_NAME|NICE_NAME|TYPE_ID
SELECT DISTINCT
    '999|' ||
    r.FORWARD_OBJECT_ID || '|' ||
    r.OBJECT_ID || '|' ||
    NVL(sc.NAME_S_, 'Unnamed') || '|' ||
    NVL(sc.NAME_S_, 'Unnamed') || '|' ||
    NVL(sc.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class PmShortcut') || '|' ||
    NVL(cd.NICE_NAME, 'Shortcut') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM DESIGN12.REL_COMMON r
INNER JOIN DESIGN12.SHORTCUT_ sc ON r.OBJECT_ID = sc.OBJECT_ID
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON sc.CLASS_ID = cd.TYPE_ID
INNER JOIN DESIGN12.ROBCADSTUDY_ rs_parent ON r.FORWARD_OBJECT_ID = rs_parent.OBJECT_ID
WHERE EXISTS (
    SELECT 1
    FROM DESIGN12.REL_COMMON r2
    INNER JOIN DESIGN12.COLLECTION_ c2 ON r2.FORWARD_OBJECT_ID = c2.OBJECT_ID
    WHERE r2.OBJECT_ID = rs_parent.OBJECT_ID
      AND c2.OBJECT_ID IN (
        SELECT c3.OBJECT_ID
        FROM DESIGN12.REL_COMMON r3
        INNER JOIN DESIGN12.COLLECTION_ c3 ON r3.OBJECT_ID = c3.OBJECT_ID
        START WITH r3.FORWARD_OBJECT_ID = 18140190
        CONNECT BY NOCYCLE PRIOR r3.OBJECT_ID = r3.FORWARD_OBJECT_ID
      )
  );

-- Add TxProcessAssembly nodes (from PART_ table, CLASS_ID 133)
-- TxProcessAssembly nodes are stored in PART_ table, not COLLECTION_
-- These are assembly/process nodes that appear in the tree structure
-- Output: LEVEL|PARENT_ID|OBJECT_ID|CAPTION|NAME|EXTERNAL_ID|SEQ_NUMBER|CLASS_NAME|NICE_NAME|TYPE_ID
SELECT
    '999|' ||
    r.FORWARD_OBJECT_ID || '|' ||
    r.OBJECT_ID || '|' ||
    NVL(p.NAME_S_, 'Unnamed') || '|' ||
    NVL(p.NAME_S_, 'Unnamed') || '|' ||
    NVL(p.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class PmTxProcessAssembly') || '|' ||
    NVL(cd.NICE_NAME, 'TxProcessAssembly') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM DESIGN12.REL_COMMON r
INNER JOIN DESIGN12.PART_ p ON r.OBJECT_ID = p.OBJECT_ID
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON p.CLASS_ID = cd.TYPE_ID
WHERE p.CLASS_ID = 133  -- TxProcessAssembly TYPE_ID
  AND EXISTS (
    SELECT 1 FROM DESIGN12.REL_COMMON r2
    INNER JOIN DESIGN12.COLLECTION_ c2 ON r2.OBJECT_ID = c2.OBJECT_ID
    WHERE c2.OBJECT_ID = r.FORWARD_OBJECT_ID
      AND c2.OBJECT_ID IN (
        SELECT c3.OBJECT_ID
        FROM DESIGN12.REL_COMMON r3
        INNER JOIN DESIGN12.COLLECTION_ c3 ON r3.OBJECT_ID = c3.OBJECT_ID
        START WITH r3.FORWARD_OBJECT_ID = 18140190
        CONNECT BY NOCYCLE PRIOR r3.OBJECT_ID = r3.FORWARD_OBJECT_ID
      )
  );

-- NOTE: RobcadStudyInfo nodes are HIDDEN (internal metadata not shown in Siemens Navigation Tree)
-- RobcadStudyInfo contains layout configuration (LAYOUT_SR_) and study metadata for loading modes
-- Each RobcadStudyInfo is paired with a Shortcut but should not appear in the navigation tree
-- The query below is commented out to hide these internal metadata nodes

-- SELECT
--     '999|' ||
--     r.FORWARD_OBJECT_ID || '|' ||
--     r.OBJECT_ID || '|' ||
--     NVL(rsi.NAME_S_, 'Unnamed') || '|' ||
--     NVL(rsi.NAME_S_, 'Unnamed') || '|' ||
--     NVL(rsi.EXTERNALID_S_, '') || '|' ||
--     TO_CHAR(r.SEQ_NUMBER) || '|' ||
--     NVL(cd.NAME, 'class RobcadStudyInfo') || '|' ||
--     NVL(cd.NICE_NAME, 'RobcadStudyInfo') || '|' ||
--     TO_CHAR(cd.TYPE_ID)
-- FROM DESIGN12.REL_COMMON r
-- INNER JOIN DESIGN12.ROBCADSTUDYINFO_ rsi ON r.OBJECT_ID = rsi.OBJECT_ID
-- LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON rsi.CLASS_ID = cd.TYPE_ID
-- WHERE r.FORWARD_OBJECT_ID IN (
--     SELECT r2.OBJECT_ID
--     FROM DESIGN12.REL_COMMON r2
--     INNER JOIN DESIGN12.ROBCADSTUDY_ rs ON r2.OBJECT_ID = rs.OBJECT_ID
--     INNER JOIN DESIGN12.COLLECTION_ c2 ON r2.FORWARD_OBJECT_ID = c2.OBJECT_ID
--     WHERE c2.OBJECT_ID IN (
--         SELECT c3.OBJECT_ID
--         FROM DESIGN12.REL_COMMON r3
--         INNER JOIN DESIGN12.COLLECTION_ c3 ON r3.OBJECT_ID = c3.OBJECT_ID
--         START WITH r3.FORWARD_OBJECT_ID = 18140190
--         CONNECT BY NOCYCLE PRIOR r3.OBJECT_ID = r3.FORWARD_OBJECT_ID
--       )
--   );

EXIT;