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

use strict;
use warnings;

use Dpkg::Version qw(compare_versions);
use Dpkg::Arch qw(get_host_arch);
use Dpkg::ErrorHandling qw(warning);
use Dpkg::Gettext;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(@pkg_dep_fields @src_dep_fields %dep_field_type);

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

# Some factorized function

# Returns true if the arch list $p is a superset of arch list $q
sub arch_is_superset {
    my ($p, $q) = @_;
    my $p_arch_neg = defined($p) && $p->[0] =~ /^!/;
    my $q_arch_neg = defined($q) && $q->[0] =~ /^!/;

    # If "a" has no arches, it is a superset of q and we should fall through
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
    return undef if not @dep_list;
    my $dep_and;
    if ($options{union}) {
	$dep_and = Dpkg::Deps::Union->new();
    } else {
	$dep_and = Dpkg::Deps::AND->new();
    }
    $dep_and->add($_) foreach (@dep_list);
    return $dep_and;
}

package Dpkg::Deps::Simple;

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
    return undef;
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
    return @{$self->{list}};
}

sub sort {
    my $self = shift;
    my @res = ();
    @res = sort { $a->dump() cmp $b->dump() } @{$self->{list}};
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
    my $result = 1;
    foreach my $dep ($self->get_deps()) {
	my $eval = $dep->get_evaluation($facts);
	if (not defined $eval) {
	    $result = undef;
	    last;
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
	foreach my $odep (@knowndeps, @new, @{$self->{list}}) {
	    next WHILELOOP if $odep->implies($dep);
	}
	push @new, $dep;
    }
    $self->{list} = [ @new ];
}


package Dpkg::Deps::OR;

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
    my $result = 0;
    foreach my $dep ($self->get_deps()) {
	my $eval = $dep->get_evaluation($facts);
	if (not defined $eval) {
	    $result = undef;
	    last;
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

use strict;
use warnings;

sub new {
    my $this = shift;
    my $class = ref($this) || $this;
    my $self = { 'pkg' => {}, 'virtualpkg' => {} };
    bless $self, $class;
    return $self;
}

sub add_installed_package {
    my ($self, $pkg, $ver) = @_;
    $self->{pkg}{$pkg} = $ver;
}

sub add_provided_package {
    my ($self, $pkg, $rel, $ver, $by) = @_;
    if (not exists $self->{virtualpkg}{$pkg}) {
	$self->{virtualpkg}{$pkg} = [];
    }
    push @{$self->{virtualpkg}{$pkg}}, [ $by, $rel, $ver ];
}

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
