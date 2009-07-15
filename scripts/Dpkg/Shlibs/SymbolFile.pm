# Copyright (C) 2007  Raphael Hertzog
#           (C) 2009  Modestas Vainius

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

use strict;
use warnings;
use Dpkg::Gettext;
use Dpkg::ErrorHandling;
use Dpkg::Version qw(vercmp);
use Dpkg::Fields qw(capit);
use Dpkg::Shlibs::Symbol;
use Dpkg::Arch qw(get_host_arch);

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
    my %opts=@_;
    my $class = ref($this) || $this;
    my $self = \%opts;
    bless $self, $class;
    $self->{arch} = get_host_arch() unless exists $self->{arch};
    $self->clear();
    if (exists $self->{file}) {
	$self->load($self->{file}) if -e $self->{file};
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

sub add_symbol {
    my ($self, $soname, $symbol) = @_;
    my $object = (ref $soname) ? $soname : $self->{objects}{$soname};

    if (!$symbol->{deprecated} && (my $ver = $symbol->get_wildcard_version())) {
	error(_g("you can't use wildcards on unversioned symbols: %s"), $_) if $ver eq "Base";
	$object->{wildcards}{$ver} = $symbol;
	return 'wildcards';
    } else {
	$object->{syms}{$symbol->get_symbolname()} = $symbol;
	return 'syms';
    }
}

# Parameter seen is only used for recursive calls
sub load {
    my ($self, $file, $seen, $obj_ref, $base_symbol) = @_;

    sub new_symbol {
        my $base = shift || 'Dpkg::Shlibs::Symbol';
        return (ref $base) ? $base->clone(@_) : $base->new(@_);
    }

    if (defined($seen)) {
	return if exists $seen->{$file}; # Avoid include loops
    } else {
	$self->{file} = $file;
	$seen = {};
    }
    $seen->{$file} = 1;

    if (not ref($obj_ref)) { # Init ref to name of current object/lib
        $$obj_ref = undef;
    }

    open(my $sym_file, "<", $file)
	|| syserr(_g("cannot open %s"), $file);
    while (defined($_ = <$sym_file>)) {
	chomp($_);

	if (/^(?:\s+|#(?:DEPRECATED|MISSING): ([^#]+)#\s*)(.*)/) {
	    if (not defined ($$obj_ref)) {
		error(_g("Symbol information must be preceded by a header (file %s, line %s)."), $file, $.);
	    }
	    # Symbol specification
	    my $deprecated = ($1) ? $1 : 0;
	    my $sym = new_symbol($base_symbol, deprecated => $deprecated);
	    if ($sym->parse($2)) {
		$sym->process_tags(arch => $self->{arch});
		$self->add_symbol($$obj_ref, $sym);
	    } else {
		warning(_g("Failed to parse line in %s: %s"), $file, $_);
	    }
	} elsif (/^(\(.*\))?#include\s+"([^"]+)"/) {
	    my $tagspec = $1;
	    my $filename = $2;
	    my $dir = $file;
	    my $new_base_symbol;
	    if (defined $tagspec) {
                $new_base_symbol = new_symbol($base_symbol);
		$new_base_symbol->parse_tagspec($tagspec);
	    }
	    $dir =~ s{[^/]+$}{}; # Strip filename
	    $self->load("$dir$filename", $seen, $obj_ref, $new_base_symbol);
	} elsif (/^#/) {
	    # Skip possible comments
	} elsif (/^\|\s*(.*)$/) {
	    # Alternative dependency template
	    push @{$self->{objects}{$$obj_ref}{deps}}, "$1";
	} elsif (/^\*\s*([^:]+):\s*(.*\S)\s*$/) {
	    # Add meta-fields
	    $self->{objects}{$$obj_ref}{fields}{capit($1)} = $2;
	} elsif (/^(\S+)\s+(.*)$/) {
	    # New object and dependency template
	    $$obj_ref = $1;
	    if (exists $self->{objects}{$$obj_ref}) {
		# Update/override infos only
		$self->{objects}{$$obj_ref}{deps} = [ "$2" ];
	    } else {
		# Create a new object
		$self->create_object($$obj_ref, "$2");
	    }
	} else {
	    warning(_g("Failed to parse a line in %s: %s"), $file, $_);
	}
    }
    close($sym_file);
    delete $seen->{$file};
}


# Beware: we reuse the data structure of the provided symfile so make
# sure to not modify them after having called this function
sub merge_object_from_symfile {
    my ($self, $src, $objid) = @_;
    if (not $self->has_object($objid)) {
        $self->{objects}{$objid} = $src->{objects}{$objid};
    } else {
        warning(_g("Tried to merge the same object (%s) twice in a symfile."), $objid);
    }
}

sub save {
    my ($self, $file, %opts) = @_;
    $file = $self->{file} unless defined($file);
    my $fh;
    if ($file eq "-") {
	$fh = \*STDOUT;
    } else {
	open($fh, ">", $file)
	    || syserr(_g("cannot write %s"), $file);
    }
    $self->dump($fh, %opts);
    close($fh) if ($file ne "-");
}

sub dump {
    my ($self, $fh, %opts) = @_;
    $opts{template_mode} = 0 unless exists $opts{template_mode};
    $opts{with_deprecated} = 1 unless exists $opts{with_deprecated};
    foreach my $soname (sort keys %{$self->{objects}}) {
	my @deps = @{$self->{objects}{$soname}{deps}};
        my $dep = shift @deps;
        $dep =~ s/#PACKAGE#/$opts{package}/g if exists $opts{package};
	print $fh "$soname $dep\n";
        foreach $dep (@deps) {
            $dep =~ s/#PACKAGE#/$opts{package}/g if exists $opts{package};
	    print $fh "| $dep\n";
        }
	my $f = $self->{objects}{$soname}{fields};
        foreach my $field (sort keys %{$f}) {
            my $value = $f->{$field};
            $value =~ s/#PACKAGE#/$opts{package}/g if exists $opts{package};
	    print $fh "* $field: $value\n";
        }
	my $syms = $self->{objects}{$soname}{syms};
	foreach my $name (sort { $syms->{$a}->get_symboltempl() cmp
                                 $syms->{$b}->get_symboltempl() } keys %$syms) {
	    my $sym = $self->{objects}{$soname}{syms}{$name};
	    next if $sym->{deprecated} and not $opts{with_deprecated};
	    # Do not dump symbols from foreign arch unless dumping a template.
	    next if not $opts{template_mode} and
                    not $sym->arch_is_concerned($self->{arch});
	    # Dump symbol specification. Dump symbol tags only in template mode.
	    print $fh $sym->get_symbolspec($opts{template_mode}) . "\n";
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
        my $name = $sym->{name} . '@' .
                   ($sym->{version} ? $sym->{version} : "Base");
        my $symobj = $self->lookup_symbol($name, [ $soname ]);
        if (exists $blacklist{$sym->{name}}) {
            next unless (defined $symobj and $symobj->has_tag("ignore-blacklist"));
        }
        $dynsyms{$name} = $sym;
    }

    unless (exists $self->{objects}{$soname}) {
	$self->create_object($soname, '');
    }
    # Scan all symbols provided by the objects
    foreach my $name (keys %dynsyms) {
	my $obj = $self->{objects}{$soname};
        my $sym;
	if (exists $obj->{syms}{$name}) {
	    # If the symbol is already listed in the file
	    $sym = $obj->{syms}{$name};
	    if ($sym->{deprecated}) {
		# Symbol reappeared somehow
		$sym->{deprecated} = 0;
		$sym->{minver} = $minver if (not $sym->is_optional());
	    } else {
		# We assume that the right dependency information is already
		# there.
		if (vercmp($minver, $sym->{minver}) < 0) {
		    $sym->{minver} = $minver;
		}
	    }
	    if (not $sym->arch_is_concerned($self->{arch})) {
		# Remove arch tag because it is incorrect.
		$sym->delete_tag('arch');
	    }
	} else {
	    # The symbol is new and not present in the file
	    my $symobj = $dynsyms{$name};
            $sym = $self->symbol_match_wildcard($soname, $name, $symobj->{version});
            if (not defined $sym) {
                # Symbol without any special info as no wildcard did match
                $sym = Dpkg::Shlibs::Symbol->new(symbol => $name,
                                                 minver => $minver);
            }
	    $self->add_symbol($obj, $sym);
	}
    }

    # Scan all symbols in the file and mark as deprecated those that are
    # no more provided (only if the minver is bigger than the version where
    # the symbol was introduced)
    foreach my $name (keys %{$self->{objects}{$soname}{syms}}) {
	if (not exists $dynsyms{$name}) {
	    my $sym = $self->{objects}{$soname}{syms}{$name};

	    # Ignore symbols from foreign arch
	    next if not $sym->arch_is_concerned($self->{arch});

	    if ($sym->{deprecated}) {
		# Bump deprecated if the symbol is optional so that it
                # keeps reappering in the diff while it's missing
		$sym->{deprecated} = $minver if $sym->is_optional();
	    } elsif (vercmp($minver, $sym->{minver}) > 0) {
		$sym->{deprecated} = $minver;
	    }
	}
    }
}

sub symbol_match_wildcard {
    my ($self, $soname, $name, $version) = @_;
    my $obj = $self->{objects}{$soname};
    if ($version and exists $obj->{wildcards}{$version}) {
        my $w_sym = $obj->{wildcards}{$version};
        return undef unless $w_sym->arch_is_concerned($self->{arch});
        $self->{used_wildcards}++;
        return $w_sym->clone(symbol => $name);
    }
    return undef;
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
        $minver = $sym->{minver} unless defined($minver);
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
	    my $clone = $self->{objects}{$so}{syms}{$name}->clone();
	    $clone->{depends} = $self->{objects}{$so}{deps}[$dep_id];
	    $clone->{soname} = $so;
	    return $clone;
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
	foreach my $sym (grep { not $mysyms->{$_}{deprecated} and
	                        not $mysyms->{$_}->is_optional() and
	                        $mysyms->{$_}->arch_is_concerned($self->{arch})
                              } keys %{$mysyms})
	{
	    if ((not exists $refsyms->{$sym}) or
		$refsyms->{$sym}{deprecated} or
		not $refsyms->{$sym}->arch_is_concerned($self->{arch}) )
	    {
		push @res, $mysyms->{$sym}->clone(soname => $soname);
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
