# Copyright © 2007-2010 Raphaël Hertzog <hertzog@debian.org>
# Copyright © 2007-2009,2012-2015,2017-2018 Guillem Jover <guillem@debian.org>
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
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

=encoding utf8

=head1 NAME

Dpkg::Shlibs::Objdump - symbol support via objdump

=head1 DESCRIPTION

This module provides a class that wraps objdump to handle symbols and
their attributes from a shared object.

B<Note>: This is a private module, its API can change at any time.

=cut

package Dpkg::Shlibs::Objdump 0.01;

use strict;
use warnings;
use feature qw(state);

use Dpkg::Gettext;
use Dpkg::ErrorHandling;
use Dpkg::Shlibs::Objdump::Object;

sub new {
    my $this = shift;
    my $class = ref($this) || $this;
    my $self = { objects => {} };
    bless $self, $class;
    return $self;
}

sub add_object {
    my ($self, $obj) = @_;
    my $id = $obj->get_id;
    if ($id) {
	$self->{objects}{$id} = $obj;
    }
    return $id;
}

sub analyze {
    my ($self, $file) = @_;
    my $obj = Dpkg::Shlibs::Objdump::Object->new($file);

    return $self->add_object($obj);
}

sub locate_symbol {
    my ($self, $name) = @_;
    foreach my $obj (values %{$self->{objects}}) {
	my $sym = $obj->get_symbol($name);
	if (defined($sym) && $sym->{defined}) {
	    return $sym;
	}
    }
    return;
}

sub get_object {
    my ($self, $objid) = @_;
    if ($self->has_object($objid)) {
	return $self->{objects}{$objid};
    }
    return;
}

sub has_object {
    my ($self, $objid) = @_;
    return exists $self->{objects}{$objid};
}

use constant {
    # ELF Class.
    ELF_BITS_NONE           => 0,
    ELF_BITS_32             => 1,
    ELF_BITS_64             => 2,

    # ELF Data encoding.
    ELF_ORDER_NONE          => 0,
    ELF_ORDER_2LSB          => 1,
    ELF_ORDER_2MSB          => 2,

    # ELF Machine.
    EM_NONE                 => 0,
    EM_SPARC                => 2,
    EM_386                  => 3,
    EM_68K                  => 4,
    EM_MIPS                 => 8,
    EM_SPARC64_OLD          => 11,
    EM_PARISC               => 15,
    EM_SPARC32PLUS          => 18,
    EM_PPC                  => 20,
    EM_PPC64                => 21,
    EM_S390                 => 22,
    EM_ARM                  => 40,
    EM_ALPHA_OLD            => 41,
    EM_SH                   => 42,
    EM_SPARC64              => 43,
    EM_IA64                 => 50,
    EM_X86_64               => 62,
    EM_OR1K                 => 92,
    EM_AARCH64              => 183,
    EM_ARCV2                => 195,
    EM_RISCV                => 243,
    EM_LOONGARCH            => 258,
    EM_OR1K_OLD             => 0x8472,
    EM_ALPHA                => 0x9026,
    EM_S390_OLD             => 0xa390,
    EM_NIOS32               => 0xfebb,

    # ELF Version.
    EV_NONE                 => 0,
    EV_CURRENT              => 1,

    # ELF Flags (might influence the ABI).
    EF_ARM_ALIGN8           => 0x00000040,
    EF_ARM_NEW_ABI          => 0x00000080,
    EF_ARM_OLD_ABI          => 0x00000100,
    EF_ARM_SOFT_FLOAT       => 0x00000200,
    EF_ARM_HARD_FLOAT       => 0x00000400,
    EF_ARM_EABI_MASK        => 0xff000000,

    EF_IA64_ABI64           => 0x00000010,

    EF_LOONGARCH_SOFT_FLOAT     => 0x00000001,
    EF_LOONGARCH_SINGLE_FLOAT   => 0x00000002,
    EF_LOONGARCH_DOUBLE_FLOAT   => 0x00000003,
    EF_LOONGARCH_ABI_MASK       => 0x00000007,

    EF_MIPS_ABI2            => 0x00000020,
    EF_MIPS_32BIT           => 0x00000100,
    EF_MIPS_FP64            => 0x00000200,
    EF_MIPS_NAN2008         => 0x00000400,
    EF_MIPS_ABI_MASK        => 0x0000f000,
    EF_MIPS_ARCH_MASK       => 0xf0000000,

    EF_PPC64_ABI64          => 0x00000003,

    EF_SH_MACH_MASK         => 0x0000001f,
};

# These map alternative or old machine IDs to their canonical form.
my %elf_mach_map = (
    EM_ALPHA_OLD()          => EM_ALPHA,
    EM_OR1K_OLD()           => EM_OR1K,
    EM_S390_OLD()           => EM_S390,
    EM_SPARC32PLUS()        => EM_SPARC,
    EM_SPARC64_OLD()        => EM_SPARC64,
);

# These masks will try to expose processor flags that are ABI incompatible,
# and as such are part of defining the architecture ABI. If uncertain it is
# always better to not mask a flag, because that preserves the historical
# behavior, and we do not drop dependencies.
my %elf_flags_mask = (
    EM_IA64()               => EF_IA64_ABI64,
    EM_LOONGARCH()          => EF_LOONGARCH_ABI_MASK,
    EM_MIPS()               => EF_MIPS_ABI_MASK | EF_MIPS_ABI2,
    EM_PPC64()              => EF_PPC64_ABI64,
);

sub get_format {
    my ($file) = @_;
    state %format;

    return $format{$file} if exists $format{$file};

    my $header;

    open my $fh, '<', $file or syserr(g_('cannot read %s'), $file);
    my $rc = read $fh, $header, 64;
    if (not defined $rc) {
        syserr(g_('cannot read %s'), $file);
    } elsif ($rc != 64) {
        return;
    }
    close $fh;

    my %elf;

    # Unpack the identifier field.
    @elf{qw(magic bits endian vertype osabi verabi)} = unpack 'a4C5', $header;

    return unless $elf{magic} eq "\x7fELF";
    return unless $elf{vertype} == EV_CURRENT;

    my ($elf_word, $elf_endian);
    if ($elf{bits} == ELF_BITS_32) {
        $elf_word = 'L';
    } elsif ($elf{bits} == ELF_BITS_64) {
        $elf_word = 'Q';
    } else {
        return;
    }
    if ($elf{endian} == ELF_ORDER_2LSB) {
        $elf_endian = '<';
    } elsif ($elf{endian} == ELF_ORDER_2MSB) {
        $elf_endian = '>';
    } else {
        return;
    }

    # Unpack the endianness and size dependent fields.
    my $tmpl = "x16(S2Lx[${elf_word}3]L)${elf_endian}";
    @elf{qw(type mach version flags)} = unpack $tmpl, $header;

    # Canonicalize the machine ID.
    $elf{mach} = $elf_mach_map{$elf{mach}} // $elf{mach};

    # Mask any processor flags that might not change the architecture ABI.
    $elf{flags} &= $elf_flags_mask{$elf{mach}} // 0;

    # Repack for easy comparison, as a big-endian byte stream, so that
    # unpacking for output gives meaningful results.
    $format{$file} = pack 'C2(SL)>', @elf{qw(bits endian mach flags)};

    return $format{$file};
}

sub is_elf {
    my $file = shift;
    open(my $file_fh, '<', $file) or syserr(g_('cannot read %s'), $file);
    my ($header, $result) = ('', 0);
    if (read($file_fh, $header, 4) == 4) {
	$result = 1 if ($header =~ /^\177ELF$/);
    }
    close($file_fh);
    return $result;
}

=head1 CHANGES

=head2 Version 0.xx

This is a private module.

=cut

1;
