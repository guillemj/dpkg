package Dpkg::Fields;

use strict;
use warnings;

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(capit set_field_importance sort_field_by_importance);

sub capit {
    my @pieces = map { ucfirst(lc) } split /-/, $_[0];
    return join '-', @pieces;
}

our %fieldimps;

sub set_field_importance(@)
{
    my @fields = @_;
    my $i = 1;

    grep($fieldimps{$_} = $i++, @fields);
}

sub sort_field_by_importance($$)
{
    my ($a, $b) = @_;

    if (defined $fieldimps{$a} && defined $fieldimps{$b}) {
	$fieldimps{$a} <=> $fieldimps{$b};
    } elsif (defined($fieldimps{$a})) {
	-1;
    } elsif (defined($fieldimps{$b})) {
	1;
    } else {
	$a cmp $b;
    }
}

1;
