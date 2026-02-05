# Set environment:
#------------------ 
#!C:\MKSNT/perl.exe

# Get command arguments:
# first argument: Oracle Base - directory under which Database admin and oradata directories will be installed
# second argument: Oracle Home - directory under which Oracle RDBMS software is installed    
# third argument: Oracle SID - name of the database instance that will be created 
# fourth argument: IP - ip address of the machine on which the installation is performed

use File::Path;


# Use command arguments to assign values to local variables
local $oracle_home;
local $sid;
local $pdb;
local $ip;
local $oradata_path;
local $small_database;

local $db_block_buffers;
local $pga_aggregate_target;
local $shared_pool_size;
local $shared_pool_reserved_size;
local $system_size;
local $large_tbs_size;
local $medium_tbs_size;
local $small_tbs_size;
local $large_ext_size;
local $medium_ext_size;
local $small_ext_size;
local $large_autoext_size;
local $medium_autoext_size;
local $small_autoext_size;
local $redo_log_size;

local $oracle_base = shift(@ARGV);
$oracle_home = shift(@ARGV);
$sid = shift(@ARGV);
$pdb = shift(@ARGV);
$ip = shift(@ARGV);
$port = shift(@ARGV);
$oradata_path = shift(@ARGV);
local $admin_path = "${oracle_base}/admin/${sid}";

$oradata_path = "${oracle_base}\\oradata\\${sid}" unless defined ($oradata_path);

# Unremark the following line for a small installation
#$small_database = "TRUE"; 

if (defined $small_database) {
	# database parameters for small installation
	$pga_aggregate_target = "50M";
	$sga_target_size = "150M";	 	
	$system_size = "150M"; 
	$large_tbs_size = "200M"; 
	$medium_tbs_size = "150M"; 
	$small_tbs_size = "100M";
	$large_ext_size = "1M"; 
	$medium_ext_size = "512K"; 
	$small_ext_size = "128K";
	$large_autoext_size = "10M"; 
	$medium_autoext_size = "5120K"; 
	$small_autoext_size = "1M"; 
	$redo_log_size = "50M";
} else {
	# The next 3 parameters are responsible for Oracle memory usage.
	# Numbers are set for at least 2G memory machine.
	$pga_aggregate_target = "800M";	 
	$sga_target_size = "3000M";	 
	$system_size = "500M";	
	$large_tbs_size = "500M";
	$medium_tbs_size = "300M";
	$small_tbs_size = "200M";
	$large_ext_size = "10M";
	$medium_ext_size = "1M";
	$small_ext_size = "128K";
	$large_autoext_size = "100M"; 
	$medium_autoext_size = "30M"; 
	$small_autoext_size = "20M"; 
	$redo_log_size = "100M";
}


# Create OFA-compliant directories for DB administration files
local $admin_base = "${oracle_base}\\admin";
local $admin_path = "${admin_base}\\${sid}";
mkdir "${admin_base}",777;
mkdir "${admin_path}",777;
mkdir "${admin_path}\\create",777;
mkdir "${admin_path}\\pfile",777;
mkdir "${admin_path}\\applog",777;
mkdir "${oracle_base}\\diag",777;


# Create OFA-compliant directory for database files
$oradata_path = "${oracle_base}\\oradata\\${sid}" unless defined ($oradata_path);
#$oradata_path =~ tr/\\/\// ;
mkpath("${oradata_path}\\PDBSEED");
mkpath("${oradata_path}\\${pdb}");



# Create a file into which success/failure messages will be written
rename "${admin_path}\\create\\build_files.log","${admin_path}\\create\\build_files.log.old";
local $logfile = "${admin_path}\\create\\build_files.log";
if (open(LOG_FILE, ">$logfile"))  {
	print "File $logfile created successfully\n";
}
else  {
	print "Couldn't open file: $logfile\n";
}

# Build file to be placed in a default location for initSID.ora. The file contains reference to an
# actual initialization file (IFILE = ...)    
rename "${oracle_home}\\database\\init${sid}.ora","${oracle_home}\\database\\init${sid}.ora.old";
local $ifile = "${oracle_home}\\database\\init${sid}.ora";
if (open(OUT_FILE, ">$ifile"))  {
	print LOG_FILE "File $ifile created successfully\n";
}
else  {
	print LOG_FILE "Couldn't open file: $ifile\n";
}
print OUT_FILE "IFILE = \'${admin_path}\\pfile\\init.ora\'";
close(OUT_FILE);

# Build actual init.ora
rename "${admin_path}\\pfile\\init.ora","${admin_path}\\pfile\\init.ora.old";
local $initora = "${admin_path}\\pfile\\init.ora";
if (open(OUT_FILE, ">$initora"))  {
	print LOG_FILE "File $initora created successfully\n";
}
else  {
	print LOG_FILE "Couldn't open file: $initora\n";
}
print OUT_FILE  <<EOF;

db_name = "${sid}"
instance_name = ${sid}
service_names = ${sid}
db_files = 1024
control_files = ("${oradata_path}\\control01.ctl", "${oradata_path}\\control02.ctl", "${oradata_path}\\control03.ctl")
# Files Locations
diagnostic_dest= ${oracle_base}\\diag
#utl_file_dir=${admin_path}\\applog # depricated

db_file_multiblock_read_count = 8
db_block_size = 8192
#sga_target replaces buffer_cache, shared_pool, large_pool and java_pool sizes
sga_target = ${sga_target_size}
pga_aggregate_target=${pga_aggregate_target}
log_buffer = 1638400
max_dump_file_size = 10M

processes = 500
global_names = false

#pluggable databases

enable_pluggable_database=true
remote_login_passwordfile = exclusive
os_authent_prefix = ""
compatible = 12.2.0
open_cursors = 400
#session_cached_cursors = 20 -- default since 11 is 50, that is good
job_queue_processes = 1000 # was set to 2, due to that in 10.2 the default was 0, in 12.2 the default is 4000, so, leaving it 1000
#aq_tm_processes = 1 -- deafault value since 11
#optimizer_mode = CHOOSE - not supported any more
optimizer_index_cost_adj = 10
#optimizer_dynamic_sampling = 2 -- default since 10
optimizer_adaptive_plans=FALSE
query_rewrite_enabled=FALSE
#star_transformation_enabled=FALSE -- default since 10
fast_start_mttr_target=300
#undo_management=AUTO default
#undo_retention=600 # 10 mins deault is bigger
undo_tablespace=UNDOTBS1

# For statspack
timed_statistics=TRUE
#sec_case_sensitive_logon=FALSE #deprecated
deferred_segment_creation=FALSE
recyclebin=off

EOF

close(OUT_FILE);

# Build Net configuration files: tnsnames.ora, listener.ora, sqlnet.ora
local $net8_path = "${oracle_home}\\network\\admin";

### Building tnsnames.ora
local $tnsnames = "${net8_path}\\tnsnames.ora";
if (open(OUT_FILE, ">>$tnsnames"))  {
	print LOG_FILE "File $tnsnames was successfully set\n";
}
else  {
	print LOG_FILE "Couldn't open file: $tnsnames\n";
}
print OUT_FILE <<EOF;

${pdb} =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = ${ip})(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = ${pdb})
    )
  )
EOF
close(OUT_FILE);

### Building listener.ora
local $listener = "${net8_path}\\listener.ora";
if ( -e $listener) {
	print LOG_FILE "WARNING: File $listener skipped - file already exists\n";
} 
else {
	if (open(OUT_FILE, ">$listener"))  {
		print LOG_FILE "File $listener created successfully\n";
	}
	else  {
		print LOG_FILE "Couldn't open file: $listener\n";
	}

	print OUT_FILE <<EOF;
LISTENER =
  (DESCRIPTION_LIST =
	 (DESCRIPTION =
		(ADDRESS_LIST =
			(ADDRESS = (PROTOCOL = TCP)(HOST = ${ip})(PORT = ${port}))
		)
		(ADDRESS_LIST =
			(ADDRESS = (PROTOCOL = IPC)(KEY = EXTPROC0))
		)
	 )
  )
EOF
	close(OUT_FILE);
}

### Building sqlnet.ora
local $sqlnet = "${net8_path}\\sqlnet.ora";
if (-e $sqlnet) {
	print LOG_FILE "WARNING: File $sqlnet skipped - file already exists\n";
}
else {
	if (open(OUT_FILE, ">$sqlnet"))  {
		print LOG_FILE "File $sqlnet created successfully\n";
	}
	else  {
		print LOG_FILE "Couldn't open file: $sqlnet\n";
	}
	print OUT_FILE "SQLNET.AUTHENTICATION_SERVICES = (NTS)";  
	print OUT_FILE "SQLNET.EXPIRE_TIME = 1";  
	close(OUT_FILE);
}

# Building DB creation and customization scripts
local $credb_path = "${admin_path}\\create";

### Building SIDrun.sql - script to create DB
rename "${credb_path}\\${sid}run.sql","${credb_path}\\${sid}run.sql.old";
local $SIDrun = "${credb_path}\\${sid}run.sql";
if (open(OUT_FILE, ">$SIDrun"))  {
	print LOG_FILE "File $SIDrun created successfully\n";
}
else  {
	print LOG_FILE "Couldn't open file: $SIDrun\n";
}
print OUT_FILE <<EOF;

spool ${credb_path}\\${sid}run.log
set echo on
connect sys/change_on_install@${sid} as SYSDBA
startup nomount pfile="${admin_path}\\pfile\\init.ora"
whenever sqlerror exit failure

CREATE DATABASE ${sid}
USER SYS IDENTIFIED BY change_on_install
USER SYSTEM IDENTIFIED BY manager
LOGFILE group 1 ('${oradata_path}\\${sid}_g1_m1.rdo',
		 '${oradata_path}\\${sid}_g1_m2.rdo') SIZE ${redo_log_size},
	group 2 ('${oradata_path}\\${sid}_g2_m1.rdo',
		 '${oradata_path}\\${sid}_g2_m2.rdo') SIZE ${redo_log_size},
	group 3 ('${oradata_path}\\${sid}_g3_m1.rdo',
		 '${oradata_path}\\${sid}_g3_m2.rdo') SIZE ${redo_log_size},
	group 4 ('${oradata_path}\\${sid}_g4_m1.rdo',
		 '${oradata_path}\\${sid}_g4_m2.rdo') SIZE ${redo_log_size}
 MAXLOGHISTORY 1
 MAXLOGFILES 32
 MAXLOGMEMBERS 2
 MAXDATAFILES 1024
 CHARACTER SET AL32UTF8
 NATIONAL CHARACTER SET AL16UTF16
 EXTENT MANAGEMENT LOCAL
DATAFILE '${oradata_path}\\system01.dbf' SIZE ${system_size} REUSE AUTOEXTEND ON NEXT 5M 
SYSAUX DATAFILE '${oradata_path}\\sysaux01.dbf' SIZE ${system_size} REUSE AUTOEXTEND ON NEXT 5M 
DEFAULT TEMPORARY TABLESPACE TEMP TEMPFILE '${oradata_path}\\temp01.dbf' SIZE ${medium_tbs_size} REUSE AUTOEXTEND ON NEXT ${medium_autoext_size} EXTENT MANAGEMENT LOCAL
UNDO TABLESPACE "UNDOTBS1" DATAFILE '${oradata_path}\\undotbs01.dbf' SIZE ${large_tbs_size} REUSE AUTOEXTEND ON NEXT 5M
 ENABLE PLUGGABLE DATABASE
 SEED
 FILE_NAME_CONVERT = ('${oradata_path}',
 '${oradata_path}\\pdbseed\\')
 LOCAL UNDO ON;
CREATE SPFILE FROM PFILE='${admin_path}/pfile/init.ora'; 
spool off
exit
EOF
close(OUT_FILE);

### Building SIDrun1.sql - script to customize DB
rename "${credb_path}\\${sid}run1.sql","${credb_path}\\${sid}run1.sql.old";
local $SIDrun1 = "${credb_path}\\${sid}run1.sql";
if (open(OUT_FILE, ">$SIDrun1"))  {
	print LOG_FILE "File $SIDrun1 created successfully\n";
}
else  {
	print LOG_FILE "Couldn't open file: $SIDrun1\n";
}                  
print OUT_FILE <<EOF;
spool ${credb_path}\\${sid}run1.log
set echo on
connect sys/change_on_install@${sid} as SYSDBA

--------------------------- Obsolete in 9i ---------------------------
-- No need to alter the default storage for the system tablespace,
-- uniform extent allocation is used.

-- No need to create RBS tablespaces, automatic undo is on.

-- No need to create the temp tablespace,
-- default temporary tablespace is created during database creation.
----------------------------------------------------------------------

\@${oracle_home}\\Rdbms\\admin\\catcdb.sql ${credb_path} catcdb.out;
---\@${oracle_home}\\Rdbms\\admin\\catalog.sql;
---\@${oracle_home}\\Rdbms\\admin\\catproc.sql;
connect system/manager
\@${oracle_home}\\sqlplus\\admin\\pupbld.sql
connect sys/change_on_install as SYSDBA
\@${oracle_home}\\rdbms\\admin\\utlrp.sql
alter profile default limit password_life_time unlimited;

CREATE PLUGGABLE DATABASE ${pdb} ADMIN USER pdbadmin IDENTIFIED BY pdbadmin
FILE_NAME_CONVERT=('${oradata_path}\\pdbseed\\','${oradata_path}\\${pdb}\\');

ALTER PLUGGABLE DATABASE ${pdb} OPEN;

ALTER PLUGGABLE DATABASE ${pdb} SAVE STATE;

ALTER SESSION SET CONTAINER = ${pdb};

---\@${oracle_home}/rdbms/admin/catalog.sql;
---\@${oracle_home}/rdbms/admin/catproc.sql;
connect system/manager
ALTER SESSION SET CONTAINER = ${pdb};
connect system/manager
\@${oracle_home}/sqlplus/admin/pupbld.sql
connect sys/change_on_install as SYSDBA
ALTER SESSION SET CONTAINER = ${pdb};
\@${oracle_home}/rdbms/admin/utlrp.sql
ALTER SESSION SET CONTAINER = ${pdb};
GRANT SELECT, INSERT, DELETE, UPDATE ON plan_table TO public;
GRANT plustrace TO public;

alter profile default limit password_life_time unlimited;
show con_name


REM ********** TABLESPACES FOR TABLES **********
CREATE TABLESPACE PP_DATA_128K DATAFILE '${oradata_path}\\${pdb}\\pp_data_128k_01.dbf' SIZE ${small_tbs_size} REUSE
AUTOEXTEND ON NEXT ${small_autoext_size}
EXTENT MANAGEMENT LOCAL UNIFORM SIZE ${small_ext_size};

CREATE TABLESPACE PP_DATA_1M DATAFILE '${oradata_path}\\${pdb}\\pp_data_1m_01.dbf' SIZE ${medium_tbs_size} REUSE
AUTOEXTEND ON NEXT ${medium_autoext_size}
EXTENT MANAGEMENT LOCAL UNIFORM SIZE ${medium_ext_size};

CREATE TABLESPACE PP_DATA_10M DATAFILE '${oradata_path}\\${pdb}\\pp_data_10m_01.dbf' SIZE ${large_tbs_size} REUSE
AUTOEXTEND ON NEXT ${large_autoext_size}
EXTENT MANAGEMENT LOCAL UNIFORM SIZE ${large_ext_size};

REM ********** TABLESPACES FOR INDEXES **********
CREATE TABLESPACE PP_INDEX_128K DATAFILE '${oradata_path}\\${pdb}\\pp_index_128k_01.dbf' SIZE ${small_tbs_size} REUSE
AUTOEXTEND ON NEXT ${small_autoext_size}
EXTENT MANAGEMENT LOCAL UNIFORM SIZE ${small_ext_size};

CREATE TABLESPACE PP_INDEX_1M DATAFILE '${oradata_path}\\${pdb}\\pp_index_1m_01.dbf' SIZE ${medium_tbs_size} REUSE
AUTOEXTEND ON NEXT ${medium_autoext_size}
EXTENT MANAGEMENT LOCAL UNIFORM SIZE ${medium_ext_size};

CREATE TABLESPACE PP_INDEX_10M DATAFILE '${oradata_path}\\${pdb}\\pp_index_10m_01.dbf' SIZE ${large_tbs_size} REUSE
AUTOEXTEND ON NEXT ${large_autoext_size}
EXTENT MANAGEMENT LOCAL UNIFORM SIZE ${large_ext_size};

REM ********** TABLESPACE FOR AQ TABLES **********
CREATE TABLESPACE AQ_DATA DATAFILE '${oradata_path}\\${pdb}\\aq01.dbf' SIZE ${small_tbs_size} REUSE
AUTOEXTEND ON NEXT ${small_autoext_size}
EXTENT MANAGEMENT LOCAL UNIFORM SIZE ${small_ext_size};

REM ********** TABLESPACE FOR STATSPACK **********
CREATE TABLESPACE PERFSTAT_DATA DATAFILE '${oradata_path}\\${pdb}\\perfstat_data_01.dbf' SIZE ${small_tbs_size} REUSE
AUTOEXTEND ON NEXT ${small_autoext_size}
EXTENT MANAGEMENT LOCAL AUTOALLOCATE;

spool off
exit
EOF
close(OUT_FILE);
close(LOG_FILE);


