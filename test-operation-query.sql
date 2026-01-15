SET PAGESIZE 100
SET LINESIZE 200
SET FEEDBACK ON
SET HEADING ON

PROMPT Testing OPERATION_ extraction for FORD_DEARBORN project...

-- Simplified test: Find operations where we can trace back to project root
SELECT COUNT(*) as OPERATION_COUNT
FROM DESIGN12.OPERATION_ op
INNER JOIN DESIGN12.REL_COMMON r ON op.OBJECT_ID = r.OBJECT_ID
WHERE EXISTS (
    -- Traverse up the REL_COMMON chain from this operation's parent
    SELECT 1 FROM DESIGN12.REL_COMMON rc
    WHERE rc.OBJECT_ID IN (
        -- Get all ancestors by traversing up from the operation's parent
        SELECT rc2.OBJECT_ID
        FROM DESIGN12.REL_COMMON rc2
        START WITH rc2.OBJECT_ID = r.FORWARD_OBJECT_ID
        CONNECT BY NOCYCLE PRIOR rc2.FORWARD_OBJECT_ID = rc2.OBJECT_ID
    )
    AND rc.OBJECT_ID IN (
        -- Check if this ancestor is a COLLECTION_ in our project tree
        SELECT c.OBJECT_ID
        FROM DESIGN12.COLLECTION_ c
        START WITH c.OBJECT_ID = 18140190
        CONNECT BY NOCYCLE PRIOR c.OBJECT_ID = (
            SELECT rc3.FORWARD_OBJECT_ID
            FROM DESIGN12.REL_COMMON rc3
            WHERE rc3.OBJECT_ID = PRIOR c.OBJECT_ID
            AND ROWNUM = 1
        )
    )
);

PROMPT
PROMPT Testing simpler approach: check if operation or any ancestor is in project tree...

-- Alternative: Start from operation and traverse up until we hit project root
SELECT COUNT(*) as OPERATION_COUNT_ALT
FROM DESIGN12.OPERATION_ op
INNER JOIN DESIGN12.REL_COMMON r ON op.OBJECT_ID = r.OBJECT_ID
WHERE 18140190 IN (
    -- Get all ancestors by traversing up from the operation
    SELECT rc.FORWARD_OBJECT_ID
    FROM DESIGN12.REL_COMMON rc
    START WITH rc.OBJECT_ID = op.OBJECT_ID
    CONNECT BY NOCYCLE PRIOR rc.FORWARD_OBJECT_ID = rc.OBJECT_ID
);

PROMPT
PROMPT Sample operations using alternative approach:

SELECT op.OBJECT_ID, op.NAME_S_, op.CAPTION_S_, r.FORWARD_OBJECT_ID as PARENT_ID
FROM DESIGN12.OPERATION_ op
INNER JOIN DESIGN12.REL_COMMON r ON op.OBJECT_ID = r.OBJECT_ID
WHERE 18140190 IN (
    SELECT rc.FORWARD_OBJECT_ID
    FROM DESIGN12.REL_COMMON rc
    START WITH rc.OBJECT_ID = op.OBJECT_ID
    CONNECT BY NOCYCLE PRIOR rc.FORWARD_OBJECT_ID = rc.OBJECT_ID
)
AND (op.NAME_S_ IN ('MOV_HOME', 'COMM_PICK01') OR ROWNUM <= 5);

EXIT;
