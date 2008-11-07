# Copyright Colin Watson <cjwatson@debian.org>
# Copyright Ian Jackson <iwj@debian.org>
# Copyright 2007 by Don Armstrong <don@donarmstrong.com>.

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

package Dpkg::Version;

use strict;
use warnings;

use Dpkg::ErrorHandling qw(error);
use Dpkg::Gettext;

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(vercmp compare_versions check_version parseversion);

=head1 NAME

Dpkg::Version - pure-Perl dpkg-style version comparison

=head1 DESCRIPTION

The Dpkg::Version module provides pure-Perl routines to compare
dpkg-style version numbers, as used in Debian packages. If you have the
libapt-pkg Perl bindings available (Debian package libapt-pkg-perl), they
may offer better performance.

=head1 METHODS

=over 8

=cut

sub parseversion ($)
{
    my $ver = shift;
    my %verhash;
    if ($ver =~ /:/)
    {
	$ver =~ /^(\d+):(.+)/ or die "bad version number '$ver'";
	$verhash{epoch} = $1;
	$ver = $2;
    }
    else
    {
	$verhash{epoch} = 0;
    }
    if ($ver =~ /(.+)-(.*)$/)
    {
	$verhash{version} = $1;
	$verhash{revision} = $2;
    }
    else
    {
	$verhash{version} = $ver;
	$verhash{revision} = 0;
    }
    return %verhash;
}

# verrevcmp

# This function is almost exactly equivalent
# to dpkg's verrevcmp function, including the
# order subroutine which it uses.

sub verrevcmp($$)
{

     sub order{
	  my ($x) = @_;
	  ##define order(x) ((x) == '~' ? -1 \
	  #           : cisdigit((x)) ? 0 \
	  #           : !(x) ? 0 \
	  #           : cisalpha((x)) ? (x) \
	  #           : (x) + 256)
	  # This comparison is out of dpkg's order to avoid
	  # comparing things to undef and triggering warnings.
	  if (not defined $x or not length $x) {
	       return 0;
	  }
	  elsif ($x eq '~') {
	       return -1;
	  }
	  elsif ($x =~ /^\d$/) {
	       return 0;
	  }
	  elsif ($x =~ /^[A-Z]$/i) {
	       return ord($x);
	  }
	  else {
	       return ord($x) + 256;
	  }
     }

     sub next_elem(\@){
	  my $a = shift;
	  return @{$a} ? shift @{$a} : undef;
     }
     my ($val, $ref) = @_;
     $val = "" if not defined $val;
     $ref = "" if not defined $ref;
     my @val = split //,$val;
     my @ref = split //,$ref;
     my $vc = next_elem @val;
     my $rc = next_elem @ref;
     while (defined $vc or defined $rc) {
	  my $first_diff = 0;
	  while ((defined $vc and $vc !~ /^\d$/) or
		 (defined $rc and $rc !~ /^\d$/)) {
	       my $vo = order($vc); my $ro = order($rc);
	       # Unlike dpkg's verrevcmp, we only return 1 or -1 here.
	       return (($vo - $ro > 0) ? 1 : -1) if $vo != $ro;
	       $vc = next_elem @val; $rc = next_elem @ref;
	  }
	  while (defined $vc and $vc eq '0') {
	       $vc = next_elem @val;
	  }
	  while (defined $rc and $rc eq '0') {
	       $rc = next_elem @ref;
	  }
	  while (defined $vc and $vc =~ /^\d$/ and
		 defined $rc and $rc =~ /^\d$/) {
	       $first_diff = ord($vc) - ord($rc) if !$first_diff;
	       $vc = next_elem @val; $rc = next_elem @ref;
	  }
	  return 1 if defined $vc and $vc =~ /^\d$/;
	  return -1 if defined $rc and $rc =~ /^\d$/;
	  return (($first_diff  > 0) ? 1 : -1) if $first_diff;
     }
     return 0;
}

=item vercmp

Compare the two arguments as dpkg-style version numbers. Returns -1 if the
first argument represents a lower version number than the second, 1 if the
first argument represents a higher version number than the second, and 0 if
the two arguments represent equal version numbers.

=cut

sub vercmp ($$)
{
    my %version = parseversion $_[0];
    my %refversion = parseversion $_[1];
    return 1 if $version{epoch} > $refversion{epoch};
    return -1 if $version{epoch} < $refversion{epoch};
    my $r = verrevcmp($version{version}, $refversion{version});
    return $r if $r;
    return verrevcmp($version{revision}, $refversion{revision});
}

=item compare_versions

Emulates dpkg --compare-versions. Takes two versions as arguments
one and three and one operator as argument two. Supports the following
operators: 'gt', 'ge', 'eq', 'le', 'lt', and '>>', '>=', '=', '<=', '<<'.
Returns a true value if the specified condition is true, a false value
otherwise.

=cut

sub compare_versions ($$$)
{
    my $rel = $_[1];
    my $res = vercmp($_[0], $_[2]);

    if ($rel eq 'gt' or $rel eq ">" or $rel eq ">>") {
	return $res > 0;
    } elsif ($rel eq 'ge' or $rel eq '>=') {
	return $res >= 0;
    } elsif ($rel eq 'eq' or $rel eq '=') {
	return $res == 0;
    } elsif ($rel eq 'le' or $rel eq '<=') {
	return $res <= 0;
    } elsif ($rel eq 'lt' or $rel eq "<" or $rel eq "<<") {
	return $res < 0;
    } else {
	die "bad relation '$rel'";
    }
}

=item check_version($version)

Check the version string and fails it it's invalid.

=cut
sub check_version ($) {
    my $version = shift || '';
    $version =~ m/[^-+:.0-9a-zA-Z~]/o &&
        error(_g("version number contains illegal character `%s'"), $&);
}

=back

=head1 AUTHOR

Don Armstrong <don@donarmstrong.com> and Colin Watson
E<lt>cjwatson@debian.orgE<gt>, based on the implementation in
C<dpkg/lib/vercmp.c> by Ian Jackson and others.

=cut

1;
