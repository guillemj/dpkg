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

package Dpkg::Shlibs::Objdump;

require 'dpkg-gettext.pl';

sub new {
    my $this = shift;
    my $class = ref($this) || $this;
    my $self = { 'objects' => {} };
    bless $self, $class;
    return $self;
}

sub parse {
    my ($self, $file) = @_;
    local $ENV{LC_ALL} = 'C';
    open(OBJDUMP, "-|", "objdump", "-w", "-p", "-T", $file) ||
	    syserr(sprintf(_g("Can't execute objdump: %s"), $!));
    my $obj = Dpkg::Shlibs::Objdump::Object->new($file);
    my $section = "none";
    while (defined($_ = <OBJDUMP>)) {
	chomp($_);
	next if (/^\s*$/);

	if ($_ =~ /^DYNAMIC SYMBOL TABLE:/) {
	    $section = "dynsym";
	    next;
	} elsif ($_ =~ /^Dynamic Section:/) {
	    $section = "dyninfo";
	    next;
	} elsif ($_ =~ /^Program Header:/) {
	    $section = "header";
	    next;
	} elsif ($_ =~ /^Version definitions:/) {
	    $section = "verdef";
	    next;
	} elsif ($_ =~ /^Version References:/) {
	    $section = "verref";
	    next;
	}

	if ($section eq "dynsym") {
	    $self->parse_dynamic_symbol($_, $obj);
	} elsif ($section eq "dyninfo") {
	    if ($_ =~ /^\s*NEEDED\s+(\S+)/) {
		push @{$obj->{NEEDED}}, $1;
	    } elsif ($_ =~ /^\s*SONAME\s+(\S+)/) {
		$obj->{SONAME} = $1;
	    } elsif ($_ =~ /^\s*HASH\s+(\S+)/) {
		$obj->{HASH} = $1;
	    } elsif ($_ =~ /^\s*GNU_HASH\s+(\S+)/) {
		$obj->{GNU_HASH} = $1;
	    } elsif ($_ =~ /^\s*RPATH\s+(\S+)/) {
		push @{$obj->{RPATH}}, split (/:/, $1);
	    }
	} elsif ($section eq "none") {
	    if ($_ =~ /^\s*\S+:\s*file\s+format\s+(\S+)\s*$/) {
		$obj->{format} = $1;
	    }
	}
    }
    close(OBJDUMP);
    if ($section eq "none") {
	return undef;
    } else {
	my $id = $obj->{SONAME} || $obj->{file};
	$self->{objects}{$id} = $obj;
	return $id;
    }
}

# Output format of objdump -w -T
#
# /lib/libc.so.6:     file format elf32-i386
#
# DYNAMIC SYMBOL TABLE:
# 00056ef0 g    DF .text  000000db  GLIBC_2.2   getwchar
# 00000000 g    DO *ABS*  00000000  GCC_3.0     GCC_3.0
# 00069960  w   DF .text  0000001e  GLIBC_2.0   bcmp
# 00000000  w   D  *UND*  00000000              _pthread_cleanup_pop_restore
# 0000b788 g    DF .text  0000008e  Base        .protected xine_close
# |        ||||||| |      |         |           |
# |        ||||||| |      |         Version str (.visibility) + Symbol name
# |        ||||||| |      Alignment
# |        ||||||| Section name (or *UND* for an undefined symbol)
# |        ||||||F=Function,f=file,O=object
# |        |||||d=debugging,D=dynamic
# |        ||||I=Indirect
# |        |||W=warning
# |        ||C=constructor
# |        |w=weak
# |        g=global,l=local,!=both global/local
# Size of the symbol
#
# GLIBC_2.2 is the version string associated to the symbol
# (GLIBC_2.2) is the same but the symbol is hidden, a newer version of the
# symbol exist

sub parse_dynamic_symbol {
    my ($self, $line, $obj) = @_;
    my $vis = '(?:\s+(?:\.protected|\.hidden|\.internal|0x\S+))?';
    if ($line =~ /^[0-9a-f]+ (.{7})\s+(\S+)\s+[0-9a-f]+\s+(\S+)?(?:$vis\s+(\S+))/) {

	my ($flags, $sect, $ver, $name) = ($1, $2, $3, $4);
	my $symbol = {
		'name' => $name,
		'version' => defined($ver) ? $ver : '',
		'section' => $sect,
		'dynamic' => substr($flags, 5, 1) eq "D",
		'debug' => substr($flags, 5, 1) eq "d",
		'type' => substr($flags, 6, 1),
		'weak' => substr($flags, 1, 1) eq "w",
		'hidden' => 0,
		'defined' => $sect ne '*UND*'
	    };

	# Handle hidden symbols
	if (defined($ver) and $ver =~ /^\((.*)\)$/) {
	    $ver = $1;
	    $symbol->{'version'} = $1;
	    $symbol->{'hidden'} = 1;
	}

	# Register symbol
	$obj->add_dynamic_symbol($symbol);
    } elsif ($line =~ /^[0-9a-f]+ (.{7})\s+(\S+)\s+[0-9a-f]+/) {
	# Same start but no version and no symbol ... just ignore
    } else {
	main::warning(sprintf(_g("Couldn't parse one line of objdump's output: %s"), $line));
    }
}

sub locate_symbol {
    my ($self, $name) = @_;
    foreach my $obj (values %{$self->{objects}}) {
	my $sym = $obj->get_symbol($name);
	if (defined($sym) && $sym->{defined}) {
	    return $sym;
	}
    }
    return undef;
}

sub get_object {
    my ($self, $objid) = @_;
    if (exists $self->{objects}{$objid}) {
	return $self->{objects}{$objid};
    }
    return undef;
}

{
    my %format; # Cache of result
    sub get_format {
	my ($file) = @_;

	if (exists $format{$file}) {
	    return $format{$file};
	} else {
	    local $ENV{LC_ALL} = "C";
	    open(P, "objdump -a -- $file |") || syserr(_g("cannot fork for objdump"));
	    while (<P>) {
		chomp;
		if (/^\s*\S+:\s*file\s+format\s+(\S+)\s*$/) {
		    $format{$file} = $1;
		    return $format{$file};
		}
	    }
	    close(P) or main::subprocerr(sprintf(_g("objdump on \`%s'"), $file));
	}
    }
}

sub is_elf {
    my ($file) = @_;
    open(FILE, "<", $file) || main::syserr(sprintf(_g("Can't open %s for test: %s"), $file, $!));
    my ($header, $result) = ("", 0);
    if (read(FILE, $header, 4) == 4) {
	$result = 1 if ($header =~ /^\177ELF$/);
    }
    close(FILE);
    return $result;
}

package Dpkg::Shlibs::Objdump::Object;

sub new {
    my $this = shift;
    my $file = shift || '';
    my $class = ref($this) || $this;
    my $self = {
	'file' => $file,
	'SONAME' => '',
	'NEEDED' => [],
	'RPATH' => [],
	'dynsyms' => {}
    };
    bless $self, $class;
    return $self;
}

sub add_dynamic_symbol {
    my ($self, $symbol) = @_;
    $symbol->{soname} = $self->{SONAME};
    if ($symbol->{version}) {
	$self->{dynsyms}{$symbol->{name} . '@' . $symbol->{version}} = $symbol;
    } else {
	$self->{dynsyms}{$symbol->{name}} = $symbol;
    }
}

sub get_symbol {
    my ($self, $name) = @_;
    if (exists $self->{dynsyms}{$name}) {
	return $self->{dynsyms}{$name};
    }
    return undef;
}

sub get_exported_dynamic_symbols {
    my ($self) = @_;
    return grep { $_->{defined} && $_->{dynamic} }
	    values %{$self->{dynsyms}};
}

sub get_undefined_dynamic_symbols {
    my ($self) = @_;
    return grep { (!$_->{defined}) && $_->{dynamic} }
	    values %{$self->{dynsyms}};
}

sub get_needed_libraries {
    my $self = shift;
    return @{$self->{NEEDED}};
}

1;
