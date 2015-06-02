#!/usr/bin/perl
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

use strict;
use warnings;

use Test::More tests => 92;

use File::Basename;

use Dpkg::File;

BEGIN {
    use_ok('Dpkg::Changelog');
    use_ok('Dpkg::Changelog::Debian');
    use_ok('Dpkg::Vendor', qw(get_current_vendor));
};

my $srcdir = $ENV{srcdir} || '.';
my $datadir = $srcdir . '/t/Dpkg_Changelog';

my $vendor = get_current_vendor();

#########################

foreach my $file ("$datadir/countme", "$datadir/shadow", "$datadir/fields",
    "$datadir/regressions", "$datadir/date-format") {

    my $changes = Dpkg::Changelog::Debian->new(verbose => 0);
    $changes->load($file);

    open(my $clog_fh, '<', "$file") or die "can't open $file\n";
    my $content = file_slurp($clog_fh);
    close($clog_fh);
    cmp_ok($content, 'eq', "$changes", "string output of Dpkg::Changelog on $file");

    my $errors = $changes->get_parse_errors();
    my $basename = basename( $file );
    is($errors, '', "Parse example changelog $file without errors" );

    my @data = @$changes;
    ok(@data, 'data is not empty');

    my $str;
    if ($file eq "$datadir/countme") {
	# test range options
	cmp_ok(@data, '==', 7, 'no options -> count');
	my $all_versions = join( '/', map { $_->get_version() } @data);

	sub check_options {
	    my ($changes, $data, $options, $count, $versions,
		$check_name) = @_;

	    my @cnt = $changes->get_range($options);
	    cmp_ok( @cnt, '==', $count, "$check_name -> count" );
	    if ($count == @$data) {
		is_deeply( \@cnt, $data, "$check_name -> returns all" );

	    } else {
		is( join( '/', map { $_->get_version() } @cnt),
		    $versions, "$check_name -> versions" );
	    }
	}

	check_options( $changes, \@data,
		       { count => 3 }, 3, '2:2.0-1/1:2.0~rc2-3/1:2.0~rc2-2',
		       'positive count' );
	check_options( $changes, \@data,
		       { count => -3 }, 3,
		       '1:2.0~rc2-1sarge2/1:2.0~rc2-1sarge1/1.5-1',
		       'negative count' );
	check_options( $changes, \@data,
		       { count => 1 }, 1, '2:2.0-1',
		       'count 1' );
	check_options( $changes, \@data,
		       { count => 1, default_all => 1 }, 1, '2:2.0-1',
		       'count 1 (d_a 1)' );
	check_options( $changes, \@data,
		       { count => -1 }, 1, '1.5-1',
		       'count -1' );

	check_options( $changes, \@data,
		       { count => 3, offset => 2 }, 3,
		       '1:2.0~rc2-2/1:2.0~rc2-1sarge3/1:2.0~rc2-1sarge2',
		       'positve count + positive offset' );
	check_options( $changes, \@data,
		       { count => -3, offset => 4 }, 3,
		       '1:2.0~rc2-3/1:2.0~rc2-2/1:2.0~rc2-1sarge3',
		       'negative count + positive offset' );

	check_options( $changes, \@data,
		       { count => 4, offset => 5 }, 2,
		       '1:2.0~rc2-1sarge1/1.5-1',
		       'positve count + positive offset (>max)' );
	check_options( $changes, \@data,
		       { count => -4, offset => 2 }, 2,
		       '2:2.0-1/1:2.0~rc2-3',
		       'negative count + positive offset (<0)' );

	check_options( $changes, \@data,
		       { count => 3, offset => -4 }, 3,
		       '1:2.0~rc2-1sarge3/1:2.0~rc2-1sarge2/1:2.0~rc2-1sarge1',
		       'positve count + negative offset' );
	check_options( $changes, \@data,
		       { count => -3, offset => -3 }, 3,
		       '1:2.0~rc2-3/1:2.0~rc2-2/1:2.0~rc2-1sarge3',
		       'negative count + negative offset' );

	check_options( $changes, \@data,
		       { count => 5, offset => -2 }, 2,
		       '1:2.0~rc2-1sarge1/1.5-1',
		       'positve count + negative offset (>max)' );
	check_options( $changes, \@data,
		       { count => -5, offset => -4 }, 3,
		       '2:2.0-1/1:2.0~rc2-3/1:2.0~rc2-2',
		       'negative count + negative offset (<0)' );

	check_options( $changes, \@data,
		       { count => 7 }, 7, '',
		       'count 7 (max)' );
	check_options( $changes, \@data,
		       { count => -7 }, 7, '',
		       'count -7 (-max)' );
	check_options( $changes, \@data,
		       { count => 10 }, 7, '',
		       'count 10 (>max)' );
	check_options( $changes, \@data,
		       { count => -10 }, 7, '',
		       'count -10 (<-max)' );

	check_options( $changes, \@data,
		       { from => '1:2.0~rc2-1sarge3' }, 4,
		       '2:2.0-1/1:2.0~rc2-3/1:2.0~rc2-2/1:2.0~rc2-1sarge3',
		       'from => "1:2.0~rc2-1sarge3"' );
	check_options( $changes, \@data,
		       { since => '1:2.0~rc2-1sarge3' }, 3,
		       '2:2.0-1/1:2.0~rc2-3/1:2.0~rc2-2',
		       'since => "1:2.0~rc2-1sarge3"' );
        $SIG{__WARN__} = sub {};
        check_options( $changes, \@data,
                       { since => 0 }, 7, '',
                       'since => 0 returns all');
        delete $SIG{__WARN__};
	check_options( $changes, \@data,
		       { to => '1:2.0~rc2-1sarge2' }, 3,
		       '1:2.0~rc2-1sarge2/1:2.0~rc2-1sarge1/1.5-1',
		       'to => "1:2.0~rc2-1sarge2"' );
	## no critic (ControlStructures::ProhibitUntilBlocks)
	check_options( $changes, \@data,
		       { until => '1:2.0~rc2-1sarge2' }, 2,
		       '1:2.0~rc2-1sarge1/1.5-1',
		       'until => "1:2.0~rc2-1sarge2"' );
	## use critic
	#TODO: test combinations
    }
    if ($file eq "$datadir/fields") {
	my $str = $changes->dpkg({ all => 1 });
	my $expected = 'Source: fields
Version: 2.0-0etch1
Distribution: stable
Urgency: high
Maintainer: Frank Lichtenheld <frank@lichtenheld.de>
Date: Sun, 13 Jan 2008 15:49:19 +0100
Closes: 1000000 1111111 2222222
Changes:
 fields (2.0-0etch1) stable; urgency=low
 .
   * Upload to stable (Closes: #1111111, #2222222)
   * Fix more stuff. (LP: #54321, #2424242)
 .
 fields (2.0-1) unstable  frozen; urgency=medium
 .
   [ Frank Lichtenheld ]
   * Upload to unstable (Closes: #1111111, #2222222)
   * Fix stuff. (LP: #12345, #424242)
 .
   [ Raphaël Hertzog ]
   * New upstream release.
     - implements a
     - implements b
   * Update S-V.
 .
 fields (2.0~b1-1) unstable; urgency=low,xc-userfield=foobar
 .
   * Beta
 .
 fields (1.0) experimental; urgency=high,xb-userfield2=foobar
 .
   * First upload (Closes: #1000000)
Xb-Userfield2: foobar
Xc-Userfield: foobar
';
	if ($vendor eq 'Ubuntu') {
	    $expected =~ s/^(Closes:.*)/$1\nLaunchpad-Bugs-Fixed: 12345 54321 424242 2424242/m;
	}
	cmp_ok($str, 'eq', $expected, 'fields handling');

	$str = $changes->dpkg({ offset => 1, count => 2 });
	$expected = 'Source: fields
Version: 2.0-1
Distribution: unstable frozen
Urgency: medium
Maintainer: Frank Lichtenheld <djpig@debian.org>
Date: Sun, 12 Jan 2008 15:49:19 +0100
Closes: 1111111 2222222
Changes:
 fields (2.0-1) unstable  frozen; urgency=medium
 .
   [ Frank Lichtenheld ]
   * Upload to unstable (Closes: #1111111, #2222222)
   * Fix stuff. (LP: #12345, #424242)
 .
   [ Raphaël Hertzog ]
   * New upstream release.
     - implements a
     - implements b
   * Update S-V.
 .
 fields (2.0~b1-1) unstable; urgency=low,xc-userfield=foobar
 .
   * Beta
Xc-Userfield: foobar
';
	if ($vendor eq 'Ubuntu') {
	    $expected =~ s/^(Closes:.*)/$1\nLaunchpad-Bugs-Fixed: 12345 424242/m;
	}
	cmp_ok($str, 'eq', $expected, 'fields handling 2');

	$str = $changes->rfc822({ offset => 2, count => 2 });
	$expected = 'Source: fields
Version: 2.0~b1-1
Distribution: unstable
Urgency: low
Maintainer: Frank Lichtenheld <frank@lichtenheld.de>
Date: Sun, 11 Jan 2008 15:49:19 +0100
Changes:
 fields (2.0~b1-1) unstable; urgency=low,xc-userfield=foobar
 .
   * Beta
Xc-Userfield: foobar

Source: fields
Version: 1.0
Distribution: experimental
Urgency: high
Maintainer: Frank Lichtenheld <djpig@debian.org>
Date: Sun, 10 Jan 2008 15:49:19 +0100
Closes: 1000000
Changes:
 fields (1.0) experimental; urgency=high,xb-userfield2=foobar
 .
   * First upload (Closes: #1000000)
Xb-Userfield2: foobar

';
	cmp_ok($str, 'eq', $expected, 'fields handling 3');

	# Test Dpkg::Changelog::Entry methods
	is($data[1]->get_version(), '2.0-1', 'get_version');
	is($data[1]->get_source(), 'fields', 'get_source');
	is(scalar $data[1]->get_distributions(), 'unstable', 'get_distribution');
	is(join('|', $data[1]->get_distributions()), 'unstable|frozen',
	    'get_distributions');
	is($data[3]->get_optional_fields(),
	    "Urgency: high\nCloses: 1000000\nXb-Userfield2: foobar\n",
	    'get_optional_fields');
	is($data[1]->get_maintainer(), 'Frank Lichtenheld <djpig@debian.org>',
	    'get_maintainer');
	is($data[1]->get_timestamp(), 'Sun, 12 Jan 2008 15:49:19 +0100',
	    'get_timestamp');
	my @items = $data[1]->get_change_items();
	is($items[0], "  [ Frank Lichtenheld ]\n", 'change items 1');
	is($items[4], '  * New upstream release.
    - implements a
    - implements b
', 'change items 2');
	is($items[5], "  * Update S-V.\n", 'change items 3');
    }
    if ($file eq "$datadir/date-format") {
        is($data[0]->get_timestamp(), '01 Jul 2100 23:59:59 -1200',
           'get date w/o DoW, and negative timezone offset');
        is($data[1]->get_timestamp(), 'Tue, 27 Feb 2050 12:00:00 +1245',
           'get date w/ DoW, and positive timezone offset');
        is($data[2]->get_timestamp(), 'Mon, 01 Jan 2000 00:00:00 +0000',
           'get date w/ DoW, and zero timezone offset');
    }
    if ($file eq "$datadir/regressions") {
	my $f = $changes->dpkg();
	is("$f->{Version}", '0', 'version 0 correctly parsed');
    }

    SKIP: {
	skip('avoid spurious warning with only one entry', 2)
	    if @data == 1;

	my $oldest_version = $data[-1]->{Version};
	$str = $changes->dpkg({ since => $oldest_version });

	$str = $changes->rfc822();

	ok(1, 'TODO check rfc822 output');

	$str = $changes->rfc822({ since => $oldest_version });

	ok(1, 'TODO check rfc822 output with ranges');
    }
}

foreach my $test (( [ "$datadir/misplaced-tz", 6 ])) {

    my $file = shift @$test;
    my $changes = Dpkg::Changelog::Debian->new(verbose => 0);
    $changes->load($file);
    my @errors = $changes->get_parse_errors();

    ok(@errors, 'errors occured');
    is_deeply( [ map { $_->[1] } @errors ], $test, 'check line numbers' );
}
