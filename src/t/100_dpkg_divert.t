# -*- mode: cperl;-*-
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
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

use Test::More;
use File::Spec;
use Dpkg::IPC;

use strict;
use warnings;

my $srcdir = $ENV{srcdir} || '.';
my $builddir = $ENV{builddir} || '.';
my $tmpdir = 't.tmp/950_dpkg_divert';
my $admindir = File::Spec->rel2abs("$tmpdir/admindir");
my $testdir = File::Spec->rel2abs("$tmpdir/testdir");

my @dd = ("$builddir/../src/dpkg-divert");

if (! -x "@dd") {
    plan skip_all => "dpkg-divert not available";
    exit(0);
}

plan tests => 235;

sub cleanup {
    system("rm -rf $tmpdir && mkdir -p $testdir");
    system("mkdir -p $admindir/updates && touch $admindir/status");
}

sub install_diversions {
    my ($txt) = @_;
    open(O, "> $admindir/diversions");
    print O $txt;
    close(O);
}

sub call {
    my ($prog, $args, %opts) = @_;

    my ($output, $error);
    spawn(exec => [@$prog, @$args], wait_child => 1, nocheck => 1,
          to_pipe => \$output, error_to_pipe => \$error, %opts);

    if ($opts{'expect_failure'}) {
        ok($? != 0, "@$args should fail");
    } else  {
        ok($? == 0, "@$args should not fail");
    }

    if (defined $opts{'expect_stdout'}) {
        my (@output) = <$output>;
        my (@expect) = split(/^/, $opts{'expect_stdout'});
        if (defined $opts{'expect_sorted_stdout'}) {
            @output = sort @output;
            @expect = sort @expect;
        }
        is(join('', @output), join('', @expect), "@$args stdout");
    }
    if (defined $opts{'expect_stdout_like'}) {
        like(join('', <$output>), $opts{'expect_stdout_like'}, "@$args stdout");
    }
    if (defined $opts{'expect_stderr'}) {
        is(join('', <$error>), $opts{'expect_stderr'}, "@$args stderr");
    }
    if (defined $opts{'expect_stderr_like'}) {
        like(join('', <$error>), $opts{'expect_stderr_like'}, "@$args stderr");
    }

    close($output);
    close($error);
}

sub call_divert {
    my ($params, %opts) = @_;
    call([@dd, '--admindir', $admindir], $params, %opts);
}

sub call_divert_sort {
    my ($params, %opts) = @_;
    $opts{expect_sorted_stdout} = 1;
    call_divert($params, %opts);
}

sub diversions_pack {
    my (@data) = @_;
    my @data_packed;

    for (my ($i) = 0; $i < $#data; $i += 3) {
        push @data_packed, [ @data[$i .. $i + 2] ];
    }

    return sort { $a->[0] cmp $b->[0] } @data_packed;
}

sub diversions_eq {
    my (@expected) = split /^/, shift;
    open(O, "$admindir/diversions");
    my (@contents) = <O>;
    close(O);

    my (@expected_pack) = diversions_pack(@expected);
    my (@contents_pack) = diversions_pack(@contents);

    is_deeply(\@contents_pack, \@expected_pack, "diversions contents");
}

### Tests

cleanup();

note("Command line parsing testing");

my $usagere = qr/.*Usage.*dpkg-divert.*Commands.*Options.*/s;

sub call_divert_badusage {
    my ($args, $err) = @_;
    call_divert($args, expect_failure => 1, expect_stderr_like => $err);
}

call_divert(['--help'], expect_stdout_like => $usagere,
            expect_stderr => '');
call_divert(['--version'], expect_stdout_like => qr/.*dpkg-divert.*free software.*/s,
            expect_stderr => '');

call_divert_badusage(['--jachsmitbju'], qr/unknown option/);
call_divert_badusage(['--add', '--remove'], qr/(conflicting|two).*remove.*add.*/s);
call_divert_badusage(['--divert'], qr/(takes a value|needs.*argument)/);
call_divert_badusage(['--divert', "foo\nbar"], qr/newline/);
call_divert_badusage(['--package'], qr/(takes a value|needs.*argument)/);
call_divert_badusage(['--package', "foo\nbar"], qr/newline/);

install_diversions('');

call_divert_badusage(['--add',], qr/needs a single argument/);
call_divert_badusage(['--add', 'foo'], qr/absolute/);
call_divert_badusage(['--add', "/foo\nbar"], qr/newline/);
call_divert_badusage(['--add', "$testdir"], qr/director(y|ies)/);
call_divert_badusage(['--add', "--divert", "bar", "/foo/bar"], qr/absolute/);
call_divert_badusage(['--remove'], qr/needs a single argument/);
call([@dd, '--admindir'], [],
     expect_failure => 1, expect_stderr_like => qr/(takes a value|needs.*argument)/);

cleanup();

note("Querying information from diverts db (empty one)");

install_diversions('');

call_divert_sort(['--list'], expect_stdout => '', expect_stderr => '');
call_divert_sort(['--list', '*'], expect_stdout => '', expect_stderr => '');
call_divert_sort(['--list', 'baz'], expect_stdout => '', expect_stderr => '');

cleanup();

note("Querying information from diverts db (1)");

install_diversions(<<EOF);
/bin/sh
/bin/sh.distrib
dash
/usr/share/man/man1/sh.1.gz
/usr/share/man/man1/sh.distrib.1.gz
dash
/usr/bin/nm
/usr/bin/nm.single
binutils-multiarch
EOF

my $di_dash = "diversion of /bin/sh to /bin/sh.distrib by dash\n";
my $di_dashman = "diversion of /usr/share/man/man1/sh.1.gz to /usr/share/man/man1/sh.distrib.1.gz by dash\n";
my $di_nm = "diversion of /usr/bin/nm to /usr/bin/nm.single by binutils-multiarch\n";

my $all_di = $di_dash . $di_dashman . $di_nm;

call_divert_sort(['--list'], expect_stdout => $all_di, expect_stderr => '');
call_divert_sort(['--list', '*'], expect_stdout => $all_di, expect_stderr => '');
call_divert_sort(['--list', ''], expect_stdout => '', expect_stderr => '');

call_divert_sort(['--list', '???????'], expect_stdout => $di_dash, expect_stderr => '');
call_divert_sort(['--list', '*/sh'], expect_stdout => $di_dash, expect_stderr => '');
call_divert_sort(['--list', '/bin/*'], expect_stdout => $di_dash, expect_stderr => '');
call_divert_sort(['--list', 'binutils-multiarch'], expect_stdout => $di_nm, expect_stderr => '');
call_divert_sort(['--list', '/bin/sh'], expect_stdout => $di_dash, expect_stderr => '');
call_divert_sort(['--list', '--', '/bin/sh'], expect_stdout => $di_dash, expect_stderr => '');
call_divert_sort(['--list', '/usr/bin/nm.single'], expect_stdout => $di_nm, expect_stderr => '');
call_divert_sort(['--list', '/bin/sh', '/usr/share/man/man1/sh.1.gz'], expect_stdout => $di_dash . $di_dashman,
            expect_stderr => '');

cleanup();

note("Querying information from diverts db (2)");

install_diversions(<<EOF);
/bin/sh
/bin/sh.distrib
dash
/bin/true
/bin/true.coreutils
:
EOF

call_divert(['--listpackage'], expect_failure => 1);
call_divert(['--listpackage', 'foo', 'bar'], expect_failure => 1);
call_divert(['--listpackage', '/bin/sh'], expect_stdout => "dash\n", expect_stderr => '');
call_divert(['--listpackage', '/bin/true'], expect_stdout => "LOCAL\n", expect_stderr => '');
call_divert(['--listpackage', '/bin/false'], expect_stdout => '', expect_stderr => '');

call_divert(['--truename'], expect_failure => 1);
call_divert(['--truename', '/bin/sh'], expect_stdout => "/bin/sh.distrib\n", expect_stderr => '');
call_divert(['--truename', '/bin/sh.distrib'], expect_stdout => "/bin/sh.distrib\n", expect_stderr => '');
call_divert(['--truename', '/bin/something'], expect_stdout => "/bin/something\n", expect_stderr => '');

cleanup();

note("Adding diversion");

my $diversions_added_foo_local = <<EOF;
$testdir/foo
$testdir/foo.distrib
:
EOF

install_diversions('');

system("touch $testdir/foo");
call_divert(['--rename', '--add', "$testdir/foo"],
            expect_stdout_like => qr,Adding.*local.*diversion.*\Q$testdir\E/foo.*\Q$testdir\E/foo.distrib,,
            expect_stderr => '');
ok(-e "$testdir/foo.distrib", "foo diverted");
ok(!-e "$testdir/foo", "foo diverted");
diversions_eq($diversions_added_foo_local);

cleanup();

note("Adding diversion (2)");

install_diversions('');

system("touch $testdir/foo");
call_divert(['--add', "$testdir/foo"],
            expect_stdout_like => qr,Adding.*local.*diversion.*\Q$testdir\E/foo.*\Q$testdir\E/foo.distrib,,
            expect_stderr => '');
ok(!-e "$testdir/foo.distrib", "foo diverted");
ok(-e "$testdir/foo", "foo diverted");
diversions_eq($diversions_added_foo_local);

cleanup();

note("Adding diversion (3)");

install_diversions('');

system("touch $testdir/foo");
call_divert(['--quiet', '--rename', '--add', "$testdir/foo"],
            expect_stdout => '', expect_stderr => '');
ok(-e "$testdir/foo.distrib", "foo diverted");
ok(!-e "$testdir/foo", "foo diverted");
diversions_eq($diversions_added_foo_local);

cleanup();

note("Adding diversion (4)");

install_diversions('');
system("touch $testdir/foo");
call_divert(['--quiet', '--rename', '--test', "$testdir/foo"],
            expect_stdout => '', expect_stderr => '');
ok(-e "$testdir/foo", "foo not diverted");
ok(!-e "$testdir/foo.distrib", "foo diverted");
diversions_eq('');

cleanup();

note("Adding diversion (5)");

install_diversions('');
call_divert(['--quiet', '--rename', "$testdir/foo"],
            expect_stdout => '', expect_stderr => '');
ok(!-e "$testdir/foo", "foo does not exist");
ok(!-e "$testdir/foo.distrib", "foo was not created out of thin air");

cleanup();

note("Adding diversion (6)");

install_diversions('');
system("touch $testdir/foo");
call_divert(['--quiet', '--local', '--rename', "$testdir/foo"],
            expect_stdout => '', expect_stderr => '');

ok(-e "$testdir/foo.distrib", "foo diverted");
ok(!-e "$testdir/foo", "foo diverted");
diversions_eq($diversions_added_foo_local);

cleanup();

note("Adding diversion (7)");

install_diversions('');
call_divert(['--quiet', '--rename', '--package', 'bash', "$testdir/foo"],
            expect_stdout => '', expect_stderr => '');
diversions_eq(<<EOF);
$testdir/foo
$testdir/foo.distrib
bash
EOF

note("Adding diversion (8)");

install_diversions('');
system("touch $testdir/foo; ln $testdir/foo $testdir/foo.distrib");
call_divert(["--rename", "$testdir/foo"]);
diversions_eq($diversions_added_foo_local);
ok(!-e "$testdir/foo", "foo diverted");
ok(-e "$testdir/foo.distrib", "foo diverted");

cleanup();

note("Adding diversion (9)");

install_diversions('');
system("touch $testdir/foo $testdir/foo.distrib");
call_divert(["--rename", "$testdir/foo"], expect_failure => 1,
            expect_stderr_like => qr/overwriting/);
diversions_eq('');

cleanup();

note("Adding second diversion");

install_diversions('');
call_divert(["$testdir/foo"]);

call_divert(["$testdir/foo"], expect_stdout_like => qr/Leaving/);
call_divert(['--quiet', "$testdir/foo"], expect_stdout => '');
call_divert(['--divert', "$testdir/foo.bar", "$testdir/foo"],
            expect_failure => 1, expect_stderr_like => qr/clashes/);
call_divert(['--package', 'foobar', "$testdir/foo"], expect_failure => 1,
            expect_stderr_like => qr/clashes/);
call_divert(['--divert', "$testdir/foo.distrib", "$testdir/bar"],
            expect_failure => 1, expect_stderr_like => qr/clashes/);
call_divert(["$testdir/foo.distrib"],
            expect_failure => 1, expect_stderr_like => qr/clashes/);
call_divert(['--divert', "$testdir/foo", "$testdir/bar"],
            expect_failure => 1, expect_stderr_like => qr/clashes/);

cleanup();

note("Adding third diversion");

install_diversions('');
call_divert(["$testdir/foo"]);
call_divert(["$testdir/bar"]);

call_divert(['--quiet', "$testdir/foo"], expect_stdout => '');
call_divert(['--package', 'foobar', "$testdir/bar"], expect_failure => 1,
           expect_stderr_like => qr/clashes/);

cleanup();

note("Adding diversion in non-existing directory");

install_diversions('');

call_divert(['--quiet', '--rename', '--add', "$testdir/zoo/foo"],
            expect_stderr => '', expect_stdout => '');
diversions_eq(<<EOF);
$testdir/zoo/foo
$testdir/zoo/foo.distrib
:
EOF

cleanup();

note("Remove diversions");

install_diversions('');

call_divert(['--remove', '/bin/sh'], expect_stdout_like => qr/No diversion/, expect_stderr => '');
call_divert(['--remove', '--quiet', '/bin/sh'], expect_stdout => '', expect_stderr => '');

cleanup();

note("Remove diversion (2)");

install_diversions('');
call_divert(["$testdir/foo"]);
call_divert(["$testdir/bar"]);
call_divert(["$testdir/baz"]);

call_divert(["--divert", "$testdir/foo.my", "--remove", "$testdir/foo"],
           expect_failure => 1, expect_stderr_like => qr/mismatch on divert-to/);
call_divert(["--package", "baz", "--remove", "$testdir/foo"],
            expect_failure => 1, expect_stderr_like => qr/mismatch on package/);
call_divert(["--package", "baz", "--divert", "$testdir/foo.my", "--remove", "$testdir/foo"],
            expect_failure => 1, expect_stderr_like =>qr/mismatch on (package|divert-to)/);

call_divert(["--divert", "$testdir/foo.distrib", "--remove", "$testdir/foo"],
            expect_stdout_like => qr,Removing.*\Q$testdir\E/foo,);
diversions_eq(<<EOF);
$testdir/bar
$testdir/bar.distrib
:
$testdir/baz
$testdir/baz.distrib
:
EOF

cleanup();

note("Remove diversion (3)");

install_diversions('');

call_divert(["$testdir/foo"]);
call_divert(["$testdir/bar"]);
call_divert(["$testdir/baz"]);

call_divert(["--remove", "$testdir/bar"],
            expect_stdout_like => qr,Removing.*\Q$testdir\E/bar,);
diversions_eq(<<EOF);
$testdir/foo
$testdir/foo.distrib
:
$testdir/baz
$testdir/baz.distrib
:
EOF

cleanup();

note("Remove diversion (4)");

install_diversions('');

call_divert(["$testdir/foo"]);
call_divert(["$testdir/bar"]);
call_divert(["--package", "bash", "$testdir/baz"]);

call_divert(["--quiet", "--package", "bash", "--remove", "$testdir/baz"],
            expect_stdout => '', expect_stderr => '');
diversions_eq(<<EOF);
$testdir/foo
$testdir/foo.distrib
:
$testdir/bar
$testdir/bar.distrib
:
EOF

cleanup();

note("Remove diversion(5)");

install_diversions('');
system("touch $testdir/foo");
call_divert(["--rename", "$testdir/foo"]);

call_divert(["--test", "--rename", "--remove", "$testdir/foo"],
            expect_stdout_like => qr,Removing.*\Q$testdir\E/foo,, expect_stderr => '');
ok(-e "$testdir/foo.distrib");
ok(!-e "$testdir/foo");
diversions_eq($diversions_added_foo_local);

call_divert(["--quiet", "--rename", "--remove", "$testdir/foo"],
            expect_stdout => '', expect_stderr => '');
ok(-e "$testdir/foo");
ok(!-e "$testdir/foo.distrib");
diversions_eq('');

cleanup();

note("Corrupted divertions db handling");

SKIP: {
    skip "running as root or similar", 3, if (defined($ENV{FAKEROOTKEY}) or $> == 0);

    # An inexistent diversions db file should not be considered a failure,
    # but a failure to open it should be.
    install_diversions('');
    system("chmod 000 $admindir/diversions");
    call_divert_sort(['--list'], expect_failure => 1,
                expect_stderr_like => qr/(cannot|failed).*open/, expect_stdout => '');
    system("chmod 644 $admindir/diversions");
}

install_diversions(<<EOF);
/bin/sh
EOF

call_divert_sort(['--list'], expect_failure => 1,
            expect_stderr_like => qr/(corrupt|unexpected eof)/, expect_stdout => '');

install_diversions(<<EOF);
/bin/sh
bash
EOF

call_divert_sort(['--list'], expect_failure => 1,
            expect_stderr_like => qr/(corrupt|unexpected eof)/, expect_stdout => '');

cleanup();

SKIP: {
    skip "running as root or similar", 10, if (defined($ENV{FAKEROOTKEY}) or $> == 0);

    note("R/O directory");

    install_diversions('');
    system("mkdir $testdir/rodir && touch $testdir/rodir/foo $testdir/bar && chmod 500 $testdir/rodir");
    call_divert(['--rename', '--add', "$testdir/rodir/foo"],
                expect_failure => 1, expect_stderr_like => qr/error/);
    call_divert(['--rename', '--divert', "$testdir/rodir/bar", '--add', "$testdir/bar"],
                expect_failure => 1, expect_stderr_like => qr/error/);
    diversions_eq('');

    system("chmod 755 $testdir/rodir");
    cleanup();

    note("Unavailable file");

    install_diversions('');
    system("mkdir $testdir/nadir && chmod 000 $testdir/nadir");
    call_divert(['--rename', '--add', "$testdir/nadir/foo"],
                expect_failure => 1, expect_stderr_like => qr/Permission denied/);
    system("touch $testdir/foo");
    call_divert(['--rename', '--divert', "$testdir/nadir/foo", '--add', "$testdir/foo"],
                expect_failure => 1, expect_stderr_like => qr/Permission denied/);
    diversions_eq('');

    cleanup();
}

note("Errors during saving diversions db");

install_diversions('');

SKIP: {
    skip "running as root or similar", 4, if (defined($ENV{FAKEROOTKEY}) or $> == 0);

    system("chmod 500 $admindir");
    call_divert(["$testdir/foo"], expect_failure => 1, expect_stderr_like => qr/create.*new/);
    system("chmod 755 $admindir; ln -s /dev/full $admindir/diversions-new");
    call_divert(["$testdir/foo"], expect_failure => 1, expect_stderr_like => qr/(write|flush|close).*new/);
}

system("rm -f $admindir/diversions-new; mkdir $admindir/diversions-old");
call_divert(["$testdir/foo"], expect_failure => 1, expect_stderr_like => qr/remov.*old/);
