# Set environment:
#------------------
#!C:\MKSNT/perl.exe

use File::Path;
use File::Copy;

# Get command arguments:
# first argument: Oracle Base - directory under which Database admin and oradata directories will be installed
# second argument: Oracle Home - directory under which Oracle RDBMS software is installed    
# third argument: Oracle SID - name of the database instance that will be created 
# fourth argument: Oradata path - the path to create database files


local $oracle_base = shift(@ARGV);
local $oracle_home = shift(@ARGV);
local $sid = shift(@ARGV);
local $oradata_path = shift(@ARGV);


# Create OFA-compliant directory for database files
$oradata_path = "${oracle_base}/oradata/${sid}" unless defined ($oradata_path);
mkpath ("${oradata_path}");

local $admin_path = "${oracle_base}\\admin\\${sid}";
local $credb_path = "${admin_path}\\create";

$ENV {'ORACLE_SID'} = "${sid}";

$ENV{'CATCDB_SYS_PASSWD'}      = "change_on_install";
$ENV{'CATCDB_SYSTEM_PASSWD'}   = "manager";
$ENV{'CATCDB_TEMPTS'}          = "TEMP";

@command_args = ("${oracle_home}\\bin\\oradim","-new","-sid","${sid}","-intpwd","change_on_install","-startmode","auto","-pfile","${admin_path}\\pfile\\init.ora");
    system(@command_args) == 0
         or die "system @command_args failed: $?";

@command_args = ("${oracle_home}\\bin\\sqlplus","/nolog","\@${credb_path}\\${sid}run.sql");
    system(@command_args) == 0
         or die "system @command_args failed: $?";

@command_args = ("${oracle_home}\\bin\\sqlplus","/nolog","\@${credb_path}\\${sid}run1.sql");
    system(@command_args) == 0
         or die "system @command_args failed: $?";

@command_args = ("${oracle_home}\\bin\\oradim","-edit","-sid","${sid}","-startmode","auto");
    system(@command_args) == 0
         or die "system @command_args failed: $?";

@command_args = ("${oracle_home}\\bin\\lsnrctl","start");
    system(@command_args) == 0
         or die "system @command_args failed: $?";

$_ = `sc query |find "TNS" | find "SERVICE"`;

my @abc = split(/\s+/);

@command_args = ("C:\\Windows\\System32\\sc.exe ","config ",$abc[1]," start= AUTO");
   system(@command_args) == 0
       or die "@command_args failed: $?";



