# Copyright 2007 Raphaël Hertzog <hertzog@debian.org>

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

package Dpkg::Path;

use strict;
use warnings;

use Exporter;
use File::Spec;
use Cwd qw(realpath);
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(get_pkg_root_dir relative_to_pkg_root
		    guess_pkg_root_dir check_files_are_the_same
		    resolve_symlink canonpath);

=head1 NAME

Dpkg::Path - some common path handling functions

=head1 DESCRIPTION

It provides some functions to handle various path.

=head1 METHODS

=over 8

=item get_pkg_root_dir($file)

This function will scan upwards the hierarchy of directory to find out
the directory which contains the "DEBIAN" sub-directory and it will return
its path. This directory is the root directory of a package being built.

If no DEBIAN subdirectory is found, it will return undef.

=cut

sub get_pkg_root_dir($) {
    my $file = shift;
    $file =~ s{/+$}{};
    $file =~ s{/+[^/]+$}{} if not -d $file;
    while ($file) {
	return $file if -d "$file/DEBIAN";
	last if $file !~ m{/};
	$file =~ s{/+[^/]+$}{};
    }
    return undef;
}

=item relative_to_pkg_root($file)

Returns the filename relative to get_pkg_root_dir($file).

=cut

sub relative_to_pkg_root($) {
    my $file = shift;
    my $pkg_root = get_pkg_root_dir($file);
    if (defined $pkg_root) {
	$pkg_root .= "/";
	return $file if ($file =~ s/^\Q$pkg_root\E//);
    }
    return undef;
}

=item guess_pkg_root_dir($file)

This function tries to guess the root directory of the package build tree.
It will first use get_pkg_root_dir(), but it will fallback to a more
imprecise check: namely it will use the parent directory that is a
sub-directory of the debian directory.

It can still return undef if a file outside of the debian sub-directory is
provided.

=cut
sub guess_pkg_root_dir($) {
    my $file = shift;
    my $root = get_pkg_root_dir($file);
    return $root if defined $root;

    $file =~ s{/+$}{};
    $file =~ s{/+[^/]+$}{} if not -d $file;
    my $parent = $file;
    while ($file) {
	$parent =~ s{/+[^/]+$}{};
	last if not -d $parent;
	return $file if check_files_are_the_same("debian", $parent);
	$file = $parent;
	last if $file !~ m{/};
    }
    return undef;
}

=item check_files_are_the_same($file1, $file2, $resolve_symlink)

This function verifies that both files are the same by checking that the device
numbers and the inode numbers returned by stat()/lstat() are the same. If
$resolve_symlink is true then stat() is used, otherwise lstat() is used.

=cut
sub check_files_are_the_same($$;$) {
    my ($file1, $file2, $resolve_symlink) = @_;
    return 0 if ((! -e $file1) || (! -e $file2));
    my (@stat1, @stat2);
    if ($resolve_symlink) {
        @stat1 = stat($file1);
        @stat2 = stat($file2);
    } else {
        @stat1 = lstat($file1);
        @stat2 = lstat($file2);
    }
    my $result = ($stat1[0] == $stat2[0]) && ($stat1[1] == $stat2[1]);
    return $result;
}


=item canonpath($file)

This function returns a cleaned path. It simplifies double //, and remove
/./ and /../ intelligently. For /../ it simplifies the path only if the
previous element is not a symlink. Thus it should only be used on real
filenames.

=cut
sub canonpath($) {
    my $path = shift;
    $path = File::Spec->canonpath($path);
    my ($v, $dirs, $file) = File::Spec->splitpath($path);
    my @dirs = File::Spec->splitdir($dirs);
    my @new;
    foreach my $d (@dirs) {
	if ($d eq '..') {
	    if (scalar(@new) > 0 and $new[-1] ne "..") {
		next if $new[-1] eq ""; # Root directory has no parent
		my $parent = File::Spec->catpath($v,
			File::Spec->catdir(@new), '');
		if (not -l $parent) {
		    pop @new;
		} else {
		    push @new, $d;
		}
	    } else {
		push @new, $d;
	    }
	} else {
	    push @new, $d;
	}
    }
    return File::Spec->catpath($v, File::Spec->catdir(@new), $file);
}

=item $newpath = resolve_symlink($symlink)

Return the filename of the file pointed by the symlink. The new name is
canonicalized by canonpath().

=cut
sub resolve_symlink($) {
    my $symlink = shift;
    my $content = readlink($symlink);
    return undef unless defined $content;
    if (File::Spec->file_name_is_absolute($content)) {
	return canonpath($content);
    } else {
	my ($link_v, $link_d, $link_f) = File::Spec->splitpath($symlink);
	my ($cont_v, $cont_d, $cont_f) = File::Spec->splitpath($content);
	my $new = File::Spec->catpath($link_v, $link_d . "/" . $cont_d, $cont_f);
	return canonpath($new);
    }
}

=back

=head1 AUTHOR

Raphael Hertzog <hertzog@debian.org>.

=cut

1;
