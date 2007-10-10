# -*- mode: cperl;-*-

use Test::More;

use warnings;
use strict;

# Default cmp '>'
my @versions = ({a      => '1.0-1',
		 b      => '2.0-2',
		 result => -1,
		 relation => 'lt',
		},
		{a      => '2.2~rc-4',
		 b      => '2.2-1',
		 result => -1,
		 relation => 'lt',
		},
		{a      => '2.2-1',
		 b      => '2.2~rc-4',
		 result => 1,
		 relation => 'gt',
		},
		{a      => '1.0000-1',
		 b      => '1.0-1',
		 result => 0,
		 relation => 'eq',
		},
		{a      => '1.0000-1',
		 b      => '1.0-1',
		 result => 0,
		 relation => 'ge',
		},
		{a      => '1',
		 b      => '0:1',
		 result => 0,
		 relation => 'eq',
		},
		{a      => '2:2.5',
		 b      => '1:7.5',
		 result => 1,
		 relation => 'gt',
		},
	       );
my @test_failure = ({a      => '1.0-1',
		     b      => '2.0-2',
		     relation => 'gt',
		    },
		    {a      => '2.2~rc-4',
		     b      => '2.2-1',
		     relation => 'eq',
		    },
		   );

plan tests => @versions * 3 + @test_failure * 2 + 1;

sub dpkg_vercmp{
     my ($a,$b,$cmp) = @_;
     $cmp = 'gt' if not defined $cmp;
     return system('dpkg','--compare-versions',$a,$cmp,$b) == 0;
}


use_ok('Dpkg::Version');

for my $version_cmp (@versions) {
     ok(Dpkg::Version::vercmp($$version_cmp{a},$$version_cmp{b}) == $$version_cmp{result},
	"vercmp: Version $$version_cmp{a} $$version_cmp{relation} $$version_cmp{b} ok");
     ok(Dpkg::Version::compare_versions($$version_cmp{a},$$version_cmp{relation},$$version_cmp{b}),
       "compare_versions: Version $$version_cmp{a} $$version_cmp{relation} $$version_cmp{b} ok");
     ok(dpkg_vercmp($$version_cmp{a},$$version_cmp{b},$$version_cmp{relation}),
	"Dpkg concures: Version $$version_cmp{a} $$version_cmp{relation} $$version_cmp{b}");
}

for my $version_cmp (@test_failure) {
     ok(!Dpkg::Version::compare_versions($$version_cmp{a},$$version_cmp{relation},$$version_cmp{b}),
       "compare_versions: Version $$version_cmp{a} $$version_cmp{relation} $$version_cmp{b} false");
     ok(!dpkg_vercmp($$version_cmp{a},$$version_cmp{b},$$version_cmp{relation}),
	"Dpkg concures: Version $$version_cmp{a} $$version_cmp{relation} $$version_cmp{b}");
}
