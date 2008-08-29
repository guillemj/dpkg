#!/usr/bin/perl

use strict;
use warnings;

use Dpkg;
use Dpkg::Arch qw(get_host_arch);
use Dpkg::Shlibs qw(@librarypaths);
use Dpkg::Shlibs::Objdump;
use Dpkg::Shlibs::SymbolFile;
use Dpkg::Gettext;
use Dpkg::ErrorHandling qw(warning error syserr usageerr);
use Dpkg::Control;
use Dpkg::Changelog qw(parse_changelog);
use Dpkg::Path qw(check_files_are_the_same);

textdomain("dpkg-dev");

my $packagebuilddir = 'debian/tmp';

my $sourceversion;
my $stdout;
my $oppackage;
my $compare = 1; # Bail on missing symbols by default
my $input;
my $output;
my $debug = 0;
my $host_arch = get_host_arch();

sub version {
    printf _g("Debian %s version %s.\n"), $progname, $version;

    printf _g("
Copyright (C) 2007 Raphael Hertzog.
");

    printf _g("
This is free software; see the GNU General Public Licence version 2 or
later for copying conditions. There is NO warranty.
");
}

sub usage {
    printf _g(
"Usage: %s [<option> ...]

Options:
  -p<package>              generate symbols file for package.
  -P<packagebuilddir>      temporary build dir instead of debian/tmp.
  -e<library>              explicitely list libraries to scan.
  -v<version>              version of the packages (defaults to
                           version extracted from debian/changelog).
  -c<level>                compare generated symbols file with the
                           reference file in the debian directory.
			   Fails if difference are too important
			   (level goes from 0 for no check, to 4
			   for all checks). By default checks at
			   level 1.
  -I<file>                 force usage of <file> as reference symbols
                           file instead of the default file.
  -O<file>                 write to <file>, not .../DEBIAN/symbols.
  -O                       write to stdout, not .../DEBIAN/symbols.
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
    } elsif (m/^-d$/) {
	$debug = 1;
    } elsif (m/^-v(.*)/) {
	$sourceversion = $1;
    } elsif (m/^-e(.*)/) {
	my $file = $1;
	if (-e $file) {
	    push @files, $file;
	} else {
	    push @files, glob($file);
	}
    } elsif (m/^-p(.*)/) {
	error(_g("Illegal package name \`%s'"), $1);
    } elsif (m/^-P(.*)$/) {
	$packagebuilddir = $1;
	$packagebuilddir =~ s{/+$}{};
    } elsif (m/^-O$/) {
	$stdout = 1;
    } elsif (m/^-I(.+)$/) {
	$input = $1;
    } elsif (m/^-O(.+)$/) {
	$output = $1;
    } elsif (m/^-(h|-help)$/) {
	&usage; exit(0);
    } elsif (m/^--version$/) {
	&version; exit(0);
    } else {
	usageerr(_g("unknown option \`%s'"), $_);
    }
}

if (exists $ENV{DPKG_GENSYMBOLS_CHECK_LEVEL}) {
    $compare = $ENV{DPKG_GENSYMBOLS_CHECK_LEVEL};
}

if (not defined($sourceversion)) {
    my $changelog = parse_changelog();
    $sourceversion = $changelog->{"Version"};
}
if (not defined($oppackage)) {
    my $control = Dpkg::Control->new();
    my @packages = map { $_->{'Package'} } $control->get_packages();
    @packages == 1 ||
	error(_g("must specify package since control info has many (%s)"),
	      "@packages");
    $oppackage = $packages[0];
}

my $symfile = Dpkg::Shlibs::SymbolFile->new();
my $ref_symfile = Dpkg::Shlibs::SymbolFile->new();
# Load source-provided symbol information
foreach my $file ($input, $output, "debian/$oppackage.symbols.$host_arch",
    "debian/symbols.$host_arch", "debian/$oppackage.symbols",
    "debian/symbols")
{
    if (defined $file and -e $file) {
	print "Using references symbols from $file\n" if $debug;
	$symfile->load($file);
	$ref_symfile->load($file) if $compare;
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
    my $objid = $od->parse($file);
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
    $output = "standard output";
    $symfile->save("-");
} else {
    unless (defined($output)) {
	unless($symfile->is_empty()) {
	    $output = "$packagebuilddir/DEBIAN/symbols";
	    mkdir("$packagebuilddir/DEBIAN") if not -e "$packagebuilddir/DEBIAN";
	}
    }
    if (defined($output)) {
	print "Storing symbols in $output.\n" if $debug;
	$symfile->save($output);
    } else {
	print "No symbol information to store.\n" if $debug;
    }
}

# Check if generated files differs from reference file
my $exitcode = 0;
if ($compare) {
    use File::Temp;
    use Digest::MD5;
    # Compare
    if (my @libs = $symfile->get_new_libs($ref_symfile)) {
	warning(_g("new libraries appeared in the symbols file: %s"), "@libs");
	$exitcode = 4 if ($compare >= 4);
    }
    if (my @libs = $symfile->get_lost_libs($ref_symfile)) {
	warning(_g("some libraries disappeared in the symbols file: %s"), "@libs");
	$exitcode = 3 if ($compare >= 3);
    }
    if ($symfile->get_new_symbols($ref_symfile)) {
	unless ($symfile->used_wildcards()) {
	    # Wildcards are used to replace many additional symbols, so we
	    # have no idea if this is really true, so don't say it and
	    # don't check it
	    warning(_g("some new symbols appeared in the symbols file: %s"),
		    _g("see diff output below"));
	    $exitcode = 2 if ($compare >= 2);
	}
    }
    if (my @syms = $symfile->get_lost_symbols($ref_symfile)) {
	my $list = _g("see diff output below");
	if ($symfile->used_wildcards()) {
	    # If wildcards are used, we don't get a diff, so list
	    # explicitely symbols which are lost
	    $list = "\n";
	    my $cur_soname = "";
	    foreach my $sym (sort { $a->{soname} cmp $b->{soname} or
				    $a->{name} cmp $b->{name} } @syms) {
		if ($cur_soname ne $sym->{soname}) {
		    $list .= $sym->{soname} . "\n";
		    $cur_soname = $sym->{soname};
		}
		$list .= " " . $sym->{name} . "\n";
	    }
	}
	warning(_g("some symbols disappeared in the symbols file: %s"), $list);
	$exitcode = 1 if ($compare >= 1);
    }
    unless ($symfile->used_wildcards()) {
	# If wildcards are not used, we can compare symbols files before
	# and after
	my $before = File::Temp->new(TEMPLATE=>'dpkg-gensymbolsXXXXXX');
	my $after = File::Temp->new(TEMPLATE=>'dpkg-gensymbolsXXXXXX');
	$ref_symfile->dump($before); $symfile->dump($after);
	seek($before, 0, 0); seek($after, 0, 0);
	my ($md5_before, $md5_after) = (Digest::MD5->new(), Digest::MD5->new());
	$md5_before->addfile($before);
	$md5_after->addfile($after);
	# Output diffs between symbols files if any
	if ($md5_before->hexdigest() ne $md5_after->hexdigest()) {
	    if (defined($ref_symfile->{file})) {
		warning(_g("%s doesn't match completely %s"),
			$output, $ref_symfile->{file});
	    } else {
		warning(_g("no debian/symbols file used as basis for generating %s"),
			$output);
	    }
	    my ($a, $b) = ($before->filename, $after->filename);
	    system("diff", "-u", $a, $b) if -x "/usr/bin/diff";
	}
    }
}
exit($exitcode);
