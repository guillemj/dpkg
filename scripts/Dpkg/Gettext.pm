#!/usr/bin/perl -w
# Copied from /usr/share/perl5/Debconf/Gettext.pm

package Dpkg::Gettext;

use strict;
use warnings;

BEGIN {
	eval 'use Locale::gettext';
	if ($@) {
		eval q{
			sub _g {
				return shift;
			}
			sub textdomain {
			}
			sub ngettext {
				if ($_[2] == 1) {
					return $_[0];
				} else {
					return $_[1];
				}
			}
		};
	} else {
		eval q{
			sub _g {
				return gettext(shift);
			}
		};
	}
}

use base qw(Exporter);
our @EXPORT=qw(_g textdomain ngettext);

1;
