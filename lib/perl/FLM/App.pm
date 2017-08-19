package FLM::App;
use strict;

use FLM::Config;
use FLM::Common::Errors;
use CGI;
use DBI;
use File::Copy;
use File::Type;
use MIME::Types;
use Try::Tiny;
use JSON;

our $commands = {
    upload_file => { proc => \&UploadFile, resp_type => 'json'},
    get_files_list => { proc => \&GetFilesList, resp_type => 'json'},
    download_file => { proc => \&DownloadFile },
    delete_file => { proc => \&DeleteFile, resp_type => "json" },
};

sub new($)
{
    my($class) = @_;

    my $self = {
        cgi => new CGI(),
        dbh => DBI->connect("dbi:Pg:dbname=$FLM::Config::dbi_dbName;host=$FLM::Config::dbi_dbHost;port=$FLM::Config::dbi_dbPort;", $FLM::Config::dbi_dbUser, $FLM::Config::Auth),
        mt  => MIME::Types->new(),
        ft  => File::Type->new(),
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

        $$self{forbid_file_types} = defined $$self{forbid_file_types} ? $$self{forbid_file_types} : $self->GetForbidFileTypes();
        
        my $method = $$self{cgi}->param('method');
        ASSERT(defined $method, "method is undefined", "SYS01");
        ASSERT_PEER(defined $$commands{ $method }, "Method not found", "PEER01"); 

        my $command = $$commands{ $method };

        print CGI::header("-charset" => 'utf8');

        my $resp_type = "";

        if(defined $$command{ resp_type })
        {
            if($$command{ resp_type } eq "json")
            {
                $resp_type = $$command{ resp_type };
                print CGI::header("-type" => "application/json"); 
            }
        }

        my $resp = $$command{ proc }->($self);
       
        if($resp_type eq "json")
        {
            $resp = $self->GetSuccessRespObj($resp);
            print to_json($resp);
        }
        else
        {
            print $resp;
        }

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

sub GetFilesList($)
{
    my($self) = @_;

    ASSERT(defined $self, "Undefined self", "SYS31");
    
    my $sth = $$self{dbh}->prepare("
        SELECT *
        FROM files
        WHERE is_deleted IS FALSE
        ORDER BY inserted_at DESC
    ");

    $sth->execute();

    my $data = [];

    while(my $row = $sth->fetchrow_hashref)
    {
        my $file_hash = {
            name => $$row{ pub_name },
            meta_data => from_json($$row{ meta_data_json }),
            inserted_at => $$row{ inserted_at },
            id => $$row{ id }
        };

        push @$data, $file_hash;
    }

    return $data;
}

sub DownloadFile($)
{
    my($self) = @_;

    ASSERT(defined $self, "Undefined self", "SYS32");

    my $file_id = $$self{cgi}->param('file_id');

    ASSERT_PEER(defined $file_id, "Missing param file_id", "PEER12");

    my $sth = $$self{dbh}->prepare("
        SELECT F.*
        FROM files F
        WHERE F.id=?
            AND F.is_deleted IS FALSE
    ");

    $sth->execute($file_id);

    ASSERT_USER($sth->rows == 1, "File does not exists", "UI30");

    my $row = $sth->fetchrow_hashref;
    my $meta_data = from_json($$row{ meta_data_json });

    my $mime_type = "application/octet-stream";

    if(defined $$meta_data{ mime_type })
    {
        $mime_type = $$meta_data{ mime_type };
    }

    print CGI::header("-type" => $mime_type,
                        "-attachment" => "$$row{ pub_name }");

    open FILE, "$FLM::Config::FILES_DIR/$$row{ name }" or die "Can't open file $$row{ name }, $!";
    my ($file, $buff);
    while(read FILE, $buff, 1024) {
        $file .= $buff;
    }
    close FILE;

    return $file;
}

sub DeleteFile($)
{
    my($self) = @_;

    #TODO - return file info hash

    ASSERT(defined $self, "Undefined self", "SYS32");

    my $file_id = $$self{cgi}->param('file_id');

    ASSERT_PEER(defined $file_id, "Missing param file_id", "PEER13");

    my $rows = $$self{dbh}->do("
        UPDATE files
        SET is_deleted=TRUE
        WHERE id=?
            AND is_deleted IS FALSE
    ", undef, $file_id);

    ASSERT_USER($rows == 1, "File does not exists", "UI30");

    return {}; 
}

sub UploadFile($)
{
    my($self) = @_;

    #TODO - Rename pub file name if already exists
    #TODO - Add uuid for files as pub id
    #TODO - Max Number of uploaded files
     
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
        my $tmp_file_name = $$self{cgi}->tmpFileName($file);

        my @file_stat = stat($tmp_file_name);

        my $file_size_b = $file_stat[7];

        ASSERT_USER($file_size_b <= $FLM::Config::MAX_FILE_SIZE, "Reached file size for $file_name, Allowed file size is $FLM::Config::MAX_FILE_SIZE Bytes", "UI02");

        my $file_type = $$self{ft}->checktype_filename($tmp_file_name);
        my $mime_type = $$self{mt}->type($file_type);
        $mime_type = defined $mime_type ? "$mime_type" : "$file_type";

        ASSERT_USER(!defined $$self{forbid_file_types}{ $mime_type }, "File type is not allowed!", "UI03");

        my ($ext) = $file_name =~ /(\.[^.]+)$/;

        my $intern_file_name = "file_".time()."_$$"."_$i".$ext;
        
        my $rows = $self->InsertInto("files", {
            name => $intern_file_name,
            pub_name => $file_name,
            meta_data_json => to_json({
                mime_type => $mime_type,
                file_size_bytes => $file_size_b,
                file_atime => $file_stat[8],
                file_mtime => $file_stat[9],
                file_ctime => $file_stat[10],
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

sub GetForbidFileTypes($)
{
    my($self) = @_;
    
    ASSERT(defined $self, "Undefined self", "SYS40");
    
    my $forbid_file_types_arr = $FLM::Config::FORBIDDEN_FILE_EXT;  
    my $forbid_file_types_hash = {};
    
    for(my $i = 0; $i < @$forbid_file_types_arr; $i++)
    {
        my $mime_type = $$self{mt}->mimeTypeOf($$forbid_file_types_arr[ $i ]);

        if(defined $mime_type)
        {
            $$forbid_file_types_hash{ $mime_type } = 1;
        }
    }

    return $forbid_file_types_hash;
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
