# -*- mode: cperl;-*-
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

use Test::More tests => 63;
use Cwd;
use IO::String;

use strict;
use warnings;

use_ok('Dpkg::Shlibs');

my @tmp;

my @save_paths = @Dpkg::Shlibs::librarypaths;
@Dpkg::Shlibs::librarypaths = ();

my $srcdir = $ENV{srcdir} || '.';
my $datadir = $srcdir . '/t/200_Dpkg_Shlibs';
my $tmpdir = 't.tmp/200_Dpkg_Shlibs';

# We want relative paths inside the ld.so.conf fragments to work, and $srcdir
# is usually a relative path, so let's temporarily switch directory.
# XXX: An alternative would be to make parse_ldso_conf relative path aware.
my $cwd = cwd();
chdir($srcdir);
Dpkg::Shlibs::parse_ldso_conf("t/200_Dpkg_Shlibs/ld.so.conf");
chdir($cwd);

use Data::Dumper;
is_deeply([qw(/nonexistant32 /nonexistant/lib64
	     /usr/local/lib /nonexistant/lib128 )],
	  \@Dpkg::Shlibs::librarypaths, "parsed library paths");

use_ok('Dpkg::Shlibs::Objdump');

my $obj = Dpkg::Shlibs::Objdump::Object->new;

open my $objdump, '<', "$datadir/objdump.dbd-pg"
  or die "$datadir/objdump.dbd-pg: $!";
$obj->_parse($objdump);
close $objdump;
ok(!$obj->is_public_library(), 'Pg.so is not a public library');
ok(!$obj->is_executable(), 'Pg.so is not an executable');

open $objdump, '<', "$datadir/objdump.ls"
  or die "$datadir/objdump.ls: $!";
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

open $objdump, '<', "$datadir/objdump.libc6-2.6"
  or die "$datadir/objdump.libc6-2.6: $!";
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

open $objdump, '<', "$datadir/objdump.libc6-2.3"
  or die "$datadir/objdump.libc6-2.3: $!";
$obj_old->_parse($objdump);
close $objdump;


use_ok('Dpkg::Shlibs::SymbolFile');
use_ok('Dpkg::Shlibs::Symbol');

my $sym_file = Dpkg::Shlibs::SymbolFile->new(file => "$datadir/symbol_file.tmp");
my $sym_file_dup = Dpkg::Shlibs::SymbolFile->new(file => "$datadir/symbol_file.tmp");
my $sym_file_old = Dpkg::Shlibs::SymbolFile->new(file => "$datadir/symbol_file.tmp");

$sym_file->merge_symbols($obj_old, "2.3.6.ds1-13");
$sym_file_old->merge_symbols($obj_old, "2.3.6.ds1-13");

ok( $sym_file->has_object('libc.so.6'), 'SONAME in sym file' );

$sym_file->merge_symbols($obj, "2.6-1");

ok( $sym_file->get_new_symbols($sym_file_old), 'has new symbols' );
ok( $sym_file_old->get_lost_symbols($sym_file), 'has lost symbols' );

is( $sym_file_old->lookup_symbol('__bss_start@Base', ['libc.so.6']),
    undef, 'internal symbols are blacklisted');

$sym = $sym_file->lookup_symbol('_errno@GLIBC_2.0', ['libc.so.6'], 1);
isa_ok($sym, 'Dpkg::Shlibs::Symbol');
is_deeply($sym, Dpkg::Shlibs::Symbol->new( 'symbol' => '_errno@GLIBC_2.0',
		  'minver' => '2.3.6.ds1-13', 'dep_id' => 0,
		  'deprecated' => '2.6-1', 'depends' => '',
		  'soname' => 'libc.so.6' ), 'deprecated symbol');

# Wildcard test
$sym = Dpkg::Shlibs::Symbol->new(symbol => '*@GLIBC_PRIVATE', minver => '2.3.6.wildcard');
$sym_file_old->add_symbol('libc.so.6', $sym);
$sym_file_old->merge_symbols($obj, "2.6-1");
$sym = $sym_file_old->lookup_symbol('__nss_services_lookup@GLIBC_PRIVATE', ['libc.so.6']);
is_deeply($sym, Dpkg::Shlibs::Symbol->new( 'symbol' => '__nss_services_lookup@GLIBC_PRIVATE',
		  'minver' => '2.3.6.wildcard', 'dep_id' => 0,
		  'deprecated' => 0, 'depends' => '',
		  'soname' => 'libc.so.6' ), 'wildcarded symbol');

# Save -> Load test
use File::Temp;

my $save_file = new File::Temp;

$sym_file->save($save_file->filename);

$sym_file_dup->load($save_file->filename);
$sym_file_dup->{file} = "$datadir/symbol_file.tmp";

is_deeply($sym_file_dup, $sym_file, 'save -> load' );

# Test include mechanism of SymbolFile
$sym_file = Dpkg::Shlibs::SymbolFile->new(file => "$datadir/symbols.include-1");

$sym = $sym_file->lookup_symbol('symbol_before@Base', ['libfake.so.1']);
is_deeply($sym, Dpkg::Shlibs::Symbol->new( 'symbol' => 'symbol_before@Base',
		  'minver' => '0.9', 'dep_id' => 0, 'deprecated' => 0,
		  'depends' => 'libfake1 #MINVER#', 'soname' => 'libfake.so.1' ),
	    'symbol before include not lost');

$sym = $sym_file->lookup_symbol('symbol_after@Base', ['libfake.so.1']);
is_deeply($sym, Dpkg::Shlibs::Symbol->new( 'symbol' => 'symbol_after@Base',
		  'minver' => '1.1', 'dep_id' => 0, 'deprecated' => 0,
		  'depends' => 'libfake1 #MINVER#', 'soname' => 'libfake.so.1' ),
	    'symbol after include not lost');

$sym = $sym_file->lookup_symbol('symbol1_fake1@Base', ['libfake.so.1']);
is_deeply($sym, Dpkg::Shlibs::Symbol->new( 'symbol' => 'symbol1_fake1@Base',
		  'minver' => '1.0', 'dep_id' => 0, 'deprecated' => 0,
		  'depends' => 'libfake1 #MINVER#', 'soname' => 'libfake.so.1' ),
	    'overrides order with #include');

$sym = $sym_file->lookup_symbol('symbol3_fake1@Base', ['libfake.so.1']);
is_deeply($sym, Dpkg::Shlibs::Symbol->new ( 'symbol' => 'symbol3_fake1@Base',
		  'minver' => '0', 'dep_id' => 0, 'deprecated' => 0,
		  'depends' => 'libfake1 #MINVER#', 'soname' => 'libfake.so.1' ),
	    'overrides order with #include');

is($sym_file->get_smallest_version('libfake.so.1'), "0",
   'get_smallest_version with null version');

$sym = $sym_file->lookup_symbol('symbol_in_libdivert@Base', ['libdivert.so.1']);
is_deeply($sym, Dpkg::Shlibs::Symbol->new ( 'symbol' => 'symbol_in_libdivert@Base',
		  'minver' => '1.0~beta1', 'dep_id' => 0, 'deprecated' => 0,
		  'depends' => 'libdivert1 #MINVER#', 'soname' => 'libdivert.so.1'),
	    '#include can change current object');

$sym_file = Dpkg::Shlibs::SymbolFile->new(file => "$datadir/symbols.include-2");

$sym = $sym_file->lookup_symbol('symbol1_fake2@Base', ['libfake.so.1']);
is_deeply($sym, Dpkg::Shlibs::Symbol->new ( 'symbol' => 'symbol1_fake2@Base',
		  'minver' => '1.0', 'dep_id' => 1, 'deprecated' => 0,
		  'depends' => 'libvirtualfake', 'soname' => 'libfake.so.1' ),
	    'overrides order with circular #include');

is($sym_file->get_smallest_version('libfake.so.1'), "1.0",
   'get_smallest_version');

# Check dump output
my $io = IO::String->new();
$sym_file->dump($io, package => "libfake1");
is(${$io->string_ref()},
'libfake.so.1 libfake1 #MINVER#
| libvirtualfake
* Build-Depends-Package: libfake-dev
 symbol1_fake2@Base 1.0 1
 symbol2_fake2@Base 1.0
 symbol3_fake2@Base 1.1
', "Dump of $datadir/symbols.include-2");


# Check parsing of objdump output on ia64 (local symbols
# without versions and with visibility attribute)
$obj = Dpkg::Shlibs::Objdump::Object->new;

open $objdump, '<', "$datadir/objdump.glib-ia64"
  or die "$datadir/objdump.glib-ia64: $!";
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

####### Test symbol tagging support  ######

# Parsing/dumping
# Template mode
$sym_file = Dpkg::Shlibs::SymbolFile->new(file => "$datadir/symbols.tags.in", arch => 'amd64');
$sym_file->save($save_file->filename, template_mode => 1);

$sym_file_dup = Dpkg::Shlibs::SymbolFile->new(file => $save_file, arch => 'amd64');
$sym_file_dup->{file} = "$datadir/symbols.tags.in";

is_deeply($sym_file_dup, $sym_file, 'template save -> load' );
is( system("diff -u '$datadir/symbols.tags.in' '" . $save_file->filename . "' >&2"), 0, "symbols.tags.in template dumped identical" );

# Dumping in non-template mode (amd64) (test for arch, subst tags)
$io = IO::String->new();
$sym_file->dump($io);
is(${$io->string_ref()},
'libsymboltags.so.1 libsymboltags1 #MINVER#
| libsymboltags1 (>= 1.1)
 symbol11_optional@Base 1.1 1
 symbol21_amd64@Base 2.1
 symbol31_randomtag@Base 3.1
 symbol51_untagged@Base 5.1
', "template vs. non-template on amd64" );

# Dumping in non-template mode (i386) (test for arch, subst tags)
$io = IO::String->new();
$sym_file = Dpkg::Shlibs::SymbolFile->new(file => "$datadir/symbols.tags.in", arch => 'i386');
$sym_file_dup = Dpkg::Shlibs::SymbolFile->new(file => "$datadir/symbols.tags.in", arch => 'i386');
$sym_file->dump($io);
is(${$io->string_ref()},
'libsymboltags.so.1 libsymboltags1 #MINVER#
| libsymboltags1 (>= 1.1)
 symbol11_optional@Base 1.1 1
 symbol22_i386@Base 2.2
 symbol31_randomtag@Base 3.1
 symbol41_i386_and_optional@Base 4.1
 symbol51_untagged@Base 5.1
', "template vs. non-template on i386" );

ok (defined $sym_file->{objects}{'libsymboltags.so.1'}{syms}{'symbol21_amd64@Base'},
    "syms keys are symbol names without quotes");

# Preload objdumps
my $tags_obj_i386 = Dpkg::Shlibs::Objdump::Object->new();
open $objdump, '<', "$tmpdir/objdump.tags-i386"
    or die "$tmpdir/objdump.tags-i386: $!";
$tags_obj_i386->_parse($objdump);
close $objdump;
$sym_file->merge_symbols($tags_obj_i386, '100.MISSING');
is_deeply($sym_file, $sym_file_dup, "is objdump.tags-i386 and symbols.tags.in in sync");

my $tags_obj_amd64 = Dpkg::Shlibs::Objdump::Object->new();
open $objdump, '<', "$tmpdir/objdump.tags-amd64"
    or die "$tmpdir/objdump.tags-amd64: $!";
$tags_obj_amd64->_parse($objdump);
close $objdump;

# Merge/get_{new,lost} tests for optional tag:
#  - disappeared
my $symbol11 = $tags_obj_i386->get_symbol('symbol11_optional@Base');
delete $tags_obj_i386->{dynsyms}{'symbol11_optional@Base'};
$sym_file->merge_symbols($tags_obj_i386, '100.MISSING');

$sym = $sym_file->lookup_symbol('symbol11_optional@Base', ['libsymboltags.so.1'], 1);
is_deeply($sym, Dpkg::Shlibs::Symbol->new( 'symbol' => 'symbol11_optional@Base', 'symbol_templ' => 'symbol11_optional@Base',
		  'minver' => '1.1', 'dep_id' => 1, 'deprecated' => '100.MISSING',
		  'depends' => 'libsymboltags1 (>= 1.1)', 'soname' => 'libsymboltags.so.1',
		  'tags' => { 'optional' => undef }, 'tagorder' => [ 'optional' ] ),
	    'disappered optional symbol gets deprecated');

$sym_file->merge_symbols($tags_obj_i386, '101.MISSING');
$sym = $sym_file->lookup_symbol('symbol11_optional@Base', ['libsymboltags.so.1'], 1);
is_deeply($sym, Dpkg::Shlibs::Symbol->new( 'symbol' => 'symbol11_optional@Base', 'symbol_templ' => 'symbol11_optional@Base',
		  'minver' => '1.1', 'dep_id' => 1, 'deprecated' => '101.MISSING',
		  'depends' => 'libsymboltags1 (>= 1.1)', 'soname' => 'libsymboltags.so.1',
		  'tags' => { 'optional' => undef }, 'tagorder' => [ 'optional' ] ),
	    'deprecated text of MISSING optional symbol gets rebumped each merge');

is( scalar($sym_file->get_lost_symbols($sym_file_dup)), 0, "missing optional symbol is not LOST");

# - reappeared (undeprecate, minver should be 1.1, not 100.MISSED)
$tags_obj_i386->add_dynamic_symbol($symbol11);
$sym_file->merge_symbols($tags_obj_i386, '100.MISSING');
$sym = $sym_file->lookup_symbol('symbol11_optional@Base', ['libsymboltags.so.1']);
is_deeply($sym, Dpkg::Shlibs::Symbol->new( 'symbol' => 'symbol11_optional@Base', 'symbol_templ' => 'symbol11_optional@Base',
		  'minver' => '1.1', 'dep_id' => 1, 'deprecated' => 0,
		  'depends' => 'libsymboltags1 (>= 1.1)', 'soname' => 'libsymboltags.so.1',
		  'tags' => { 'optional' => undef }, 'tagorder' => [ 'optional' ] ),
	    'reappered optional symbol gets undeprecated + minver');
is( scalar($sym_file->get_lost_symbols($sym_file_dup) +
           $sym_file->get_new_symbols($sym_file_dup)), 0, "reappeared optional symbol: neither NEW nor LOST");

# Merge/get_{new,lost} tests for arch tag:
# - arch specific appears on wrong arch: 'arch' tag should be removed
my $symbol21 = $tags_obj_amd64->get_symbol('symbol21_amd64@Base');
$tags_obj_i386->add_dynamic_symbol($symbol21);
$sym_file->merge_symbols($tags_obj_i386, '100.MISSING');
$sym = $sym_file->lookup_symbol('symbol21_amd64@Base', ['libsymboltags.so.1']);
is_deeply($sym, Dpkg::Shlibs::Symbol->new( 'symbol' => 'symbol21_amd64@Base', 'symbol_templ' => 'symbol21_amd64@Base',
		  'symbol_quoted' => "'", 'minver' => '2.1', 'dep_id' => 0, 'deprecated' => 0,
		  'depends' => 'libsymboltags1 #MINVER#', 'soname' => 'libsymboltags.so.1' ),
	    'symbol appears on foreign arch, arch tag should be removed');
@tmp = map { $_->get_symbolname() } $sym_file->get_new_symbols($sym_file_dup);
is_deeply( \@tmp, [ 'symbol21_amd64@Base' ], "symbol from foreign arch is NEW");
is( $sym->get_symbolspec(1), ' symbol21_amd64@Base 2.1', 'no tags => no quotes in the symbol name' );

# - arch specific symbol disappears
delete $tags_obj_i386->{dynsyms}{'symbol22_i386@Base'};
delete $tags_obj_i386->{dynsyms}{'symbol41_i386_and_optional@Base'};
$sym_file->merge_symbols($tags_obj_i386, '100.MISSING');

$sym = $sym_file->lookup_symbol('symbol22_i386@Base', ['libsymboltags.so.1'], 1);
is_deeply($sym, Dpkg::Shlibs::Symbol->new( 'symbol' => 'symbol22_i386@Base', 'symbol_templ' => 'symbol22_i386@Base',
		  'minver' => '2.2', 'dep_id' => 0, 'deprecated' => '100.MISSING',
		  'depends' => 'libsymboltags1 #MINVER#', 'soname' => 'libsymboltags.so.1',
		  'tags' => { 'arch' => '!amd64 !ia64 !alpha' }, 'tagorder' => [ 'arch' ] ),
	    'disappeared arch specific symbol gets deprecated');
$sym = $sym_file->lookup_symbol('symbol41_i386_and_optional@Base', ['libsymboltags.so.1'], 1);
is_deeply($sym, Dpkg::Shlibs::Symbol->new( 'symbol' => 'symbol41_i386_and_optional@Base',
		  'symbol_templ' => 'symbol41_i386_and_optional@Base', 'symbol_quoted' => '"',
		  'minver' => '4.1', 'dep_id' => 0, 'deprecated' => '100.MISSING',
		  'depends' => 'libsymboltags1 #MINVER#', 'soname' => 'libsymboltags.so.1',
		  'tags' => { 'arch' => 'i386', 'optional' => 'reason' }, 'tagorder' => [ 'arch', 'optional' ] ),
	    'disappeared optional arch specific symbol gets deprecated');
@tmp = map { $_->get_symbolname() } $sym_file->get_lost_symbols($sym_file_dup);
is_deeply( \@tmp, [ 'symbol22_i386@Base' ], "missing arch specific is LOST, but optional arch specific isn't");

# Tests for tagged #includes
$sym_file = Dpkg::Shlibs::SymbolFile->new(file => "$datadir/symbols.include-3", arch => 'i386');
$sym = $sym_file->lookup_symbol('symbol2_fake1@Base', ['libsymboltags.so.2']);
is_deeply($sym, Dpkg::Shlibs::Symbol->new( 'symbol' => 'symbol2_fake1@Base',
		  'minver' => '1.0', 'depends' => 'libsymboltags2', 'soname' => 'libsymboltags.so.2',
		  'tags' => { 'optional' => undef, 'random tag' => 'random value' },
		  'tagorder' => [ 'optional', 'random tag' ] ),
	    'symbols from #included file inherits tags');
$sym = $sym_file->lookup_symbol('symbol41_i386_and_optional@Base', ['libsymboltags.so.1']);
is_deeply($sym, Dpkg::Shlibs::Symbol->new( 'symbol' => 'symbol41_i386_and_optional@Base',
		  'symbol_templ' => 'symbol41_i386_and_optional@Base', symbol_quoted => '"',
		  'minver' => '4.1', 'depends' => 'libsymboltags1 #MINVER#', 'soname' => 'libsymboltags.so.1',
		  'tags' => { 'optional' => 'reason', 't' => 'v', 'arch' => 'i386' },
		  'tagorder' => [ 'optional', 't', 'arch' ] ),
	    'symbols in #included file can override tag values');
$sym = $sym_file->lookup_symbol('symbol51_untagged@Base', ['libsymboltags.so.1']);
is_deeply($sym, Dpkg::Shlibs::Symbol->new( 'symbol' => 'symbol51_untagged@Base',
		  'minver' => '5.1', 'depends' => 'libsymboltags1 #MINVER#', 'soname' => 'libsymboltags.so.1',
		  'tags' => { 'optional' => 'from parent', 't' => 'v' },
		  'tagorder' => [ 'optional', 't' ] ),
	    'symbols are properly cloned when #including');
