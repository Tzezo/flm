use strict;
use warnings;

use lib qw{../lib/perl ../common/lib/perl};
use Test::More; 
use Test::Exception;
use Test::MockObject;
use Test::MockModule;

use Data::Dumper;

require_ok( 'FLM::App' );

sub FLM::App::TRACE { };

my $resp = FLM::App->GetRespObj("test_err", {code => "TESTSYS000", msg => "Test error msg"});

ok(defined $$resp{ status }, "Test status object is defined");
is($$resp{ status }{ status }, "test_err", "Test resp status");
is($$resp{ status }{ code }, "TESTSYS000", "Test resp code");
is($$resp{ status }{ msg }, "Test error msg", "Test resp msg");

$resp = FLM::App->GetRespObj("test_err2", {code => "TESTPEER000"});
ok(defined $$resp{ status }, "Test status object is defined");
is($$resp{ status }{ status }, "test_err2", "Test resp status");
is($$resp{ status }{ code }, "TESTPEER000", "Test resp code");
ok(!defined $$resp{ status }{ msg }, "Test resp msg");

dies_ok{ FLM::App->GetErrorRespObj("test_stauts", {code => "TEST001", msg => "Test msg"}) } 'die test, wrong status';
dies_ok{ FLM::App->GetErrorRespObj("peer_err") } 'die test, missing adit_params';
dies_ok{ FLM::App->GetErrorRespObj("sys_err", {msg => "Test msg"}) } 'die test, missing code from adit_params';
dies_ok{ FLM::App->GetErrorRespObj("sys_err", {code => "SYS01"}) } 'die test, missing msg from adit_params';
lives_ok{ FLM::App->GetErrorRespObj("sys_err", {msg => "Test msg", code => "SYS01", extra_param => "TEST"}) } 'lives_ok test, added extra param in adit_params';

dies_ok{ FLM::App->GetSuccessRespObj() } 'die test, missing result parameter';
lives_ok{ FLM::App->GetSuccessRespObj("test") } 'lives_ok test';

####GetFileDataTest
my $fetchrow_hashref_hash = {
    id => 1,
    pub_name => "Test",
    meta_data_json => "{}",
    inserted_at => "2017-01-01 00:00:00"
};

my $params_hash = {
    file_id => 33
};


my $mock_sth = Test::MockObject->new();
$mock_sth->mock( 'rows',
            sub { return 1 } );

$mock_sth->mock( 'fetchrow_hashref',
            sub { 
                    return $fetchrow_hashref_hash;
                } 
            );

$mock_sth->mock( 'execute',
                sub { return 1 } );

my $mock_dbh = Test::MockObject->new();
$mock_dbh->mock( 'prepare', 
                sub { return $mock_sth }
                );

my $mock_cgi = Test::MockObject->new();
$mock_cgi->mock( 'param',
                sub {
                    return $$params_hash{ $_[1] };
                } );

my $app = FLM::App->new();
$$app{cgi} = $mock_cgi;
$$app{dbh} = $mock_dbh;

lives_ok{ $app->GetFileData() } 'lives_ok get_file_data';

done_testing();
