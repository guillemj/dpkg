# -*- mode: cperl;-*-

use Test::More tests => 37;
use IO::String;

use strict;
use warnings;

use_ok('Dpkg::Shlibs');

my @save_paths = @Dpkg::Shlibs::librarypaths;
@Dpkg::Shlibs::librarypaths = ();

my $srcdir = $ENV{srcdir} || '.';
$srcdir .= '/t/200_Dpkg_Shlibs';

Dpkg::Shlibs::parse_ldso_conf("t.tmp/ld.so.conf");

use Data::Dumper;
is_deeply([qw(/nonexistant32 /nonexistant/lib64
	     /usr/local/lib /nonexistant/lib128 )],
	  \@Dpkg::Shlibs::librarypaths, "parsed library paths");

use_ok('Dpkg::Shlibs::Objdump');

my $obj = Dpkg::Shlibs::Objdump::Object->new;

open my $objdump, '<', "$srcdir/objdump.dbd-pg"
  or die "$srcdir/objdump.dbd-pg: $!";
$obj->_parse($objdump);
close $objdump;
ok(!$obj->is_public_library(), 'Pg.so is not a public library');
ok(!$obj->is_executable(), 'Pg.so is not an executable');

open $objdump, '<', "$srcdir/objdump.ls"
  or die "$srcdir/objdump.ls: $!";
$obj->reset();
$obj->_parse($objdump);
close $objdump;
ok(!$obj->is_public_library(), 'ls is not a public library');
ok($obj->is_executable(), 'ls is an executable');

my $sym = $obj->get_symbol('optarg@GLIBC_2.0');
ok($sym, 'optarg@GLIBC_2.0 exists');
ok(!$sym->{'defined'}, 'R_*_COPY relocations are taken into account');

# Non-regression test for #506139
$sym = $obj->get_symbol('singlespace');
ok($sym, 'version less symbol separated by a single space are correctly parsed');

open $objdump, '<', "$srcdir/objdump.libc6-2.6"
  or die "$srcdir/objdump.libc6-2.6: $!";
$obj->reset();
$obj->_parse($objdump);
close $objdump;

ok($obj->is_public_library(), 'libc6 is a public library');
ok(!$obj->is_executable(), 'libc6 is not an executable');

is($obj->{SONAME}, 'libc.so.6', 'SONAME');
is($obj->{HASH}, '0x13d99c', 'HASH');
is($obj->{GNU_HASH}, '0x194', 'GNU_HASH');
is($obj->{format}, 'elf32-i386', 'format');
is_deeply($obj->{flags}, { DYNAMIC => 1, HAS_SYMS => 1, D_PAGED => 1 }, 'flags');
is_deeply($obj->{NEEDED}, [ 'ld-linux.so.2' ], 'NEEDED');
is_deeply([ $obj->get_needed_libraries ], [ 'ld-linux.so.2' ], 'NEEDED');

$sym = $obj->get_symbol('_sys_nerr@GLIBC_2.3');
is_deeply( $sym, { name => '_sys_nerr', version => 'GLIBC_2.3',
		   soname => 'libc.so.6', objid => 'libc.so.6',
		   section => '.rodata', dynamic => 1,
		   debug => '', type => 'O', weak => '',
		   local => '', global => 1, visibility => '',
		   hidden => 1, defined => 1 }, 'Symbol' );
$sym = $obj->get_symbol('_IO_stdin_used');
is_deeply( $sym, { name => '_IO_stdin_used', version => '',
		   soname => 'libc.so.6', objid => 'libc.so.6',
		   section => '*UND*', dynamic => 1,
		   debug => '', type => ' ', weak => 1,
		   local => '', global => '', visibility => '',   
		   hidden => '', defined => '' }, 'Symbol 2' );

my @syms = $obj->get_exported_dynamic_symbols;
is( scalar @syms, 2231, 'defined && dynamic' );
@syms = $obj->get_undefined_dynamic_symbols;
is( scalar @syms, 9, 'undefined && dynamic' );


my $obj_old = Dpkg::Shlibs::Objdump::Object->new;

open $objdump, '<', "$srcdir/objdump.libc6-2.3"
  or die "$srcdir/objdump.libc6-2.3: $!";
$obj_old->_parse($objdump);
close $objdump;


use_ok('Dpkg::Shlibs::SymbolFile');

my $sym_file = Dpkg::Shlibs::SymbolFile->new("$srcdir/symbol_file.tmp");
my $sym_file_dup = Dpkg::Shlibs::SymbolFile->new("$srcdir/symbol_file.tmp");
my $sym_file_old = Dpkg::Shlibs::SymbolFile->new("$srcdir/symbol_file.tmp");

$sym_file->merge_symbols($obj_old, "2.3.6.ds1-13");
$sym_file_old->merge_symbols($obj_old, "2.3.6.ds1-13");

ok( $sym_file->has_object('libc.so.6'), 'SONAME in sym file' );

$sym_file->merge_symbols($obj, "2.6-1");

ok( $sym_file->get_new_symbols($sym_file_old), 'has new symbols' );
ok( $sym_file_old->get_lost_symbols($sym_file), 'has lost symbols' );

is( $sym_file_old->lookup_symbol('__bss_start@Base', ['libc.so.6']),
    undef, 'internal symbols are blacklisted');

$sym = $sym_file->lookup_symbol('_errno@GLIBC_2.0', ['libc.so.6'], 1);
is_deeply($sym, { 'minver' => '2.3.6.ds1-13', 'dep_id' => 0, 
		  'deprecated' => '2.6-1', 'depends' => '', 
		  'soname' => 'libc.so.6' }, 'deprecated symbol');

use File::Temp;

my $save_file = new File::Temp;

$sym_file->save($save_file->filename);

$sym_file_dup->load($save_file->filename);
$sym_file_dup->{file} = "$srcdir/symbol_file.tmp";

is_deeply($sym_file_dup, $sym_file, 'save -> load' );

# Test include mechanism of SymbolFile
$sym_file = Dpkg::Shlibs::SymbolFile->new("$srcdir/symbols.include-1");

$sym = $sym_file->lookup_symbol('symbol_before@Base', ['libfake.so.1']);
is_deeply($sym, { 'minver' => '0.9', 'dep_id' => 0, 'deprecated' => 0,
		  'depends' => 'libfake1 #MINVER#', 'soname' => 'libfake.so.1' }, 
	    'symbol before include not lost');

$sym = $sym_file->lookup_symbol('symbol_after@Base', ['libfake.so.1']);
is_deeply($sym, {'minver' => '1.1', 'dep_id' => 0, 'deprecated' => 0, 
		  'depends' => 'libfake1 #MINVER#', 'soname' => 'libfake.so.1' }, 
	    'symbol after include not lost');

$sym = $sym_file->lookup_symbol('symbol1_fake1@Base', ['libfake.so.1']);
is_deeply($sym, {'minver' => '1.0', 'dep_id' => 0, 'deprecated' => 0, 
		  'depends' => 'libfake1 #MINVER#', 'soname' => 'libfake.so.1' }, 
	    'overrides order with #include');

$sym = $sym_file->lookup_symbol('symbol3_fake1@Base', ['libfake.so.1']);
is_deeply($sym, { 'minver' => '1.1', 'dep_id' => 0, 'deprecated' => 0,
		  'depends' => 'libfake1 #MINVER#', 'soname' => 'libfake.so.1' }, 
	    'overrides order with #include');

$sym_file = Dpkg::Shlibs::SymbolFile->new("$srcdir/symbols.include-2");

$sym = $sym_file->lookup_symbol('symbol1_fake2@Base', ['libfake.so.1']);
is_deeply($sym, { 'minver' => '1.0', 'dep_id' => 1, 'deprecated' => 0,
		  'depends' => 'libvirtualfake', 'soname' => 'libfake.so.1' }, 
	    'overrides order with circular #include');

# Check dump output
my $io = IO::String->new();
$sym_file->dump($io);
is(${$io->string_ref()},
'libfake.so.1 libfake1 #MINVER#
| libvirtualfake
* Build-Depends-Package: libfake-dev
 symbol1_fake2@Base 1.0 1
 symbol2_fake2@Base 1.0
 symbol3_fake2@Base 1.0
', "Dump of $srcdir/symbols.include-2");


# Check parsing of objdump output on ia64 (local symbols
# without versions and with visibility attribute)
$obj = Dpkg::Shlibs::Objdump::Object->new;

open $objdump, '<', "$srcdir/objdump.glib-ia64"
  or die "$srcdir/objdump.glib-ia64: $!";
$obj->_parse($objdump);
close $objdump;

$sym = $obj->get_symbol('IA__g_free');
is_deeply( $sym, { name => 'IA__g_free', version => '',
		   soname => 'libglib-2.0.so.0', objid => 'libglib-2.0.so.0',
		   section => '.text', dynamic => 1,
		   debug => '', type => 'F', weak => '',
		   local => 1, global => '', visibility => 'hidden',
		   hidden => '', defined => 1 }, 
		   'symbol with visibility without version' );

