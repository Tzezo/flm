package FLM::Config;
use strict;

use vars qw($dbi_dbUser $dbi_dbAuth $dbi_dbName $dbi_dbHost $dbi_dbPort $FILES_DIR $FORBIDDEN_FILE_EXT $MAX_FILE_SIZE $MAX_UPLOADED_FILES);

BEGIN
{
    use Exporter;
    use vars       qw($VERSION @ISA @EXPORT);

    $VERSION     = 1.02;
    @ISA = qw(Exporter);

    @EXPORT = qw($dbi_dbUser $dbi_dbAuth $dbi_dbName $dbi_dbHost $dbi_dbPort $FILES_DIR $FORBIDDEN_FILE_EXT $MAX_FILE_SIZE $MAX_UPLOADED_FILES);
    
    $dbi_dbName = "pgpool";
    $dbi_dbHost = "localhost";
    $dbi_dbUser = "tzezo";
    $dbi_dbAuth = "123";
    $dbi_dbPort = "5432";

    $FILES_DIR = "/var/www/files/";

    $FORBIDDEN_FILE_EXT = [];
    $MAX_FILE_SIZE = 1 * 1024; #Bytes
    $MAX_UPLOADED_FILES = 15; 
}

1;
