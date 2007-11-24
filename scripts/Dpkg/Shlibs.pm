# Copyright (C) 2007  Raphael Hertzog

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

package Dpkg::Shlibs;

use strict;
use warnings;

use base qw(Exporter);
our @EXPORT_OK = qw(@librarypaths find_library);

use Dpkg::Gettext;
use Dpkg::ErrorHandling qw(syserr);
use Dpkg::Shlibs::Objdump;

use constant DEFAULT_LIBRARY_PATH =>
    qw(/lib /usr/lib /lib32 /usr/lib32 /lib64 /usr/lib64
       /emul/ia32-linux/lib /emul/ia32-linux/usr/lib);
our @librarypaths = (DEFAULT_LIBRARY_PATH);

# Update library paths with LD_LIBRARY_PATH
if ($ENV{LD_LIBRARY_PATH}) {
    foreach my $path (reverse split( /:/, $ENV{LD_LIBRARY_PATH} )) {
	$path =~ s{/+$}{};
	unshift @librarypaths, $path;
    }
}

# Update library paths with ld.so config
parse_ldso_conf("/etc/ld.so.conf") if -e "/etc/ld.so.conf";

my %visited;
sub parse_ldso_conf {
    my $file = shift;
    open my $fh, "<", $file
	or syserr(sprintf(_g("couldn't open %s"), $file));
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
	    unless (scalar grep { $_ eq $libdir } @librarypaths) {
		push @librarypaths, $libdir;
	    }
	}
    }
    close $fh or syserr(sprintf(_g("couldn't close %s"), $file));;
}

# find_library ($soname, \@rpath, $format, $root)
sub find_library {
    my ($lib, $rpath, $format, $root) = @_;
    $root = "" if not defined($root);
    $root =~ s{/+$}{};
    my @rpath = @{$rpath};
    foreach my $dir (@rpath, @librarypaths) {
	if (-e "$root$dir/$lib") {
	    my $libformat = Dpkg::Shlibs::Objdump::get_format("$root$dir/$lib");
	    if ($format eq $libformat) {
		return "$root$dir/$lib";
	    }
	}
    }
    return undef;
}

1;
