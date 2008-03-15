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

package Dpkg::Source::Package::V3_0::quilt;

use strict;
use warnings;

# Based on wig&pen implementation
use base 'Dpkg::Source::Package::V2_0';

use Dpkg;
use Dpkg::Gettext;
use Dpkg::ErrorHandling qw(error syserr warning usageerr subprocerr info);
use Dpkg::Source::Patch;
use Dpkg::IPC;

use File::Basename;
use File::Spec;

sub get_autopatch_name {
    my ($self) = @_;
    return "debian-changes-" . $self->{'fields'}{'Version'} . ".diff";
}

sub get_series_file {
    my ($self, $dir) = @_;
    my $pd = File::Spec->catdir($dir, "debian", "patches");
    # TODO: replace "debian" with the current distro name once we have a
    # way to figure it out
    foreach (File::Spec->catfile($pd, "debian.series"),
             File::Spec->catfile($pd, "series")) {
        return $_ if -e $_;
    }
    return undef;
}

sub get_patches {
    my ($self, $dir, $skip_auto) = @_;
    my @patches;
    my $auto_patch = $self->get_autopatch_name();
    my $series = $self->get_series_file($dir);
    if (defined($series)) {
        open(SERIES, "<" , $series) || syserr(_g("cannot read %s"), $series);
        while(defined($_ = <SERIES>)) {
            chomp; s/^\s+//; s/\s+$//; # Strip leading/trailing spaces
            s/\s#.*$//; # Strip trailing comment
            next unless $_;
            next if $skip_auto and $_ eq $auto_patch;
            push @patches, $_;
        }
        close(SERIES);
    }
    return @patches;
}

sub apply_patches {
    my ($self, $dir, $skip_auto) = @_;

    # Check if quilt is available
    my $have_quilt = (-x "/usr/bin/quilt") ? 1 : 0;

    # Update debian/patches/series symlink if needed to allow quilt usage
    my $series = $self->get_series_file($dir);
    return unless $series; # No series, no patches
    my $basename = basename($series);
    if ($basename ne "series") {
        my $dest = File::Spec->catfile($dir, "debian", "patches", "series");
        unlink($dest) if -l $dest;
        unless (-f _) { # Don't overwrite real files
            symlink($basename, $dest) ||
                syserr(_g("can't create symlink %s"), $dest);
        }
    }

    # Apply patches
    my $now = time();
    foreach my $patch ($self->get_patches($dir, $skip_auto)) {
        my $path = File::Spec->catfile($dir, "debian", "patches", $patch);
        my $patch_obj = Dpkg::Source::Patch->new(filename => $path);
        if ($have_quilt) {
            info(_g("applying %s with quilt"), $patch) unless $skip_auto;
            my $analysis = $patch_obj->analyze($dir);
            foreach my $dir (keys %{$analysis->{'dirtocreate'}}) {
                eval { mkpath($dir); };
                syserr(_g("cannot create directory %s"), $dir) if $@;
            }
            my %opts = (
                env => { QUILT_PATCHES => 'debian/patches' },
                delete_env => [ 'QUILT_PATCH_OPTS' ],
                'chdir' => $dir,
                'exec' => [ 'quilt', '--quiltrc', '/dev/null', 'push', $patch ],
                wait_child => 1,
                to_file => '/dev/null',
            );
            fork_and_exec(%opts);
            foreach my $fn (keys %{$analysis->{'filepatched'}}) {
                utime($now, $now, $fn) ||
                    syserr(_g("cannot change timestamp for %s"), $fn);
            }
        } else {
            info(_g("applying %s"), $patch) unless $skip_auto;
            $patch_obj->apply($dir, timestamp => $now,
                    force_timestamp => 1, create_dirs => 1,
                    add_options => [ '-E' ]);
        }
    }
}

sub prepare_build {
    my ($self, $dir) = @_;
    # Skip .pc directories of quilt by default and ignore difference
    # on debian/patches/series symlinks
    my $func = sub {
        return 1 if $_[0] =~ m{^debian/patches/series$} and -l $_[0];
        return 1 if $_[0] =~ /^.pc(\/|$)/;
        return 1 if $_[0] =~ /$self->{'options'}{'diff_ignore_regexp'}/;
        return 0;
    };
    $self->{'diff_options'} = {
        diff_ignore_func => $func
    };
}

sub register_autopatch {
    my ($self, $dir) = @_;
    my $auto_patch = $self->get_autopatch_name();
    my $has_patch = (grep { $_ eq $auto_patch } $self->get_patches($dir)) ? 1 : 0;
    my $series = $self->get_series_file($dir);
    $series ||= File::Spec->catfile($dir, "debian", "patches", "series");
    if (-e "$dir/debian/patches/$auto_patch") {
        # Add auto_patch to series file
        if (not $has_patch) {
            open(SERIES, ">>", $series) || syserr(_g("cannot write %s"), $series);
            print SERIES "$auto_patch\n";
            close(SERIES);
        }
    } else {
        # Remove auto_patch from series
        if ($has_patch) {
            open(SERIES, "<", $series) || syserr(_g("cannot read %s"), $series);
            my @lines = <SERIES>;
            close(SERIES);
            open(SERIES, ">", $series) || syserr(_g("cannot write %s"), $series);
            print(SERIES $_) foreach grep { not /^\Q$auto_patch\E\s*$/ } @lines;
            close(SERIES);
        }
    }
}

# vim:et:sw=4:ts=8
1;
