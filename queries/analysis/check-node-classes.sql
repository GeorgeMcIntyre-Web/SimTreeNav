SET PAGESIZE 50
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING ON

-- Get class names for specific nodes from the tree
SELECT c.OBJECT_ID, c.CAPTION_S_, cd.NAME as CLASS_NAME, cd.NICE_NAME
FROM DESIGN12.COLLECTION_ c
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON c.CLASS_ID = cd.TYPE_ID
WHERE c.OBJECT_ID IN (
    18140190,  -- FORD_DEARBORN
    18144070,  -- DES_Studies
    18195357,  -- P702 (root level)
    18195358,  -- P736 (root level)
    18153685,  -- EngineeringResourceLibrary
    18143951,  -- PartLibrary
    18143953,  -- PartInstanceLibrary
    18143955,  -- MfgLibrary
    18143956   -- IPA
)
ORDER BY c.OBJECT_ID;
EXIT;