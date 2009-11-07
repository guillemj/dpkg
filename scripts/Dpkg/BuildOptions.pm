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
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

package Dpkg::BuildOptions;

use strict;
use warnings;

use Dpkg::Gettext;
use Dpkg::ErrorHandling;

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
