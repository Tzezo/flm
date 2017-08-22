package FLM::Common::DBIHelper;
use strict;

=pod
=head1 NAME

FLM::Common::DBIHelper

=head2 DESCRIPTION

Provides some helper functionality for DBI. 
    FLM::Common::DBIHelper->connect($params); #DBI PG connection without transactions
    FLM::Common::DBIHelper->connect_transact($params); #DBI PG connection with transactions with default DBI isolation level SERIALIZABLE
    $dbi->InsertInto($table_name, {col => $val}); #Generate and execute Insert query from hashref. Returns inserted row as hashref.

=cut

use DBI;
use FLM::Common::Errors; 

sub connect($$)
{
    my($class, $params) = @_;
    
    my $conn = DBI->connect(
        "dbi:Pg:dbname=$$params{ dbname };host=$$params{ host };port=$$params{ port };", 
         $$params{ user }, 
         $$params{ pass }
    );

    $conn->{RaiseError} = 1;    
    
    my $self = $conn;

    bless $self, 'FLM::Common::DBIHelper::db'; 

    return $self;    
}

sub connect_transact($$)
{
    my($class, $params) = @_;
    
    my $conn = $class->connect($params);

    $conn->{AutoCommit} = 0;
    
    return $conn;
} 


package FLM::Common::DBIHelper::db;
use strict;

use base qw(DBI::db);

use FLM::Common::Errors; 

sub InsertInto($$$)
{
    my($self, $table, $data) = @_;

    ASSERT(defined $self, "Undefined self", "SYS20");
    ASSERT(defined $table, "Undefined table", "SYS21");
    ASSERT(defined $data, "Undefined data", "SYS22");

    $table = $self->quote_identifier( $table );

    my $cols = [];
    my $vals = [];

    while(my($key, $val) = each(%$data))
    {
        push(@$cols, $self->quote_identifier( $key ));
        push(@$vals, $self->quote( $val ));
    }
    
    my $cols_str = join ", ", @$cols;
    my $vals_str = join ", ", @$vals;

    my $query = "INSERT INTO $table ($cols_str) VALUES ($vals_str) RETURNING *";
    
    my $sth = $self->prepare($query) or die "$!";
    $sth->execute();

    ASSERT($sth->rows == 1, "Insert error", "SYS50");

    my $row = $sth->fetchrow_hashref;    

    TRACE("Rowsss ", $sth->rows, $row, $query);
    return $row;
}

1;
