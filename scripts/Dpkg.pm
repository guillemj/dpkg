package Dpkg;

use strict;
use warnings;

use base qw(Exporter);
our @EXPORT = qw($version $progname $admindir $dpkglibdir $pkgdatadir);
our %EXPORT_TAGS = ( 'compression' =>
		     [ qw(@comp_supported %comp_supported %comp_ext $comp_regex) ] );
our @EXPORT_OK = @{$EXPORT_TAGS{compression}};

our ($progname) = $0 =~ m#(?:.*/)?([^/]*)#;

# The following lines are automatically fixed at install time
our $version = "1.14";
our $admindir = "/var/lib/dpkg";
our $dpkglibdir = ".";
our $pkgdatadir = "..";

# Compression
our @comp_supported = qw(gzip bzip2 lzma);
our %comp_supported = map { $_ => 1 } @comp_supported;
our %comp_ext = ( gzip => 'gz', bzip2 => 'bz2', lzma => 'lzma' );
our $comp_regex = '(?:gz|bz2|lzma)';

1;
