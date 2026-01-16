-- Debug EngineeringResourceLibrary icon issue
-- Check what NICE_NAME value is actually in the database

SELECT
    NODE_ID,
    NAME,
    CLASS_NAME,
    TYPE_ID,
    NICE_NAME
FROM ROBUST_ROBCAD_ORACLE.ROBCADNODE_
WHERE NODE_ID = 18153685;
