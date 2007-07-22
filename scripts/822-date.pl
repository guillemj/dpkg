#!/usr/bin/perl --

use strict;
use warnings;

use Dpkg;

push(@INC, $dpkglibdir);
require 'dpkg-gettext.pl';
textdomain("dpkg-dev");

require 'controllib.pl';

@ARGV && die _g("Usage: 822-date")."\n";

warning(_g("This program is deprecated. Please use 'date -R' instead."));

print `date -R`;

