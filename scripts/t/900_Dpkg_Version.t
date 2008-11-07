# -*- mode: cperl;-*-

use Test::More;

use strict;
use warnings;

my @tests = <DATA>;
my @ops = ("<", "<<", "lt",
	   "<=", "le",
	   "=", "eq",
	   ">=", "ge",
	   ">", ">>", "gt");

plan tests => scalar(@tests) * (scalar(@ops) + 1) + 1;

use_ok('Dpkg::Version', qw(vercmp compare_versions));

my $truth = {
    "-1" => {
	"<" => 1, "<<" => 1, "lt" => 1,
	"<=" => 1, "le" => 1,
	"=" => 0, "eq" => 0,
	">=" => 0, "ge" => 0,
	">" => 0, ">>" => 0, "gt" => 0,
    },
    "0" => {
	"<" => 0, "<<" => 0, "lt" => 0,
	"<=" => 1, "le" => 1,
	"=" => 1, "eq" => 1,
	">=" => 1, "ge" => 1,
	">" => 0, ">>" => 0, "gt" => 0,
    },
    "1" => {
	"<" => 0, "<<" => 0, "lt" => 0,
	"<=" => 0, "le" => 0,
	"=" => 0, "eq" => 0,
	">=" => 1, "ge" => 1,
	">" => 1, ">>" => 1, "gt" => 1,
    },
};

foreach my $case (@tests) {
    my ($a, $b, $res) = split " ", $case;
    is(vercmp($a, $b), $res, "$a cmp $b => $res");
    foreach my $op (@ops) {
	if ($truth->{$res}{$op}) {
	    ok(compare_versions($a, $op, $b), "$a $op $b => true");
	} else {
	    ok(!compare_versions($a, $op, $b), "$a $op $b => false");
	}
    }
}

__DATA__
1:foo foo 1
0:foo foo 0
foo foo 0
foo- foo 0
foo fo 1
foo- foo+ -1
foo~1 foo -1
foo~foo+Bar foo~foo+bar -1
foo~~ foo~ -1
12345+that-really-is-some-ver-0 12345+that-really-is-some-ver-10 -1
foo-0 foo-01 -1
foo.bar foobar 1
foo.bar foo1bar 1
foo.bar foo0bar 1
1foo-1 foo-1 -1
foo2.0 foo2 1
foo2.0.0 foo2.10.0 -1
foo2.0 foo2.0.0 -1
foo2.0 foo2.10 -1
foo2.1 foo2.10 -1
1.09 1.9 0
1.0.8+nmu1 1.0.8 1
3.11 3.10+nmu1 1
0.9j-20080306-4 0.9i-20070324-2 1
1.2.0~b7-1 1.2.0~b6-1 1
1.011-1 1.06-2 1
0.0.9+dfsg1-1 0.0.8+dfsg1-3 1
4.6.99+svn6582-1 4.6.99+svn6496-1 1
53 52 1
0.9.9~pre122-1 0.9.9~pre111-1 1
2:2.3.2-2+lenny2 2:2.3.2-2 1
1:3.8.1-1 3.8.GA-1 1
1.0.1+gpl-1 1.0.1-2 1
