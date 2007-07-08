package Dpkg::Version;

use strict;
use warnings;

use Exporter 'import';
our @EXPORT_OK = qw(compare_versions);

sub compare_versions {
    my ($a, $op, $b) = @_;
    # TODO: maybe replace by a real full-perl versions
    system("dpkg", "--compare-versions", $a, $op, $b) == 0
	or return 0;
    return 1;
}

1;
