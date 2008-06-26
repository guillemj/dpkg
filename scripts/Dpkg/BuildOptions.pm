package Dpkg::BuildOptions;

use strict;
use warnings;

use Dpkg::Gettext;
use Dpkg::ErrorHandling qw(warning);

sub parse {
    my ($env) = @_;

    $env ||= $ENV{DEB_BUILD_OPTIONS};

    unless ($env) { return {}; }

    my %opts;

    foreach (split(/\s+/, $env)) {
	unless (/^([a-z][a-z0-9_-]*)(=(\S*))?$/) {
            warning(_g("invalid flag in DEB_BUILD_OPTIONS: %s"), $_);
            next;
        }

	my ($k, $v) = ($1, $3 || '');

	# Sanity checks
	if ($k =~ /^(noopt|nostrip|nocheck)$/ && length($v)) {
	    $v = '';
	} elsif ($k eq 'parallel' && $v !~ /^-?\d+$/) {
	    next;
	}

	$opts{$k} = $v;
    }

    return \%opts;
}

sub set {
    my ($opts, $overwrite) = @_;
    $overwrite = 1 if not defined($overwrite);

    my $new = {};
    $new = parse() unless $overwrite;
    while (my ($k, $v) = each %$opts) {
        $new->{$k} = $v;
    }

    my $env = join(" ", map { $new->{$_} ? $_ . "=" . $new->{$_} : $_ } sort keys %$new);

    $ENV{DEB_BUILD_OPTIONS} = $env;
    return $env;
}

1;
