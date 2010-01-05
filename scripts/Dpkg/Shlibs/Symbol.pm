# Copyright © 2007 Raphaël Hertzog <hertzog@debian.org>
# Copyright © 2009 Modestas Vainius <modestas@vainius.eu>
#
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

package Dpkg::Shlibs::Symbol;

use strict;
use warnings;
use Dpkg::Gettext;
use Dpkg::Deps;
use Dpkg::ErrorHandling;
use Storable qw();
use Dpkg::Shlibs::Cppfilt;

sub new {
    my $this = shift;
    my $class = ref($this) || $this;
    my %args = @_;
    my $self = bless {
	symbol => undef,
	symbol_templ => undef,
	minver => undef,
	dep_id => 0,
	deprecated => 0,
	tags => {},
	tagorder => [],
    }, $class;
    $self->{$_} = $args{$_} foreach keys %args;
    return $self;
}

# Shallow clone
sub sclone {
    my $self = shift;
    my $clone = { %$self };
    if (@_) {
	my %args=@_;
	$clone->{$_} = $args{$_} foreach keys %args;
    }
    return bless $clone, ref $self;
}

# Deep clone
sub dclone {
    my $self = shift;
    my $clone = Storable::dclone($self);
    if (@_) {
	my %args=@_;
	$clone->{$_} = $args{$_} foreach keys %args;
    }
    return $clone;
}

sub parse_tagspec {
    my ($self, $tagspec) = @_;

    if ($tagspec =~ /^\((.*?)\)(.*)$/ && $1) {
	# (tag1=t1 value|tag2|...|tagN=tNp)
	# Symbols ()|= cannot appear in the tag names and values
	my $tagspec = $1;
	my $rest = ($2) ? $2 : "";
	my @tags = split(/\|/, $tagspec);

	# Parse each tag
	for my $tag (@tags) {
	    if ($tag =~ /^(.*)=(.*)$/) {
		# Tag with value
		$self->add_tag($1, $2);
	    } else {
		# Tag without value
		$self->add_tag($tag, undef);
	    }
	}
	return $rest;
    }
    return undef;
}

sub parse {
    my ($self, $symbolspec) = @_;
    my $symbol;
    my $symbol_templ;
    my $symbol_quoted;
    my $rest;

    if (defined($symbol = $self->parse_tagspec($symbolspec))) {
	# (tag1=t1 value|tag2|...|tagN=tNp)"Foo::Bar::foobar()"@Base 1.0 1
	# Symbols ()|= cannot appear in the tag names and values

	# If the tag specification exists symbol name template might be quoted too
	if ($symbol =~ /^(['"])/ && $symbol =~ /^($1)(.*?)$1(.*)$/) {
	    $symbol_quoted = $1;
	    $symbol_templ = $2;
	    $symbol = $2;
	    $rest = $3;
	} else {
	    if ($symbol =~ m/^(\S+)(.*)$/) {
		$symbol_templ = $1;
		$symbol = $1;
		$rest = $2;
	    }
	}
	error(_g("symbol name unspecified: %s"), $symbolspec) if (!$symbol);
    } else {
	# No tag specification. Symbol name is up to the first space
	# foobarsymbol@Base 1.0 1
	if ($symbolspec =~ m/^(\S+)(.*)$/) {
	    $symbol = $1;
	    $rest = $2;
	} else {
	    return 0;
	}
    }
    $self->{symbol} = $symbol;
    $self->{symbol_templ} = $symbol_templ;
    $self->{symbol_quoted} = $symbol_quoted if ($symbol_quoted);

    # Now parse "the rest" (minver and dep_id)
    if ($rest =~ /^\s(\S+)(?:\s(\d+))?/) {
	$self->{minver} = $1;
	$self->{dep_id} = defined($2) ? $2 : 0;
    } else {
	return 0;
    }
    return 1;
}

# A hook for symbol initialization (typically processing of tags). The code
# here may even change symbol name. Called from
# Dpkg::Shlibs::SymbolFile::load().
sub initialize {
    my $self = shift;

    # Look for tags marking symbol patterns. The pattern may match multiple
    # real symbols.
    if ($self->has_tag('c++')) {
	# Raw symbol name is always demangled to the same alias while demangled
	# symbol name cannot be reliably converted back to raw symbol name.
	# Therefore, we can use hash for mapping.
	$self->init_pattern('alias-c++'); # Alias subtype is c++.
    }
    # Wildcard is an alias based pattern. It gets recognized here even if it is
    # not specially tagged.
    if (my $ver = $self->get_wildcard_version()) {
	error(_g("you can't use wildcards on unversioned symbols: %s"), $_) if $ver eq "Base";
	$self->init_pattern(($self->is_pattern()) ? 'generic' : 'alias-wildcard');
	$self->{pattern}{wildcard} = 1;
    }
    # As soon as regex is involved, we need to match each real
    # symbol against each pattern (aka 'generic' pattern).
    if ($self->has_tag('regex')) {
	$self->init_pattern('generic');
	# Pre-compile regular expression for better performance.
	my $regex = $self->get_symbolname();
	$self->{pattern}{regex} = qr/$regex/;
    }
}

sub get_symbolname {
    return $_[0]->{symbol};
}

sub get_symboltempl {
    return $_[0]->{symbol_templ} || $_[0]->{symbol};
}

sub set_symbolname {
    my ($self, $name, $quoted) = @_;
    if (defined $name) {
	$self->{symbol} = $name;
    }
    $self->{symbol_templ} = undef;
    if ($quoted) {
	$self->{symbol_quoted} = $quoted;
    } else {
	delete $self->{symbol_quoted};
    }
}

sub get_wildcard_version {
    my $self = shift;
    if ($self->get_symbolname() =~ /^\*@(.*)$/) {
	return $1;
    }
    return undef;
}

sub has_tags {
    my $self = shift;
    return scalar (@{$self->{tagorder}});
}

sub add_tag {
    my ($self, $tagname, $tagval) = @_;
    if (exists $self->{tags}{$tagname}) {
	$self->{tags}{$tagname} = $tagval;
	return 0;
    } else {
	$self->{tags}{$tagname} = $tagval;
	push @{$self->{tagorder}}, $tagname;
    }
    return 1;
}

sub delete_tag {
    my ($self, $tagname) = @_;
    if (exists $self->{tags}{$tagname}) {
	delete $self->{tags}{$tagname};
        $self->{tagorder} = [ grep { $_ ne $tagname } @{$self->{tagorder}} ];
	return 1;
    }
    return 0;
}

sub has_tag {
    my ($self, $tag) = @_;
    return exists $self->{tags}{$tag};
}

sub get_tag_value {
    my ($self, $tag) = @_;
    return $self->{tags}{$tag};
}

# Checks if the symbol is equal to another one (by name and tag set)
sub equals {
    my ($self, $other) = @_;

    # Compare names and tag sets
    return 0 if $self->{symbol} ne $other->{symbol};
    return 0 if scalar(@{$self->{tagorder}}) != scalar(@{$other->{tagorder}});

    for (my $i = 0; $i < scalar(@{$self->{tagorder}}); $i++) {
	my $tag = $self->{tagorder}->[$i];
	return 0 if $tag ne $other->{tagorder}->[$i];
	if (defined $self->{tags}{$tag} && defined $other->{tags}{$tag}) {
	    return 0 if $self->{tags}{$tag} ne defined $other->{tags}{$tag};
	} elsif (defined $self->{tags}{$tag} || defined $other->{tags}{$tag}) {
	    return 0;
	}
    }
    return 1;
}


sub is_optional {
    my $self = shift;
    return $self->has_tag("optional");
}

sub is_arch_specific {
    my $self = shift;
    return $self->has_tag("arch");
}

sub arch_is_concerned {
    my ($self, $arch) = @_;
    my $arches = $self->{tags}{arch};

    if (defined $arch && defined $arches) {
	my $dep = Dpkg::Deps::Simple->new();
	my @arches = split(/[\s,]+/, $arches);
	$dep->{package} = "dummy";
	$dep->{arches} = \@arches;
	return $dep->arch_is_concerned($arch);
    }

    return 1;
}

# Get reference to the pattern the symbol matches (if any)
sub get_pattern {
    return $_[0]->{matching_pattern};
}

### NOTE: subroutines below require (or initialize) $self to be a pattern ###

# Initialises this symbol as a pattern of the specified type.
sub init_pattern {
    my $self = shift;
    my $type = shift;

    $self->{pattern}{type} = $type;
    # To be filled with references to symbols matching this pattern.
    $self->{pattern}{matches} = [];
}

# Is this symbol a pattern or not?
sub is_pattern {
    return exists $_[0]->{pattern};
}

# Get pattern type if this symbol is a pattern.
sub get_pattern_type {
    return $_[0]->{pattern}{type} || "";
}

# Get (sub)type of the alias pattern. Returns empty string if current
# pattern is not alias.
sub get_alias_type {
    return ($_[0]->get_pattern_type() =~ /^alias-(.+)/ && $1) || "";
}

# Get a list of symbols matching this pattern if this symbol is a pattern
sub get_pattern_matches {
    return @{$_[0]->{pattern}{matches}};
}

# Create a new symbol based on the pattern (i.e. $self)
# and add it to the pattern matches list.
sub create_pattern_match {
    my $self = shift;
    return undef unless $self->is_pattern();

    # Leave out 'pattern' subfield while deep-cloning
    my $pattern_stuff = $self->{pattern};
    delete $self->{pattern};
    my $newsym = $self->dclone(@_);
    $self->{pattern} = $pattern_stuff;

    # Clean up symbol name related internal fields
    $newsym->set_symbolname();

    # Set newsym pattern reference, add to pattern matches list
    $newsym->{matching_pattern} = $self;
    push @{$self->{pattern}{matches}}, $newsym;
    return $newsym;
}

### END of pattern subroutines ###

# Given a raw symbol name the call returns its alias according to the rules of
# the current pattern ($self). Returns undef if the supplied raw name is not
# transformable to alias.
sub convert_to_alias {
    my $self = shift;
    my $rawname = shift;
    my $type = shift || $self->get_alias_type();
    if ($type) {
	if ($type eq 'wildcard') {
	    # In case of wildcard, alias is like "*@SYMBOL_VERSION". Extract
	    # symbol version from the rawname.
	    return "*\@$1" if ($rawname =~ /\@([^@]+)$/);
	} elsif ($rawname =~ /^_Z/ && $type eq "c++") {
	    return cppfilt_demangle($rawname, "gnu-v3");
	}
    }
    return undef;
}

sub get_tagspec {
    my ($self) = @_;
    if ($self->has_tags()) {
	my @tags;
	for my $tagname (@{$self->{tagorder}}) {
	    my $tagval = $self->{tags}{$tagname};
	    if (defined $tagval) {
		push @tags, $tagname . "="  . $tagval;
	    } else {
		push @tags, $tagname;
	    }
	}
	return "(". join("|", @tags) . ")";
    }
    return "";
}

sub get_symbolspec {
    my $self = shift;
    my $template_mode = shift;
    my $spec = "";
    $spec .= "#MISSING: $self->{deprecated}#" if $self->{deprecated};
    $spec .= " ";
    if ($template_mode && $self->has_tags()) {
	$spec .= sprintf('%s%3$s%s%3$s', $self->get_tagspec(),
	    $self->get_symboltempl(), $self->{symbol_quoted} || "");
    } else {
	$spec .= $self->get_symbolname();
    }
    $spec .= " $self->{minver}";
    $spec .= " $self->{dep_id}" if $self->{dep_id};
    return $spec;
}

1;
