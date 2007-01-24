#!/usr/bin/perl --

use strict;
use warnings;

my $dpkglibdir = "."; # This line modified by Makefile
push(@INC, $dpkglibdir);
require 'dpkg-gettext.pl';
textdomain("dpkg-dev");

require 'controllib.pl';

@ARGV && die _g("Usage: 822-date")."\n";

&warn(_g("This program is deprecated. Please use 'date -R' instead."));

print `date -R`;

