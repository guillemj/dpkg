# -*- mode: cperl;-*-

use Test::More tests => 14;

use strict;
use warnings;

use_ok('Dpkg::Shlibs');

my @save_paths = @Dpkg::Shlibs::librarypaths;
@Dpkg::Shlibs::librarypaths = ();

Dpkg::Shlibs::parse_ldso_conf("t/200_Dpkg_Shlibs/ld.so.conf");

use Data::Dumper;
is_deeply([qw(/nonexistant32 /nonexistant/lib64
	     /usr/local/lib /nonexistant/lib128 )],
	  \@Dpkg::Shlibs::librarypaths, "parsed library paths");

use_ok('Dpkg::Shlibs::Objdump');

my $obj = Dpkg::Shlibs::Objdump::Object->new;

open my $objdump, '<', "t/200_Dpkg_Shlibs/objdump.libc6"
  or die "t/200_Dpkg_Shlibs/objdump.libc6: $!";
$obj->_parse($objdump);
close $objdump;

is($obj->{SONAME}, 'libc.so.6', 'SONAME');
is($obj->{HASH}, '0x13d99c', 'HASH');
is($obj->{GNU_HASH}, '0x194', 'GNU_HASH');
is($obj->{format}, 'elf32-i386', 'format');
is_deeply($obj->{NEEDED}, [ 'ld-linux.so.2' ], 'NEEDED');
is_deeply([ $obj->get_needed_libraries ], [ 'ld-linux.so.2' ], 'NEEDED');

my $sym = $obj->get_symbol('_sys_nerr@GLIBC_2.3');
is_deeply( $sym, { name => '_sys_nerr', version => 'GLIBC_2.3',
		   soname => 'libc.so.6', section => '.rodata', dynamic => 1,
		   debug => '', type => 'O', weak => '',
		   hidden => 1, defined => 1 }, 'Symbol' );
$sym = $obj->get_symbol('_IO_stdin_used');
is_deeply( $sym, { name => '_IO_stdin_used', version => '',
		   soname => 'libc.so.6', section => '*UND*', dynamic => 1,
		   debug => '', type => ' ', weak => 1,
		   hidden => '', defined => '' }, 'Symbol 2' );

my @syms = $obj->get_exported_dynamic_symbols;
is( scalar @syms, 2231, 'defined && dynamic' );
@syms = $obj->get_undefined_dynamic_symbols;
is( scalar @syms, 9, 'undefined && dynamic' );


use_ok('Dpkg::Shlibs::SymbolFile');
