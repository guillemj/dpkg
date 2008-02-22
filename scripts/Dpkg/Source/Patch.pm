# Copyright 2008 Raphaël Hertzog <hertzog@debian.org>

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

package Dpkg::Source::Patch;

use strict;
use warnings;

use Dpkg;
use Dpkg::Source::CompressedFile;
use Dpkg::Source::Compressor;
use Dpkg::Compression;
use Dpkg::Gettext;
use Dpkg::IPC;
use Dpkg::ErrorHandling qw(error syserr warning subprocerr);

use POSIX;
use File::Find;
use File::Basename;
use File::Spec;
use Fcntl ':mode';

use base 'Dpkg::Source::CompressedFile';

sub create {
    my ($self, %opts) = @_;
    $self->{'handle'} = $self->open_for_write();
    $self->{'errors'} = 0;
    if ($opts{'old'} and $opts{'new'}) {
        $opts{'old'} = "/dev/null" unless -e $opts{'old'};
        $opts{'new'} = "/dev/null" unless -e $opts{'new'};
        if (-d $opts{'old'} and -d $opts{'new'}) {
            $self->add_diff_directory($opts{'old'}, $opts{'new'}, %opts);
        } elsif (-f $opts{'old'} and -f $opts{'new'}) {
            $self->add_diff_file($opts{'old'}, $opts{'new'}, %opts);
        } else {
            $self->_fail_not_same_type($opts{'old'}, $opts{'new'});
        }
        $self->close() unless $opts{"noclose"};
    }
}

sub add_diff_file {
    my ($self, $old, $new, %opts) = @_;
    # Default diff options
    my @options;
    if ($opts{"options"}) {
        push @options, @{$opts{"options"}};
    } else {
        push @options, '-p';
    }
    # Add labels
    if ($opts{"label_old"} and $opts{"label_new"}) {
        # Space in filenames need special treatment
        $opts{"label_old"} .= "\t" if $opts{"label_old"} =~ / /;
        $opts{"label_new"} .= "\t" if $opts{"label_new"} =~ / /;
        push @options, "-L", $opts{"label_old"},
                       "-L", $opts{"label_new"};
    }
    # Generate diff
    my $diffgen;
    my $diff_pid = fork_and_exec(
        'exec' => [ 'diff', '-u', @options, '--', $old, $new ],
        'env' => { LC_ALL => 'C', LANG => 'C', TZ => 'UTC0' },
        'to_pipe' => \$diffgen
    );
    # Check diff and write it in patch file
    my $difflinefound = 0;
    while (<$diffgen>) {
        if (m/^binary/i) {
            $self->_fail_with_msg($new,_g("binary file contents changed"));
            last;
        } elsif (m/^[-+\@ ]/) {
            $difflinefound++;
        } elsif (m/^\\ No newline at end of file$/) {
            warning(_g("file %s has no final newline (either " .
                       "original or modified version)"), $new);
        } else {
            chomp;
            internerr(_g("unknown line from diff -u on %s: `%s'"),
                      $new, $_);
        }
        print({ $self->{'handle'} } $_) || syserr(_g("failed to write"));
    }
    close($diffgen) or syserr("close on diff pipe");
    wait_child($diff_pid, nocheck => 1,
               cmdline => "diff -u @options -- $old $new");
    # Verify diff process ended successfully
    # Exit code of diff: 0 => no difference, 1 => diff ok, 2 => error
    my $exit = WEXITSTATUS($?);
    unless (WIFEXITED($?) && ($exit == 0 || $exit == 1)) {
        subprocerr(_g("diff on %s"), $new);
    }
    return $exit;
}

sub add_diff_directory {
    my ($self, $old, $new, %opts) = @_;
    # TODO: make this function more configurable
    # - offer diff generation for removed files
    # - offer to disable some checks
    my $basedir = $opts{"basedirname"} || basename($new);
    my $diff_ignore;
    if ($opts{"diff_ignore_func"}) {
        $diff_ignore = $opts{"diff_ignore_func"};
    } elsif ($opts{"diff_ignore_regexp"}) {
        $diff_ignore = sub { return $_[0] =~ /$opts{"diff_ignore_regexp"}/o };
    } else {
        $diff_ignore = sub { return 0 };
    }

    my %files_in_new;
    my $scan_new = sub {
        my $fn = File::Spec->abs2rel($_, $new);
        next if &$diff_ignore($fn);
        $files_in_new{$fn} = 1;
        lstat("$new/$fn") || syserr(_g("cannot stat file %s"), "$new/$fn");
        my $mode = S_IMODE((lstat(_))[2]);
        my $size = (lstat(_))[7];
        if (-l _) {
            unless (-l "$old/$fn") {
                $self->_fail_not_same_type("$old/$fn", "$new/$fn");
                return;
            }
            defined(my $n = readlink("$new/$fn")) ||
                syserr(_g("cannot read link %s"), "$new/$fn");
            defined(my $n2 = readlink("$old/$fn")) ||
                syserr(_g("cannot read link %s"), "$old/$fn");
            unless ($n eq $n2) {
                $self->_fail_not_same_type("$old/$fn", "$new/$fn");
            }
        } elsif (-f _) {
            my $old_file = "$old/$fn";
            if (not lstat("$old/$fn")) {
                $! == ENOENT ||
                    syserr(_g("cannot stat file %s"), "$old/$fn");
                $old_file = '/dev/null';
                if (not $size) {
                    warning(_g("newly created empty file '%s' will not " .
                               "be represented in diff"), $fn);
                } else {
                    if ($mode & (S_IXUSR | S_IXGRP | S_IXOTH)) {
                        warning(_g("executable mode %04o of '%s' will " .
                                   "not be represented in diff"), $mode, $fn)
                            unless $fn eq 'debian/rules';
                    }
                    if ($mode & (S_ISUID | S_ISGID | S_ISVTX)) {
                        warning(_g("special mode %04o of '%s' will not " .
                                   "be represented in diff"), $mode, $fn);
                    }
                }
            } elsif (not -f _) {
                $self->_fail_not_same_type("$old/$fn", "$new/$fn");
                return;
            }

            $self->add_diff_file($old_file, "$new/$fn",
                label_old => "$basedir.orig/$fn",
                label_new => "$basedir/$fn",
                %opts);
        } elsif (-p _) {
            unless (-p "$old/$fn") {
                $self->_fail_not_same_type("$old/$fn", "$new/$fn");
            }
        } elsif (-b _ || -c _ || -S _) {
            $self->_fail_with_msg("$new/$fn",
                _g("device or socket is not allowed"));
        } elsif (-d _) {
            if (not lstat("$old/$fn")) {
                $! == ENOENT ||
                    syserr(_g("cannot stat file %s"), "$old/$fn");
            } elsif (not -d _) {
                $self->_fail_not_same_type("$old/$fn", "$new/$fn");
            }
        } else {
            $self->_fail_with_msg("$new/$fn", _g("unknown file type"));
        }
    };
    my $scan_old = sub {
        my $fn = File::Spec->abs2rel($_, $old);
        return if &$diff_ignore($fn);
        return if $files_in_new{$fn};
        lstat("$new/$fn") || syserr(_g("cannot stat file %s"), "$old/$fn");
        if (-f _) {
            warning(_g("ignoring deletion of file %s"), $fn);
        } elsif (-d _) {
            warning(_g("ignoring deletion of directory %s"), $fn);
        } elsif (-l _) {
            warning(_g("ignoring deletion of symlink %s"), $fn);
        } else {
            $self->_fail_not_same_type("$old/$fn", "$new/$fn");
        }
    };

    find({ wanted => $scan_new, no_chdir => 1 }, $new);
    find({ wanted => $scan_old, no_chdir => 1 }, $old);
}

sub close {
    my ($self) = @_;
    close($self->{'handle'}) ||
            syserr(_g("cannot close %s"), $self->get_filename());
    delete $self->{'handle'};
    $self->cleanup_after_open();
    return not $self->{'errors'};
}

sub _fail_with_msg {
    my ($self, $file, $msg) = @_;
    printf(STDERR _g("%s: cannot represent change to %s: %s")."\n",
                  $progname, $file, $msg);
    $self->{'errors'}++;
}
sub _fail_not_same_type {
    my ($self, $old, $new) = @_;
    my $old_type = get_type($old);
    my $new_type = get_type($new);
    printf(STDERR _g("%s: cannot represent change to %s:\n".
                     "%s:  new version is %s\n".
                     "%s:  old version is %s\n"),
                  $progname, $new, $progname, $old_type, $progname, $new_type);
    $self->{'errors'}++;
}

sub apply {
    my ($self, $destdir, %opts) = @_;
    # TODO: check diff
    # TODO: create missing directories
    $opts{"options"} ||= [ '-s', '-t', '-F', '0', '-N', '-p1', '-u',
            '-V', 'never', '-g0', '-b', '-z', '.dpkg-orig'];
    my $diff_handle = $self->open_for_read();
    fork_and_exec(
	'exec' => [ 'patch', @{$opts{"options"}} ],
	'chdir' => $destdir,
	'env' => { LC_ALL => 'C', LANG => 'C' },
	'wait_child' => 1,
	'from_handle' => $diff_handle
    );
    $self->cleanup_after_open();
}

# Helper functions
sub get_type {
    my $file = shift;
    if (not lstat($file)) {
        return _g("nonexistent") if $! == ENOENT;
        syserr(_g("cannot stat %s"), $file);
    } else {
        -f _ && return _g("plain file");
        -d _ && return _g("directory");
        -l _ && return sprintf(_g("symlink to %"), readlink($file));
        -b _ && return _g("block device");
        -c _ && return _g("character device");
        -p _ && return _g("named pipe");
        -S _ && return _g("named socket");
    }
}

1;
# vim: set et sw=4 ts=8
