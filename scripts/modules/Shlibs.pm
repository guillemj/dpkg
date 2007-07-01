#!/usr/bin/perl -w

use strict;
use warnings;

require 'dpkg-gettext.pl';

use IO::File;

use Exporter 'import';
our @EXPORT_OK = qw(@librarypaths find_library);

our @librarypaths = qw(/lib /usr/lib /lib32 /usr/lib32 /lib64 /usr/lib64
                       /emul/ia32-linux/lib /emul/ia32-linux/usr/lib);

# Update library paths with LD_LIBRARY_PATH
if ($ENV{LD_LIBRARY_PATH}) {
    foreach my $path (reverse split( /:/, $ENV{LD_LIBRARY_PATH} )) {
        $path =~ s{/+$}{};
        unless (scalar grep { $_ eq $path } @librarypaths) {
            unshift @librarypaths, $path;
        }
    }
}

# Update library paths with ld.so config
parse_ldso_conf("/etc/ld.so.conf") if -e "/etc/ld.so.conf";

sub parse_ldso_conf {
    my $file = shift;
    my $fh = new IO::File;
    $fh->open("< $file")
	or main::syserr(sprintf(_g("couldn't open %s: %s"), $file, $!));
    while (<$fh>) {
	next if /^\s*$/;
        chomp;
	s{/+$}{};
	if (/^include\s+(\S.*\S)\s*$/) {
	    foreach my $include (glob($1)) {
		parse_ldso_conf($include) if -e $include;
	    }
	} elsif (m{^\s*/}) {
	    s/^\s+//;
	    my $libdir = $_;
	    unless (scalar grep { $_ eq $libdir } @librarypaths) {
		push @librarypaths, $libdir;
	    }
	}
    }
    $fh->close;
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

