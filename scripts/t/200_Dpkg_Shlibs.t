# -*- mode: cperl;-*-

use Test::More tests => 4;

use strict;
use warnings;

use_ok('Dpkg::Shlibs');

my @save_paths = @Dpkg::Shlibs::librarypaths;
@Dpkg::Shlibs::librarypaths = ();

Dpkg::Shlibs::parse_ldso_conf("t/200_Dpkg_Shlibs/ld.so.conf");

use Data::Dumper;
is_deeply([qw(/nonexistant32 /nonexistant/lib64
	     /usr/local/lib /nonexistant/lib128 )],
	  \@Dpkg::Shlibs::librarypaths, "parsed library paths");

use_ok('Dpkg::Shlibs::Objdump');
use_ok('Dpkg::Shlibs::SymbolFile');
