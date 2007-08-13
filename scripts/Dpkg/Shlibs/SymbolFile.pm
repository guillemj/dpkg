# Copyright (C) 2007  Raphael Hertzog

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

package Dpkg::Shlibs::SymbolFile;

use Dpkg::Gettext;
use Dpkg::ErrorHandling qw(syserr warning error);
use Dpkg::Version qw(vercmp);
textdomain("dpkg-dev");

sub new {
    my $this = shift;
    my $file = shift;
    my $class = ref($this) || $this;
    my $self = { };
    bless $self, $class;
    if (defined($file) ) {
	$self->{file} = $file;
	$self->load($file) if -e $file;
    }
    return $self;
}

sub clear {
    my ($self) = @_;
    $self->{objects} = {};
}

sub clear_except {
    my ($self, @ids) = @_;
    my %has;
    $has{$_} = 1 foreach (@ids);
    foreach my $objid (keys %{$self->{objects}}) {
	delete $self->{objects}{$objid} unless exists $has{$objid};
    }
}

# Parameter seen is only used for recursive calls
sub load {
    my ($self, $file, $seen) = @_;

    if (defined($seen)) {
	return if exists $seen->{$file}; # Avoid include loops
    } else {
	$self->{file} = $file;
	$seen = {};
    }
    $seen->{$file} = 1;

    open(my $sym_file, "<", $file)
	|| syserr(sprintf(_g("Can't open %s: %s"), $file));
    my ($object);
    while (defined($_ = <$sym_file>)) {
	chomp($_);
	if (/^\s+(\S+)\s(\S+)(?:\s(\d+))?/) {
	    if (not defined ($object)) {
		error(sprintf(_g("Symbol information must be preceded by a header (file %s, line %s).", $file, $.)));
	    }
	    # New symbol
	    my $sym = {
		minver => $2,
		dep_id => defined($3) ? $3 : 0,
		deprecated => 0
	    };
	    $self->{objects}{$object}{syms}{$1} = $sym;
	} elsif (/^#include\s+"([^"]+)"/) {
	    my $filename = $1;
	    my $dir = $file;
	    $dir =~ s{[^/]+$}{}; # Strip filename
	    $self->load("$dir$filename", $seen);
	} elsif (/^#DEPRECATED: ([^#]+)#\s*(\S+)\s(\S+)(?:\s(\d+))?/) {
	    my $sym = {
		minver => $3,
		dep_id => defined($4) ? $4 : 0,
		deprecated => $1
	    };
	    $self->{objects}{$object}{syms}{$2} = $sym;
	} elsif (/^#/) {
	    # Skip possible comments
	} elsif (/^\|\s*(.*)$/) {
	    # Alternative dependency template
	    push @{$self->{objects}{$object}{deps}}, "$1";
	} elsif (/^(\S+)\s+(.*)$/) {
	    # New object and dependency template
	    $object = $1;
	    if (exists $self->{objects}{$object}) {
		# Update/override infos only
		$self->{objects}{$object}{deps} = [ "$2" ];
	    } else {
		# Create a new object
		$self->{objects}{$object} = {
		    syms => {},
		    deps => [ "$2" ]
		};
	    }
	} else {
	    warning(sprintf(_g("Failed to parse a line in %s: %s"), $file, $_));
	}
    }
    close($sym_file);
}

sub save {
    my ($self, $file) = @_;
    $file = $self->{file} unless defined($file);
    my $fh;
    if ($file eq "-") {
	$fh = \*STDOUT;
    } else {
	open($fh, ">", $file)
	    || syserr(sprintf(_g("Can't open %s for writing: %s"), $file, $!));
    }
    $self->dump($fh);
    close($fh) if ($file ne "-");
}

sub dump {
    my ($self, $fh) = @_;
    foreach my $soname (sort keys %{$self->{objects}}) {
	print $fh "$soname $self->{objects}{$soname}{deps}[0]\n";
	print $fh "| $_" foreach (@{$self->{objects}{$soname}{deps}}[ 1 .. -1 ]);
	foreach my $sym (sort keys %{$self->{objects}{$soname}{syms}}) {
	    my $info = $self->{objects}{$soname}{syms}{$sym};
	    print $fh "#DEPRECATED: $info->{deprecated}#" if $info->{deprecated};
	    print $fh " $sym $info->{minver}";
	    print $fh " $info->{dep_id}" if $info->{dep_id};
	    print $fh "\n";
	}
    }
}

# merge_symbols($object, $minver)
# Needs $Objdump->get_object($soname) as parameter
sub merge_symbols {
    my ($self, $object, $minver) = @_;
    my $soname = $object->{SONAME} || error(_g("Can't merge symbols from objects without SONAME."));
    my %dynsyms = map { $_ => $object->{dynsyms}{$_} }
	grep { local $a = $object->{dynsyms}{$_}; $a->{dynamic} && $a->{defined} }
	keys %{$object->{dynsyms}};
    unless ($self->{objects}{$soname}) {
	$self->create_object($soname, '');
    }
    # Scan all symbols provided by the objects
    foreach my $sym (keys %dynsyms) {
	if (exists $self->{objects}{$soname}{syms}{$sym}) {
	    # If the symbol is already listed in the file
	    my $info = $self->{objects}{$soname}{syms}{$sym};
	    if ($info->{deprecated}) {
		# Symbol reappeared somehow
		$info->{deprecated} = 0;
		$info->{minver} = $minver;
		next;
	    }
	    # We assume that the right dependency information is already
	    # there.
	    if (vercmp($minver, $info->{minver}) < 0) {
		$info->{minver} = $minver;
	    }
	} else {
	    # The symbol is new and not present in the file
	    my $info = {
		minver => $minver,
		deprecated => 0,
		dep_id => 0
	    };
	    $self->{objects}{$soname}{syms}{$sym} = $info;
	}
    }

    # Scan all symbols in the file and mark as deprecated those that are
    # no more provided
    foreach my $sym (keys %{$self->{objects}{$soname}{syms}}) {
	if (! exists $dynsyms{$sym}) {
	    $self->{objects}{$soname}{syms}{$sym}{deprecated} = $minver;
	}
    }
}

sub is_empty {
    my ($self) = @_;
    return scalar(keys %{$self->{objects}}) ? 0 : 1;
}

sub has_object {
    my ($self, $soname) = @_;
    return exists $self->{objects}{$soname};
}

sub create_object {
    my ($self, $soname, @deps) = @_;
    $self->{objects}{$soname} = {
	syms => {},
	deps => [ @deps ]
    };
}

sub get_dependency {
    my ($self, $soname, $dep_id) = @_;
    $dep_id = 0 unless defined($dep_id);
    return $self->{objects}{$soname}{deps}[$dep_id];
}

sub lookup_symbol {
    my ($self, $name, $sonames) = @_;
    foreach my $so (@{$sonames}) {
	next if (! exists $self->{objects}{$so});
	if (exists $self->{objects}{$so}{syms}{$name} and
	    not $self->{objects}{$so}{syms}{$name}{deprecated})
	{
	    my $dep_id = $self->{objects}{$so}{syms}{$name}{dep_id};
	    return {
		'depends' => $self->{objects}{$so}{deps}[$dep_id],
		'soname' => $so,
		%{$self->{objects}{$so}{syms}{$name}}
	    };
	}
    }
    return undef;
}

sub has_new_symbols {
    my ($self, $ref) = @_;
    foreach my $soname (keys %{$self->{objects}}) {
	my $mysyms = $self->{objects}{$soname}{syms};
	next if not exists $ref->{objects}{$soname};
	my $refsyms = $ref->{objects}{$soname}{syms};
	foreach my $sym (grep { not $mysyms->{$_}{deprecated} }
	    keys %{$mysyms})
	{
	    if ((not exists $refsyms->{$sym}) or
		$refsyms->{$sym}{deprecated})
	    {
		return 1;
	    }
	}
    }
    return 0;
}

sub has_lost_symbols {
    my ($self, $ref) = @_;
    return $ref->has_new_symbols($self);
}


sub has_new_libs {
    my ($self, $ref) = @_;
    foreach my $soname (keys %{$self->{objects}}) {
	return 1 if not exists $ref->{objects}{$soname};
    }
    return 0;
}

sub has_lost_libs {
    my ($self, $ref) = @_;
    return $ref->has_new_libs($self);
}

1;
