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

    $$self{dbh}->{AutoCommit} = 0;
    $$self{dbh}->{RaiseError} = 1;

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

        $$self{dbh}->commit();
    }
    catch
    {
        my($err, $err_data) = @_;

        $$self{dbh}->rollback();

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

    #TODO - get file meta data
   
    ASSERT_PEER(defined $$self{cgi}->param('file'), "File parameter is not defined", "PEER10");
   
    my $files = $$self{cgi}->param('file');
    
    if(ref $files ne "ARRAY")
    {
        $files = [$files];
    }
    
    my $res = [];
    my $upld_files_arr = [];

    for(my $i = 0; $i < @$files; $i++)
    {
        my $file = $$files[ $i ];
        my $file_name = "$$files[ $i ]";
        my $mime_type = $$self{cgi}->uploadInfo($file)->{'Content-Type'};
        my $tmp_file_name = $$self{cgi}->tmpFileName($file);

        my $file_size_b = -s $tmp_file_name;
        ASSERT_USER($file_size_b <= $FLM::Config::MAX_FILE_SIZE, "Reached file size for $file_name, Allowed file size is $FLM::Config::MAX_FILE_SIZE Bytes", "UI02");

        my ($ext) = $file_name =~ /(\.[^.]+)$/;

        my $intern_file_name = "file_".time()."_$$"."_$i".$ext;
        
        my $rows = $self->InsertInto("files", {
            name => $intern_file_name,
            pub_name => $file_name,
            meta_data_json => to_json({
                mime_type => $mime_type,
                file_size_bytes => $file_size_b,
                ext => $ext,
            }),
        });

        ASSERT_USER($rows == 1, "Upload failed", "UI01");

        push @$upld_files_arr, {
            tmp_file_path => $tmp_file_name,
            intern_file_name => $intern_file_name
        };
        
        push @$res, {
            file_name => $file_name,
            mime_type => $mime_type,
            tmp_file_name => $tmp_file_name
        };
    }
 
    for(my $i = 0; $i < @$upld_files_arr; $i++)
    {
        move($$upld_files_arr[ $i ]{ tmp_file_path }, "$FLM::Config::FILES_DIR/$$upld_files_arr[ $i ]{ intern_file_name }");
    }

    return $res;
}

sub CheckFileSize($$)
{
    my ($self, $file) = @_;

    ASSERT(defined $file, "Undefined file", "SYS23");

    my $file_info = stat($file);

    TRACE("File info ", $file_info);
}

#RESP
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
    
    #if(ref $result eq "HASH"
    #    || ref $result eq "ARRAY")
    #{
    #    $result = to_json($result);
    #}
 
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

#DB
sub InsertInto($$$)
{
    my($self, $table, $data) = @_;

    ASSERT(defined $self, "Undefined self", "SYS20");
    ASSERT(defined $table, "Undefined table", "SYS21");
    ASSERT(defined $data, "Undefined data", "SYS22");

    $table = $$self{dbh}->quote_identifier( $table );

    my $cols = [];
    my $vals = [];

    while(my($key, $val) = each(%$data))
    {
        push(@$cols, $$self{dbh}->quote_identifier( $key ));
        push(@$vals, $$self{dbh}->quote( $val ));
    }
    
    my $cols_str = join ", ", @$cols;
    my $vals_str = join ", ", @$vals;

    my $query = "INSERT INTO $table ($cols_str) VALUES ($vals_str)";   
    
    my $rows = $$self{dbh}->do($query) or die "$!";
    TRACE("Rowsss ", $rows, $query);
    return $rows;
}

1;
