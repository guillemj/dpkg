# -*- mode: cperl -*-

use Test::More tests => 7;

use strict;
use warnings;
use File::Temp qw(tempfile);

use_ok('Dpkg::IPC');

$/ = undef;

my ($tmp_fh, $tmp_name) = tempfile;
my ($tmp2_fh, $tmp2_name) = tempfile;

my $string = "foo\nbar\n";
my $string2;

open TMP, '>', $tmp_name;
print TMP $string;
close TMP;

my $pid = fork_and_exec(exec => "cat",
			from_string => \$string,
			to_string => \$string2);

ok($pid);

is($string2, $string, "{from,to}_string");

$pid = fork_and_exec(exec => "cat",
		     from_handle => $tmp_fh,
		     to_handle => $tmp2_fh);

ok($pid);

wait_child($pid);

open TMP, '<', $tmp2_name;
$string2 = <TMP>;
close TMP;

is($string2, $string, "{from,to}_handle");

$pid = fork_and_exec(exec => "cat",
		     from_file => $tmp_name,
		     to_file => $tmp2_name,
		     wait_child => 1);

ok($pid);

open TMP, '<', $tmp2_name;
$string2 = <TMP>;
close TMP;

is($string2, $string, "{from,to}_file");

unlink($tmp_name);
unlink($tmp2_name);
