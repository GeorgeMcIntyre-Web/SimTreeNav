-- Management Reporting Queries
-- Purpose: Track work activity across all 5 work types in Process Simulate
-- Date: 2026-01-19

-- ==============================================================================
-- QUERY 1: Project Database Setup Activity
-- ==============================================================================
-- Tracks: Project creation/modification, users, checkout status

SELECT
    'PROJECT_DATABASE' as work_type,
    c.OBJECT_ID as object_id,
    c.CAPTION_S_ as object_name,
    'Project' as object_type,
    c.CREATEDBY_S_ as created_by,
    c.MODIFICATIONDATE_DA_ as last_modified,
    c.LASTMODIFIEDBY_S_ as modified_by,
    p.OWNER_ID as checked_out_by_user_id,
    u.CAPTION_S_ as checked_out_by_user_name,
    CASE WHEN p.WORKING_VERSION_ID > 0 THEN 'Checked Out' ELSE 'Available' END as status,
    p.WORKING_VERSION_ID as version_id
FROM &Schema..COLLECTION_ c
LEFT JOIN &Schema..PROXY p ON c.OBJECT_ID = p.OBJECT_ID AND p.WORKING_VERSION_ID > 0
LEFT JOIN &Schema..USER_ u ON p.OWNER_ID = u.OBJECT_ID
WHERE c.OBJECT_ID = &ProjectId
  AND c.MODIFICATIONDATE_DA_ > TO_DATE('&StartDate', 'YYYY-MM-DD');

-- ==============================================================================
-- QUERY 2: Resource Library Activity
-- ==============================================================================
-- Tracks: Resources created/modified, resource types, checkout status

SELECT
    'RESOURCE_LIBRARY' as work_type,
    r.OBJECT_ID as object_id,
    r.NAME_S_ as object_name,
    cd.NICE_NAME as object_type,
    r.CREATEDBY_S_ as created_by,
    r.MODIFICATIONDATE_DA_ as last_modified,
    r.LASTMODIFIEDBY_S_ as modified_by,
    p.OWNER_ID as checked_out_by_user_id,
    u.CAPTION_S_ as checked_out_by_user_name,
    CASE WHEN p.WORKING_VERSION_ID > 0 THEN 'Checked Out' ELSE 'Available' END as status,
    p.WORKING_VERSION_ID as version_id
FROM &Schema..RESOURCE_ r
LEFT JOIN &Schema..CLASS_DEFINITIONS cd ON r.CLASS_ID = cd.TYPE_ID
LEFT JOIN &Schema..PROXY p ON r.OBJECT_ID = p.OBJECT_ID
LEFT JOIN &Schema..USER_ u ON p.OWNER_ID = u.OBJECT_ID
WHERE r.MODIFICATIONDATE_DA_ > TO_DATE('&StartDate', 'YYYY-MM-DD')
ORDER BY r.MODIFICATIONDATE_DA_ DESC;

-- ==============================================================================
-- QUERY 3: Part/MFG Library Activity
-- ==============================================================================
-- Tracks: Parts created/modified, panel codes (CC, RC, SC), hierarchy

SELECT
    'PART_LIBRARY' as work_type,
    p.OBJECT_ID as object_id,
    p.NAME_S_ as object_name,
    cd.NICE_NAME as object_type,
    CASE
        WHEN p.NAME_S_ IN ('CC', 'RCC') THEN 'Cell Coat'
        WHEN p.NAME_S_ = 'RC' THEN 'Robot Coat'
        WHEN p.NAME_S_ = 'SC' THEN 'Spot Coat'
        WHEN p.NAME_S_ = 'CMN' THEN 'Common'
        WHEN p.NAME_S_ IN ('P702', 'P736') THEN 'Build Assembly'
        WHEN REGEXP_LIKE(p.NAME_S_, '^[0-9]+$') THEN 'Level Code'
        ELSE 'Panel/Part'
    END as category,
    p.CREATEDBY_S_ as created_by,
    p.MODIFICATIONDATE_DA_ as last_modified,
    p.LASTMODIFIEDBY_S_ as modified_by,
    pr.OWNER_ID as checked_out_by_user_id,
    u.CAPTION_S_ as checked_out_by_user_name,
    CASE WHEN pr.WORKING_VERSION_ID > 0 THEN 'Checked Out' ELSE 'Available' END as status
FROM &Schema..PART_ p
LEFT JOIN &Schema..CLASS_DEFINITIONS cd ON p.CLASS_ID = cd.TYPE_ID
LEFT JOIN &Schema..PROXY pr ON p.OBJECT_ID = pr.OBJECT_ID
LEFT JOIN &Schema..USER_ u ON pr.OWNER_ID = u.OBJECT_ID
WHERE p.MODIFICATIONDATE_DA_ > TO_DATE('&StartDate', 'YYYY-MM-DD')
ORDER BY p.MODIFICATIONDATE_DA_ DESC;

-- ==============================================================================
-- QUERY 4: IPA Assembly Activity
-- ==============================================================================
-- Tracks: Process assemblies (TxProcessAssembly), station sequences

SELECT
    'IPA_ASSEMBLY' as work_type,
    pa.OBJECT_ID as object_id,
    pa.NAME_S_ as object_name,
    'TxProcessAssembly' as object_type,
    pa.CREATEDBY_S_ as created_by,
    pa.MODIFICATIONDATE_DA_ as last_modified,
    pa.LASTMODIFIEDBY_S_ as modified_by,
    pr.OWNER_ID as checked_out_by_user_id,
    u.CAPTION_S_ as checked_out_by_user_name,
    CASE WHEN pr.WORKING_VERSION_ID > 0 THEN 'Checked Out' ELSE 'Available' END as status,
    COUNT(DISTINCT o.OBJECT_ID) as operation_count
FROM &Schema..PART_ pa
LEFT JOIN &Schema..REL_COMMON r ON pa.OBJECT_ID = r.FORWARD_OBJECT_ID
LEFT JOIN &Schema..OPERATION_ o ON r.OBJECT_ID = o.OBJECT_ID
LEFT JOIN &Schema..PROXY pr ON pa.OBJECT_ID = pr.OBJECT_ID
LEFT JOIN &Schema..USER_ u ON pr.OWNER_ID = u.OBJECT_ID
WHERE pa.CLASS_ID = 133  -- TxProcessAssembly
  AND pa.MODIFICATIONDATE_DA_ > TO_DATE('&StartDate', 'YYYY-MM-DD')
GROUP BY pa.OBJECT_ID, pa.NAME_S_, pa.CREATEDBY_S_, pa.MODIFICATIONDATE_DA_,
         pa.LASTMODIFIEDBY_S_, pr.OWNER_ID, u.CAPTION_S_, pr.WORKING_VERSION_ID
ORDER BY pa.MODIFICATIONDATE_DA_ DESC;

-- ==============================================================================
-- QUERY 5A: Study Nodes - Summary
-- ==============================================================================
-- Tracks: Studies created/modified, study types, users, checkout status

SELECT
    'STUDY_SUMMARY' as work_type,
    rs.OBJECT_ID as study_id,
    rs.NAME_S_ as study_name,
    cd.NICE_NAME as study_type,
    rs.CREATEDBY_S_ as created_by,
    rs.MODIFICATIONDATE_DA_ as last_modified,
    rs.LASTMODIFIEDBY_S_ as modified_by,
    p.OWNER_ID as checked_out_by_user_id,
    u.CAPTION_S_ as checked_out_by_user_name,
    CASE WHEN p.WORKING_VERSION_ID > 0 THEN 'Active' ELSE 'Idle' END as status,
    p.WORKING_VERSION_ID as version_id
FROM &Schema..ROBCADSTUDY_ rs
LEFT JOIN &Schema..CLASS_DEFINITIONS cd ON rs.CLASS_ID = cd.TYPE_ID
LEFT JOIN &Schema..PROXY p ON rs.OBJECT_ID = p.OBJECT_ID
LEFT JOIN &Schema..USER_ u ON p.OWNER_ID = u.OBJECT_ID
WHERE rs.MODIFICATIONDATE_DA_ > TO_DATE('&StartDate', 'YYYY-MM-DD')
ORDER BY rs.MODIFICATIONDATE_DA_ DESC;

-- ==============================================================================
-- QUERY 5B: Study Nodes - Resource Allocation
-- ==============================================================================
-- Tracks: Which resources/stations allocated to studies

SELECT
    'STUDY_RESOURCES' as work_type,
    rs.OBJECT_ID as study_id,
    rs.NAME_S_ as study_name,
    s.OBJECT_ID as shortcut_id,
    s.NAME_S_ as shortcut_name,
    res.OBJECT_ID as resource_id,
    res.NAME_S_ as resource_name,
    cd.NICE_NAME as resource_type,
    CASE
        WHEN s.NAME_S_ = 'LAYOUT' THEN 'Layout Configuration'
        WHEN s.NAME_S_ LIKE '8J-%' AND s.NAME_S_ NOT LIKE '%\_%' ESCAPE '\' THEN 'Station Reference'
        WHEN s.NAME_S_ LIKE '%\_CMN' ESCAPE '\' THEN 'Common Operations'
        WHEN s.NAME_S_ LIKE '%\_SC' ESCAPE '\' THEN 'Spot Coat Operations'
        WHEN s.NAME_S_ LIKE '%\_RC' ESCAPE '\' THEN 'Robot Coat Operations'
        WHEN s.NAME_S_ LIKE '%\_CC' ESCAPE '\' THEN 'Cell Coat Operations'
        ELSE 'Other'
    END as allocation_type,
    r.SEQ_NUMBER as sequence
FROM &Schema..ROBCADSTUDY_ rs
INNER JOIN &Schema..REL_COMMON r ON rs.OBJECT_ID = r.FORWARD_OBJECT_ID
INNER JOIN &Schema..SHORTCUT_ s ON r.OBJECT_ID = s.OBJECT_ID
LEFT JOIN &Schema..RESOURCE_ res ON s.NAME_S_ = res.NAME_S_
LEFT JOIN &Schema..CLASS_DEFINITIONS cd ON res.CLASS_ID = cd.TYPE_ID
WHERE rs.MODIFICATIONDATE_DA_ > TO_DATE('&StartDate', 'YYYY-MM-DD')
ORDER BY rs.NAME_S_, r.SEQ_NUMBER;

-- ==============================================================================
-- QUERY 5C: Study Nodes - Panel Usage
-- ==============================================================================
-- Tracks: Which panels (CC, RC, SC) used in studies (via shortcut names)

SELECT
    'STUDY_PANELS' as work_type,
    rs.OBJECT_ID as study_id,
    rs.NAME_S_ as study_name,
    s.NAME_S_ as shortcut_name,
    CASE
        WHEN s.NAME_S_ LIKE '%\_CC' ESCAPE '\' THEN 'CC (Cell Coat)'
        WHEN s.NAME_S_ LIKE '%\_RC' ESCAPE '\' THEN 'RC (Robot Coat)'
        WHEN s.NAME_S_ LIKE '%\_SC' ESCAPE '\' THEN 'SC (Spot Coat)'
        WHEN s.NAME_S_ LIKE '%\_CMN' ESCAPE '\' THEN 'CMN (Common)'
        ELSE 'N/A'
    END as panel_code,
    SUBSTR(s.NAME_S_, 1, INSTR(s.NAME_S_, '_') - 1) as station,
    rs.MODIFICATIONDATE_DA_ as last_modified
FROM &Schema..ROBCADSTUDY_ rs
INNER JOIN &Schema..REL_COMMON r ON rs.OBJECT_ID = r.FORWARD_OBJECT_ID
INNER JOIN &Schema..SHORTCUT_ s ON r.OBJECT_ID = s.OBJECT_ID
WHERE s.NAME_S_ LIKE '%\_%' ESCAPE '\'  -- Has underscore (operation shortcuts)
  AND rs.MODIFICATIONDATE_DA_ > TO_DATE('&StartDate', 'YYYY-MM-DD')
ORDER BY rs.NAME_S_, s.NAME_S_;

-- ==============================================================================
-- QUERY 5D: Study Nodes - Operation Tree Activity
-- ==============================================================================
-- Tracks: Operations created/modified, weld operations, operation types

SELECT
    'STUDY_OPERATIONS' as work_type,
    o.OBJECT_ID as operation_id,
    o.NAME_S_ as operation_name,
    o.CAPTION_S_ as operation_caption,
    cd.NICE_NAME as operation_class,
    o.OPERATIONTYPE_S_ as operation_type,
    o.MODIFICATIONDATE_DA_ as last_modified,
    o.LASTMODIFIEDBY_S_ as modified_by,
    o.CREATEDBY_S_ as created_by,
    o.ALLOCATEDTIME_D_ as allocated_time,
    o.CALCULATEDTIME_D_ as calculated_time,
    o.VALUEADDEDTIME_D_ as value_added_time,
    CASE
        WHEN o.NAME_S_ LIKE 'PG%' THEN 'Weld Point Group'
        WHEN o.NAME_S_ LIKE 'MOV\_%' ESCAPE '\' THEN 'Movement Operation'
        WHEN o.NAME_S_ LIKE 'tip\_%' ESCAPE '\' THEN 'Tool Maintenance'
        WHEN o.NAME_S_ LIKE '%WELD%' THEN 'Weld Operation'
        ELSE 'Other'
    END as operation_category
FROM &Schema..OPERATION_ o
LEFT JOIN &Schema..CLASS_DEFINITIONS cd ON o.CLASS_ID = cd.TYPE_ID
WHERE o.MODIFICATIONDATE_DA_ > TO_DATE('&StartDate', 'YYYY-MM-DD')
  AND o.CLASS_ID = 141  -- Weld operations
ORDER BY o.MODIFICATIONDATE_DA_ DESC;

-- ==============================================================================
-- QUERY 5E: Study Nodes - Movement/Location Changes
-- ==============================================================================
-- Tracks: Location and rotation changes via STUDYLAYOUT and VEC tables

SELECT
    'STUDY_MOVEMENTS' as work_type,
    sl.OBJECT_ID as studylayout_id,
    sl.STUDYINFO_SR_ as studyinfo_id,
    rsi.NAME_S_ as studyinfo_name,
    sl.LOCATION_V_ as location_vector_id,
    sl.ROTATION_V_ as rotation_vector_id,
    sl.MODIFICATIONDATE_DA_ as last_modified,
    sl.LASTMODIFIEDBY_S_ as modified_by,
    -- Get X, Y, Z coordinates
    (SELECT vl.DATA FROM &Schema..VEC_LOCATION_ vl WHERE vl.OBJECT_ID = sl.LOCATION_V_ AND vl.SEQ_NUMBER = 0) as x_coord,
    (SELECT vl.DATA FROM &Schema..VEC_LOCATION_ vl WHERE vl.OBJECT_ID = sl.LOCATION_V_ AND vl.SEQ_NUMBER = 1) as y_coord,
    (SELECT vl.DATA FROM &Schema..VEC_LOCATION_ vl WHERE vl.OBJECT_ID = sl.LOCATION_V_ AND vl.SEQ_NUMBER = 2) as z_coord,
    -- Get rotation angles
    (SELECT vr.DATA FROM &Schema..VEC_ROTATION_ vr WHERE vr.OBJECT_ID = sl.ROTATION_V_ AND vr.SEQ_NUMBER = 0) as rx_angle,
    (SELECT vr.DATA FROM &Schema..VEC_ROTATION_ vr WHERE vr.OBJECT_ID = sl.ROTATION_V_ AND vr.SEQ_NUMBER = 1) as ry_angle,
    (SELECT vr.DATA FROM &Schema..VEC_ROTATION_ vr WHERE vr.OBJECT_ID = sl.ROTATION_V_ AND vr.SEQ_NUMBER = 2) as rz_angle
FROM &Schema..STUDYLAYOUT_ sl
LEFT JOIN &Schema..ROBCADSTUDYINFO_ rsi ON sl.STUDYINFO_SR_ = rsi.OBJECT_ID
WHERE sl.MODIFICATIONDATE_DA_ > TO_DATE('&StartDate', 'YYYY-MM-DD')
ORDER BY sl.MODIFICATIONDATE_DA_ DESC;

-- ==============================================================================
-- QUERY 5F: Study Nodes - Weld Point Count
-- ==============================================================================
-- Tracks: Spot welds added/modified, weld point counts

SELECT
    'STUDY_WELDS' as work_type,
    o.OBJECT_ID as operation_id,
    o.NAME_S_ as operation_name,
    COUNT(DISTINCT vl.OBJECT_ID) as weld_point_count,
    o.MODIFICATIONDATE_DA_ as last_modified,
    o.LASTMODIFIEDBY_S_ as modified_by
FROM &Schema..OPERATION_ o
LEFT JOIN &Schema..VEC_LOCATION_ vl ON o.OBJECT_ID = vl.OBJECT_ID
WHERE o.CLASS_ID = 141  -- Weld operations
  AND o.MODIFICATIONDATE_DA_ > TO_DATE('&StartDate', 'YYYY-MM-DD')
GROUP BY o.OBJECT_ID, o.NAME_S_, o.MODIFICATIONDATE_DA_, o.LASTMODIFIEDBY_S_
HAVING COUNT(DISTINCT vl.OBJECT_ID) > 0
ORDER BY o.MODIFICATIONDATE_DA_ DESC;

-- ==============================================================================
-- QUERY 6: User Activity Summary
-- ==============================================================================
-- Tracks: All activity by user across all work types

SELECT
    u.OBJECT_ID as user_id,
    u.CAPTION_S_ as user_name,
    u.NAME_ as username,
    COUNT(DISTINCT p.OBJECT_ID) as objects_checked_out,
    COUNT(DISTINCT CASE WHEN p.WORKING_VERSION_ID > 0 THEN p.OBJECT_ID END) as active_checkouts
FROM &Schema..USER_ u
LEFT JOIN &Schema..PROXY p ON u.OBJECT_ID = p.OWNER_ID
GROUP BY u.OBJECT_ID, u.CAPTION_S_, u.NAME_
HAVING COUNT(DISTINCT p.OBJECT_ID) > 0
ORDER BY active_checkouts DESC, objects_checked_out DESC;

EXIT;
