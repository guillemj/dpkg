# Copyright © 2015 Guillem Jover <guillem@debian.org>
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

=encoding utf8

=head1 NAME

Test::Dpkg - helpers for test scripts for the dpkg suite

=head1 DESCRIPTION

This module provides helper functions to ease implementing test scripts
for the dpkg suite of tools.

B<Note>: This is a private module, its API can change at any time.

=cut

package Test::Dpkg 0.00;

use v5.36;

our @EXPORT_OK = qw(
    all_po_files
    all_shell_files
    all_perl_files
    all_perl_modules
    all_pod_modules
    test_get_data_path
    test_get_temp_path
    test_chdir_srcdir
    test_needs_author
    test_needs_module
    test_needs_command
    test_needs_openpgp_backend
    test_neutralize_checksums
);
our %EXPORT_TAGS = (
    needs => [ qw(
        test_needs_author
        test_needs_module
        test_needs_command
        test_needs_openpgp_backend
    ) ],
    paths => [ qw(
        all_po_files
        all_shell_files
        all_perl_files
        all_perl_modules
        all_pod_modules
        test_get_data_path
        test_get_temp_path
        test_chdir_srcdir
    ) ],
);

use Exporter qw(import);
use Cwd;
use File::Find;
use File::Basename;
use File::Path qw(make_path rmtree);
use IPC::Cmd qw(can_run);
use Test::More;

my $test_mode;

BEGIN {
    $test_mode = $ENV{DPKG_TEST_MODE} // 'dpkg';
}

sub _test_get_caller_dir
{
    my (undef, $path, undef) = caller 1;

    $path =~ s{\.t$}{};
    $path =~ s{^\./}{};

    return $path;
}

sub test_get_data_path
{
    my $path = shift;

    if (defined $path) {
        my $srcdir;
        $srcdir = $ENV{srcdir} if $test_mode ne 'cpan';
        $srcdir ||= '.';
        return "$srcdir/$path";
    } else {
        return _test_get_caller_dir();
    }
}

sub test_get_temp_path
{
    my $path = shift // _test_get_caller_dir();
    $path = 't.tmp/' . fileparse($path);

    rmtree($path);
    make_path($path);
    return $path;
}

sub test_chdir_srcdir
{
    if (defined $ENV{srcdir}) {
        chdir $ENV{srcdir} or BAIL_OUT("cannot chdir to source directory: $!");
    }
}

sub _test_get_po_dirs
{
    if ($test_mode eq 'cpan') {
        return qw();
    } else {
        return qw(po scripts/po dselect/po man/po);
    }
}

sub _test_get_perl_dirs
{
    if ($test_mode eq 'cpan') {
        return qw(t lib);
    } else {
        return qw(t lib utils/t scripts dselect);
    }
}

sub _test_scan_files($visit_func, $dirs)
{
    my $scan_files = {
        wanted => $visit_func,
        no_chdir => 1,
    };
    find($scan_files, @{$dirs});
}

sub _test_get_files($keep_func, $dirs)
{
    my @files;
    my $visit_func = sub {
        push @files, $File::Find::name if $keep_func->($File::Find::name);
    };

    _test_scan_files($visit_func, $dirs);

    return @files;
}

sub all_po_files
{
    my $keep_po_files = sub ($file) {
        return $file =~ m{\.(?:po|pot)$};
    };

    return _test_get_files($keep_po_files, [ _test_get_po_dirs() ]);
}

sub all_shell_files(@files_todo)
{
    my %files_todo = map { $_ => 1 } @files_todo;
    my @files = qw(
        autogen
        build-aux/gen-release
        build-aux/get-vcs-id
        build-aux/get-version
        build-aux/run-script
        debian/dpkg.cron.daily
        debian/dpkg.postinst
        debian/dpkg.postrm
        debian/dselect.postrm
    );

    my $keep_shell_file = sub ($file) {
        return 0 if exists $files_todo{$file};
        return $file =~ qr{\.sh$};
    };
    my $keep_shebang_file = sub ($file) {
        return 0 if exists $files_todo{$file};

        return 0 if -z $file;
        return 0 unless -f $file;

        open my $fh, '<', $file
            or die "error: cannot read file $file: $!\n";
        my $shebang = readline $fh;
        close $fh;

        chomp $shebang;

        return $shebang =~ m{^#!/bin/sh};
    };


    push @files, _test_get_files(
        $keep_shell_file,
        [ qw(
            dselect/methods
            src
        ) ],
    );
    push @files, _test_get_files(
        $keep_shebang_file,
        [ qw(
            debian/tests
            lib/dpkg/t/data
            scripts/t
            tests
        ) ],
    );

    return @files;
}

sub all_perl_files
{
    my $keep_perl_files = sub ($file) {
        return $file =~ m{\.(?:PL|pl|pm|t)$};
    };

    return _test_get_files($keep_perl_files, [ _test_get_perl_dirs() ]);
}

sub all_perl_modules
{
    my $keep_perl_modules = sub ($file) {
        return $file =~ m{\.pm$};
    };

    return _test_get_files($keep_perl_modules, [ _test_get_perl_dirs() ]);
}

sub all_pod_modules
{
    my @modules_todo = @_;
    my %modules_todo = map { $_ => 1 } @modules_todo;
    my @modules;

    require Module::Metadata;
    my $scan_perl_modules = sub {
        my $module = $File::Find::name;

        # Only check modules, scripts are documented in man pages.
        return unless $module =~ s/\.pm$//;

        my $mod = Module::Metadata->new_from_file($File::Find::name);

        # As a first step just check public modules (version > 0.xx).
        return if $mod->version() =~ m/^0\.\d\d$/;

        $module =~ s{^\Q$File::Find::topdir\E/}{};
        $module =~ s{/}{::}g;

        return if exists $modules_todo{$module};

        push @modules, $module;
    };

    _test_scan_files($scan_perl_modules, [ _test_get_perl_dirs() ]);

    return @modules;
}

sub test_needs_author
{
    if (not $ENV{AUTHOR_TESTING}) {
        plan skip_all => 'author test';
    }
}

sub test_needs_module
{
    my ($module, @imports) = @_;
    my ($package) = caller;

    require version;
    my $version = '';
    if (@imports >= 1 and version::is_lax($imports[0])) {
        $version = shift @imports;
    }

    eval qq{
        package $package;
        use $module $version \@imports;
        1;
    } or do {
        plan skip_all => "requires module $module $version";
    }
}

sub test_needs_command
{
    my $command = shift;

    if (not can_run($command)) {
        plan skip_all => "requires command $command";
    }
}

my @openpgp_backends = (
    {
        backend => 'gpg',
        cmd => 'gpg-sq',
        cmdv => 'gpgv-sq',
    },
    {
        backend => 'gpg',
        cmd => 'gpg',
        cmdv => 'gpgv',
    },
    {
        backend => 'sq',
        cmd => 'sq',
        cmdv => 'sqv',
    },
    {
        backend => 'sop',
        cmd => 'sop',
        cmdv => 'sopv',
    },
    {
        backend => 'sop',
        cmd => 'sqop',
        cmdv => 'sqopv',
    },
    {
        backend => 'sop',
        cmd => 'rsop',
        cmdv => 'rsopv',
    },
    {
        backend => 'sop',
        cmd => 'gosop',
    },
    {
        backend => 'sop',
        cmd => 'pgpainless-cli',
    },
);

sub test_needs_openpgp_backend
{
    my @have_backends;
    foreach my $backend (@openpgp_backends) {
        my $name = $backend->{backend};
        my $cmd = $backend->{cmd} // q();
        my $cmdv = $backend->{cmdv} // q();

        my $have_cmd = $cmd eq 'none' ? 0 : can_run($cmd);
        my $have_cmdv = $cmdv eq 'none' ? 0 : can_run($cmdv);

        next unless ($have_cmd || $have_cmdv);

        my $have_backend = {
            backend => $name,
        };
        $have_backend->{cmd} = $cmd if $have_cmd;
        $have_backend->{cmdv} = $cmdv if $have_cmdv;

        push @have_backends, $have_backend;

        if ($have_cmd && $have_cmdv) {
            push @have_backends, {
                backend => $name,
                cmd => $cmd,
                cmdv => 'none',
            };
            push @have_backends, {
                backend => $name,
                cmd => 'none',
                cmdv => $cmdv,
            };
        }
    }
    if (@have_backends == 0) {
        my @cmds = grep {
            $_ ne 'none'
        } map {
            ($_->{cmd}, $_->{cmdv})
        } @openpgp_backends;
        plan skip_all => "requires >= 1 openpgp command: @cmds";
    }

    return @have_backends;
}

sub test_neutralize_checksums
{
    my $filename = shift;
    my $filenamenew = "$filename.new";

    my $cwd = getcwd();
    open my $fhnew, '>', $filenamenew or die "cannot open new $filenamenew in $cwd: $!";
    open my $fh, '<', $filename or die "cannot open $filename in $cwd: $!";
    while (<$fh>) {
        s/^ ([0-9a-f]{32,}) [1-9][0-9]* /q{ } . $1 =~ tr{0-9a-f}{0}r . q{ 0 }/e;
        print { $fhnew } $_;
    }
    close $fh or die "cannot close $filename";
    close $fhnew or die "cannot close $filenamenew";

    rename $filenamenew, $filename or die "cannot rename $filenamenew to $filename";
}

=head1 CHANGES

=head2 Version 0.xx

This is a private module.

=cut

1;
