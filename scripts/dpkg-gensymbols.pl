#!/usr/bin/perl
#
# dpkg-gensymbols
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

use strict;
use warnings;

use Dpkg;
use Dpkg::Arch qw(get_host_arch);
use Dpkg::Shlibs qw(@librarypaths);
use Dpkg::Shlibs::Objdump;
use Dpkg::Shlibs::SymbolFile;
use Dpkg::Gettext;
use Dpkg::ErrorHandling;
use Dpkg::Control::Info;
use Dpkg::Changelog::Parse;
use Dpkg::Path qw(check_files_are_the_same);

textdomain("dpkg-dev");

my $packagebuilddir = 'debian/tmp';

my $sourceversion;
my $stdout;
my $oppackage;
my $compare = 1; # Bail on missing symbols by default
my $quiet = 0;
my $input;
my $output;
my $template_mode = 0; # non-template mode by default
my $verbose_output = 0;
my $debug = 0;
my $host_arch = get_host_arch();

sub version {
    printf _g("Debian %s version %s.\n"), $progname, $version;

    printf _g("
Copyright (C) 2007 Raphael Hertzog.
");

    printf _g("
This is free software; see the GNU General Public License version 2 or
later for copying conditions. There is NO warranty.
");
}

sub usage {
    printf _g(
"Usage: %s [<option> ...]

Options:
  -p<package>              generate symbols file for package.
  -P<packagebuilddir>      temporary build dir instead of debian/tmp.
  -e<library>              explicitly list libraries to scan.
  -v<version>              version of the packages (defaults to
                           version extracted from debian/changelog).
  -c<level>                compare generated symbols file with the
                           reference template in the debian directory
                           and fail if difference is too important
                           (level goes from 0 for no check, to 4
                           for all checks). By default checks at
                           level 1.
  -q                       keep quiet and never emit any warnings or
                           generate a diff between generated symbols
                           file and the reference template.
  -I<file>                 force usage of <file> as reference symbols
                           file instead of the default file.
  -O<file>                 write to <file>, not .../DEBIAN/symbols.
  -O                       write to stdout, not .../DEBIAN/symbols.
  -t                       write in template mode (tags are not
                           processed and included in output).
  -V                       verbose output. Write deprecated symbols and
                           pattern matching symbols as comments
                           (in template mode only).
  -a<arch>                 assume <arch> as host architecture when processing
                           symbol files.
  -d                       display debug information during work.
  -h, --help               show this help message.
      --version            show the version.
"), $progname;
}

my @files;
while (@ARGV) {
    $_ = shift(@ARGV);
    if (m/^-p([-+0-9a-z.]+)$/) {
	$oppackage = $1;
    } elsif (m/^-c(\d)?$/) {
	$compare = defined($1) ? $1 : 1;
    } elsif (m/^-q$/) {
	$quiet = 1;
    } elsif (m/^-d$/) {
	$debug = 1;
    } elsif (m/^-v(.+)$/) {
	$sourceversion = $1;
    } elsif (m/^-e(.+)$/) {
	my $file = $1;
	if (-e $file) {
	    push @files, $file;
	} else {
	    push @files, glob($file);
	}
    } elsif (m/^-p(.*)/) {
	error(_g("Illegal package name \`%s'"), $1);
    } elsif (m/^-P(.+)$/) {
	$packagebuilddir = $1;
	$packagebuilddir =~ s{/+$}{};
    } elsif (m/^-O$/) {
	$stdout = 1;
    } elsif (m/^-I(.+)$/) {
	$input = $1;
    } elsif (m/^-O(.+)$/) {
	$output = $1;
    } elsif (m/^-t$/) {
	$template_mode = 1;
    } elsif (m/^-V$/) {
	$verbose_output = 1;
    } elsif (m/^-a(.+)$/) {
	$host_arch = $1;
    } elsif (m/^-(h|-help)$/) {
	usage();
	exit(0);
    } elsif (m/^--version$/) {
	version();
	exit(0);
    } else {
	usageerr(_g("unknown option \`%s'"), $_);
    }
}

umask 0022; # ensure sane default permissions for created files

if (exists $ENV{DPKG_GENSYMBOLS_CHECK_LEVEL}) {
    $compare = $ENV{DPKG_GENSYMBOLS_CHECK_LEVEL};
}

if (not defined($sourceversion)) {
    my $changelog = changelog_parse();
    $sourceversion = $changelog->{"Version"};
}
if (not defined($oppackage)) {
    my $control = Dpkg::Control::Info->new();
    my @packages = map { $_->{'Package'} } $control->get_packages();
    @packages == 1 ||
	error(_g("must specify package since control info has many (%s)"),
	      "@packages");
    $oppackage = $packages[0];
}

my $symfile = Dpkg::Shlibs::SymbolFile->new(arch => $host_arch);
my $ref_symfile = Dpkg::Shlibs::SymbolFile->new(arch => $host_arch);
# Load source-provided symbol information
foreach my $file ($input, $output, "debian/$oppackage.symbols.$host_arch",
    "debian/symbols.$host_arch", "debian/$oppackage.symbols",
    "debian/symbols")
{
    if (defined $file and -e $file) {
	print "Using references symbols from $file\n" if $debug;
	$symfile->load($file);
	$ref_symfile->load($file) if $compare || ! $quiet;
	last;
    }
}

# Scan package build dir looking for libraries
if (not scalar @files) {
    PATH: foreach my $path (@librarypaths) {
	my $libdir = "$packagebuilddir$path";
	$libdir =~ s{/+}{/}g;
	lstat $libdir;
	next if not -d _;
	next if -l _; # Skip directories which are symlinks
        # Skip any directory _below_ a symlink as well
        my $updir = $libdir;
        while (($updir =~ s{/[^/]*$}{}) and
               not check_files_are_the_same($packagebuilddir, $updir)) {
            next PATH if -l $updir;
        }
	opendir(DIR, "$libdir") ||
	    syserr(_g("Can't read directory %s: %s"), $libdir, $!);
	push @files, grep {
	    /(\.so\.|\.so$)/ && -f $_ &&
	    Dpkg::Shlibs::Objdump::is_elf($_);
	} map { "$libdir/$_" } readdir(DIR);
	close(DIR);
    }
}

# Merge symbol information
my $od = Dpkg::Shlibs::Objdump->new();
foreach my $file (@files) {
    print "Scanning $file for symbol information\n" if $debug;
    my $objid = $od->analyze($file);
    unless (defined($objid) && $objid) {
	warning(_g("Objdump couldn't parse %s\n"), $file);
	next;
    }
    my $object = $od->get_object($objid);
    if ($object->{SONAME}) { # Objects without soname are of no interest
	print "Merging symbols from $file as $object->{SONAME}\n" if $debug;
	if (not $symfile->has_object($object->{SONAME})) {
	    $symfile->create_object($object->{SONAME}, "$oppackage #MINVER#");
	}
	$symfile->merge_symbols($object, $sourceversion);
    } else {
	print "File $file doesn't have a soname. Ignoring.\n" if $debug;
    }
}
$symfile->clear_except(keys %{$od->{objects}});

# Write out symbols files
if ($stdout) {
    $output = _g("<standard output>");
    $symfile->output(\*STDOUT, package => $oppackage,
                     template_mode => $template_mode,
                     with_pattern_matches => $verbose_output,
                     with_deprecated => $verbose_output);
} else {
    unless (defined($output)) {
	unless($symfile->is_empty()) {
	    $output = "$packagebuilddir/DEBIAN/symbols";
	    mkdir("$packagebuilddir/DEBIAN") if not -e "$packagebuilddir/DEBIAN";
	}
    }
    if (defined($output)) {
	print "Storing symbols in $output.\n" if $debug;
	$symfile->save($output, package => $oppackage,
	               template_mode => $template_mode,
	               with_pattern_matches => $verbose_output,
	               with_deprecated => $verbose_output);
    } else {
	print "No symbol information to store.\n" if $debug;
    }
}

# Check if generated files differs from reference file
my $exitcode = 0;
if ($compare || ! $quiet) {
    # Compare
    if (my @libs = $symfile->get_new_libs($ref_symfile)) {
	warning(_g("new libraries appeared in the symbols file: %s"), "@libs")
	    unless $quiet;
	$exitcode = 4 if ($compare >= 4);
    }
    if (my @libs = $symfile->get_lost_libs($ref_symfile)) {
	warning(_g("some libraries disappeared in the symbols file: %s"), "@libs")
	    unless $quiet;
	$exitcode = 3 if ($compare >= 3);
    }
    if ($symfile->get_new_symbols($ref_symfile)) {
	warning(_g("some new symbols appeared in the symbols file: %s"),
		_g("see diff output below")) unless $quiet;
	$exitcode = 2 if ($compare >= 2);
    }
    if ($symfile->get_lost_symbols($ref_symfile)) {
	warning(_g("some symbols or patterns disappeared in the symbols file: %s"),
	        _g("see diff output below")) unless $quiet;
	$exitcode = 1 if ($compare >= 1);
    }
}

unless ($quiet) {
    use File::Temp;
    use Digest::MD5;
    # Compare template symbols files before and after
    my $before = File::Temp->new(TEMPLATE=>'dpkg-gensymbolsXXXXXX');
    my $after = File::Temp->new(TEMPLATE=>'dpkg-gensymbolsXXXXXX');
    $ref_symfile->output($before, package => $oppackage, template_mode => 1);
    $symfile->output($after, package => $oppackage, template_mode => 1);
    seek($before, 0, 0); seek($after, 0, 0);
    my ($md5_before, $md5_after) = (Digest::MD5->new(), Digest::MD5->new());
    $md5_before->addfile($before);
    $md5_after->addfile($after);
    # Output diffs between symbols files if any
    if ($md5_before->hexdigest() ne $md5_after->hexdigest()) {
	if (not defined($output)) {
	    warning(_g("the generated symbols file is empty"));
	} elsif (defined($ref_symfile->{file})) {
	    warning(_g("%s doesn't match completely %s"),
		    $output, $ref_symfile->{file});
	} else {
	    warning(_g("no debian/symbols file used as basis for generating %s"),
		    $output);
	}
	my ($a, $b) = ($before->filename, $after->filename);
	my $diff_label = sprintf("%s (%s_%s_%s)",
	($ref_symfile->{file}) ? $ref_symfile->{file} : "new_symbol_file",
	$oppackage, $sourceversion, $host_arch);
	system("diff", "-u", "-L", $diff_label, $a, $b) if -x "/usr/bin/diff";
    }
}
exit($exitcode);
