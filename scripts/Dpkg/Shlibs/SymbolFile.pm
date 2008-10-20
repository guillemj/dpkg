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
use Dpkg::Fields qw(capit);

my %blacklist = (
    '__bss_end__' => 1,		# arm
    '__bss_end' => 1,		# arm
    '_bss_end__' => 1,		# arm
    '__bss_start' => 1,		# ALL
    '__bss_start__' => 1,	# arm
    '__data_start' => 1,	# arm
    '__do_global_ctors_aux' => 1,   # ia64
    '__do_global_dtors_aux' => 1,   # ia64
    '__do_jv_register_classes' => 1,# ia64
    '_DYNAMIC' => 1,		# ALL
    '_edata' => 1,		# ALL
    '_end' => 1,		# ALL
    '__end__' => 1,		# arm
    '__exidx_end' => 1,		# armel
    '__exidx_start' => 1,	# armel
    '_fbss' => 1,		# mips, mipsel
    '_fdata' => 1,		# mips, mipsel
    '_fini' => 1,		# ALL
    '_ftext' => 1,		# mips, mipsel
    '_GLOBAL_OFFSET_TABLE_' => 1,   # hppa, mips, mipsel
    '__gmon_start__' => 1,	# hppa
    '__gnu_local_gp' => 1,      # mips, mipsel
    '_gp' => 1,			# mips, mipsel
    '_init' => 1,		# ALL
    '_PROCEDURE_LINKAGE_TABLE_' => 1, # sparc, alpha
    '_SDA2_BASE_' => 1,		# powerpc
    '_SDA_BASE_' => 1,		# powerpc
);

for (my $i = 14; $i <= 31; $i++) {
    # Many powerpc specific symbols
    $blacklist{"_restfpr_$i"} = 1;
    $blacklist{"_restfpr_$i\_x"} = 1;
    $blacklist{"_restgpr_$i"} = 1;
    $blacklist{"_restgpr_$i\_x"} = 1;
    $blacklist{"_savefpr_$i"} = 1;
    $blacklist{"_savegpr_$i"} = 1;
}

# Many armel-specific symbols
$blacklist{"__aeabi_$_"} = 1 foreach (qw(cdcmpeq cdcmple cdrcmple cfcmpeq
cfcmple cfrcmple d2f d2iz d2lz d2uiz d2ulz dadd dcmpeq dcmpge dcmpgt
dcmple dcmplt dcmpun ddiv dmul dneg drsub dsub f2d f2iz f2lz f2uiz f2ulz
fadd fcmpeq fcmpge fcmpgt fcmple fcmplt fcmpun fdiv fmul fneg frsub fsub
i2d i2f idiv idivmod l2d l2f lasr lcmp ldivmod llsl llsr lmul ui2d ui2f
uidiv uidivmod ul2d ul2f ulcmp uldivmod unwind_cpp_pr0 unwind_cpp_pr1
unwind_cpp_pr2 uread4 uread8 uwrite4 uwrite8));

sub new {
    my $this = shift;
    my $file = shift;
    my $class = ref($this) || $this;
    my $self = { };
    bless $self, $class;
    $self->clear();
    if (defined($file) ) {
	$self->{file} = $file;
	$self->load($file) if -e $file;
    }
    return $self;
}

sub clear {
    my ($self) = @_;
    $self->{objects} = {};
    $self->{used_wildcards} = 0;
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
    my ($self, $file, $seen, $current_object_ref) = @_;

    if (defined($seen)) {
	return if exists $seen->{$file}; # Avoid include loops
    } else {
	$self->{file} = $file;
	$seen = {};
    }
    $seen->{$file} = 1;

    open(my $sym_file, "<", $file)
	|| syserr(_g("cannot open %s"), $file);
    if (not ref($current_object_ref)) {
        my $obj;
        $current_object_ref = \$obj;
    }
    local *object = $current_object_ref;
    while (defined($_ = <$sym_file>)) {
	chomp($_);
	if (/^\s+(\S+)\s(\S+)(?:\s(\d+))?/) {
	    if (not defined ($object)) {
		error(_g("Symbol information must be preceded by a header (file %s, line %s)."), $file, $.);
	    }
	    my $name = $1;
	    # New symbol
	    my $sym = {
		minver => $2,
		dep_id => defined($3) ? $3 : 0,
		deprecated => 0
	    };
	    if ($name =~ /^\*@(.*)$/) {
		error(_g("you can't use wildcards on unversioned symbols: %s"), $_) if $1 eq "Base";
		$self->{objects}{$object}{wildcards}{$1} = $sym;
	    } else {
		$self->{objects}{$object}{syms}{$name} = $sym;
	    }
	} elsif (/^#include\s+"([^"]+)"/) {
	    my $filename = $1;
	    my $dir = $file;
	    $dir =~ s{[^/]+$}{}; # Strip filename
	    $self->load("$dir$filename", $seen, $current_object_ref);
	} elsif (/^#(?:DEPRECATED|MISSING): ([^#]+)#\s*(\S+)\s(\S+)(?:\s(\d+))?/) {
	    my $sym = {
		minver => $3,
		dep_id => defined($4) ? $4 : 0,
		deprecated => $1
	    };
	    $self->{objects}{$object}{syms}{$2} = $sym;
	} elsif (/^#/) {
	    # Skip possible comments
	} elsif (/^\|\s*(.*)$/) {
	    # Alternative dependency template
	    push @{$self->{objects}{$object}{deps}}, "$1";
	} elsif (/^\*\s*([^:]+):\s*(.*\S)\s*$/) {
	    # Add meta-fields
	    $self->{objects}{$object}{fields}{capit($1)} = $2;
	} elsif (/^(\S+)\s+(.*)$/) {
	    # New object and dependency template
	    $object = $1;
	    if (exists $self->{objects}{$object}) {
		# Update/override infos only
		$self->{objects}{$object}{deps} = [ "$2" ];
	    } else {
		# Create a new object
		$self->create_object($object, "$2");
	    }
	} else {
	    warning(_g("Failed to parse a line in %s: %s"), $file, $_);
	}
    }
    close($sym_file);
    delete $seen->{$file};
}

sub save {
    my ($self, $file, $with_deprecated) = @_;
    $file = $self->{file} unless defined($file);
    my $fh;
    if ($file eq "-") {
	$fh = \*STDOUT;
    } else {
	open($fh, ">", $file)
	    || syserr(_g("cannot write %s"), $file);
    }
    $self->dump($fh, $with_deprecated);
    close($fh) if ($file ne "-");
}

sub dump {
    my ($self, $fh, $with_deprecated) = @_;
    $with_deprecated = 1 unless defined($with_deprecated);
    foreach my $soname (sort keys %{$self->{objects}}) {
	my @deps = @{$self->{objects}{$soname}{deps}};
	print $fh "$soname $deps[0]\n";
	shift @deps;
	print $fh "| $_\n" foreach (@deps);
	my $f = $self->{objects}{$soname}{fields};
	print $fh "* $_: $f->{$_}\n" foreach (sort keys %{$f});
	foreach my $sym (sort keys %{$self->{objects}{$soname}{syms}}) {
	    my $info = $self->{objects}{$soname}{syms}{$sym};
	    next if $info->{deprecated} and not $with_deprecated;
	    print $fh "#MISSING: $info->{deprecated}#" if $info->{deprecated};
	    print $fh " $sym $info->{minver}";
	    print $fh " $info->{dep_id}" if $info->{dep_id};
	    print $fh "\n";
	}
    }
}

# merge_symbols($object, $minver)
# Needs $Objdump->get_object($soname) as parameter
# Don't merge blacklisted symbols related to the internal (arch-specific)
# machinery
sub merge_symbols {
    my ($self, $object, $minver) = @_;
    my $soname = $object->{SONAME} || error(_g("Can't merge symbols from objects without SONAME."));
    my %dynsyms;
    foreach my $sym ($object->get_exported_dynamic_symbols()) {
	next if exists $blacklist{$sym->{name}};
	if ($sym->{version}) {
	    $dynsyms{$sym->{name} . '@' . $sym->{version}} = $sym;
	} else {
	    $dynsyms{$sym->{name}} = $sym;
	}
    }

    unless ($self->{objects}{$soname}) {
	$self->create_object($soname, '');
    }
    # Scan all symbols provided by the objects
    foreach my $sym (keys %dynsyms) {
	my $obj = $self->{objects}{$soname};
	if (exists $obj->{syms}{$sym}) {
	    # If the symbol is already listed in the file
	    my $info = $obj->{syms}{$sym};
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
	    my $info;
	    my $symobj = $dynsyms{$sym};
	    if ($symobj->{version} and exists $obj->{wildcards}{$symobj->{version}}) {
		# Get the info from wildcards
		$info = $obj->{wildcards}{$symobj->{version}};
		$self->{used_wildcards}++;
	    } else {
		# New symbol provided by the current release
		$info = {
		    minver => $minver,
		    deprecated => 0,
		    dep_id => 0
		};
	    }
	    $obj->{syms}{$sym} = $info;
	}
    }

    # Scan all symbols in the file and mark as deprecated those that are
    # no more provided (only if the minver is bigger than the version where
    # the symbol was introduced)
    foreach my $sym (keys %{$self->{objects}{$soname}{syms}}) {
	if (! exists $dynsyms{$sym}) {
	    # Do nothing if already deprecated
	    next if $self->{objects}{$soname}{syms}{$sym}{deprecated};

	    my $info = $self->{objects}{$soname}{syms}{$sym};
	    if (vercmp($minver, $info->{minver}) > 0) {
		$self->{objects}{$soname}{syms}{$sym}{deprecated} = $minver;
	    }
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
	fields => {},
	wildcards => {},
	deps => [ @deps ]
    };
}

sub get_dependency {
    my ($self, $soname, $dep_id) = @_;
    $dep_id = 0 unless defined($dep_id);
    return $self->{objects}{$soname}{deps}[$dep_id];
}

sub get_smallest_version {
    my ($self, $soname, $dep_id) = @_;
    $dep_id = 0 unless defined($dep_id);
    my $minver;
    foreach my $sym (values %{$self->{objects}{$soname}{syms}}) {
        next if $dep_id != $sym->{dep_id};
        $minver ||= $sym->{minver};
        if (vercmp($minver, $sym->{minver}) > 0) {
            $minver = $sym->{minver};
        }
    }
    return $minver;
}

sub get_dependencies {
    my ($self, $soname) = @_;
    return @{$self->{objects}{$soname}{deps}};
}

sub get_field {
    my ($self, $soname, $name) = @_;
    if (exists $self->{objects}{$soname}{fields}{$name}) {
	return $self->{objects}{$soname}{fields}{$name};
    }
    return undef;
}

sub contains_wildcards {
    my ($self) = @_;
    my $res = 0;
    foreach my $soname (sort keys %{$self->{objects}}) {
	if (scalar keys %{$self->{objects}{$soname}{wildcards}}) {
	    $res = 1;
	}
    }
    return $res;
}

sub used_wildcards {
    my ($self) = @_;
    return $self->{used_wildcards};
}

sub lookup_symbol {
    my ($self, $name, $sonames, $inc_deprecated) = @_;
    $inc_deprecated = 0 unless defined($inc_deprecated);
    foreach my $so (@{$sonames}) {
	next if (! exists $self->{objects}{$so});
	if (exists $self->{objects}{$so}{syms}{$name} and
	    ($inc_deprecated or not
	    $self->{objects}{$so}{syms}{$name}{deprecated}))
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

sub get_new_symbols {
    my ($self, $ref) = @_;
    my @res;
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
		push @res, {
		    'soname' => $soname,
		    'name' => $sym,
		    %{$mysyms->{$sym}}
		};
	    }
	}
    }
    return @res;
}

sub get_lost_symbols {
    my ($self, $ref) = @_;
    return $ref->get_new_symbols($self);
}


sub get_new_libs {
    my ($self, $ref) = @_;
    my @res;
    foreach my $soname (keys %{$self->{objects}}) {
	push @res, $soname if not exists $ref->{objects}{$soname};
    }
    return @res;
}

sub get_lost_libs {
    my ($self, $ref) = @_;
    return $ref->get_new_libs($self);
}

1;
