use strict;
use warnings;

use lib qw{../lib/perl ../common/lib/perl};
use Test::More; 
use Test::Exception;
use Test::MockObject::Extends;
use Test::MockModule;

use Data::Dumper;

require_ok( 'FLM::App' );

my $fetchrow_hashref_arr = [{}];
my $params_hash = {};
my $tmp_file_name = "";
my $returned_rows = 1;
my $mock_sth;
my $mock_dbh;
my $mock_cgi;
my $app;

sub teardown()
{
    $returned_rows = 1;
    $mock_sth = Test::MockObject->new();
    $mock_sth->mock( 'rows',
                sub { 
                        my $rows = \$returned_rows;
                        return $$rows 
                    } 
                 );

    $mock_sth->mock( 'fetchrow_hashref',
                sub { 
                        return pop @$fetchrow_hashref_arr;
                    } 
                );

    $mock_sth->mock( 'execute',
                    sub { return 1 } );

    $mock_dbh = Test::MockObject->new();
    $mock_dbh->mock( 'prepare', 
                    sub { return $mock_sth }
                    );

    $mock_dbh->mock( 'InsertInto',
                    sub { 
                            print STDERR "TESTTTTTT";
                            print STDERR Dumper $fetchrow_hashref_arr;
                            return pop @$fetchrow_hashref_arr; 
                        }
                    );

    $mock_cgi = Test::MockObject->new();
    $mock_cgi->mock( 'param',
                    sub {
                        return $$params_hash{ $_[1] };
                    } );
    $mock_cgi->mock( 'tmpFileName',
                    sub {
                        my $file_name = \$tmp_file_name;
                        return $$file_name;
                    }
                    );
    

    $app = FLM::App->new();
    $app = Test::MockObject::Extends->new($app);
   
    $app->mock('_MoveFile', 
                sub { return 1; }
                );
 
    $$app{cgi} = $mock_cgi;
    $$app{dbh} = $mock_dbh;
    
    $FLM::Config::FORBIDDEN_FILE_EXT = [];
    $FLM::Config::MAX_FILE_SIZE = 5 * 1024 * 1024;
    $FLM::Config::MAX_UPLOADED_FILES = 15;
    $FLM::Config::FILES_DIR = "./files/";

    return 1;
}

teardown();

my $res;

note "_GetRespObj Test";
    $res = $app->_GetRespObj("test_err", {code => "TESTSYS000", msg => "Test error msg"});

    ok(defined $$res{ status }, "Test status object is defined");
    is($$res{ status }{ status }, "test_err", "Test resp status");
    is($$res{ status }{ code }, "TESTSYS000", "Test resp code");
    is($$res{ status }{ msg }, "Test error msg", "Test resp msg");

    $res = $app->_GetRespObj("test_err2", {code => "TESTPEER000"});
    ok(defined $$res{ status }, "Test status object is defined");
    is($$res{ status }{ status }, "test_err2", "Test resp status");
    is($$res{ status }{ code }, "TESTPEER000", "Test resp code");
    ok(!defined $$res{ status }{ msg }, "Test resp msg");
    teardown();

note "_GetErrorRespObj Test";
    dies_ok{ $app->_GetErrorRespObj("test_stauts", {code => "TEST001", msg => "Test msg"}) } 'die test, wrong status';
    dies_ok{ $app->_GetErrorRespObj("peer_err") } 'die test, missing adit_params';
    dies_ok{ $app->_GetErrorRespObj("sys_err", {msg => "Test msg"}) } 'die test, missing code from adit_params';
    dies_ok{ $app->_GetErrorRespObj("sys_err", {code => "SYS01"}) } 'die test, missing msg from adit_params';
    lives_ok{ $app->_GetErrorRespObj("sys_err", {msg => "Test msg", code => "SYS01", extra_param => "TEST"}) } 'lives_ok test, added extra param in adit_params';
    teardown();

note "_GetSuccessRespObj Test";
    dies_ok{ $app->_GetSuccessRespObj() } 'die test, missing result parameter';
    lives_ok{ $app->_GetSuccessRespObj("test") } 'lives_ok test';
    teardown();

note "_GetFilePubName Test";
    dies_ok{ $app->_GetFilePubName() } 'die test, missing file_orig_name parameter';        
    lives_ok{ $app->_GetFilePubName('test.png') } 'lives_ok test, all parameters passed';    
 
    $fetchrow_hashref_arr = [{
        count => 0
    }]; 

    $res = $app->_GetFilePubName("test.png");
    is($res, "test.png", "test returned file name");    
    
    $$fetchrow_hashref_arr[0]{ count } = 5;
    $res = $app->_GetFilePubName('test.png');
    is($res, "test (5).png", "Test renaming");

    $$fetchrow_hashref_arr[0]{ count } = 5;
    $res = $app->_GetFilePubName('test.tar.gz');
    is($res, "test (5).tar.gz", "Test renaming with two dots extention");

    teardown();    

note "_CheckUploadedFilesNumber Test";
    $fetchrow_hashref_arr = [{
        files_count => 1
    }];

    dies_ok{ $app->_CheckUploadedFilesNumber() } 'die test, missing new_files_num parameter';
    lives_ok{ $app->_CheckUploadedFilesNumber(5) } 'lives_ok test, all parameters passed';
    
    $$fetchrow_hashref_arr[0]{ files_count } = 5;
    $FLM::Config::MAX_UPLOADED_FILES = 4;
    dies_ok{ $app->_CheckUploadedFilesNumber(2) } 'die test, Max uploaded files limit reached';
    teardown();    

note "_CheckUploadedFileSize Test";
    dies_ok{ $app->_CheckUploadedFileSize() } 'die test, missing params';
    lives_ok{ $app->_CheckUploadedFileSize('./files/apple.png', 'apple.png') } 'lives_ok test, all parameters passed';

    $FLM::Config::MAX_FILE_SIZE = 50;
    dies_ok{ $app->_CheckUploadedFileSize('./files/apple.png', 'apple.png') } 'die test, Max file size limit reached';
    
    $FLM::Config::MAX_FILE_SIZE = 1000000;
    lives_ok{ $app->_CheckUploadedFileSize('./files/apple.png', 'apple.png') } 'lives_ok test, Max file size limit not reached';
    teardown();

note "_GetFileMimeType Test";
    dies_ok{ $app->_GetFileMimeType() } 'die test, missing parameters';
    lives_ok{ $app->_GetFileMimeType('./files/apple.png') } 'lives_ok test, all parameters passed';

    $res = $app->_GetFileMimeType('./files/apple.png');
    is($res, 'image/png', 'Test png mime type');

    $res = $app->_GetFileMimeType('./files/test.txt');
    is($res, "application/octet-stream", "Test unkonown mime type");

    $res = $app->_GetFileMimeType('./files/test_without_ext');
    is($res, "application/octet-stream", "Test unknown mime type and file without extention");
    
    $res = $app->_GetFileMimeType('unknown_file');
    is($res, '', "Test with non-existent file");    
    teardown();   

note "_GetForbidFileTypes Test";
    $FLM::Config::FORBIDDEN_FILE_EXT = []; 
    $res = $app->_GetForbidFileTypes();
    is(scalar %$res, 0, "Test hash is empty");
    
    $FLM::Config::FORBIDDEN_FILE_EXT = [".png"];
    $res = $app->_GetForbidFileTypes();
    
    ok(defined $$res{'.png'}, "Test file ext is defined");
    ok(defined $$res{'image/png'}, "Test file mime type is defined");

    teardown();    

note "_GetFileObj Test";
    dies_ok{ $app->_GetFileObj() } 'die test, missing parameters';
    dies_ok{ $app->_GetFileObj({id=>1, pub_name => 'test.png'}) } 'die test, missing parameter'; 
   
    $res = $app->_GetFileObj({
        id => 1,
        pub_name => 'file.png',
        meta_data_json => '{"test":"abc"}',
        inserted_at => "2017-01-01 00:00:00"
    });

    ok(defined $$res{id}, 'Test is defined id');
    ok(defined $$res{name}, 'Test is defined name');
    ok(defined $$res{meta_data}, 'Test is defined meta_data');
    ok(defined $$res{meta_data}{test}, "Test is defined meta_data->test");
    ok(defined $$res{inserted_at}, "Test is defined inserted_at");

    teardown();

note "GetFileData Test";
    $params_hash = {};

    dies_ok{ $app->GetFileData() } 'die test, missing parameters';
    
    $$params_hash{ file_id } = 33;
    $fetchrow_hashref_arr = [{
        id => 13,
        name => "file_1503227374_9251_0.png",
        pub_name => "Apple-Logo-Png-Download (1).png",
        orig_name => "Apple-Logo-Png-Download.png",
        inserted_at => "2017-08-20 11:09:34.625098",
        meta_data_json => '{"file_ctime":1503227374,"ext":".png","file_mtime":1503227374,"file_atime":1503227374,"file_size_bytes":929419,"mime_type":"image/png"}',
    }];

    lives_ok{ $app->GetFileData() } 'lives_ok test, passing all prams';
    
    teardown();    

note "GetFilesList Test";
    $params_hash = {};
    
    lives_ok{ $app->GetFilesList() } 'lives_ok test';
    
    $res = $app->GetFilesList();

    is(scalar @$res, 0, "Test return empty list");

    $fetchrow_hashref_arr = [{
        id => 13,
        name => "file_1503227374_9251_0.png",
        pub_name => "Apple-Logo-Png-Download (1).png",
        orig_name => "Apple-Logo-Png-Download.png",
        inserted_at => "2017-08-20 11:09:34.625098",
        meta_data_json => '{"file_ctime":1503227374,"ext":".png","file_mtime":1503227374,"file_atime":1503227374,"file_size_bytes":929419,"mime_type":"image/png"}',
    },
    {
        id => 13,
        name => "file_1503227374_9251_0.png",
        pub_name => "Apple-Logo-Png-Download (1).png",
        orig_name => "Apple-Logo-Png-Download.png",
        inserted_at => "2017-08-20 11:09:34.625098",
        meta_data_json => '{"file_ctime":1503227374,"ext":".png","file_mtime":1503227374,"file_atime":1503227374,"file_size_bytes":929419,"mime_type":"image/png"}',
    }];

    $res = $app->GetFilesList();
    
    is(scalar @$res, 2, "Test return 2 elements in list");


    teardown();

note "DownloadFile Test";
    $params_hash = {};
    dies_ok{ $app->DownloadFile() } 'die test, missing parameters';

    $params_hash = {
        file_id => 33
    };

    $fetchrow_hashref_arr = [{
        id => 13,
        name => "apple.png",
        pub_name => "Apple-Logo-Png-Download (1).png",
        orig_name => "Apple-Logo-Png-Download.png",
        inserted_at => "2017-08-20 11:09:34.625098",
        meta_data_json => '{"file_ctime":1503227374,"ext":".png","file_mtime":1503227374,"file_atime":1503227374,"file_size_bytes":929419,"mime_type":"image/png"}',
    }];    

    $res = $app->DownloadFile();
    
    ok(length $res > 0, 'Test return file');

    $returned_rows = 0;
    dies_ok{ $app->DownloadFile() } 'die test, file not found';
    
    teardown();

note "DeleteFile Test";
    $params_hash = {};
    dies_ok{ $app->DeleteFile() } 'die test, missing parameters';

    $params_hash = {
        file_id => 33
    };
    
    $fetchrow_hashref_arr = [{
        id => 13,
        name => "apple.png",
        pub_name => "Apple-Logo-Png-Download (1).png",
        orig_name => "Apple-Logo-Png-Download.png",
        inserted_at => "2017-08-20 11:09:34.625098",
        meta_data_json => '{"file_ctime":1503227374,"ext":".png","file_mtime":1503227374,"file_atime":1503227374,"file_size_bytes":929419,"mime_type":"image/png"}',
    }];

    lives_ok{ $app->DeleteFile() } 'lives_ok test, passed all parameters';

    $fetchrow_hashref_arr = [{
        id => 13,
        name => "apple.png",
        pub_name => "Apple-Logo-Png-Download (1).png",
        orig_name => "Apple-Logo-Png-Download.png",
        inserted_at => "2017-08-20 11:09:34.625098",
        meta_data_json => '{"file_ctime":1503227374,"ext":".png","file_mtime":1503227374,"file_atime":1503227374,"file_size_bytes":929419,"mime_type":"image/png"}',
    }];
    $returned_rows = 0;   
    dies_ok{ $app->DeleteFile() } 'die test, file not found';

    teardown(); 

note "UploadFile Test";
    $params_hash = {
        file => './files/apple.png'
    };
    $tmp_file_name = './files/apple.png';

    $fetchrow_hashref_arr = [
    {
        id => 13,
        name => "apple.png",
        pub_name => "Apple-Logo-Png-Download (1).png",
        orig_name => "Apple-Logo-Png-Download.png",
        inserted_at => "2017-08-20 11:09:34.625098",
        meta_data_json => '{"file_ctime":1503227374,"ext":".png","file_mtime":1503227374,"file_atime":1503227374,"file_size_bytes":929419,"mime_type":"image/png"}',
    },{},{}];
    $returned_rows = 1;
    #my $test_row = $$app{dbh}->InsertInto('files', {});
    #print Dumper $test_row;

    lives_ok{ $app->UploadFile() } 'Lives ok test'; 

done_testing();
