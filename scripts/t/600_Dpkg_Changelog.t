# -*- perl -*-

use strict;
use warnings;

use File::Basename;

BEGIN {
    my $no_examples = 4;
    my $no_err_examples = 1;
    my $no_tests = $no_examples * 4
	+ $no_err_examples * 2
	+ 24 # countme
	+  2 # fields
	+ 24;

    require Test::More;
    import Test::More tests => $no_tests;
}
BEGIN {
    use_ok('Dpkg::Changelog');
    use_ok('Dpkg::Changelog::Debian');
};

my $srcdir = $ENV{srcdir} || '.';
$srcdir .= '/t/600_Dpkg_Changelog';

#########################

my $test = Dpkg::Changelog::Debian->init( { infile => '/nonexistant',
					    quiet => 1 } );
ok( !defined($test), "fatal parse errors lead to init() returning undef");

my $save_data;
foreach my $file ("$srcdir/countme", "$srcdir/shadow", "$srcdir/fields",
    "$srcdir/regressions") {

    my $changes = Dpkg::Changelog::Debian->init( { infile => $file,
						   quiet => 1 } );
    my $errors = $changes->get_parse_errors();
    my $basename = basename( $file );

#    use Data::Dumper;
#    diag(Dumper($changes));

    ok( !$errors, "Parse example changelog $file without errors" );

    my @data = $changes->data;

    ok( @data, "data is not empty" );

    my $str = $changes->dpkg_str();

#    is( $str, `dpkg-parsechangelog -l$file`,
#	'Output of dpkg_str equal to output of dpkg-parsechangelog' );

    if ($file eq "$srcdir/countme") {
	$save_data = $changes->rfc822_str({ all => 1 });

	# test range options
	cmp_ok( @data, '==', 7, "no options -> count" );
	my $all_versions = join( '/', map { $_->{Version} } @data);

	sub check_options {
	    my ($changes, $data, $options, $count, $versions,
		$check_name) = @_;

	    my @cnt = $changes->data( $options );
	    cmp_ok( @cnt, '==', $count, "$check_name -> count" );
	    if ($count == @$data) {
		is_deeply( \@cnt, $data, "$check_name -> returns all" );

	    } else {
		is( join( "/", map { $_->{Version} } @cnt),
		    $versions, "$check_name -> versions" );
	    }
	}

	check_options( $changes, \@data,
		       { count => 3 }, 3, '2:2.0-1/1:2.0~rc2-3/1:2.0~rc2-2',
		       'positve count' );
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
	check_options( $changes, \@data,
		       { to => '1:2.0~rc2-1sarge2' }, 3,
		       '1:2.0~rc2-1sarge2/1:2.0~rc2-1sarge1/1.5-1',
		       'to => "1:2.0~rc2-1sarge2"' );
	check_options( $changes, \@data,
		       { until => '1:2.0~rc2-1sarge2' }, 2,
		       '1:2.0~rc2-1sarge1/1.5-1',
		       'until => "1:2.0~rc2-1sarge2"' );
	#TODO: test combinations
    }
    if ($file eq "$srcdir/fields") {
	my $str = $changes->dpkg_str({ all => 1 });
	my $expected = 'Source: fields
Version: 2.0-0etch1
Distribution: stable
Urgency: high
Maintainer: Frank Lichtenheld <frank@lichtenheld.de>
Date: Sun, 13 Jan 2008 15:49:19 +0100
Closes: 1000000 1111111 1111111 2222222 2222222
Changes: 
 fields (2.0-0etch1) stable; urgency=low
 .
   * Upload to stable (Closes: #1111111, #2222222)
 .
 fields (2.0-1) unstable; urgency=medium
 .
   * Upload to unstable (Closes: #1111111, #2222222)
 .
 fields (2.0~b1-1) unstable; urgency=low,xc-userfield=foobar
 .
   * Beta
 .
 fields (1.0) experimental; urgency=high
 .
   * First upload (Closes: #1000000)
Xc-Userfield: foobar
';
	cmp_ok($str,'eq',$expected,"fields handling");

	$str = $changes->dpkg_str({ offset => 1, count => 2 });
	$expected = 'Source: fields
Version: 2.0-1
Distribution: unstable
Urgency: medium
Maintainer: Frank Lichtenheld <djpig@debian.org>
Date: Sun, 12 Jan 2008 15:49:19 +0100
Closes: 1111111 2222222
Changes: 
 fields (2.0-1) unstable; urgency=medium
 .
   * Upload to unstable (Closes: #1111111, #2222222)
 .
 fields (2.0~b1-1) unstable; urgency=low,xc-userfield=foobar
 .
   * Beta
Xc-Userfield: foobar
';
	cmp_ok($str,'eq',$expected,"fields handling 2");

    }

#     if ($file eq 'Changes') {
# 	my $v = $data[0]->Version;
# 	$v =~ s/[a-z]$//;
# 	cmp_ok( $v, 'eq', $Parse::DebianChangelog::VERSION,
# 		'version numbers in module and Changes match' );
#     }

    SKIP: {
	skip("avoid spurios warning with only one entry", 2)
	    if @data == 1;

	my $oldest_version = $data[-1]->{Version};
	$str = $changes->dpkg_str({ since => $oldest_version });

	$str = $changes->rfc822_str();

	ok( 1 );

	$str = $changes->rfc822_str({ since => $oldest_version });

	ok( 1 );
    }
}

open CHANGES, '<', "$srcdir/countme";
my $string = join('',<CHANGES>);

my $str_changes = Dpkg::Changelog::Debian->init( { instring => $string,
						   quiet => 1 } );
my $errors = $str_changes->get_parse_errors();
ok( !$errors,
    "Parse example changelog $srcdir/countme without errors from string" );

my $str_data = $str_changes->rfc822_str({ all => 1 });
is( $str_data, $save_data,
    "Compare result of parse from string with result of parse from file" );


foreach my $test (( [ "$srcdir/misplaced-tz", 6 ])) {

    my $file = shift @$test;
    my $changes = Dpkg::Changelog::Debian->init( { infile => $file,
						   quiet => 1 } );
    my @errors = $changes->get_parse_errors();

    ok( @errors, 'errors occoured' );
    is_deeply( [ map { $_->[1] } @errors ], $test, 'check line numbers' );
}
