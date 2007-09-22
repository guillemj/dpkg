package Dpkg;

use strict;
use warnings;

use base qw(Exporter);
our @EXPORT = qw($version $progname $admindir $dpkglibdir $pkgdatadir);

our ($progname) = $0 =~ m#(?:.*/)?([^/]*)#;

# The following lines are automatically fixed at install time
our $version = "1.14";
our $admindir = "/var/lib/dpkg";
our $dpkglibdir = ".";
our $pkgdatadir = "..";

1;
