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

use v5.36;

use Test::More;

use File::Spec;

use Dpkg::IPC;
use Dpkg::File qw(file_slurp);
use Dpkg::Path qw(find_command);

if (! -x "$ENV{builddir}/update-alternatives") {
    plan skip_all => 'update-alternatives not available';
}
plan tests => 712;

my $srcdir = $ENV{srcdir} || '.';
my $tmpdir = 't.tmp/update_alternatives';
my $admindir = File::Spec->rel2abs("$tmpdir/admindir"),
my $altdir = File::Spec->rel2abs("$tmpdir/alternatives");
my $bindir = File::Spec->rel2abs("$tmpdir/bin");
my @ua = (
    "$ENV{builddir}/update-alternatives",
    '--log', '/dev/null',
    '--quiet',
    '--admindir', "$admindir",
    '--altdir', "$altdir",
);

my $rootdir_envvar = $ENV{UA_ROOTDIR_ENVVAR} // 'DPKG_ROOT';
my $admindir_envvar = $ENV{UA_ADMINDIR_ENVVAR} // 'DPKG_ADMINDIR';

delete $ENV{$rootdir_envvar};
delete $ENV{$admindir_envvar};

my %paths = (
    true => find_command('true'),
    false => find_command('false'),
    yes => find_command('yes'),
    cat => find_command('cat'),
    date => find_command('date'),
    sleep => find_command('sleep'),
);

my $main_link = "$bindir/generic-test";
my $main_name = 'generic-test';
my @choices = (
    {
        path => $paths{true},
        priority => 20,
        slaves => [
            {
                link => "$bindir/slave2",
                name => 'slave2',
                path => $paths{cat},
            },
            {
                link => "$bindir/slave3",
                name => 'slave3',
                path => $paths{cat},
            },
            {
                link => "$bindir/slave1",
                name => 'slave1',
                path => $paths{yes},
            },
            {
                link => "$bindir/slave4",
                name => 'slave4',
                path => $paths{cat},
            },
        ],
    },
    {
        path => $paths{false},
        priority => 10,
        slaves => [
            {
                link => "$bindir/slave1",
                name => 'slave1',
                path => $paths{date},
            },
        ],
    },
    {
        path => $paths{sleep},
        priority => 5,
        slaves => [],
    },
);

sub cleanup {
    system("rm -rf $tmpdir && mkdir -p $admindir && mkdir -p $altdir");
    system("mkdir -p $bindir/more");
}

sub call_ua {
    my ($params, %opts) = @_;

    my %env;
    %env = %{delete $opts{env}} if exists $opts{env};
    my @cmd;
    if (exists $opts{cmd}) {
        @cmd = @{delete $opts{cmd}};
    } else {
        @cmd = @ua;
    }

    spawn(
        exec => [ @cmd, @{$params} ],
        env => {
            LC_ALL => 'C',
            %env,
        },
        no_check => 1,
        wait_child => 1,
        %opts,
    );
    my $test_id = '';
    $test_id = "$opts{test_id}: " if defined $opts{test_id};
    if ($opts{expect_failure}) {
        ok($? != 0, "${test_id}update-alternatives @$params should fail.") or
            diag("Did not fail as expected: @ua @$params");
    } else {
        ok($? == 0, "${test_id}update-alternatives @$params should work.") or
            diag("Did not succeed as expected: @ua @$params");
    }
}

sub call_ua_dirs {
    my (%opts) = @_;

    $opts{cmd} = [ "$ENV{builddir}/update-alternatives" ];

    my @params;
    @params = @{delete $opts{params}} if exists $opts{params};
    push @params, qw(--debug);
    push @params, qw(--log /dev/null);
    push @params, qw(--get-selections);

    die unless exists $opts{expected};

    my $stderr;
    my $expected = delete $opts{expected};
    $opts{to_file} = '/dev/null';
    $opts{error_to_string} = \$stderr;

    call_ua(\@params, %opts);

    ok($stderr =~ $expected, "output '$stderr' does not match expected '$expected'");
}

sub install_choice {
    my ($id, %opts) = @_;
    my $alt = $choices[$id];
    my @params;
    push @params, @{$opts{params}} if exists $opts{params};
    push @params, '--install', "$main_link", "$main_name",
                  $alt->{path}, $alt->{priority};
    foreach my $slave (@{ $alt->{slaves} }) {
        push @params, '--slave', $slave->{link}, $slave->{name}, $slave->{path};
    }
    call_ua(\@params, %opts);
}

sub remove_choice {
    my ($id, %opts) = @_;
    my $alt = $choices[$id];
    my @params;
    push @params, @{$opts{params}} if exists $opts{params};
    push @params, '--remove', $main_name, $alt->{path};
    call_ua(\@params, %opts);
}

sub remove_all_choices {
    my (%opts) = @_;
    my @params;
    push @params, @{$opts{params}} if exists $opts{params};
    push @params, '--remove-all', $main_name;
    call_ua(\@params, %opts);
}

sub set_choice {
    my ($id, %opts) = @_;
    my $alt = $choices[$id];
    my @params;
    push @params, @{$opts{params}} if exists $opts{params};
    push @params, '--set', $main_name, $alt->{path};
    call_ua(\@params, %opts);
}

sub config_choice {
    my ($id, %opts) = @_;
    my ($input, $output) = ('', '');
    if ($id >= 0) {
        my $alt = $choices[$id];
        $input = $alt->{path};
    } else {
        $input = '0';
    }
    $input .= "\n";
    $opts{from_string} = \$input;
    $opts{to_string} = \$output;
    my @params;
    push @params, @{$opts{params}} if exists $opts{params};
    push @params, '--config', $main_name;
    call_ua(\@params, %opts);
}

sub get_slaves_status {
    my ($id) = @_;
    my %slaves;
    # None of the slaves are installed.
    foreach my $alt (@choices) {
        for my $i (0 .. @{$alt->{slaves}} - 1) {
            $slaves{$alt->{slaves}[$i]{name}} = $alt->{slaves}[$i];
            $slaves{$alt->{slaves}[$i]{name}}{installed} = 0;
        }
    }
    # Except those of the current alternative (minus optional slaves).
    if (defined($id)) {
        my $alt = $choices[$id];
        for my $i (0 .. @{$alt->{slaves}} - 1) {
            $slaves{$alt->{slaves}[$i]{name}} = $alt->{slaves}[$i];
            if (-e $alt->{slaves}[$i]{path}) {
                $slaves{$alt->{slaves}[$i]{name}}{installed} = 1;
            }
        }
    }
    my @slaves = sort { $a->{name} cmp $b->{name} } values %slaves;

    return @slaves;
}

sub check_link {
    my ($link, $value, $msg) = @_;
    ok(-l $link, "$msg: $link disappeared.");
    is(readlink($link), $value, "$link doesn't point to $value.");
}
sub check_no_link {
    my ($link, $msg) = @_;
    lstat($link);
    ok(! -e _, "$msg: $link still exists.");
    # We need the same number of tests as check_link().
    ok(1, 'fake test');
}

sub check_slaves {
    my ($id, $msg) = @_;
    foreach my $slave (get_slaves_status($id)) {
        if ($slave->{installed}) {
            check_link("$altdir/$slave->{name}", $slave->{path}, $msg);
            check_link($slave->{link}, "$altdir/$slave->{name}", $msg);
        } else {
            check_no_link("$altdir/$slave->{name}", $msg);
            check_no_link($slave->{link}, $msg);
        }
    }
}

sub check_choice {
    my ($id, $mode, $msg) = @_;
    my $output;
    if (defined $id) {
        # Check status.
        call_ua(
            [
                '--query', "$main_name",
            ],
            to_string => \$output,
            test_id => $msg,
        );
        my $status = q{};
        if ($output =~ /^Status: (.*)$/im) {
            $status = $1;
        }
        is($status, $mode, "$msg: status is not $mode.");
        # Check links.
        my $alt = $choices[$id];
        check_link("$altdir/$main_name", $alt->{path}, $msg);
        check_link($main_link, "$altdir/$main_name", $msg);
        check_slaves($id, $msg);
    } else {
        call_ua(
            [
                '--query', "$main_name",
            ],
            error_to_string => \$output,
            expect_failure => 1,
            test_id => $msg,
        );
        ok($output =~ /no alternatives/, "$msg: bad error message for --query.");
        # Check that all links have disappeared.
        check_no_link("$altdir/$main_name", $msg);
        check_no_link($main_link, $msg);
        check_slaves(undef, $msg);
    }
}

## Tests.

cleanup();

# Check directory overrides.

my $DEFAULT_ROOTDIR = '';
my $DEFAULT_ADMINDIR = $ENV{UA_ADMINDIR_DEFAULT} // '/var/lib/dpkg/alternatives';

# ENV_ADMINDIR + defaults.
call_ua_dirs(
    env => {
        $admindir_envvar => '/admindir_env',
    },
    expected => "root=$DEFAULT_ROOTDIR admdir=/admindir_env",
);

# ENV_ROOT + defaults.
call_ua_dirs(
    env => {
        $rootdir_envvar => '/rootdir_env'
    },
    expected => "root=/rootdir_env admdir=/rootdir_env$DEFAULT_ADMINDIR",
);

# ENV_ROOT + ENV_ADMINDIR.
call_ua_dirs(
    env => {
        $rootdir_envvar => '/rootdir_env',
        $admindir_envvar => '/admindir_env',
    },
    expected => 'root=/rootdir_env admdir=/admindir_env',
);

# ENV_ADMINDIR + options.
call_ua_dirs(
    env => {
        $admindir_envvar => '/admindir_env',
    },
    params => [ qw(--root /rootdir_opt) ],
    expected => "root=/rootdir_opt admdir=/rootdir_opt$DEFAULT_ADMINDIR",
);
call_ua_dirs(
    env => {
        $admindir_envvar => '/admindir_env',
    },
    params => [ qw(--admindir /admindir_opt) ],
    expected => "root=$DEFAULT_ROOTDIR admdir=/admindir_opt",
);
call_ua_dirs(
    env => {
        $admindir_envvar => '/admindir_env',
    },
    params => [ qw(--root /rootdir_opt --admindir /admindir_opt) ],
    expected => 'root=/rootdir_opt admdir=/admindir_opt',
);
call_ua_dirs(
    env => {
        $admindir_envvar => '/admindir_env',
    },
    params => [ qw(--admindir /admindir_opt --root /rootdir_opt) ],
    expected => "root=/rootdir_opt admdir=/rootdir_opt$DEFAULT_ADMINDIR",
);

# ENV_ROOT + options.
call_ua_dirs(
    env => {
        $rootdir_envvar => '/rootdir_env',
    },
    params => [ qw(--root /rootdir_opt) ],
    expected => "root=/rootdir_opt admdir=/rootdir_opt$DEFAULT_ADMINDIR",
);
call_ua_dirs(
    env => {
        $rootdir_envvar => '/rootdir_env',
    },
    params => [ qw(--admindir /admindir_opt) ],
    expected => 'root=/rootdir_env admdir=/admindir_opt',
);
call_ua_dirs(
    env => {
        $rootdir_envvar => '/rootdir_env',
    },
    params => [ qw(--root /rootdir_opt --admindir /admindir_opt) ],
    expected => 'root=/rootdir_opt admdir=/admindir_opt',
);
call_ua_dirs(
    env => {
        $rootdir_envvar => '/rootdir_env',
    },
    params => [ qw(--admindir /admindir_opt --root /rootdir_opt) ],
    expected => "root=/rootdir_opt admdir=/rootdir_opt$DEFAULT_ADMINDIR",
);

# ENV_ROOT + ENV_ADMINDIR + options.
call_ua_dirs(
    env => {
        $rootdir_envvar => '/rootdir_env',
        $admindir_envvar => '/admindir_env',
    },
    params => [ qw(--root /rootdir_opt) ],
    expected => "root=/rootdir_opt admdir=/rootdir_opt$DEFAULT_ADMINDIR",
);
call_ua_dirs(
    env => {
        $rootdir_envvar => '/rootdir_env',
        $admindir_envvar => '/admindir_env',
    },
    params => [ qw(--admindir /admindir_opt) ],
    expected => 'root=/rootdir_env admdir=/admindir_opt',
);
call_ua_dirs(
    env => {
        $rootdir_envvar => '/rootdir_env',
        $admindir_envvar => '/admindir_env',
    },
    params => [ qw(--root /rootdir_opt --admindir /admindir_opt) ],
    expected => 'root=/rootdir_opt admdir=/admindir_opt',
);
call_ua_dirs(
    env => {
        $rootdir_envvar => '/rootdir_env',
        $admindir_envvar => '/admindir_env',
    },
    params => [ qw(--admindir /admindir_opt --root /rootdir_opt) ],
    expected => "root=/rootdir_opt admdir=/rootdir_opt$DEFAULT_ADMINDIR",
);

cleanup();
# Removal when not installed should not fail.
remove_choice(0);
# Successive install in auto mode.
install_choice(1);
check_choice(1, 'auto', 'initial install 1');
# 2 is lower prio, stays at 1.
install_choice(2);
check_choice(1, 'auto', 'initial install 2');
# 0 is higher priority.
install_choice(0);
check_choice(0, 'auto', 'initial install 3');

# Verify that the administrative file is sorted properly.
{
    my $content = file_slurp("$admindir/generic-test");
    my $expected =
"auto
$bindir/generic-test
slave1
$bindir/slave1
slave2
$bindir/slave2
slave3
$bindir/slave3
slave4
$bindir/slave4

";

    my %slaves;

    # Store slaves in a hash to easily retrieve present and missing ones.
    foreach my $alt (@choices) {
        foreach my $slave (@{$alt->{slaves}}) {
            $slaves{$slave->{name}}{$alt->{path}} = $slave;
        }
    }

    foreach my $alt (sort { $a->{path} cmp $b->{path} } @choices) {
        $expected .= $alt->{path} . "\n";
        $expected .= $alt->{priority} . "\n";
        foreach my $slave_name (sort keys %slaves) {
            $expected .= $slaves{$slave_name}{$alt->{path}}{path} || '';
            $expected .= "\n";
        }
    }
    $expected .= "\n";

    is($content, $expected, 'administrative file is as expected');
}

# Manual change with --set-selections.
my $input = "doesntexist auto $paths{date}\ngeneric-test manual $paths{false}\n";
my $output = '';
call_ua(
    [
        '--set-selections',
    ],
    from_string => \$input,
    to_string => \$output,
    test_id => 'manual update with --set-selections',
);
check_choice(1, 'manual', 'manual update with --set-selections');
$input = "generic-test auto $paths{true}\n";
call_ua(
    [
        '--set-selections',
    ],
    from_string => \$input,
    to_string => \$output,
    test_id => 'auto update with --set-selections',
);
check_choice(0, 'auto', 'auto update with --set-selections');
# Manual change with set.
set_choice(2, test_id => 'manual update with --set');
# (Regression test for #388313.)
check_choice(2, 'manual', 'manual update with --set');
remove_choice(2, test_id => 'remove manual, back to auto');
check_choice(0, 'auto', 'remove manual, back to auto');
remove_choice(0, test_id => 'remove best');
check_choice(1, 'auto', 'remove best');
remove_choice(1, test_id => 'no alternative left');
check_choice(undef, '', 'no alternative left');
# Single choice in manual mode, to be removed.
install_choice(1);
set_choice(1);
check_choice(1, 'manual', 'single manual choice');
remove_choice(1);
check_choice(undef, '', 'removal single manual');
# Test --remove-all.
install_choice(0);
install_choice(1);
install_choice(2);
remove_all_choices(test_id => 'remove all');
check_choice(undef, '', 'no alternative left');
# Check auto-recovery of user mistakes (#100135).
install_choice(1);
ok(unlink("$bindir/generic-test"), 'failed removal');
ok(unlink("$bindir/slave1"), 'failed removal');
install_choice(1);
check_choice(1, 'auto', 'recreate links in auto mode');
set_choice(1);
ok(unlink("$bindir/generic-test"), 'failed removal');
ok(unlink("$bindir/slave1"), 'failed removal');
install_choice(1);
check_choice(1, 'manual', 'recreate links in manual mode');
# Check recovery of «/etc/alternatives/*».
install_choice(0);
ok(unlink("$altdir/generic-test"), 'failed removal');
install_choice(1);
check_choice(0, 'auto', '<altdir>/generic-test lost, back to auto');
# Test --config.
config_choice(0);
check_choice(0, 'manual', 'config to best but manual');
config_choice(1);
check_choice(1, 'manual', 'config to manual');
config_choice(-1);
check_choice(0, 'auto', 'config auto');

# Test rename of links.
install_choice(0);
my $old_slave = $choices[0]{slaves}[0]{link};
my $old_link = $main_link;
$choices[0]{slaves}[0]{link} = "$bindir/more/generic-slave";
$main_link = "$bindir/more/mytest";
install_choice(0);
check_choice(0, 'auto', 'test rename of links');
check_no_link($old_link, 'test rename of links');
check_no_link($old_slave, 'test rename of links');
# Rename with installing other alternatives.
$old_link = $main_link;
$main_link = "$bindir/generic-test";
install_choice(1);
check_choice(0, 'auto', 'rename link');
check_no_link($old_link, 'rename link');
# Rename with lost file.
unlink($old_slave);
$old_slave = $choices[0]{slaves}[0]{link};
$choices[0]{slaves}[0]{link} = "$bindir/generic-slave-bis";
install_choice(0);
check_choice(0, 'auto', 'rename lost file');
check_no_link($old_slave, 'rename lost file');
# Update of alternative with many slaves not currently installed
# and the link of the renamed slave exists while it should not.
set_choice(1);
symlink("$paths{cat}", "$bindir/generic-slave-bis");
$choices[0]{slaves}[0]{link} = "$bindir/slave2";
install_choice(0, test_id => 'update with non-installed slaves');
check_no_link("$bindir/generic-slave-bis",
              'drop renamed symlink that should not be installed');

# Test install with empty admin file (#457863).
cleanup();
system("touch $admindir/generic-test");
install_choice(0);
# Test install with garbage admin file.
cleanup();
system("echo garbage > $admindir/generic-test");
install_choice(0,
    error_to_file => '/dev/null',
    expect_failure => 1,
);

# Test invalid usages.
cleanup();
install_choice(0);
# Try to install a slave alternative as new master.
call_ua(
    [
        '--install', "$bindir/testmaster", 'slave1', "$paths{date}", '10',
    ],
    expect_failure => 1,
    to_file => '/dev/null',
    error_to_file => '/dev/null',
);
# Try to install a master alternative as slave.
call_ua(
    [
        '--install', "$bindir/testmaster", 'testmaster', "$paths{date}", '10',
        '--slave', "$bindir/testslave", 'generic-test', "$paths{true}",
    ],
    expect_failure => 1,
    to_file => '/dev/null',
    error_to_file => '/dev/null',
);
# Try to reuse master link in slave.
call_ua(
    [
        '--install', "$bindir/testmaster", 'testmaster', "$paths{date}", '10',
        '--slave', "$bindir/testmaster", 'testslave', "$paths{true}",
    ],
    expect_failure => 1,
    to_file => '/dev/null',
    error_to_file => '/dev/null',
);
# Try to reuse links in master alternative.
call_ua(
    [
        '--install', "$bindir/slave1", 'testmaster', "$paths{date}", '10',
    ],
    expect_failure => 1,
    to_file => '/dev/null',
    error_to_file => '/dev/null',
);
# Try to reuse links in slave alternative.
call_ua(
    [
        '--install', "$bindir/testmaster", 'testmaster', "$paths{date}", '10',
        '--slave', "$bindir/generic-test", 'testslave', "$paths{true}",
    ],
    expect_failure => 1,
    to_file => '/dev/null',
    error_to_file => '/dev/null',
);
# Try to reuse slave link in another slave alternative of another choice of
# the same main alternative.
call_ua(
    [
        '--install', $main_link, $main_name, "$paths{date}", '10',
        '--slave', "$bindir/slave1", 'testslave', "$paths{true}",
    ],
    expect_failure => 1,
    to_file => '/dev/null',
    error_to_file => '/dev/null',
);
# Lack of absolute filenames in links or file path, non-existing path.
call_ua(
    [
        '--install', '../testmaster', 'testmaster', "$paths{date}", '10',
    ],
    expect_failure => 1,
    to_file => '/dev/null',
    error_to_file => '/dev/null',
);
call_ua(
    [
        '--install', "$bindir/testmaster", 'testmaster', './update-alternatives.pl', '10',
    ],
    expect_failure => 1,
    to_file => '/dev/null',
    error_to_file => '/dev/null',
);
# Non-existing alternative path.
call_ua(
    [
        '--install', "$bindir/testmaster", 'testmaster', "$bindir/doesntexist", '10',
    ],
    expect_failure => 1,
    to_file => '/dev/null',
    error_to_file => '/dev/null',
);
# Invalid alternative name in master.
call_ua(
    [
        '--install', "$bindir/testmaster", 'test/master', "$paths{date}", '10',
    ],
    expect_failure => 1,
    to_file => '/dev/null',
    error_to_file => '/dev/null',
);
# Invalid alternative name in slave.
call_ua(
    [
        '--install', "$bindir/testmaster", 'testmaster', "$paths{date}", '10',
        '--slave', "$bindir/testslave", 'test slave', "$paths{true}",
    ],
    expect_failure => 1,
    to_file => '/dev/null',
    error_to_file => '/dev/null',
);
# Install in non-existing dir should fail.
call_ua(
    [
        '--install', "$bindir/doesntexist/testmaster", 'testmaster', "$paths{date}", '10',
        '--slave', "$bindir/testslave", 'testslave', "$paths{true}",
    ],
    expect_failure => 1,
    to_file => '/dev/null',
    error_to_file => '/dev/null',
);
call_ua(
    [
        '--install', "$bindir/testmaster", 'testmaster', "$paths{date}", '10',
        '--slave', "$bindir/doesntexist/testslave", 'testslave', "$paths{true}",
    ],
    expect_failure => 1,
    to_file => '/dev/null',
    error_to_file => '/dev/null',
);

# Non-existing alternative path in slave is not a failure.
my $old_path = $choices[0]{slaves}[0]{path};
$old_slave = $choices[0]{slaves}[0]{link};
$choices[0]{slaves}[0]{path} = "$bindir/doesntexist";
$choices[0]{slaves}[0]{link} = "$bindir/baddir/slave2";
# Test rename of slave link that existed but that does not anymore
# and link is moved into non-existing dir at the same time.
install_choice(0);
check_choice(0, 'auto', 'optional renamed slave2 in non-existing dir');
# Same but on fresh install.
cleanup();
install_choice(0);
check_choice(0, 'auto', 'optional slave2 in non-existing dir');
$choices[0]{slaves}[0]{link} = $old_slave;
# Test fresh install with a non-existing slave file.
cleanup();
install_choice(0);
check_choice(0, 'auto', 'optional slave2');
$choices[0]{slaves}[0]{path} = $old_path;

# Test management of pre-existing files.
cleanup();
system("touch $main_link $bindir/slave1");
install_choice(0);
ok(! -l $main_link, 'install preserves files that should be links');
ok(! -l "$bindir/slave1", 'install preserves files that should be slave links');
remove_choice(0);
ok(-f $main_link, 'removal keeps real file installed as master link');
ok(-f "$bindir/slave1", 'removal keeps real files installed as slave links');
install_choice(0, params => [ '--force' ]);
check_choice(0, 'auto', 'install --force replaces files with links');

# Test management of pre-existing files #2.
cleanup();
system("touch $main_link $bindir/slave2");
install_choice(0);
install_choice(1);
ok(! -l $main_link, 'inactive install preserves files that should be links');
ok(! -l "$bindir/slave2", 'inactive install preserves files that should be slave links');
ok(-f $main_link, 'inactive install keeps real file installed as master link');
ok(-f "$bindir/slave2", 'inactive install keeps real files installed as slave links');
set_choice(1);
ok(! -l $main_link, 'manual switching preserves files that should be links');
ok(! -l "$bindir/slave2", 'manual switching preserves files that should be slave links');
ok(-f $main_link, 'manual switching keeps real file installed as master link');
ok(-f "$bindir/slave2", 'manual switching keeps real files installed as slave links');
remove_choice(1);
ok(! -l $main_link, 'auto switching preserves files that should be links');
ok(! -l "$bindir/slave2", 'auto switching preserves files that should be slave links');
ok(-f $main_link, 'auto switching keeps real file installed as master link');
ok(-f "$bindir/slave2", 'auto switching keeps real files installed as slave links');
remove_all_choices(params => [ '--force' ]);
ok(! -e "$bindir/slave2", 'forced removeall drops real files installed as slave links');

# Test management of pre-existing files #3.
cleanup();
system("touch $main_link $bindir/slave2");
install_choice(0);
install_choice(1);
remove_choice(0);
ok(! -l $main_link, 'removal + switching preserves files that should be links');
ok(! -l "$bindir/slave2", 'removal + switching preserves files that should be slave links');
ok(-f $main_link, 'removal + switching keeps real file installed as master link');
ok(-f "$bindir/slave2", 'removal + switching keeps real files installed as slave links');
install_choice(0);
ok(! -l $main_link, 'install + switching preserves files that should be links');
ok(! -l "$bindir/slave2", 'install + switching preserves files that should be slave links');
ok(-f $main_link, 'install + switching keeps real file installed as master link');
ok(-f "$bindir/slave2", 'install + switching keeps real files installed as slave links');
set_choice(1, params => [ '--force' ]);
ok(! -e "$bindir/slave2", 'forced switching w/o slave drops real files installed as slave links');
check_choice(1, 'manual', 'set --force replaces files with links');

# Check disappearence of obsolete slaves (#916799).
cleanup();
call_ua(
    [
        '--install', "$bindir/test-obsolete", 'test-obsolete', "$paths{date}", '10',
        '--slave', "$bindir/test-slave-a", 'test-slave-a', "$bindir/impl-slave-a",
        '--slave', "$bindir/test-slave-b", 'test-slave-b', "$bindir/impl-slave-b",
        '--slave', "$bindir/test-slave-c", 'test-slave-c', "$bindir/impl-slave-c",
    ],
    to_file => '/dev/null',
    error_to_file => '/dev/null',
);

my $content;
my $expected;

$content = file_slurp("$admindir/test-obsolete");
$expected =
"auto
$bindir/test-obsolete
test-slave-a
$bindir/test-slave-a
test-slave-b
$bindir/test-slave-b
test-slave-c
$bindir/test-slave-c

$paths{date}
10
$bindir/impl-slave-a
$bindir/impl-slave-b
$bindir/impl-slave-c

";
is($content, $expected, 'administrative file for non-obsolete slaves is as expected');

call_ua(
    [
        '--install', "$bindir/test-obsolete", 'test-obsolete', "$paths{date}", '20',
        '--slave', "$bindir/test-slave-c", 'test-slave-c', "$bindir/impl-slave-c",
    ],
    to_file => '/dev/null',
    error_to_file => '/dev/null',
);

$content = file_slurp("$admindir/test-obsolete");
$expected =
"auto
$bindir/test-obsolete
test-slave-c
$bindir/test-slave-c

$paths{date}
20
$bindir/impl-slave-c

";
is($content, $expected, 'administrative file for obsolete slaves is as expected');
