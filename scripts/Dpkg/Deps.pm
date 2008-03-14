# Copyright 2007 Raphael Hertzog <hertzog@debian.org>
#
# This program is free software; you may redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2, or (at your option)
# any later version.
#
# This is distributed in the hope that it will be useful, but without
# any warranty; without even the implied warranty of merchantability or
# fitness for a particular purpose. See the GNU General Public License
# for more details.
#
# A copy of the GNU General Public License is available as
# /usr/share/common-licenses/GPL in the Debian GNU/Linux distribution
# or on the World Wide Web at http://www.gnu.org/copyleft/gpl.html.
# You can also obtain it by writing to the Free Software Foundation, Inc.,
# 51 Franklin St, Fifth Floor, Boston, MA 02110-1301, USA.
#########################################################################
# Several parts are inspired by lib/Dep.pm from lintian (same license)
#
# Copyright (C) 1998 Richard Braakman
# Portions Copyright (C) 1999 Darren Benham
# Portions Copyright (C) 2000 Sean 'Shaleh' Perry
# Portions Copyright (C) 2004 Frank Lichtenheld
# Portions Copyright (C) 2006 Russ Allbery

package Dpkg::Deps;

=head1 NAME

Dpkg::Deps - parse and manipulate dependencies of Debian packages

=head1 DESCRIPTION

The Dpkg::Deps module provides one generic Dpkg::Deps::parse() function
to turn a dependency line in a set of Dpkg::Deps::{Simple,AND,OR,Union}
objects depending on the case.

It also provides some constants:

=over 4

=item @pkg_dep_fields

List of fields that contains dependency-like information in a binary
Debian package. The fields that express real dependencies are sorted from
the stronger to the weaker.

=item @src_dep_fields

List of fields that contains dependencies-like information in a binary
Debian package.

=item %dep_field_type

Associate to each field a type, either "normal" for a real dependency field
(Pre-Depends, Depends, ...) or "union" for other relation fields sharing
the same syntax (Conflicts, Breaks, etc.).

=back

=head1 FUNCTIONS

=over 4

=cut

use strict;
use warnings;

use Dpkg::Version qw(compare_versions);
use Dpkg::Arch qw(get_host_arch);
use Dpkg::ErrorHandling qw(warning);
use Dpkg::Gettext;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(@pkg_dep_fields @src_dep_fields %dep_field_type
		    %relation_ordering);

# Some generic variables
our @pkg_dep_fields = qw(Pre-Depends Depends Recommends Suggests Enhances
                         Conflicts Breaks Replaces Provides);
our @src_dep_fields = qw(Build-Depends Build-Depends-Indep
                         Build-Conflicts Build-Conflicts-Indep);
our %dep_field_type = (
	'Pre-Depends' => 'normal',
	'Depends' => 'normal',
	'Recommends' => 'normal',
	'Suggests' => 'normal',
	'Enhances' => 'union',
	'Conflicts' => 'union',
	'Breaks' => 'union',
	'Replaces' => 'union',
	'Provides' => 'union',
	'Build-Depends' => 'normal',
	'Build-Depends-Indep' => 'normal',
	'Build-Conflicts' => 'union',
	'Build-Conflicts-Indep' => 'union',
);

our %relation_ordering = (
	'undef' => 0,
	'>=' => 1,
	'>>' => 2,
	'=' => 3,
	'<<' => 4,
	'<=' => 5,
);

# Some factorized function

=item Dpkg::Deps::arch_is_superset(\@p, \@q)

Returns true if the arch list @p is a superset of arch list @q.
The arguments can also be undef in case there's no explicit architecture
restriction.

=cut
sub arch_is_superset {
    my ($p, $q) = @_;
    my $p_arch_neg = defined($p) && $p->[0] =~ /^!/;
    my $q_arch_neg = defined($q) && $q->[0] =~ /^!/;

    # If "p" has no arches, it is a superset of q and we should fall through
    # to the version check.
    if (not defined $p) {
	return 1;
    }

    # If q has no arches, it is a superset of p and there are no useful
    # implications.
    elsif (not defined $q) {
	return 0;
    }

    # Both have arches.  If neither are negated, we know nothing useful
    # unless q is a subset of p.
    elsif (not $p_arch_neg and not $q_arch_neg) {
	my %p_arches = map { $_ => 1 } @{$p};
	my $subset = 1;
	for my $arch (@{$q}) {
	    $subset = 0 unless $p_arches{$arch};
	}
	return 0 unless $subset;
    }

    # If both are negated, we know nothing useful unless p is a subset of
    # q (and therefore has fewer things excluded, and therefore is more
    # general).
    elsif ($p_arch_neg and $q_arch_neg) {
	my %q_arches = map { $_ => 1 } @{$q};
	my $subset = 1;
	for my $arch (@{$p}) {
	    $subset = 0 unless $q_arches{$arch};
	}
	return 0 unless $subset;
    }

    # If q is negated and p isn't, we'd need to know the full list of
    # arches to know if there's any relationship, so bail.
    elsif (not $p_arch_neg and $q_arch_neg) {
	return 0;
    }

    # If p is negated and q isn't, q is a subset of p if none of the
    # negated arches in p are present in q.
    elsif ($p_arch_neg and not $q_arch_neg) {
	my %q_arches = map { $_ => 1 } @{$q};
	my $subset = 1;
	for my $arch (@{$p}) {
	    $subset = 0 if $q_arches{substr($arch, 1)};
	}
	return 0 unless $subset;
    }
    return 1;
}

=item Dpkg::Deps::version_implies($rel_p, $v_p, $rel_q, $v_q)

($rel_p, $v_p) and ($rel_q, $v_q) express two dependencies as (relation,
version). The relation variable can have the following values: '=', '<<',
'<=', '>=', '>>'.

This functions returns 1 if the "p" dependency implies the "q"
dependency. It returns 0 if the "p" dependency implies that "q" is
not satisfied. It returns undef when there's no implication.

=cut
sub version_implies {
    my ($rel_p, $v_p, $rel_q, $v_q) = @_;

    # q wants an exact version, so p must provide that exact version.  p
    # disproves q if q's version is outside the range enforced by p.
    if ($rel_q eq '=') {
        if ($rel_p eq '<<') {
            return compare_versions($v_p, '<=', $v_q) ? 0 : undef;
        } elsif ($rel_p eq '<=') {
            return compare_versions($v_p, '<<', $v_q) ? 0 : undef;
        } elsif ($rel_p eq '>>') {
            return compare_versions($v_p, '>=', $v_q) ? 0 : undef;
        } elsif ($rel_p eq '>=') {
            return compare_versions($v_p, '>>', $v_q) ? 0 : undef;
        } elsif ($rel_p eq '=') {
            return compare_versions($v_p, '=', $v_q);
        }
    }

    # A greater than clause may disprove a less than clause. An equal
    # cause might as well.  Otherwise, if
    # p's clause is <<, <=, or =, the version must be <= q's to imply q.
    if ($rel_q eq '<=') {
        if ($rel_p eq '>>') {
            return compare_versions($v_p, '>=', $v_q) ? 0 : undef;
        } elsif ($rel_p eq '>=') {
            return compare_versions($v_p, '>>', $v_q) ? 0 : undef;
	} elsif ($rel_p eq '=') {
            return compare_versions($v_p, '<=', $v_q) ? 1 : 0;
        } else { # <<, <=
            return compare_versions($v_p, '<=', $v_q) ? 1 : undef;
        }
    }

    # Similar, but << is stronger than <= so p's version must be << q's
    # version if the p relation is <= or =.
    if ($rel_q eq '<<') {
        if ($rel_p eq '>>' or $rel_p eq '>=') {
            return compare_versions($v_p, '>=', $v_p) ? 0 : undef;
        } elsif ($rel_p eq '<<') {
            return compare_versions($v_p, '<=', $v_q) ? 1 : undef;
	} elsif ($rel_p eq '=') {
            return compare_versions($v_p, '<<', $v_q) ? 1 : 0;
        } else { # <<, <=
            return compare_versions($v_p, '<<', $v_q) ? 1 : undef;
        }
    }

    # Same logic as above, only inverted.
    if ($rel_q eq '>=') {
        if ($rel_p eq '<<') {
            return compare_versions($v_p, '<=', $v_q) ? 0 : undef;
        } elsif ($rel_p eq '<=') {
            return compare_versions($v_p, '<<', $v_q) ? 0 : undef;
	} elsif ($rel_p eq '=') {
            return compare_versions($v_p, '>=', $v_q) ? 1 : 0;
        } else { # >>, >=
            return compare_versions($v_p, '>=', $v_q) ? 1 : undef;
        }
    }
    if ($rel_q eq '>>') {
        if ($rel_p eq '<<' or $rel_p eq '<=') {
            return compare_versions($v_p, '<=', $v_q) ? 0 : undef;
        } elsif ($rel_p eq '>>') {
            return compare_versions($v_p, '>=', $v_q) ? 1 : undef;
	} elsif ($rel_p eq '=') {
            return compare_versions($v_p, '>>', $v_q) ? 1 : 0;
        } else {
            return compare_versions($v_p, '>>', $v_q) ? 1 : undef;
        }
    }

    return undef;
}

=item Dpkg::Deps::parse($line, %options)

This function parse the dependency line and returns an object, either a
Dpkg::Deps::AND or a Dpkg::Deps::Union. Various options can alter the
behaviour of that function.

=over 4

=item use_arch (defaults to 1)

Take into account the architecture restriction part of the dependencies.
Set to 0 to completely ignore that information.

=item host_arch (defaults to the current architecture)

Define the host architecture. Needed only if the reduce_arch option is
set to 1. By default it uses Dpkg::Arch::get_host_arch() to identify
the proper architecture.

=item reduce_arch (defaults to 0)

If set to 1, ignore dependencies that do not concern the current host
architecture. This implicitely strips off the architecture restriction
list so that the resulting dependencies are directly applicable to the
current architecture.

=item union (defaults to 0)

If set to 1, returns a Dpkg::Deps::Union instead of a Dpkg::Deps::AND. Use
this when parsing non-dependency fields like Conflicts (see
%dep_field_type).

=back

=cut
sub parse {
    my $dep_line = shift;
    my %options = (@_);
    $options{use_arch} = 1 if not exists $options{use_arch};
    $options{reduce_arch} = 0 if not exists $options{reduce_arch};
    $options{host_arch} = get_host_arch() if not exists $options{host_arch};
    $options{union} = 0 if not exists $options{union};

    my @dep_list;
    foreach my $dep_and (split(/\s*,\s*/m, $dep_line)) {
        my @or_list = ();
        foreach my $dep_or (split(/\s*\|\s*/m, $dep_and)) {
	    my $dep_simple = Dpkg::Deps::Simple->new($dep_or);
	    if (not defined $dep_simple->{package}) {
		warning(sprintf(_g("can't parse dependency %s"), $dep_and));
		return undef;
	    }
	    $dep_simple->{arches} = undef if not $options{use_arch};
            if ($options{reduce_arch}) {
		$dep_simple->reduce_arch($options{host_arch});
		next if not $dep_simple->arch_is_concerned($options{host_arch});
	    }
	    push @or_list, $dep_simple;
        }
	next if not @or_list;
	if (scalar @or_list == 1) {
	    push @dep_list, $or_list[0];
	} else {
	    my $dep_or = Dpkg::Deps::OR->new();
	    $dep_or->add($_) foreach (@or_list);
	    push @dep_list, $dep_or;
	}
    }
    my $dep_and;
    if ($options{union}) {
	$dep_and = Dpkg::Deps::Union->new();
    } else {
	$dep_and = Dpkg::Deps::AND->new();
    }
    $dep_and->add($_) foreach (@dep_list);
    return $dep_and;
}

=item Dpkg::Deps::compare($a, $b)

This functions is used to order AND and Union dependencies prior to
dumping.

=back

=cut
sub compare {
    my ($a, $b) = @_;
    return -1 if $a->is_empty();
    return 1 if $b->is_empty();
    while ($a->isa('Dpkg::Deps::Multiple')) {
	return -1 if $a->is_empty();
	my @deps = $a->get_deps();
	$a = $deps[0];
    }
    while ($b->isa('Dpkg::Deps::Multiple')) {
	return 1 if $b->is_empty();
	my @deps = $b->get_deps();
	$b = $deps[0];
    }
    my $ar = defined($a->{relation}) ? $a->{relation} : "undef";
    my $br = defined($b->{relation}) ? $b->{relation} : "undef";
    return (($a->{package} cmp $b->{package}) ||
	    ($relation_ordering{$ar} <=> $relation_ordering{$br}) ||
	    ($a->{version} cmp $b->{version}));
}


package Dpkg::Deps::Simple;

=head1 OBJECTS - Dpkg::Deps::*

There are several kind of dependencies. A Dpkg::Deps::Simple dependency
represents a single dependency statement (it relates to one package only).
Dpkg::Deps::Multiple dependencies are built on top of this object
and combine several dependencies in a different manners. Dpkg::Deps::AND
represents the logical "AND" between dependencies while Dpkg::Deps::OR
represents the logical "OR". Dpkg::Deps::Multiple objects can contain
Dpkg::Deps::Simple object as well as other Dpkg::Deps::Multiple objects.

In practice, the code is only meant to handle the realistic cases which,
given Debian's dependencies structure, imply those restrictions: AND can
contain Simple or OR objects, OR can only contain Simple objects.

Dpkg::Deps::KnowFacts is a special object that is used while evaluating
dependencies and while trying to simplify them. It represents a set of
installed packages along with the virtual packages that they might
provide.

=head2 Common functions

=over 4

=item $dep->is_empty()

Returns true if the dependency is empty and doesn't contain any useful
information. This is true when a Dpkg::Deps::Simple object has not yet
been initialized or when a (descendant of) Dpkg::Deps::Multiple contains
an empty list of dependencies.

=item $dep->get_deps()

Return a list of sub-dependencies. For Dpkg::Deps::Simple it returns
itself.

=item $dep->dump()

Return a string representing the dependency.

=item $dep->implies($other_dep)

Returns 1 when $dep implies $other_dep. Returns 0 when $dep implies
NOT($other_dep). Returns undef when there's no implication. $dep and
$other_dep do not need to be of the same type.

=item $dep->sort()

Sort alphabetically the internal list of dependencies. It's a no-op for
Dpkg::Deps::Simple objects.

=item $dep->arch_is_concerned($arch)

Returns true if the dependency applies to the indicated architecture. For
multiple dependencies, it returns true if at least one of the
sub-dependencies apply to this architecture.

=item $dep->reduce_arch($arch)

Simplify the dependency to contain only information relevant to the given
architecture. A Dpkg::Deps::Simple object can be left empty after this
operation. For Dpkg::Deps::Multiple objects, the non-relevant
sub-dependencies are simply removed.

This trims off the architecture restriction list of Dpkg::Deps::Simple
objects.

=item $dep->get_evaluation($facts)

Evaluates the dependency given a list of installed packages and a list of
virtual packages provided. Those lists are part of the
Dpkg::Deps::KnownFacts object given as parameters.

Returns 1 when it's true, 0 when it's false, undef when some information
is lacking to conclude.

=item $dep->simplify_deps($facts, @assumed_deps)

Simplify the dependency as much as possible given the list of facts (see
object Dpkg::Deps::KnownFacts) and a list of other dependencies that we
know to be true.

=back

=head2 Dpkg::Deps::Simple

Such an object has four interesting properties:

=over 4

=item package

The package name (can be undef if the dependency has not been initialized
or if the simplification of the dependency lead to its removal).

=item relation

The relational operator: "=", "<<", "<=", ">=" or ">>". It can be
undefined if the dependency had no version restriction. In that case the
following field is also undefined.

=item version

The version.

=item arches

The list of architectures where this dependency is applicable. It's
undefined when there's no restriction, otherwise it's an
array ref. It can contain an exclusion list, in that case each
architecture is prefixed with an exclamation mark.

=back

=head3 Methods

=over 4

=item $simple_dep->parse("dpkg-dev (>= 1.14.8) [!hurd-i386]")

Parse the dependency and modify internal properties to match the parsed
dependency.

=item $simple_dep->merge_union($other_dep)

Returns true if $simple_dep could be modified to represent the union of
both dependencies. Otherwise returns false.

=back

=cut

use strict;
use warnings;

use Dpkg::Arch qw(debarch_is);
use Dpkg::Version qw(compare_versions);
use Dpkg::ErrorHandling qw(internerr);
use Dpkg::Gettext;

sub new {
    my ($this, $arg) = @_;
    my $class = ref($this) || $this;
    my $self = {
	'package' => undef,
	'relation' => undef,
	'version' => undef,
	'arches' => undef,
    };
    bless $self, $class;
    $self->parse($arg) if defined($arg);
    return $self;
}

sub parse {
    my ($self, $dep) = @_;
    return if not $dep =~
            /^\s*                           # skip leading whitespace
              ([a-zA-Z0-9][a-zA-Z0-9+.-]*)  # package name
              (?:                           # start of optional part
                \s* \(                      # open parenthesis for version part
                \s* (<<|<=|=|>=|>>|<|>)     # relation part
                \s* (.*?)                   # do not attempt to parse version
                \s* \)                      # closing parenthesis
              )?                            # end of optional part
              (?:                           # start of optional architecture
                \s* \[                      # open bracket for architecture
                \s* (.*?)                   # don't parse architectures now
                \s* \]                      # closing bracket
              )?                            # end of optional architecture
	      \s*$			    # trailing spaces at end
            /mx;
    $self->{package} = $1;
    $self->{relation} = $2;
    $self->{version} = $3;
    if (defined($4)) {
	$self->{arches} = [ split(/\s+/, $4) ];
    }
    # Standardize relation field
    if (defined($self->{relation})) {
	$self->{relation} = '<<' if ($self->{relation} eq '<');
	$self->{relation} = '>>' if ($self->{relation} eq '>');
    }
}

sub dump {
    my $self = shift;
    my $res = $self->{package};
    if (defined($self->{relation})) {
	$res .= " (" . $self->{relation} . " " . $self->{version} .  ")";
    }
    if (defined($self->{'arches'})) {
	$res .= " [" . join(" ", @{$self->{arches}}) . "]";
    }
    return $res;
}

# Returns true if the dependency in parameter can deduced from the current
# dependency. Returns false if it can be negated. Returns undef if nothing
# can be concluded.
sub implies {
    my ($self, $o) = @_;
    if ($o->isa('Dpkg::Deps::Simple')) {
	# An implication is only possible on the same package
	return undef if $self->{package} ne $o->{package};

	# Our architecture set must be a superset of the architectures for
	# o, otherwise we can't conclude anything.
	return undef unless Dpkg::Deps::arch_is_superset($self->{arches}, $o->{arches});

	# If o has no version clause, then our dependency is stronger
	return 1 if not defined $o->{relation};
	# If o has a version clause, we must also have one, otherwise there
	# can't be an implication
	return undef if not defined $self->{relation};

	return Dpkg::Deps::version_implies($self->{relation}, $self->{version},
		$o->{relation}, $o->{version});

    } elsif ($o->isa('Dpkg::Deps::AND')) {
	# TRUE: Need to imply all individual elements
	# FALSE: Need to NOT imply at least one individual element
	my $res = 1;
	foreach my $dep ($o->get_deps()) {
	    my $implication = $self->implies($dep);
	    unless (defined($implication) && $implication == 1) {
		$res = $implication;
		last if defined $res;
	    }
	}
	return $res;
    } elsif ($o->isa('Dpkg::Deps::OR')) {
	# TRUE: Need to imply at least one individual element
	# FALSE: Need to not apply all individual elements
	# UNDEF: The rest
	my $res = undef;
	foreach my $dep ($o->get_deps()) {
	    my $implication = $self->implies($dep);
	    if (defined($implication)) {
		if (not defined $res) {
		    $res = $implication;
		} else {
		    if ($implication) {
			$res = 1;
		    } else {
			$res = 0;
		    }
		}
		last if defined($res) && $res == 1;
	    }
	}
	return $res;
    } else {
	internerr(sprintf(_g("Dpkg::Deps::Simple can't evaluate implication with a %s!"), ref($o)));
    }
}

sub get_deps {
    my $self = shift;
    return $self;
}

sub sort {
    # Nothing to sort
}

sub arch_is_concerned {
    my ($self, $host_arch) = @_;

    return 0 if not defined $self->{package}; # Empty dep
    return 1 if not defined $self->{arches};  # Dep without arch spec

    my $seen_arch = 0;
    foreach my $arch (@{$self->{arches}}) {
	$arch=lc($arch);

	if ($arch =~ /^!/) {
	    my $not_arch = $arch;
	    $not_arch =~ s/^!//;

	    if (debarch_is($host_arch, $not_arch)) {
		$seen_arch = 0;
		last;
	    } else {
		# !arch includes by default all other arches
		# unless they also appear in a !otherarch
		$seen_arch = 1;
	    }
	} elsif (debarch_is($host_arch, $arch)) {
	    $seen_arch = 1;
	    last;
	}
    }
    return $seen_arch;
}

sub reduce_arch {
    my ($self, $host_arch) = @_;
    if (not $self->arch_is_concerned($host_arch)) {
	$self->{package} = undef;
	$self->{relation} = undef;
	$self->{version} = undef;
	$self->{arches} = undef;
    } else {
	$self->{arches} = undef;
    }
}

sub get_evaluation {
    my ($self, $facts) = @_;
    return undef if not defined $self->{package};
    my ($check, $param) = $facts->check_package($self->{package});
    if ($check) {
	if (defined $self->{relation}) {
	    if (ref($param)) {
		# Provided packages
		# XXX: Once support for versioned provides is in place,
		# this part must be adapted
		return 0;
	    } else {
		if (defined($param)) {
		    if (compare_versions($param, $self->{relation}, $self->{version})) {
			return 1;
		    } else {
			return 0;
		    }
		} else {
		    return undef;
		}
	    }
	} else {
	    return 1;
	}
    }
    return 0;
}

sub simplify_deps {
    my ($self, $facts) = @_;
    my $eval = $self->get_evaluation($facts);
    if (defined($eval) and $eval == 1) {
	$self->{package} = undef;
	$self->{relation} = undef;
	$self->{version} = undef;
	$self->{arches} = undef;
    }
}

sub is_empty {
    my $self = shift;
    return not defined $self->{package};
}

sub merge_union {
    my ($self, $o) = @_;
    return 0 if not $o->isa('Dpkg::Deps::Simple');
    return 0 if $self->is_empty() or $o->is_empty();
    return 0 if $self->{package} ne $o->{package};
    return 0 if defined $self->{arches} or defined $o->{arches};

    if (not defined $o->{relation} and defined $self->{relation}) {
	# Union is the non-versioned dependency
	$self->{relation} = undef;
	$self->{version} = undef;
	return 1;
    }

    my $implication = $self->implies($o);
    my $rev_implication = $o->implies($self);
    if (defined($implication)) {
	if ($implication) {
	    $self->{relation} = $o->{relation};
	    $self->{version} = $o->{version};
	    return 1;
	} else {
	    return 0;
	}
    }
    if (defined($rev_implication)) {
	if ($rev_implication) {
	    # Already merged...
	    return 1;
	} else {
	    return 0;
	}
    }
    return 0;
}

package Dpkg::Deps::Multiple;

=head2 Dpkg::Deps::Multiple

This the base class for Dpkg::Deps::{AND,OR,Union}. It contains the

=over 4

=item $mul->add($dep)

Add a new dependency object at the end of the list.

=back

=cut
use strict;
use warnings;

use Dpkg::ErrorHandling qw(internerr);

sub new {
    my $this = shift;
    my $class = ref($this) || $this;
    my $self = { 'list' => [ @_ ] };
    bless $self, $class;
    return $self;
}

sub add {
    my $self = shift;
    push @{$self->{list}}, @_;
}

sub get_deps {
    my $self = shift;
    return grep { not $_->is_empty() } @{$self->{list}};
}

sub sort {
    my $self = shift;
    my @res = ();
    @res = sort { Dpkg::Deps::compare($a, $b) } @{$self->{list}};
    $self->{list} = [ @res ];
}

sub arch_is_concerned {
    my ($self, $host_arch) = @_;
    my $res = 0;
    foreach my $dep (@{$self->{list}}) {
	$res = 1 if $dep->arch_is_concerned($host_arch);
    }
    return $res;
}

sub reduce_arch {
    my ($self, $host_arch) = @_;
    my @new;
    foreach my $dep (@{$self->{list}}) {
	$dep->reduce_arch($host_arch);
	push @new, $dep if $dep->arch_is_concerned($host_arch);
    }
    $self->{list} = [ @new ];
}

sub is_empty {
    my $self = shift;
    return scalar @{$self->{list}} == 0;
}

sub merge_union {
    internerr("The method merge_union() is only valid for Dpkg::Deps::Simple");
}

package Dpkg::Deps::AND;

=head2 Dpkg::Deps::AND

This object represents a list of dependencies who must be met at the same
time.

=over 4

=item $and->dump()

The dump method uses ", " to join the list of sub-dependencies.

=back

=cut

use strict;
use warnings;

our @ISA = qw(Dpkg::Deps::Multiple);

sub dump {
    my $self = shift;
    return join(", ", map { $_->dump() } grep { not $_->is_empty() } $self->get_deps());
}

sub implies {
    my ($self, $o) = @_;
    # If any individual member can imply $o or NOT $o, we're fine
    foreach my $dep ($self->get_deps()) {
	my $implication = $dep->implies($o);
	return 1 if defined($implication) && $implication == 1;
	return 0 if defined($implication) && $implication == 0;
    }
    # If o is an AND, we might have an implication, if we find an
    # implication within us for each predicate in o
    if ($o->isa('Dpkg::Deps::AND')) {
	my $subset = 1;
	foreach my $odep ($o->get_deps()) {
	    my $found = 0;
	    foreach my $dep ($self->get_deps()) {
		$found = 1 if $dep->implies($odep);
	    }
	    $subset = 0 if not $found;
	}
	return 1 if $subset;
    }
    return undef;
}

sub get_evaluation {
    my ($self, $facts) = @_;
    # Return 1 only if all members evaluates to true
    # Return 0 if at least one member evaluates to false
    # Return undef otherwise
    my $result = 1;
    foreach my $dep ($self->get_deps()) {
	my $eval = $dep->get_evaluation($facts);
	if (not defined $eval) {
	    $result = undef;
	} elsif ($eval == 0) {
	    $result = 0;
	    last;
	} elsif ($eval == 1) {
	    # Still possible
	}
    }
    return $result;
}

sub simplify_deps {
    my ($self, $facts, @knowndeps) = @_;
    my @new;

WHILELOOP:
    while (@{$self->{list}}) {
	my $dep = shift @{$self->{list}};
	my $eval = $dep->get_evaluation($facts);
	next if defined($eval) and $eval == 1;
	foreach my $odep (@knowndeps, @new) {
	    next WHILELOOP if $odep->implies($dep);
	}
        # When a dependency is implied by another dependency that
        # follows, then invert them
        # "a | b, c, a"  becomes "a, c" and not "c, a"
        my $i = 0;
	foreach my $odep (@{$self->{list}}) {
            if (defined $odep and $odep->implies($dep)) {
                splice @{$self->{list}}, $i, 1;
                unshift @{$self->{list}}, $odep;
                next WHILELOOP;
            }
            $i++;
	}
	push @new, $dep;
    }
    $self->{list} = [ @new ];
}


package Dpkg::Deps::OR;

=head2 Dpkg::Deps::OR

This object represents a list of dependencies of which only one must be met
for the dependency to be true.

=over 4

=item $or->dump()

The dump method uses " | " to join the list of sub-dependencies.

=back

=cut

use strict;
use warnings;

our @ISA = qw(Dpkg::Deps::Multiple);

sub dump {
    my $self = shift;
    return join(" | ", map { $_->dump() } grep { not $_->is_empty() } $self->get_deps());
}

sub implies {
    my ($self, $o) = @_;

    # Special case for AND with a single member, replace it by its member
    if ($o->isa('Dpkg::Deps::AND')) {
	my @subdeps = $o->get_deps();
	if (scalar(@subdeps) == 1) {
	    $o = $subdeps[0];
	}
    }

    # In general, an OR dependency can't imply anything except if each
    # of its member implies a member in the other OR dependency
    if ($o->isa('Dpkg::Deps::OR')) {
	my $subset = 1;
	foreach my $dep ($self->get_deps()) {
	    my $found = 0;
	    foreach my $odep ($o->get_deps()) {
		$found = 1 if $dep->implies($odep);
	    }
	    $subset = 0 if not $found;
	}
	return 1 if $subset;
    }
    return undef;
}

sub get_evaluation {
    my ($self, $facts) = @_;
    # Returns false if all members evaluates to 0
    # Returns true if at least one member evaluates to true
    # Returns undef otherwise
    my $result = 0;
    foreach my $dep ($self->get_deps()) {
	my $eval = $dep->get_evaluation($facts);
	if (not defined $eval) {
	    $result = undef;
	} elsif ($eval == 1) {
	    $result = 1;
	    last;
	} elsif ($eval == 0) {
	    # Still possible to have a false evaluation
	}
    }
    return $result;
}

sub simplify_deps {
    my ($self, $facts) = @_;
    my @new;

WHILELOOP:
    while (@{$self->{list}}) {
	my $dep = shift @{$self->{list}};
	my $eval = $dep->get_evaluation($facts);
	if (defined($eval) and $eval == 1) {
	    $self->{list} = [];
	    return;
	}
	foreach my $odep (@new, @{$self->{list}}) {
	    next WHILELOOP if $odep->implies($dep);
	}
	push @new, $dep;
    }
    $self->{list} = [ @new ];
}

package Dpkg::Deps::Union;

=head2 Dpkg::Deps::Union

This object represents a list of relationships.

=over 4

=item $union->dump()

The dump method uses ", " to join the list of relationships.

=item $union->implies($other_dep)
=item $union->get_evaluation($other_dep)

Those methods are not meaningful for this object and always return undef.

=item $union->simplify_deps($facts)

The simplication is done to generate an union of all the relationships.
It uses $simple_dep->merge_union($other_dep) to get the its job done.

=back

=cut

use strict;
use warnings;

our @ISA = qw(Dpkg::Deps::Multiple);

sub dump {
    my $self = shift;
    return join(", ", map { $_->dump() } grep { not $_->is_empty() } $self->get_deps());
}

sub implies {
    # Implication test are not useful on Union
    return undef;
}

sub get_evaluation {
    # Evaluation are not useful on Union
    return undef;
}

sub simplify_deps {
    my ($self, $facts) = @_;
    my @new;

WHILELOOP:
    while (@{$self->{list}}) {
	my $dep = shift @{$self->{list}};
	foreach my $odep (@new) {
	    next WHILELOOP if $dep->merge_union($odep);
	}
	push @new, $dep;
    }
    $self->{list} = [ @new ];
}

package Dpkg::Deps::KnownFacts;

=head2 Dpkg::Deps::KnowFacts

This object represents a list of installed packages and a list of virtual
packages provided (by the set of installed packages).

=over 4

=item my $facts = Dpkg::Deps::KnownFacts->new();

Create a new object.

=cut
use strict;
use warnings;

sub new {
    my $this = shift;
    my $class = ref($this) || $this;
    my $self = { 'pkg' => {}, 'virtualpkg' => {} };
    bless $self, $class;
    return $self;
}

=item $facts->add_installed_package($package, $version)

Record that the given version of the package is installed. If $version is
undefined we know that the package is installed but we don't know which
version it is.

=cut
sub add_installed_package {
    my ($self, $pkg, $ver) = @_;
    $self->{pkg}{$pkg} = $ver;
}

=item $facts->add_provided_package($virtual, $relation, $version, $by)

Record that the "$by" package provides the $virtual package. $relation
and $version correspond to the associated relation given in the Provides
field. This might be used in the future for versioned provides.

=cut
sub add_provided_package {
    my ($self, $pkg, $rel, $ver, $by) = @_;
    if (not exists $self->{virtualpkg}{$pkg}) {
	$self->{virtualpkg}{$pkg} = [];
    }
    push @{$self->{virtualpkg}{$pkg}}, [ $by, $rel, $ver ];
}

=item my ($check, $param) = $facts->check_package($package)

$check is one when the package is found. For a real package, $param
contains the version. For a virtual package, $param contains an array
reference containing the list of packages that provide it (each package is
listed as [ $provider, $relation, $version ]).

=back

=cut
sub check_package {
    my ($self, $pkg) = @_;
    if (exists $self->{pkg}{$pkg}) {
	return (1, $self->{pkg}{$pkg});
    }
    if (exists $self->{virtualpkg}{$pkg}) {
	return (1, $self->{virtualpkg}{$pkg});
    }
    return (0, undef);
}

1;
