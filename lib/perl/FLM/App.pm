package FLM::App;
use strict;

use FLM::Config;
use FLM::Common::Errors;
use CGI;
use FLM::Common::DBIHelper;
use File::Copy;
use File::Type;
use MIME::Types;
use Try::Tiny;
use JSON;

our $commands = {
    upload_file => { proc => \&UploadFile, resp_type => 'json'},
    get_files_list => { proc => \&GetFilesList, resp_type => 'json'},
    get_file_data => { proc => \&GetFileData, resp_type => 'json'},
    delete_file => { proc => \&DeleteFile, resp_type => "json" },
    download_file => { proc => \&DownloadFile },
};

sub new($)
{
    my($class) = @_;

    my $self = {
        cgi => new CGI(),
        dbh => FLM::Common::DBIHelper->connect_transact({
            dbname => $FLM::Config::dbi_dbName,
            host => $FLM::Config::dbi_dbHost,
            port => $FLM::Config::dbi_dbPort,
            user => $FLM::Config::dbi_dbUser,
            pass => $FLM::Config::Auth
        }),
        mt  => MIME::Types->new(),
        ft  => File::Type->new(),
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

        $$self{forbid_file_types} = defined $$self{forbid_file_types} ? $$self{forbid_file_types} : $self->_GetForbidFileTypes();
        
        my $method = $$self{cgi}->param('method');
        ASSERT_PEER(defined $method, "method is undefined", "PEER03");
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
            $resp = $self->_GetSuccessRespObj($resp);
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
    
        if(defined $err 
            && ref $err eq "HASH" 
            && defined $$err{type})
        {
            if($$err{type} eq "SYSERR")
            {
                $resp = $self->_GetErrorRespObj("sys_err", {code => "SYS000", msg => "Something went wrong, please try again!"});
            }
            elsif($$err{type} eq "PEERERR")
            {
                $resp = $self->_GetErrorRespObj("peer_err", {code => $$err{code}, msg => "Client system error!"});
            }
            elsif($$err{type} eq "USERERR")
            {
                $resp = $self->_GetErrorRespObj("user_err", {code => $$err{code}, msg => $$err{msg}});
            }
        }
        else
        {
            $resp = $self->_GetErrorRespObj("sys_err", {code => "SYS000", msg => "Something went wrong, please try again!"});
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

sub GetFileData($)
{
    my($self) = @_;

    ASSERT(defined $self, "Undefined self", "SYS32");
    
    my $file_id = $$self{cgi}->param('file_id');
    ASSERT_PEER(defined $file_id, "Missing param file_id", "PEER13");
    
    my $sth = $$self{dbh}->prepare("
        SELECT F.*,
                inserted_at::timestamp(0) AS inserted_at
        FROM files F
        WHERE F.id=?
            AND F.is_deleted IS FALSE
    ");
    
    $sth->execute($file_id);

    ASSERT_USER($sth->rows == 1, "File does not exists!", "UI41");
    
    my $row = $sth->fetchrow_hashref();

    return $self->_GetFileObj($row);
}

sub GetFilesList($)
{
    my($self) = @_;

    ASSERT(defined $self, "Undefined self", "SYS31");
    
    my $sth = $$self{dbh}->prepare("
        SELECT *,
                inserted_at::timestamp(0) AS inserted_at
        FROM files
        WHERE is_deleted IS FALSE
        ORDER BY id
    ");

    $sth->execute();

    my $data = [];

    while(my $row = $sth->fetchrow_hashref)
    {
        push @$data, $self->_GetFileObj($row);
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

    ASSERT(defined $self, "Undefined self", "SYS32");

    my $file_id = $$self{cgi}->param('file_id');

    ASSERT_PEER(defined $file_id, "Missing param file_id", "PEER13");

    my $sth = $$self{dbh}->prepare("
        UPDATE files
        SET is_deleted=TRUE
        WHERE id=?
            AND is_deleted IS FALSE
        RETURNING *
    ");

    $sth->execute($file_id);

    ASSERT_USER($sth->rows == 1, "File does not exists", "UI30");

    my $row = $sth->fetchrow_hashref;

    return $self->_GetFileObj($row); 
}

sub UploadFile($)
{
    my($self) = @_;

    #TODO - Add uuid for files as pub id
     
    ASSERT_PEER(defined $$self{cgi}->param('file'), "File parameter is not defined", "PEER10");
   
    my $files = $$self{cgi}->param('file');
    
    if(ref $files ne "ARRAY")
    {
        $files = [$files];
    }
  
    $self->_CheckUploadedFilesNumber( scalar @$files );
  
    my $res = [];
    my $upld_files_arr = [];

    for(my $i = 0; $i < @$files; $i++)
    {
        my $file = $$files[ $i ];
        my $file_name = "$$files[ $i ]";
        my $tmp_file_name = $$self{cgi}->tmpFileName($file);
            
        ASSERT(-e $tmp_file_name, "File does not exists", "SYS61");
        my @file_stat = stat($tmp_file_name);

        $self->_CheckUploadedFileSize($tmp_file_name, $file_name);
 
        my $mime_type = $self->_GetFileMimeType($tmp_file_name);
  
        my ($ext) = $file_name =~ /(\.[^.]+)$/;

        ASSERT_USER(!defined $$self{forbid_file_types}{ $mime_type }
                     && !defined $$self{forbid_file_types}{ $ext }, "File type is not allowed!", "UI03");

        my $intern_file_name = "file_".time()."_$$"."_$i".$ext;
        
        my $row = $$self{dbh}->InsertInto("files", {
            name => $intern_file_name,
            orig_name => $file_name,
            pub_name => $self->_GetFilePubName($file_name),
            meta_data_json => to_json({
                mime_type => $mime_type,
                file_size_bytes => $file_stat[7],
                file_atime => $file_stat[8],
                file_mtime => $file_stat[9],
                file_ctime => $file_stat[10],
                ext => $ext,
            }),
        });

        TRACE("FileRow ", $row);
        push @$upld_files_arr, {
            tmp_file_path => $tmp_file_name,
            intern_file_name => $intern_file_name
        };
        
        push @$res, $self->_GetFileObj($row);
    }
 
    for(my $i = 0; $i < @$upld_files_arr; $i++)
    {
        $self->_MoveFile($$upld_files_arr[ $i ]{ tmp_file_path }, "$FLM::Config::FILES_DIR/$$upld_files_arr[ $i ]{ intern_file_name }");
    }

    return $res;
}

sub _MoveFile($$$)
{
    my($self, $file_path_from, $file_path_to) = @_;

    ASSERT(defined $file_path_from, "Undefined file_path_from parameter", "SYS70");
    ASSERT(defined $file_path_to, "Undefined file_path_to parameter", "SYS71");

    move($file_path_from, $file_path_to);

    return 1;
}

sub _GetFilePubName($$)
{
    my($self, $file_orig_name) = @_;

    ASSERT(defined $file_orig_name, "Undefined file_orig_name", "SYS58");

    my $sth = $$self{dbh}->prepare("
        SELECT COUNT(id) AS count
        FROM files
        WHERE orig_name = ?
    ");

    $sth->execute($file_orig_name);

    my $row = $sth->fetchrow_hashref;

    if($$row{ count } > 0)
    {
        my @arr = split(/\./, $file_orig_name);
        
        $file_orig_name = "$arr[0] ($$row{ count }).".join('.', @arr[ 1 .. $#arr ]);  
        return $file_orig_name;
    }

    return $file_orig_name;
}

sub _CheckUploadedFilesNumber($$)
{
    my($self, $new_files_num) = @_;

    ASSERT(defined $new_files_num, "Undefined new_files_num parameter", "SYS55");

    my $sth = $$self{dbh}->prepare("
        SELECT COUNT(F.id) + ? AS files_count
        FROM files F
        WHERE F.is_deleted IS FALSE
    "); 

    $sth->execute( $new_files_num );

    my $row = $sth->fetchrow_hashref;

    ASSERT_USER($$row{files_count} <= $FLM::Config::MAX_UPLOADED_FILES, "Maximum number of uploaded files is $FLM::Config::MAX_UPLOADED_FILES", "UI05");
   
    return 1; 
}

sub _CheckUploadedFileSize($$$)
{
    my($self, $file_path, $file_name) = @_;

    ASSERT(defined $file_path, "Undefined file_path parameter", "SYS56");
    ASSERT(defined $file_name, "Undefined file_name parameter", "SYS57");

    my @file_stat = stat($file_path);
    my $file_size_b = $file_stat[7];
    
    ASSERT_USER($file_size_b <= $FLM::Config::MAX_FILE_SIZE, "Reached file size for $file_name, Allowed file size is $FLM::Config::MAX_FILE_SIZE Bytes", "UI02");
    
    return 1;
}

sub _GetFileMimeType($$)
{
    my($self, $file_path) = @_;

    ASSERT(defined $file_path, "Undefined file_path parameter", "SYS58");

    my $file_type = $$self{ft}->checktype_filename($file_path);
    my $mime_type = $$self{mt}->type($file_type);
    $mime_type = defined $mime_type ? "$mime_type" : "$file_type";

    return $mime_type;
}

sub _GetForbidFileTypes($)
{
    my($self) = @_;
    
    my $forbid_file_types_arr = $FLM::Config::FORBIDDEN_FILE_EXT;  
    my $forbid_file_types_hash = {};
    
    for(my $i = 0; $i < @$forbid_file_types_arr; $i++)
    {
        my $mime_type = $$self{mt}->mimeTypeOf($$forbid_file_types_arr[ $i ]);

        if(defined $mime_type)
        {
            $$forbid_file_types_hash{ $mime_type } = 1;
        }
        
        $$forbid_file_types_hash{ $$forbid_file_types_arr[ $i ] } = 1;
    }

    return $forbid_file_types_hash;
}

sub _GetFileObj($$)
{
    my($self, $file_row) = @_;

    ASSERT(defined $file_row, "Undefined file_row", "SYS53");

    ASSERT(defined $$file_row{ id }, "Missing file id", "SYS54");
    ASSERT(defined $$file_row{ pub_name }, "Missing file pub name", "SYS55");
    ASSERT(defined $$file_row{ meta_data_json }, "Missing file meta data json", "SYS56");
    ASSERT(defined $$file_row{ inserted_at }, "Missing file inserted_at", "SYS57");

    my $file_hash = {
        id => $$file_row{ id },
        name => $$file_row{ pub_name },
        meta_data => from_json($$file_row{ meta_data_json }),
        inserted_at => $$file_row{ inserted_at }
    };

    return $file_hash;
}

#RESP
sub _GetErrorRespObj($$$)
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

    return $self->_GetRespObj($status, $adit_data);
}

sub _GetSuccessRespObj($$)
{
    my($self, $result) = @_;

    ASSERT(defined $self, "Undefined self", "SYS10");
    ASSERT(defined $result, "Undefined result", "SYS12");
    
    return $self->_GetRespObj("ok", { result => $result });
}

sub _GetRespObj($$;$)
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
