# Copyright © 2007 Raphaël Hertzog <hertzog@debian.org>
# Copyright © 2009 Modestas Vainius <modestas@vainius.eu>

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

package Dpkg::Shlibs::Symbol;

use strict;
use warnings;
use Dpkg::Gettext;
use Dpkg::Deps;
use Dpkg::ErrorHandling;
use Storable qw(dclone);

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

sub clone {
    my $self = shift;
    my $clone = dclone($self);
    if (@_) {
	my %args=@_;
	$clone->{$_} = $args{$_} foreach keys %args;
    }
    return $clone;
};

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

# A hook for processing of tags which may change symbol name.
# Called from Dpkg::Shlibs::SymbolFile::load(). Empty for now.
sub process_tags {
    my $self = shift;
}

sub get_symbolname {
    return $_[0]->{symbol};
}

sub get_symboltempl {
    return $_[0]->{symbol_templ} || $_[0]->{symbol};
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
