package FLM::Handler;
use strict;

use CGI;
use Data::Dumper;

sub new($)
{
    my($class) = @_;

    print CGI::header();
    print "Hello world";

    my $self = {};

    bless $self, $class;
    return $self;
}

1; 
