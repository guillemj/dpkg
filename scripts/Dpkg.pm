package Dpkg;

use strict;
use warnings;

# This module is the only one provided by dpkg and not dpkg-dev
#
# Don't add things here if you don't need them in dpkg itself.
# If you do, and also use the new stuff in dpkg-dev, you'll have to bump
# the dependency of dpkg-dev on dpkg.

use base qw(Exporter);
our @EXPORT = qw($version $progname $admindir $dpkglibdir $pkgdatadir);

our ($progname) = $0 =~ m#(?:.*/)?([^/]*)#;

# The following lines are automatically fixed at install time
our $version = "1.14";
our $admindir = "/var/lib/dpkg";
our $dpkglibdir = ".";
our $pkgdatadir = "..";
$pkgdatadir = $ENV{DPKG_DATADIR} if defined $ENV{DPKG_DATADIR};

1;
