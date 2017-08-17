package FLM::Config;
use strict;

use vars qw($dbi_dbUser $dbi_dbAuth $dbi_dbName $dbi_dbHost $dbi_dbPort);

BEGIN
{
    use Exporter;
    use vars       qw($VERSION @ISA @EXPORT);

    $VERSION     = 1.02;
    @ISA = qw(Exporter);

    @EXPORT = qw($dbi_dbUser $dbi_dbAuth $dbi_dbName $dbi_dbHost $dbi_dbPort);
    
    $dbi_dbName = "pgpool";
    $dbi_dbHost = "localhost";
    $dbi_dbUser = "tzezo";
    $dbi_dbAuth = "123";
    $dbi_dbPort = "5432";
}

1;
