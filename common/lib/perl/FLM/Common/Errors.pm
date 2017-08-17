package FLM::Common::Errors;
use strict;

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
    print STDERR "TRACE----->\n";
    print STDERR Dumper @_;
    print STDERR "END TRACE<------\n";
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
