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

package Dpkg::Source::Archiver;

use strict;
use warnings;

use Dpkg::Source::CompressedFile;
use Dpkg::Source::Compressor;
use Dpkg::Compression;
use Dpkg::Gettext;
use Dpkg::IPC;
use Dpkg::ErrorHandling qw(error syserr warning);

use POSIX;
use File::Temp qw(tempdir);
use File::Path qw(rmtree mkpath);
use File::Basename qw(basename);

use base 'Dpkg::Source::CompressedFile';

sub create {
    my ($self, %opts) = @_;
    $opts{"options"} ||= [];
    my %fork_opts;
    # Redirect input/output appropriately
    $fork_opts{"to_handle"} = $self->open_for_write();
    $fork_opts{"from_pipe"} = \$self->{'tar_input'};
    # Call tar creation process
    $fork_opts{'exec'} = [ 'tar', '--null', '-T', '-',
			   @{$opts{"options"}}, '-cf', '-' ];
    $self->{"pid"} = fork_and_exec(%fork_opts);
    $self->{"cwd"} = getcwd();
}

sub _add_entry {
    my ($self, $file) = @_;
    error("call create first") unless $self->{"tar_input"};
    $file = $2 if ($file =~ /^\Q$self->{'cwd'}\E\/(.+)$/); # Relative names
    print({ $self->{'tar_input'} } "$file\0") ||
	    syserr(_g("write on tar input"));
}

sub add_file {
    my ($self, $file) = @_;
    error("add_file() doesn't handle directories") if not -l $file and -d _;
    $self->_add_entry($file);
}

sub add_directory {
    my ($self, $file) = @_;
    error("add_directory() only handles directories") unless not -l $file and -d _;
    $self->_add_entry($file);
}

sub close {
    my ($self) = @_;
    close($self->{'tar_input'}) or syserr(_g("close on tar input"));
    wait_child($self->{'pid'}, cmdline => 'tar -cf -');
    delete $self->{'pid'};
    delete $self->{'tar_input'};
    delete $self->{'cwd'};
    $self->cleanup_after_open();
}

sub extract {
    my ($self, $dest, %opts) = @_;
    $opts{"options"} ||= [];
    my %fork_opts = (wait_child => 1);

    # Prepare destination
    my $template = basename($self->get_filename()) .  ".tmp-extract.XXXXX";
    my $tmp = tempdir($template, DIR => getcwd(), CLEANUP => 1);
    $fork_opts{"chdir"} = $tmp;

    # Prepare stuff that handles the input of tar
    $fork_opts{"from_handle"} = $self->open_for_read();

    # Call tar extraction process
    $fork_opts{'exec'} = [ 'tar', '--no-same-owner', '--no-same-permissions',
                           @{$opts{"options"}}, '-xkf', '-' ];
    fork_and_exec(%fork_opts);
    $self->cleanup_after_open();

    # Fix permissions on extracted files...
    my ($mode, $modes_set, $i, $j);
    # Unfortunately tar insists on applying our umask _to the original
    # permissions_ rather than mostly-ignoring the original
    # permissions.  We fix it up with chmod -R (which saves us some
    # work) but we have to construct a u+/- string which is a bit
    # of a palaver.  (Numeric doesn't work because we need [ugo]+X
    # and [ugo]=<stuff> doesn't work because that unsets sgid on dirs.)
    #
    # We still need --no-same-permissions because otherwise tar might
    # extract directory setgid (which we want inherited, not
    # extracted); we need --no-same-owner because putting the owner
    # back is tedious - in particular, correct group ownership would
    # have to be calculated using mount options and other madness.
    #
    # It would be nice if tar could do it right, or if pax could cope
    # with GNU format tarfiles with long filenames.
    #
    $mode = 0777 & ~umask;
    for ($i = 0; $i < 9; $i += 3) {
	$modes_set .= ',' if $i;
	$modes_set .= qw(u g o)[$i/3];
	for ($j = 0; $j < 3; $j++) {
	    $modes_set .= $mode & (0400 >> ($i+$j)) ? '+' : '-';
	    $modes_set .= qw(r w X)[$j];
	}
    }
    system('chmod', '-R', $modes_set, '--', $tmp);
    subprocerr("chmod -R $modes_set $tmp") if $?;

    # Rename extracted directory
    opendir(D, $tmp) || syserr(_g("Unable to open dir %s"), $tmp);
    my @entries = grep { $_ ne "." && $_ ne ".." } readdir(D);
    closedir(D);
    my $done = 0;
    rmtree($dest) if -e $dest;
    if (scalar(@entries) == 1 && -d "$tmp/$entries[0]") {
	rename("$tmp/$entries[0]", $dest) ||
		syserr(_g("Unable to rename %s to %s"),
		       "$tmp/$entries[0]", $dest);
    } else {
	rename($tmp, $dest) ||
		syserr(_g("Unable to rename %s to %s"), $tmp, $dest);
    }
    rmtree($tmp);
}

1;
