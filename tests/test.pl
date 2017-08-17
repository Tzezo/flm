use strict;
use warnings;

use lib qw{../lib/perl ../common/lib/perl};
use Test::More; 
use Test::Exception;

use Data::Dumper;

require_ok( 'FLM::App' );

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

done_testing();
