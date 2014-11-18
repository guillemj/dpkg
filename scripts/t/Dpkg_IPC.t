#!/usr/bin/perl
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

use strict;
use warnings;

use Test::More tests => 8;

use File::Temp qw(tempfile);

use_ok('Dpkg::IPC');

$/ = undef;

my ($tmp1_fh, $tmp1_name) = tempfile(UNLINK => 1);
my ($tmp2_fh, $tmp2_name) = tempfile(UNLINK => 1);
my $tmp_fh;

my $string1 = "foo\nbar\n";
my $string2;

open $tmp_fh, '>', $tmp1_name
    or die "cannot open $tmp1_name: $!";
print { $tmp_fh } $string1;
close $tmp_fh;

my $pid = spawn(exec => 'cat',
		from_string => \$string1,
		to_string => \$string2);

ok($pid, 'execute cat program, I/O to variables');

is($string2, $string1, '{from,to}_string');

$pid = spawn(exec => 'cat',
	     from_handle => $tmp1_fh,
	     to_handle => $tmp2_fh);

ok($pid, 'execute cat program, I/O to filehandles');

wait_child($pid);

open $tmp_fh, '<', $tmp2_name
    or die "cannot open $tmp2_name: $!";
$string2 = <$tmp_fh>;
close $tmp_fh;

is($string2, $string1, '{from,to}_handle');

$pid = spawn(exec => 'cat',
	     from_file => $tmp1_name,
	     to_file => $tmp2_name,
	     wait_child => 1,
	     timeout => 5);

ok($pid, 'execute cat program, I/O to filenames, wait and timeout');

open $tmp_fh, '<', $tmp2_name
    or die "cannot open $tmp2_name: $!";
$string2 = <$tmp_fh>;
close $tmp_fh;

is($string2, $string1, '{from,to}_file');

eval {
    $pid = spawn(exec => ['sleep', '10'],
	         wait_child => 1,
	         timeout => 5);
};
ok($@, 'fails on timeout');
