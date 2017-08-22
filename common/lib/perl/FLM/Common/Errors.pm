package FLM::Common::Errors;
use strict;

=pod
=head1 NAME

FLM::Common::Errors

=head2 SYNOPSIS
    
    ASSERT($cond, "Message", "Code");
    ASSERT_PEER($cond, "Message", "Code");
    ASSERT_USER($cond, "Message", "Code");
    TRACE("Param", $hashref, $arrref, $string); #Print on STDERR all passed params, accepts list of params. Uses Data::Dumper so there is no problem to pass ARRAYREF or HASHREF as parameters.     

=head2 DESCRIPTION

Provides three types of exceptions and one trace function. Exceptions methods works like asserts i.e. accepts as a parameter some condition if condition is false, throws a exception.
The exceptions are three types:
    SYSERR - in most cases means temporary error
    PEERERR - protocol error or invalid params, this exception type must be used for validating API input params.
    USERERR - end user error for example "Reached max file size"
   
All methods in this module are static.

=cut

use Data::Dumper;

sub TRACE(@);
sub ASSERT($$$;@);
sub ASSERT_PEER($$$;@);
sub ASSERT_USER($$$;@);

sub BEGIN
{
    use Exporter;
    use vars       qw($VERSION @ISA @EXPORT);
    $VERSION = 0.10;
    @ISA = qw(Exporter);
    @EXPORT = qw(&TRACE &ASSERT &ASSERT_USER &ASSERT_PEER);
}

sub ASSERT($$$;@)
{
    my($cond, $msg, $code, @adit_params) = @_;

    if(!$cond)
    {
        TRACE("ASSERT FAILED", "msg: $msg", "code: $code", "type: SYSERR", "STACK: ", get_stack());
        die ({
            msg => $msg, 
            code => $code,
            type => "SYSERR"
        });
        #die "INTERR; $code; $msg";
    }
}

sub ASSERT_PEER($$$;@)
{
    my($cond, $msg, $code, @adit_params) = @_;
    
    if(!$cond)
    {
        TRACE("ASSERT_PEER FAILED", "msg: $msg", "code: $code", "type: PEERERR", "STACK: ", get_stack());
        die ({
            msg => $msg,
            code => $code,
            type => "PEERERR",    
        });
    }
}

sub ASSERT_USER($$$;@)
{
    my($cond, $msg, $code, @adit_params) = @_;

    if(!$cond)
    {
        TRACE("ASSERT_USER FAILED", "msg: $msg", "code: $code", "type: USERERR", "STACK: ", get_stack());
        die ({
            msg => $msg,
            code => $code,
            type => "USERERR",
        });
    }
}

sub TRACE(@)
{
    my $trace_enabled = 1;

    if(defined $FLM::Config::TRACE_ENABLED)
    {
        $trace_enabled = $FLM::Config::TRACE_ENABLED;
    }    

    if($trace_enabled)
    {
        print STDERR "TRACE----->\n";
        print STDERR Dumper @_;
        print STDERR "END TRACE<------\n";
    }
}

sub get_stack()
{
    my $stack ;
    for(my $i=1; my @call = caller($i); $i++)
    {
        $stack .= $call[1] . " $call[0]  ($call[2])\n";
    }
    return $stack;
}

1;
