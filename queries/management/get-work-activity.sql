-- get-work-activity.sql
-- Purpose: Management reporting queries for 5 work types (DESIGN12 schema).
-- Notes: Uses SQL*Plus substitution variables for ProjectId, StartDate, EndDate.

DEFINE ProjectId = 0
DEFINE StartDate = '2026-01-01'
DEFINE EndDate = '2026-01-31'

SET PAGESIZE 50000
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING ON
SET VERIFY OFF
SET COLSEP '|'
SET TRIMSPOOL ON

-- ==============================================================================
-- QUERY 1: Project Database Activity
-- ==============================================================================
SELECT
    'PROJECT_DATABASE' as work_type,
    c.OBJECT_ID as object_id,
    c.CAPTION_S_ as object_name,
    'Project' as object_type,
    c.CREATEDBY_S_ as created_by,
    TO_CHAR(c.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as last_modified,
    c.LASTMODIFIEDBY_S_ as modified_by,
    p.OWNER_ID as checked_out_by_user_id,
    u.CAPTION_S_ as checked_out_by_user_name,
    CASE WHEN p.WORKING_VERSION_ID > 0 THEN 'Checked Out' ELSE 'Available' END as status,
    p.WORKING_VERSION_ID as version_id
FROM DESIGN12.COLLECTION_ c
LEFT JOIN DESIGN12.PROXY p ON c.OBJECT_ID = p.OBJECT_ID AND p.WORKING_VERSION_ID > 0
LEFT JOIN DESIGN12.USER_ u ON p.OWNER_ID = u.OBJECT_ID
WHERE c.OBJECT_ID = &ProjectId
  AND c.MODIFICATIONDATE_DA_ >= TO_DATE('&StartDate', 'YYYY-MM-DD')
  AND c.MODIFICATIONDATE_DA_ <= TO_DATE('&EndDate', 'YYYY-MM-DD')
ORDER BY c.MODIFICATIONDATE_DA_ DESC;

-- ==============================================================================
-- QUERY 2: Resource Library Activity
-- ==============================================================================
SELECT
    'RESOURCE_LIBRARY' as work_type,
    r.OBJECT_ID as object_id,
    r.NAME_S_ as object_name,
    cd.NICE_NAME as object_type,
    r.CREATEDBY_S_ as created_by,
    TO_CHAR(r.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as last_modified,
    r.LASTMODIFIEDBY_S_ as modified_by,
    p.OWNER_ID as checked_out_by_user_id,
    u.CAPTION_S_ as checked_out_by_user_name,
    CASE WHEN p.WORKING_VERSION_ID > 0 THEN 'Checked Out' ELSE 'Available' END as status,
    p.WORKING_VERSION_ID as version_id
FROM DESIGN12.RESOURCE_ r
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON r.CLASS_ID = cd.TYPE_ID
LEFT JOIN DESIGN12.PROXY p ON r.OBJECT_ID = p.OBJECT_ID AND p.WORKING_VERSION_ID > 0
LEFT JOIN DESIGN12.USER_ u ON p.OWNER_ID = u.OBJECT_ID
WHERE r.MODIFICATIONDATE_DA_ >= TO_DATE('&StartDate', 'YYYY-MM-DD')
  AND r.MODIFICATIONDATE_DA_ <= TO_DATE('&EndDate', 'YYYY-MM-DD')
ORDER BY r.MODIFICATIONDATE_DA_ DESC;

-- ==============================================================================
-- QUERY 3: Part/MFG Library Activity
-- ==============================================================================
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
    TO_CHAR(p.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as last_modified,
    p.LASTMODIFIEDBY_S_ as modified_by,
    pr.OWNER_ID as checked_out_by_user_id,
    u.CAPTION_S_ as checked_out_by_user_name,
    CASE WHEN pr.WORKING_VERSION_ID > 0 THEN 'Checked Out' ELSE 'Available' END as status,
    pr.WORKING_VERSION_ID as version_id
FROM DESIGN12.PART_ p
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON p.CLASS_ID = cd.TYPE_ID
LEFT JOIN DESIGN12.PROXY pr ON p.OBJECT_ID = pr.OBJECT_ID AND pr.WORKING_VERSION_ID > 0
LEFT JOIN DESIGN12.USER_ u ON pr.OWNER_ID = u.OBJECT_ID
WHERE p.MODIFICATIONDATE_DA_ >= TO_DATE('&StartDate', 'YYYY-MM-DD')
  AND p.MODIFICATIONDATE_DA_ <= TO_DATE('&EndDate', 'YYYY-MM-DD')
ORDER BY p.MODIFICATIONDATE_DA_ DESC;

-- ==============================================================================
-- QUERY 4: IPA Assembly Activity
-- ==============================================================================
SELECT
    'IPA_ASSEMBLY' as work_type,
    pa.OBJECT_ID as object_id,
    pa.NAME_S_ as object_name,
    'TxProcessAssembly' as object_type,
    pa.CREATEDBY_S_ as created_by,
    TO_CHAR(pa.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as last_modified,
    pa.LASTMODIFIEDBY_S_ as modified_by,
    pr.OWNER_ID as checked_out_by_user_id,
    u.CAPTION_S_ as checked_out_by_user_name,
    CASE WHEN pr.WORKING_VERSION_ID > 0 THEN 'Checked Out' ELSE 'Available' END as status,
    COUNT(DISTINCT o.OBJECT_ID) as operation_count,
    pr.WORKING_VERSION_ID as version_id
FROM DESIGN12.PART_ pa
LEFT JOIN DESIGN12.REL_COMMON r ON pa.OBJECT_ID = r.FORWARD_OBJECT_ID
LEFT JOIN DESIGN12.OPERATION_ o ON r.OBJECT_ID = o.OBJECT_ID
LEFT JOIN DESIGN12.PROXY pr ON pa.OBJECT_ID = pr.OBJECT_ID AND pr.WORKING_VERSION_ID > 0
LEFT JOIN DESIGN12.USER_ u ON pr.OWNER_ID = u.OBJECT_ID
WHERE pa.CLASS_ID = 133
  AND pa.MODIFICATIONDATE_DA_ >= TO_DATE('&StartDate', 'YYYY-MM-DD')
  AND pa.MODIFICATIONDATE_DA_ <= TO_DATE('&EndDate', 'YYYY-MM-DD')
GROUP BY pa.OBJECT_ID, pa.NAME_S_, pa.CREATEDBY_S_, pa.MODIFICATIONDATE_DA_,
         pa.LASTMODIFIEDBY_S_, pr.OWNER_ID, u.CAPTION_S_, pr.WORKING_VERSION_ID
ORDER BY pa.MODIFICATIONDATE_DA_ DESC;

-- ==============================================================================
-- QUERY 5: Study Nodes - Summary
-- ==============================================================================
SELECT
    'STUDY_SUMMARY' as work_type,
    rs.OBJECT_ID as study_id,
    rs.NAME_S_ as study_name,
    cd.NICE_NAME as study_type,
    rs.CREATEDBY_S_ as created_by,
    TO_CHAR(rs.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as last_modified,
    rs.LASTMODIFIEDBY_S_ as modified_by,
    p.OWNER_ID as checked_out_by_user_id,
    u.CAPTION_S_ as checked_out_by_user_name,
    CASE WHEN p.WORKING_VERSION_ID > 0 THEN 'Active' ELSE 'Idle' END as status,
    p.WORKING_VERSION_ID as version_id
FROM DESIGN12.ROBCADSTUDY_ rs
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON rs.CLASS_ID = cd.TYPE_ID
LEFT JOIN DESIGN12.PROXY p ON rs.OBJECT_ID = p.OBJECT_ID AND p.WORKING_VERSION_ID > 0
LEFT JOIN DESIGN12.USER_ u ON p.OWNER_ID = u.OBJECT_ID
WHERE rs.MODIFICATIONDATE_DA_ >= TO_DATE('&StartDate', 'YYYY-MM-DD')
  AND rs.MODIFICATIONDATE_DA_ <= TO_DATE('&EndDate', 'YYYY-MM-DD')
ORDER BY rs.MODIFICATIONDATE_DA_ DESC;

-- ==============================================================================
-- QUERY 6: Study Nodes - Resource Allocation
-- ==============================================================================
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
    r.SEQ_NUMBER as sequence,
    pr.OWNER_ID as checked_out_by_user_id,
    u.CAPTION_S_ as checked_out_by_user_name,
    CASE WHEN pr.WORKING_VERSION_ID > 0 THEN 'Checked Out' ELSE 'Available' END as status,
    pr.WORKING_VERSION_ID as version_id
FROM DESIGN12.ROBCADSTUDY_ rs
INNER JOIN DESIGN12.REL_COMMON r ON rs.OBJECT_ID = r.FORWARD_OBJECT_ID
INNER JOIN DESIGN12.SHORTCUT_ s ON r.OBJECT_ID = s.OBJECT_ID
LEFT JOIN DESIGN12.RESOURCE_ res ON s.NAME_S_ = res.NAME_S_
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON res.CLASS_ID = cd.TYPE_ID
LEFT JOIN DESIGN12.PROXY pr ON res.OBJECT_ID = pr.OBJECT_ID AND pr.WORKING_VERSION_ID > 0
LEFT JOIN DESIGN12.USER_ u ON pr.OWNER_ID = u.OBJECT_ID
WHERE rs.MODIFICATIONDATE_DA_ >= TO_DATE('&StartDate', 'YYYY-MM-DD')
  AND rs.MODIFICATIONDATE_DA_ <= TO_DATE('&EndDate', 'YYYY-MM-DD')
ORDER BY rs.NAME_S_, r.SEQ_NUMBER;

-- ==============================================================================
-- QUERY 7: Study Nodes - Panel Usage
-- ==============================================================================
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
    TO_CHAR(rs.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as last_modified,
    p.OWNER_ID as checked_out_by_user_id,
    u.CAPTION_S_ as checked_out_by_user_name,
    CASE WHEN p.WORKING_VERSION_ID > 0 THEN 'Active' ELSE 'Idle' END as status,
    p.WORKING_VERSION_ID as version_id
FROM DESIGN12.ROBCADSTUDY_ rs
INNER JOIN DESIGN12.REL_COMMON r ON rs.OBJECT_ID = r.FORWARD_OBJECT_ID
INNER JOIN DESIGN12.SHORTCUT_ s ON r.OBJECT_ID = s.OBJECT_ID
LEFT JOIN DESIGN12.PROXY p ON rs.OBJECT_ID = p.OBJECT_ID AND p.WORKING_VERSION_ID > 0
LEFT JOIN DESIGN12.USER_ u ON p.OWNER_ID = u.OBJECT_ID
WHERE s.NAME_S_ LIKE '%\_%' ESCAPE '\'
  AND rs.MODIFICATIONDATE_DA_ >= TO_DATE('&StartDate', 'YYYY-MM-DD')
  AND rs.MODIFICATIONDATE_DA_ <= TO_DATE('&EndDate', 'YYYY-MM-DD')
ORDER BY rs.NAME_S_, s.NAME_S_;

-- ==============================================================================
-- QUERY 8: Study Nodes - Operation Tree Activity
-- ==============================================================================
SELECT
    'STUDY_OPERATIONS' as work_type,
    o.OBJECT_ID as operation_id,
    o.NAME_S_ as operation_name,
    o.CAPTION_S_ as operation_caption,
    cd.NICE_NAME as operation_class,
    o.OPERATIONTYPE_S_ as operation_type,
    TO_CHAR(o.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as last_modified,
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
    END as operation_category,
    p.OWNER_ID as checked_out_by_user_id,
    u.CAPTION_S_ as checked_out_by_user_name,
    CASE WHEN p.WORKING_VERSION_ID > 0 THEN 'Checked Out' ELSE 'Available' END as status,
    p.WORKING_VERSION_ID as version_id
FROM DESIGN12.OPERATION_ o
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON o.CLASS_ID = cd.TYPE_ID
LEFT JOIN DESIGN12.PROXY p ON o.OBJECT_ID = p.OBJECT_ID AND p.WORKING_VERSION_ID > 0
LEFT JOIN DESIGN12.USER_ u ON p.OWNER_ID = u.OBJECT_ID
WHERE o.MODIFICATIONDATE_DA_ >= TO_DATE('&StartDate', 'YYYY-MM-DD')
  AND o.MODIFICATIONDATE_DA_ <= TO_DATE('&EndDate', 'YYYY-MM-DD')
  AND o.CLASS_ID = 141
ORDER BY o.MODIFICATIONDATE_DA_ DESC;

-- ==============================================================================
-- QUERY 9: Study Nodes - Movement/Location Changes
-- ==============================================================================
WITH vec_points AS (
    SELECT
        vl.OBJECT_ID,
        vl.MODIFICATIONDATE_DA_ as vec_modified_at,
        MAX(CASE WHEN vl.SEQ_NUMBER = 0 THEN TO_NUMBER(vl.DATA) END) as x_coord,
        MAX(CASE WHEN vl.SEQ_NUMBER = 1 THEN TO_NUMBER(vl.DATA) END) as y_coord,
        MAX(CASE WHEN vl.SEQ_NUMBER = 2 THEN TO_NUMBER(vl.DATA) END) as z_coord
    FROM DESIGN12.VEC_LOCATION_ vl
    WHERE vl.MODIFICATIONDATE_DA_ >= TO_DATE('&StartDate', 'YYYY-MM-DD')
      AND vl.MODIFICATIONDATE_DA_ <= TO_DATE('&EndDate', 'YYYY-MM-DD')
    GROUP BY vl.OBJECT_ID, vl.MODIFICATIONDATE_DA_
),
vec_delta AS (
    SELECT
        v.*,
        LAG(v.x_coord) OVER (PARTITION BY v.OBJECT_ID ORDER BY v.vec_modified_at) as prev_x_coord,
        LAG(v.y_coord) OVER (PARTITION BY v.OBJECT_ID ORDER BY v.vec_modified_at) as prev_y_coord,
        LAG(v.z_coord) OVER (PARTITION BY v.OBJECT_ID ORDER BY v.vec_modified_at) as prev_z_coord
    FROM vec_points v
),
vec_classified AS (
    SELECT
        v.*,
        CASE
            WHEN v.prev_x_coord IS NULL OR v.prev_y_coord IS NULL OR v.prev_z_coord IS NULL THEN NULL
            ELSE GREATEST(
                ABS(v.x_coord - v.prev_x_coord),
                ABS(v.y_coord - v.prev_y_coord),
                ABS(v.z_coord - v.prev_z_coord)
            )
        END as delta_mm,
        CASE
            WHEN v.prev_x_coord IS NULL OR v.prev_y_coord IS NULL OR v.prev_z_coord IS NULL THEN 'Unknown'
            WHEN GREATEST(
                ABS(v.x_coord - v.prev_x_coord),
                ABS(v.y_coord - v.prev_y_coord),
                ABS(v.z_coord - v.prev_z_coord)
            ) >= 1000 THEN 'World'
            ELSE 'Simple'
        END as movement_type
    FROM vec_delta v
)
SELECT
    'STUDY_MOVEMENTS' as work_type,
    sl.OBJECT_ID as studylayout_id,
    rs.OBJECT_ID as study_id,
    rs.NAME_S_ as study_name,
    sl.STUDYINFO_SR_ as studyinfo_id,
    sl.LOCATION_V_ as location_vector_id,
    sl.ROTATION_V_ as rotation_vector_id,
    TO_CHAR(sl.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as last_modified,
    TO_CHAR(vc.vec_modified_at, 'YYYY-MM-DD HH24:MI:SS') as vector_modified_at,
    sl.LASTMODIFIEDBY_S_ as modified_by,
    vc.x_coord,
    vc.y_coord,
    vc.z_coord,
    vc.prev_x_coord,
    vc.prev_y_coord,
    vc.prev_z_coord,
    vc.delta_mm,
    vc.movement_type,
    p.OWNER_ID as checked_out_by_user_id,
    u.CAPTION_S_ as checked_out_by_user_name,
    CASE WHEN p.WORKING_VERSION_ID > 0 THEN 'Checked Out' ELSE 'Available' END as status,
    p.WORKING_VERSION_ID as version_id
FROM DESIGN12.STUDYLAYOUT_ sl
LEFT JOIN DESIGN12.ROBCADSTUDYINFO_ rsi ON sl.STUDYINFO_SR_ = rsi.OBJECT_ID
LEFT JOIN DESIGN12.ROBCADSTUDY_ rs ON rsi.STUDY_SR_ = rs.OBJECT_ID
LEFT JOIN vec_classified vc ON sl.LOCATION_V_ = vc.OBJECT_ID
LEFT JOIN DESIGN12.PROXY p ON sl.OBJECT_ID = p.OBJECT_ID AND p.WORKING_VERSION_ID > 0
LEFT JOIN DESIGN12.USER_ u ON p.OWNER_ID = u.OBJECT_ID
WHERE sl.MODIFICATIONDATE_DA_ >= TO_DATE('&StartDate', 'YYYY-MM-DD')
  AND sl.MODIFICATIONDATE_DA_ <= TO_DATE('&EndDate', 'YYYY-MM-DD')
ORDER BY sl.MODIFICATIONDATE_DA_ DESC;

-- ==============================================================================
-- QUERY 10: Study Nodes - Weld Point Count
-- ==============================================================================
SELECT
    'STUDY_WELDS' as work_type,
    o.OBJECT_ID as operation_id,
    o.NAME_S_ as operation_name,
    COUNT(DISTINCT vl.OBJECT_ID) as weld_point_count,
    TO_CHAR(o.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as last_modified,
    o.LASTMODIFIEDBY_S_ as modified_by,
    p.OWNER_ID as checked_out_by_user_id,
    u.CAPTION_S_ as checked_out_by_user_name,
    CASE WHEN p.WORKING_VERSION_ID > 0 THEN 'Checked Out' ELSE 'Available' END as status,
    p.WORKING_VERSION_ID as version_id
FROM DESIGN12.OPERATION_ o
LEFT JOIN DESIGN12.VEC_LOCATION_ vl ON o.OBJECT_ID = vl.OBJECT_ID
LEFT JOIN DESIGN12.PROXY p ON o.OBJECT_ID = p.OBJECT_ID AND p.WORKING_VERSION_ID > 0
LEFT JOIN DESIGN12.USER_ u ON p.OWNER_ID = u.OBJECT_ID
WHERE o.CLASS_ID = 141
  AND o.MODIFICATIONDATE_DA_ >= TO_DATE('&StartDate', 'YYYY-MM-DD')
  AND o.MODIFICATIONDATE_DA_ <= TO_DATE('&EndDate', 'YYYY-MM-DD')
GROUP BY o.OBJECT_ID, o.NAME_S_, o.MODIFICATIONDATE_DA_, o.LASTMODIFIEDBY_S_, p.OWNER_ID, u.CAPTION_S_, p.WORKING_VERSION_ID
HAVING COUNT(DISTINCT vl.OBJECT_ID) > 0
ORDER BY o.MODIFICATIONDATE_DA_ DESC;

-- ==============================================================================
-- QUERY 11: MFG Feature Usage
-- ==============================================================================
SELECT
    'MFG_FEATURE_USAGE' as work_type,
    mf.OBJECT_ID as mfg_feature_id,
    mf.NAME_S_ as mfg_feature_name,
    TO_CHAR(mf.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as last_modified,
    mf.LASTMODIFIEDBY_S_ as modified_by,
    COUNT(DISTINCT o.OBJECT_ID) as used_in_operations_count,
    p.OWNER_ID as checked_out_by_user_id,
    u.CAPTION_S_ as checked_out_by_user_name,
    CASE WHEN p.WORKING_VERSION_ID > 0 THEN 'Checked Out' ELSE 'Available' END as status,
    p.WORKING_VERSION_ID as version_id
FROM DESIGN12.MFGFEATURE_ mf
LEFT JOIN DESIGN12.OPERATION_ o ON mf.OBJECT_ID = o.MFGUSAGES_VR_
LEFT JOIN DESIGN12.PROXY p ON mf.OBJECT_ID = p.OBJECT_ID AND p.WORKING_VERSION_ID > 0
LEFT JOIN DESIGN12.USER_ u ON p.OWNER_ID = u.OBJECT_ID
WHERE mf.MODIFICATIONDATE_DA_ >= TO_DATE('&StartDate', 'YYYY-MM-DD')
  AND mf.MODIFICATIONDATE_DA_ <= TO_DATE('&EndDate', 'YYYY-MM-DD')
GROUP BY mf.OBJECT_ID, mf.NAME_S_, mf.MODIFICATIONDATE_DA_, mf.LASTMODIFIEDBY_S_, p.OWNER_ID, u.CAPTION_S_, p.WORKING_VERSION_ID
ORDER BY used_in_operations_count DESC, mf.MODIFICATIONDATE_DA_ DESC;

-- ==============================================================================
-- QUERY 12: User Activity Summary
-- ==============================================================================
SELECT
    u.OBJECT_ID as user_id,
    u.CAPTION_S_ as user_name,
    u.NAME_ as username,
    COUNT(DISTINCT p.OBJECT_ID) as objects_total,
    COUNT(DISTINCT CASE WHEN p.WORKING_VERSION_ID > 0 THEN p.OBJECT_ID END) as active_checkouts
FROM DESIGN12.USER_ u
LEFT JOIN DESIGN12.PROXY p ON u.OBJECT_ID = p.OWNER_ID
GROUP BY u.OBJECT_ID, u.CAPTION_S_, u.NAME_
HAVING COUNT(DISTINCT p.OBJECT_ID) > 0
ORDER BY active_checkouts DESC, objects_total DESC;

EXIT;
