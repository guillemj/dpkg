# -*- perl -*-
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl Parse-DebianChangelog.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use strict;
use warnings;

use File::Basename;
use XML::Simple;

BEGIN {
    my $no_examples = 3;
    my $no_err_examples = 1;
    my $no_tests = $no_examples * 13
	+ $no_err_examples * 2
	+ 49;

    require Test::More;
    import Test::More tests => $no_tests, ;
}
BEGIN {
    use_ok('Parse::DebianChangelog');
    use_ok('Parse::DebianChangelog::ChangesFilters', ':all' );
};

#########################

my $test = Parse::DebianChangelog->init( { infile => '/nonexistant',
					   quiet => 1 } );
ok( !defined($test), "fatal parse errors lead to init() returning undef");

my $save_data;
foreach my $file (qw(Changes t/examples/countme t/examples/shadow)) {

    my $changes = Parse::DebianChangelog->init( { infile => $file,
						  quiet => 1 } );
    my $errors = $changes->get_parse_errors();
    my $basename = basename( $file );

#    use Data::Dumper;
#    diag(Dumper($changes));

    ok( !$errors, "Parse example changelog $file without errors" );

    my @data = $changes->data;

    ok( @data, "data is not empty" );

    my $html_out = $changes->html( { outfile => "t/$basename.html.tmp",
				     template => "tmpl/default.tmpl" } );

    is( `tidy -qe t/$basename.html.tmp 2>&1`, '',
	'Generated HTML has no tidy errors' );

    ok( ($changes->delete_filter( 'html::changes',
				  \&common_licenses ))[0]
	== \&common_licenses );
    ok( ! $changes->delete_filter( 'html::changes',
				   \&common_licenses ) );

    $changes->html( { outfile => "t/$basename.html.tmp.2",
		      template => "tmpl/default.tmpl" } );
    is( `tidy -qe t/$basename.html.tmp.2 2>&1`, '',
	'Generated HTML has no tidy errors' );

    $changes->add_filter( 'html::changes',
			  \&common_licenses );

    my $html_out2 = $changes->html();

    # remove timestamps since they will differ
    $html_out =~ s/Generated .*? by//go;
    $html_out2 =~ s/Generated .*? by//go;

    is( $html_out, $html_out2 )
	and unlink "t/$basename.html.tmp", "t/$basename.html.tmp.2";

    my $str = $changes->dpkg_str();

    is( $str, `dpkg-parsechangelog -l$file`,
	'Output of dpkg_str equal to output of dpkg-parsechangelog' );

    if ($file eq 't/examples/countme') {
	$save_data = $changes->rfc822_str({ all => 1 });

	# test range options
	cmp_ok( @data, '==', 7, "no options -> count" );
	my $all_versions = join( '/', map { $_->Version } @data);

	sub check_options {
	    my ($changes, $data, $options, $count, $versions,
		$check_name) = @_;

	    my @cnt = $changes->data( $options );
	    cmp_ok( @cnt, '==', $count, "$check_name -> count" );
	    if ($count == @$data) {
		is_deeply( \@cnt, $data, "$check_name -> returns all" );

	    } else {
		is( join( "/", map { $_->Version } @cnt),
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

    if ($file eq 'Changes') {
	my $v = $data[0]->Version;
	$v =~ s/[a-z]$//;
	cmp_ok( $v, 'eq', $Parse::DebianChangelog::VERSION,
		'version numbers in module and Changes match' );
    }

    my $oldest_version = $data[-1]->Version;
    $str = $changes->dpkg_str({ since => $oldest_version });

    is( $str, `dpkg-parsechangelog -v$oldest_version -l$file`,
	'Output of dpkg_str equal to output of dpkg-parsechangelog' )
	or diag("oldest_version=$oldest_version");

    $str = $changes->rfc822_str();

    ok( 1 );

    $str = $changes->rfc822_str({ since => $oldest_version });

    ok( 1 );

    $str = $changes->xml( { outfile => "t/$basename.xml.tmp" });

    ok( XMLin($str, ForceArray => {},
	      KeyAttr => {} ), "can read in the result of XMLout" );
    ok( (-s "t/$basename.xml.tmp") == length($str) );

    unlink( "t/$basename.xml.tmp" );

}

open CHANGES, '<', 't/examples/countme';
my $string = join('',<CHANGES>);

my $str_changes = Parse::DebianChangelog->init( { instring => $string,
						  quiet => 1 } );
my $errors = $str_changes->get_parse_errors();
ok( !$errors,
    "Parse example changelog t/examples/countme without errors from string" );

my $str_data = $str_changes->rfc822_str({ all => 1 });
is( $str_data, $save_data,
    "Compare result of parse from string with result of parse from file" );


foreach my $test (( [ 't/examples/misplaced-tz', 6 ])) {

    my $file = shift @$test;
    my $changes = Parse::DebianChangelog->init( { infile => $file,
						  quiet => 1 } );
    my @errors = $changes->get_parse_errors();

    ok( @errors, 'errors occoured' );
    is_deeply( [ map { $_->[1] } @errors ], $test, 'check line numbers' );

}
