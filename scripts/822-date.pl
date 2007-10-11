#!/usr/bin/perl --

use strict;
use warnings;

use Dpkg;
use Dpkg::Gettext;
use Dpkg::ErrorHandling qw(warning);

textdomain("dpkg-dev");

@ARGV && die _g("Usage: 822-date")."\n";

warning(_g("This program is deprecated. Please use 'date -R' instead."));

print `date -R`;

