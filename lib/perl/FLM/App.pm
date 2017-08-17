package FLM::App;
use strict;

use FLM::Config;
use FLM::Common::Errors;
use CGI;
use DBI;
use File::Copy;
use Try::Tiny;
use JSON;

our $commands = {
    upload_file => { proc => \&UploadFile, resp_type => 'json'}
};

sub new($)
{
    my($class) = @_;

    my $self = {
        cgi => new CGI(),
        dbh => DBI->connect("dbi:Pg:dbname=$FLM::Config::dbi_dbName;host=$FLM::Config::dbi_dbHost;port=$FLM::Config::dbi_dbPort;", $FLM::Config::dbi_dbUser, $FLM::Config::Auth),
    };

    bless $self, $class;
    return $self; 
}

sub Handler($)
{
    my($self) = @_;

    try
    {
        TRACE($$self{cgi}); 
        
        my $method = $$self{cgi}->param('method');
        ASSERT(defined $method, "method is undefined", "SYS01");
        ASSERT_PEER(defined $$commands{ $method }, "Method not found", "PEER01"); 

        my $command = $$commands{ $method };

        print CGI::header("-charset" => 'utf8');

        if(defined $$command{ resp_type })
        {
            if($$command{ resp_type } eq "json")
            {
                print CGI::header("-type" => "application/json"); 
            }
        }

        my $resp = $$command{ proc }->($self);
        $resp = $self->GetSuccessRespObj($resp);
        print to_json($resp);
    }
    catch
    {
        my($err, $err_data) = @_;

        TRACE("BOOM ", $err, $err_data);

        my $resp = undef;
    
        if(defined $err && ref $err eq "HASH" && defined $$err{type})
        {
            if($$err{type} eq "SYSERR")
            {
                $resp = $self->GetErrorRespObj("sys_err", {code => "SYS000", msg => "Something went wrong, please try again!"});
            }
            elsif($$err{type} eq "PEERERR")
            {
                $resp = $self->GetErrorRespObj("peer_err", {code => $$err{code}, msg => "Client system error!"});
            }
            elsif($$err{type} eq "USERERR")
            {
                $resp = $self->GetErrorRespObj("user_err", {code => $$err{code}, msg => $$err{msg}});
            }
        }
        else
        {
            $resp = $self->GetErrorRespObj("sys_err", {code => "SYS000", msg => "Something went wrong, please try again!"});
        }

        if(defined $resp)
        {
            print CGI::header("-type" => "application/json");
            print to_json($resp);
        }
        else
        {
            die;
        }
    };
}

sub UploadFile($)
{
    my($self) = @_;

    ASSERT_PEER(defined $$self{cgi}->param('file'), "File parameter is not defined", "PEER10");

    return "Upload file Handler";
    #print "Upload File Handler";
}

sub GetErrorRespObj($$$)
{
    my($self, $status, $adit_data) = @_;
    
    ASSERT(defined $self, "Undefined self", "SYS04");
    ASSERT(defined $status, "Undefined status", "SYS05");
    ASSERT(defined $adit_data, "Undefined adit_data", "SYS06");
    ASSERT(defined $$adit_data{ code }, "Undefined adit_data{ code }", "SYS07");
    ASSERT(defined $$adit_data{ msg }, "Undefined adit_data{ msg }", "SYS08");

    ASSERT($status eq "sys_err" ||
            $status eq "peer_err" ||
            $status eq "user_err", "Invalid status", "SYS09");

    return $self->GetRespObj($status, $adit_data);
}

sub GetSuccessRespObj($$)
{
    my($self, $result) = @_;

    ASSERT(defined $self, "Undefined self", "SYS10");
    ASSERT(defined $result, "Undefined result", "SYS12");
    
    return $self->GetRespObj("ok", { result => $result });
}

sub GetRespObj($$;$)
{
    my($self, $status, $adit_data) = @_;

    my $resp = {
        status => {
            status => $status,
        },
    };

    if(defined $$adit_data{result})
    {
        $$resp{result} = $$adit_data{result};
    }

    if(defined $$adit_data{code})
    {
        $$resp{status}{code} = $$adit_data{code};
    }

    if(defined $$adit_data{msg})
    {
        $$resp{status}{msg} = $$adit_data{msg};
    }

    return $resp;
}

1;
