# Copyright © 2007 Raphaël Hertzog <hertzog@debian.org>
# Copyright © 2007-2008, 2012-2015 Guillem Jover <guillem@debian.org>
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

package Dpkg::Shlibs;

use strict;
use warnings;
use feature qw(state);

our $VERSION = '0.02';
our @EXPORT_OK = qw(
    blank_library_paths
    setup_library_paths
    get_library_paths
    add_library_dir
    find_library
);

use Exporter qw(import);
use File::Spec;

use Dpkg::Gettext;
use Dpkg::ErrorHandling;
use Dpkg::Shlibs::Objdump;
use Dpkg::Util qw(:list);
use Dpkg::Path qw(resolve_symlink canonpath);
use Dpkg::Arch qw(debarch_to_gnutriplet get_build_arch get_host_arch
                  gnutriplet_to_multiarch debarch_to_multiarch);

use constant DEFAULT_LIBRARY_PATH =>
    qw(/lib /usr/lib);
# XXX: Deprecated multilib paths.
use constant DEFAULT_MULTILIB_PATH =>
    qw(/lib32 /usr/lib32 /lib64 /usr/lib64);

my @librarypaths;
my $librarypaths_init;

sub parse_ldso_conf {
    my $file = shift;
    state %visited;
    local $_;

    open my $fh, '<', $file or syserr(g_('cannot open %s'), $file);
    $visited{$file}++;
    while (<$fh>) {
	next if /^\s*$/;
	chomp;
	s{/+$}{};
	if (/^include\s+(\S.*\S)\s*$/) {
	    foreach my $include (glob($1)) {
		parse_ldso_conf($include) if -e $include
		    && !$visited{$include};
	    }
	} elsif (m{^\s*/}) {
	    s/^\s+//;
	    my $libdir = $_;
	    if (none { $_ eq $libdir } @librarypaths) {
		push @librarypaths, $libdir;
	    }
	}
    }
    close $fh;
}

sub blank_library_paths {
    @librarypaths = ();
    $librarypaths_init = 1;
}

sub setup_library_paths {
    @librarypaths = ();

    # XXX: Deprecated. Update library paths with LD_LIBRARY_PATH.
    if ($ENV{LD_LIBRARY_PATH}) {
        foreach my $path (split /:/, $ENV{LD_LIBRARY_PATH}) {
            $path =~ s{/+$}{};
            push @librarypaths, $path;
        }
    }

    # Adjust set of directories to consider when we're in a situation of a
    # cross-build or a build of a cross-compiler.
    my $multiarch;

    # Detect cross compiler builds.
    if ($ENV{DEB_TARGET_GNU_TYPE} and
        ($ENV{DEB_TARGET_GNU_TYPE} ne $ENV{DEB_BUILD_GNU_TYPE}))
    {
        $multiarch = gnutriplet_to_multiarch($ENV{DEB_TARGET_GNU_TYPE});
    }
    # Host for normal cross builds.
    if (get_build_arch() ne get_host_arch()) {
        $multiarch = debarch_to_multiarch(get_host_arch());
    }
    # Define list of directories containing crossbuilt libraries.
    if ($multiarch) {
        push @librarypaths, "/lib/$multiarch", "/usr/lib/$multiarch";
    }

    push @librarypaths, DEFAULT_LIBRARY_PATH;

    # Update library paths with ld.so config.
    parse_ldso_conf('/etc/ld.so.conf') if -e '/etc/ld.so.conf';

    push @librarypaths, DEFAULT_MULTILIB_PATH;

    $librarypaths_init = 1;
}

sub add_library_dir {
    my $dir = shift;

    setup_library_paths() if not $librarypaths_init;

    unshift @librarypaths, $dir;
}

sub get_library_paths {
    setup_library_paths() if not $librarypaths_init;

    return @librarypaths;
}

# find_library ($soname, \@rpath, $format, $root)
sub find_library {
    my ($lib, $rpath, $format, $root) = @_;

    setup_library_paths() if not $librarypaths_init;

    $root //= '';
    $root =~ s{/+$}{};
    my @rpath = @{$rpath};
    foreach my $dir (@rpath, @librarypaths) {
	my $checkdir = "$root$dir";
	# If the directory checked is a symlink, check if it doesn't
	# resolve to another public directory (which is then the canonical
	# directory to use instead of this one). Typical example
	# is /usr/lib64 -> /usr/lib on amd64.
	if (-l $checkdir) {
	    my $newdir = resolve_symlink($checkdir);
	    if (any { "$root$_" eq "$newdir" } (@rpath, @librarypaths)) {
		$checkdir = $newdir;
	    }
	}
	if (-e "$checkdir/$lib") {
	    my $libformat = Dpkg::Shlibs::Objdump::get_format("$checkdir/$lib");
	    if ($format eq $libformat) {
		return canonpath("$checkdir/$lib");
	    }
	}
    }
    return;
}

1;
