# Copyright © Colin Watson <cjwatson@debian.org>
# Copyright © Ian Jackson <iwj@debian.org>
# Copyright © 2007 Don Armstrong <don@donarmstrong.com>.
# Copyright © 2009 Raphaël Hertzog <hertzog@debian.org>

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

use Dpkg::ErrorHandling;
use Dpkg::Gettext;

use base qw(Exporter);
our @EXPORT = qw(version_compare version_compare_op
                 version_normalize_cmp_op version_compare_string
                 version_compare_part version_split_digits version_check
                 CMP_OP_LT CMP_OP_LE CMP_OP_EQ CMP_OP_GE CMP_OP_GT);
our @EXPORT_OK = qw(vercmp compare_versions check_version parseversion);

use constant {
    CMP_OP_LT => '<<',
    CMP_OP_LE => '<=',
    CMP_OP_EQ => '=',
    CMP_OP_GE => '>=',
    CMP_OP_GT => '>>',
};

use overload
    '<=>' => \&comparison,
    'cmp' => \&comparison,
    '""'  => \&as_string,
    'bool' => sub { return 1 };

=head1 NAME

Dpkg::Version - handling and comparing dpkg-style version numbers

=head1 DESCRIPTION

The Dpkg::Version module provides pure-Perl routines to compare
dpkg-style version numbers (as used in Debian packages) and also
an object oriented interface overriding perl operators
to do the right thing when you compare Dpkg::Version object between
them.

=head1 OBJECT INTERFACE

=over 4

=item my $v = Dpkg::Version->new($version)

Create a new Dpkg::Version object corresponding to the version indicated in
the string (scalar) $version. Returns undef if the string doesn't contain
a valid version (see version_check for details).

=cut

sub new {
    my ($this, $ver) = @_;
    my $class = ref($this) || $this;
    $ver = "$ver" if ref($ver); # Try to stringify objects
    return undef unless version_check($ver);

    my $self = {};
    if ($ver =~ /^(\d*):(.+)$/) {
	$self->{'epoch'} = $1;
	$ver = $2;
    } else {
	$self->{'epoch'} = 0;
	$self->{'no_epoch'} = 1;
    }
    if ($ver =~ /(.+)-(.*)$/) {
	$self->{'version'} = $1;
	$self->{'revision'} = $2;
    } else {
	$self->{'version'} = $ver;
	$self->{'revision'} = 0;
	$self->{'no_revision'} = 1;
    }

    return bless $self, $class;
}

=item $v->epoch(), $v->version(), $v->revision()

Returns the corresponding part of the full version string.

=cut

sub epoch {
    my $self = shift;
    return $self->{'epoch'};
}

sub version {
    my $self = shift;
    return $self->{'version'};
}

sub revision {
    my $self = shift;
    return $self->{'revision'};
}

=item $v1 <=> $v2, $v1 < $v2, $v1 <= $v2, $v1 > $v2, $v1 >= $v2

Numerical comparison of various versions numbers. One of the two operands
needs to be a Dpkg::Version, the other one can be anything provided that
its string representation is a version number.

=cut

sub comparison {
    my ($a, $b, $inverted) = @_;
    if (not ref($b) or not $b->isa("Dpkg::Version")) {
        $b = Dpkg::Version->new($b);
    }
    ($a, $b) = ($b, $a) if $inverted;
    my $r = $a->epoch() <=> $b->epoch();
    return $r if $r;
    $r = version_compare_part($a->version(), $b->version());
    return $r if $r;
    return version_compare_part($a->revision(), $b->revision());
}

=item "$v"
=item $v->as_string()

Returns the string representation of the version number.

=cut
sub as_string {
    my ($self) = @_;
    my $str = "";
    $str .= $self->{epoch} . ":" unless $self->{no_epoch};
    $str .= $self->{version};
    $str .= "-" . $self->{revision} unless $self->{no_revision};
    return $str;
}

=back

=head1 FUNCTIONS

All the functions are exported by default.

=over 4

=item version_compare($a, $b)

Returns -1 is $a is smaller than $b, 0 if they are equal and 1 if $a
is bigger than $b.

If $a or $b are not valid version numbers, it dies with an error.

=cut

sub version_compare($$) {
    my ($a, $b) = @_;
    my $va = Dpkg::Version->new($a) || error(_g("%s is not a valid version"), "$a");
    my $vb = Dpkg::Version->new($b) || error(_g("%s is not a valid version"), "$b");
    return $va <=> $vb;
}

=item version_compare_op($a, $op, $b)

Returns the result (0 or 1) of the given comparison operation. This
function is implemented on top of version_compare().

Allowed values for $op are the exported constants CMP_OP_GT, CMP_OP_GE,
CMP_OP_EQ, CMP_OP_LE, CMP_OP_LT. Use version_normalize_cmp_op() if you
have an input string containing the operator.

=cut

sub version_compare_op($$$) {
    my ($a, $op, $b) = @_;
    my $res = version_compare($a, $b);

    if ($op eq CMP_OP_GT) {
	return $res > 0;
    } elsif ($op eq CMP_OP_GE) {
	return $res >= 0;
    } elsif ($op eq CMP_OP_EQ) {
	return $res == 0;
    } elsif ($op eq CMP_OP_LE) {
	return $res <= 0;
    } elsif ($op eq CMP_OP_LT) {
	return $res < 0;
    } else {
	internerr("unsupported operator for version_compare_op(): '$op'");
    }
}

=item my $cmp_op = version_normalize_cmp_op($op)

Returns the normalized constant of the comparison operator $op (a value
among CMP_OP_GT, CMP_OP_GE, CMP_OP_EQ, CMP_OP_LE and CMP_OP_LT). Supported
operators names in input are: "gt", "ge", "eq", "le", "lt", ">>", ">=",
"=", "<=", "<<". ">" and "<" are also supported but should not be used as
they are obsolete aliases of ">=" and "<=".

=cut

sub version_normalize_cmp_op($) {
    my $op = shift;

    warning("operator %s is deprecated: use %s or %s",
            $op, "$op$op", "$op=") if ($op eq '>' or $op eq '<');

    if ($op eq '>>' or $op eq 'gt') {
	return CMP_OP_GT;
    } elsif ($op eq '>=' or $op eq 'ge' or $op eq '>') {
	return CMP_OP_GE;
    } elsif ($op eq '=' or $op eq 'eq') {
	return CMP_OP_EQ;
    } elsif ($op eq '<=' or $op eq 'le' or $op eq '<') {
	return CMP_OP_LE;
    } elsif ($op eq '<<' or $op eq 'lt') {
	return CMP_OP_LT;
    } else {
	internerr("bad comparison operator '$op'");
    }
}

=item version_compare_string($a, $b)

String comparison function used for comparing non-numerical parts of version
numbers. Returns -1 is $a is smaller than $b, 0 if they are equal and 1 if $a
is bigger than $b.

The "~" character always sort lower than anything else. Digits sort lower
than non-digits. Among remaining characters alphabetic characters (A-Za-z)
sort lower than the other ones. Within each range, the ASCII decimal value
of the character is used to sort between characters.

=cut

sub version_compare_string($$) {
    sub order(_) {
        my ($x) = @_;
	if ($x eq '~') {
	    return -1;
	} elsif ($x =~ /^\d$/) {
	    return $x * 1 + 1;
	} elsif ($x =~ /^[A-Za-z]$/) {
	    return ord($x);
	} else {
	    return ord($x) + 256;
	}
    }
    my @a = map(order, split(//, shift));
    my @b = map(order, split(//, shift));
    while (1) {
        my ($a, $b) = (shift @a, shift @b);
        return 0 if not defined($a) and not defined($b);
        $a ||= 0; # Default order for "no character"
        $b ||= 0;
        return 1 if $a > $b;
        return -1 if $a < $b;
    }
}

=item version_compare_part($a, $b)

Compare two corresponding sub-parts of a version number (either upstream
version or debian revision).

Each parameter is split by version_split_digits() and resulting items
are compared together.in digits and non-digits items that are compared
together. As soon as a difference happens, it returns -1 if $a is smaller
than $b, 0 if they are equal and 1 if $a is bigger than $b.

=cut

sub version_compare_part($$) {
    my @a = version_split_digits(shift);
    my @b = version_split_digits(shift);
    while (1) {
        my ($a, $b) = (shift @a, shift @b);
        return 0 if not defined($a) and not defined($b);
        $a ||= 0; # Default value for lack of version
        $b ||= 0;
        if ($a =~ /^\d+$/ and $b =~ /^\d+$/) {
            # Numerical comparison
            my $cmp = $a <=> $b;
            return $cmp if $cmp;
        } else {
            # String comparison
            my $cmp = version_compare_string($a, $b);
            return $cmp if $cmp;
        }
    }
}

=item my @items = version_split_digits($version)

Splits a string in items that are each entirely composed either
of digits or of non-digits. For instance for "1.024~beta1+svn234" it would
return ("1", ".", "024", "~beta", "1", "+svn", "234").

=cut

sub version_split_digits($) {
    return split(/(?<=\d)(?=\D)|(?<=\D)(?=\d)/, $_[0]);
}

=item my ($ok, $msg) = version_check($version)
=item my $ok = version_check($version)

Checks the validity of $version as a version number. Returns 1 in $ok
if the version is valid, 0 otherwise. In the latter case, $msg
contains a description of the problem with the $version scalar.

=cut

sub version_check($) {
    my $version = shift;
    $version = "$version" if ref($version);

    if (not defined($version) or not length($version)) {
        my $msg = _g("version number cannot be empty");
        return (0, $msg) if wantarray;
        return 0;
    }
    if ($version =~ m/([^-+:.0-9a-zA-Z~])/o) {
        my $msg = sprintf(_g("version number contains illegal character `%s'"), $1);
        return (0, $msg) if wantarray;
        return 0;
    }
    if ($version =~ /:/ and $version !~ /^\d*:/) {
        $version =~ /^([^:]*):/;
        my $msg = sprintf(_g("epoch part of the version number " .
                             "is not a number: '%s'"), $1);
        return (0, $msg) if wantarray;
        return 0;
    }
    return (1, "") if wantarray;
    return 1;
}


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
	$verhash{no_epoch} = 1;
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
	$verhash{no_revision} = 1;
    }
    return %verhash;
}

# verrevcmp

# This function is almost exactly equivalent
# to dpkg's verrevcmp function, including the
# order subroutine which it uses.

sub verrevcmp($$)
{

     sub _order{
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
	  elsif ($x =~ /^[A-Za-z]$/) {
	       return ord($x);
	  }
	  else {
	       return ord($x) + 256;
	  }
     }

     my ($val, $ref) = @_;
     $val = "" if not defined $val;
     $ref = "" if not defined $ref;
     my @val = split //,$val;
     my @ref = split //,$ref;
     my $vc = shift @val;
     my $rc = shift @ref;
     while (defined $vc or defined $rc) {
	  my $first_diff = 0;
	  while ((defined $vc and $vc !~ /^\d$/) or
		 (defined $rc and $rc !~ /^\d$/)) {
	       my $vo = _order($vc); my $ro = _order($rc);
	       # Unlike dpkg's verrevcmp, we only return 1 or -1 here.
	       return (($vo - $ro > 0) ? 1 : -1) if $vo != $ro;
	       $vc = shift @val; $rc = shift @ref;
	  }
	  while (defined $vc and $vc eq '0') {
	       $vc = shift @val;
	  }
	  while (defined $rc and $rc eq '0') {
	       $rc = shift @ref;
	  }
	  while (defined $vc and $vc =~ /^\d$/ and
		 defined $rc and $rc =~ /^\d$/) {
	       $first_diff = ord($vc) - ord($rc) if !$first_diff;
	       $vc = shift @val; $rc = shift @ref;
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

    warning("operator %s is deprecated in compare_versions(): use %s or %s",
            $rel, "$rel$rel", "$rel=") if ($rel eq '>' or $rel eq '<');

    if ($rel eq 'gt' or $rel eq '>>') {
	return $res > 0;
    } elsif ($rel eq 'ge' or $rel eq '>=' or $rel eq '>') {
	return $res >= 0;
    } elsif ($rel eq 'eq' or $rel eq '=') {
	return $res == 0;
    } elsif ($rel eq 'le' or $rel eq '<=' or $rel eq '<') {
	return $res <= 0;
    } elsif ($rel eq 'lt' or $rel eq '<<') {
	return $res < 0;
    } else {
	die "bad relation '$rel'";
    }
}

=item check_version($version, $die)

If $die is false (or unset), returns true if the version is valid and
false if it contains illegal characters. If $die is true, it dies with
an error message if it contains illegal characters, otherwise it returns
true.

=cut

sub check_version ($;$) {
    my ($version, $die) = @_;
    $version ||= "";

    if ($version =~ m/[^-+:.0-9a-zA-Z~]/o) {
        error(_g("version number contains illegal character `%s'"), $&) if $die;
        return 0;
    }
    return 1;
}

=back

=head1 AUTHOR

Don Armstrong <don@donarmstrong.com>, Colin Watson
<cjwatson@debian.org> and Raphaël Hertzog <hertzog@debian.org>, based on
the implementation in C<dpkg/lib/vercmp.c> by Ian Jackson and others.

=cut

1;
