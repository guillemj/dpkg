#!/usr/bin/perl -w

use strict;
use warnings;

use English;
use POSIX qw(:errno_h :signal_h);
use Dpkg;
use Dpkg::Gettext;
use Dpkg::ErrorHandling qw(warning error failure syserr usageerr);
use Dpkg::Path qw(relative_to_pkg_root);
use Dpkg::Version qw(vercmp);
use Dpkg::Shlibs qw(find_library);
use Dpkg::Shlibs::Objdump;
use Dpkg::Shlibs::SymbolFile;
use Dpkg::Arch qw(get_host_arch);
use Dpkg::Fields qw(capit);

our $host_arch= get_host_arch();

# By increasing importance
my @depfields= qw(Suggests Recommends Depends Pre-Depends);
my $i=0; my %depstrength = map { $_ => $i++ } @depfields;

textdomain("dpkg-dev");

my $shlibsoverride= '/etc/dpkg/shlibs.override';
my $shlibsdefault= '/etc/dpkg/shlibs.default';
my $shlibslocal= 'debian/shlibs.local';
my $packagetype= 'deb';
my $dependencyfield= 'Depends';
my $varlistfile= 'debian/substvars';
my $varnameprefix= 'shlibs';
my $ignore_missing_info= 0;
my $debug= 0;
my @exclude = ();

my (@pkg_shlibs, @pkg_symbols);
if (-d "debian") {
    push @pkg_symbols, <debian/*/DEBIAN/symbols>;
    push @pkg_shlibs, <debian/*/DEBIAN/shlibs>;
}

my ($stdout, %exec);
foreach (@ARGV) {
    if (m/^-T(.*)$/) {
	$varlistfile= $1;
    } elsif (m/^-p(\w[-:0-9A-Za-z]*)$/) {
	$varnameprefix= $1;
    } elsif (m/^-L(.*)$/) {
	$shlibslocal= $1;
    } elsif (m/^-O$/) {
	$stdout= 1;
    } elsif (m/^-(h|-help)$/) {
	usage(); exit(0);
    } elsif (m/^--version$/) {
	version(); exit(0);
    } elsif (m/^--admindir=(.*)$/) {
	$admindir = $1;
	-d $admindir ||
	    error(_g("administrative directory '%s' does not exist"), $admindir);
    } elsif (m/^-d(.*)$/) {
	$dependencyfield= capit($1);
	defined($depstrength{$dependencyfield}) ||
	    warning(_g("unrecognised dependency field \`%s'"), $dependencyfield);
    } elsif (m/^-e(.*)$/) {
	$exec{$1} = $dependencyfield;
    } elsif (m/^--ignore-missing-info$/) {
	$ignore_missing_info = 1;
    } elsif (m/^-t(.*)$/) {
	$packagetype = $1;
    } elsif (m/^-v$/) {
	$debug = 1;
    } elsif (m/^-x(.*)$/) {
	push @exclude, $1;
    } elsif (m/^-/) {
	usageerr(_g("unknown option \`%s'"), $_);
    } else {
	$exec{$_} = $dependencyfield;
    }
}

scalar keys %exec || usageerr(_g("need at least one executable"));

my %dependencies;
my %shlibs;

my $cur_field;
foreach my $file (keys %exec) {
    $cur_field = $exec{$file};
    print "Scanning $file (for $cur_field field)\n" if $debug;

    my $obj = Dpkg::Shlibs::Objdump::Object->new($file);
    my @sonames = $obj->get_needed_libraries;

    # Load symbols files for all needed libraries (identified by SONAME)
    my %libfiles;
    foreach my $soname (@sonames) {
	my $lib = my_find_library($soname, $obj->{RPATH}, $obj->{format}, $file);
	failure(_g("couldn't find library %s (note: only packages with " .
	           "'shlibs' files are looked into)."), $soname)
	    unless defined($lib);
	$libfiles{$lib} = $soname;
	print "Library $soname found in $lib\n" if $debug;
    }
    my $file2pkg = find_packages(keys %libfiles);
    my $symfile = Dpkg::Shlibs::SymbolFile->new();
    my $dumplibs_wo_symfile = Dpkg::Shlibs::Objdump->new();
    my @soname_wo_symfile;
    foreach my $lib (keys %libfiles) {
	my $soname = $libfiles{$lib};
	if (not exists $file2pkg->{$lib}) {
	    # If the library is not available in an installed package,
	    # it's because it's in the process of being built
	    # Empty package name will lead to consideration of symbols
	    # file from the package being built only
	    $file2pkg->{$lib} = [""];
	    print "No associated package found for $lib\n" if $debug;
	}

	# Load symbols/shlibs files from packages providing libraries
	foreach my $pkg (@{$file2pkg->{$lib}}) {
	    my $dpkg_symfile;
	    if ($packagetype eq "deb") {
		# Use fine-grained dependencies only on real deb
		$dpkg_symfile = find_symbols_file($pkg, $soname);
		if (defined $dpkg_symfile) {
		    # Load symbol information
		    print "Using symbols file $dpkg_symfile for $soname\n" if $debug;
		    $symfile->load($dpkg_symfile);
		}
	    }
	    if (defined($dpkg_symfile) && $symfile->has_object($soname)) {
		# Initialize dependencies as an unversioned dependency
		my $dep = $symfile->get_dependency($soname);
		foreach my $subdep (split /\s*,\s*/, $dep) {
		    if (not exists $dependencies{$cur_field}{$subdep}) {
			$dependencies{$cur_field}{$subdep} = '';
		    }
		}
	    } else {
		# No symbol file found, fall back to standard shlibs
		my $id = $dumplibs_wo_symfile->parse($lib);
		push @soname_wo_symfile, $soname;
		my $libobj = $dumplibs_wo_symfile->get_object($id);
		# Only try to generate a dependency for libraries with a SONAME
		if ($libobj->is_public_library() and not add_shlibs_dep($soname, $pkg)) {
		    failure(_g("No dependency information found for %s " .
		               "(used by %s)."), $soname, $file)
		        unless $ignore_missing_info;
		}
	    }
	}
    }

    # Scan all undefined symbols of the binary and resolve to a
    # dependency
    my %used_sonames = map { $_ => 0 } @sonames;
    foreach my $sym ($obj->get_undefined_dynamic_symbols()) {
	my $name = $sym->{name};
	if ($sym->{version}) {
	    $name .= "\@$sym->{version}";
	} else {
	    $name .= "\@Base";
	}
	my $symdep = $symfile->lookup_symbol($name, \@sonames);
	if (defined($symdep)) {
	    my ($d, $m) = ($symdep->{depends}, $symdep->{minver});
	    $used_sonames{$symdep->{soname}}++;
	    foreach my $subdep (split /\s*,\s*/, $d) {
		if (exists $dependencies{$cur_field}{$subdep} and
		    defined($dependencies{$cur_field}{$subdep}))
		{
		    if ($dependencies{$cur_field}{$subdep} eq '' or
			vercmp($m, $dependencies{$cur_field}{$subdep}) > 0)
		    {
			$dependencies{$cur_field}{$subdep} = $m;
		    }
		} else {
		    $dependencies{$cur_field}{$subdep} = $m;
		}
	    }
	} else {
	    my $syminfo = $dumplibs_wo_symfile->locate_symbol($name);
	    if (not defined($syminfo)) {
		# Complain about missing symbols only for executables
		# and public libraries
		if ($obj->is_executable() or $obj->is_public_library()) {
		    my $print_name = $name;
		    # Drop the default suffix for readability
		    $print_name =~ s/\@Base$//;
		    warning(_g("symbol %s used by %s found in none of the " .
		               "libraries."), $print_name, $file)
		        unless $sym->{weak};
		}
	    } else {
		$used_sonames{$syminfo->{soname}}++;
	    }
	}
    }
    # Warn about un-NEEDED libraries
    foreach my $soname (@sonames) {
	unless ($used_sonames{$soname}) {
	    warning(_g("%s shouldn't be linked with %s (it uses none of its " .
	               "symbols)."), $file, $soname);
	}
    }
}

# Open substvars file
my $fh;
if ($stdout) {
    $fh = \*STDOUT;
} else {
    open(NEW, ">", "$varlistfile.new") ||
	syserr(_g("open new substvars file \`%s'"), "$varlistfile.new");
    if (-e $varlistfile) {
	open(OLD, "<", $varlistfile) ||
	    syserr(_g("open old varlist file \`%s' for reading"), $varlistfile);
	foreach my $entry (grep { not m/^\Q$varnameprefix\E:/ } (<OLD>)) {
	    print(NEW $entry) ||
	        syserr(_g("copy old entry to new varlist file \`%s'"),
	               "$varlistfile.new");
	}
	close(OLD);
    }
    $fh = \*NEW;
}

# Write out the shlibs substvars
my %depseen;

sub filter_deps {
    my ($dep, $field) = @_;
    # Skip dependencies on excluded packages
    foreach my $exc (@exclude) {
	return 0 if $dep =~ /^\s*\Q$exc\E\b/;
    }
    # Don't include dependencies if they are already
    # mentionned in a higher priority field
    if (not defined($depseen{$dep})) {
	$depseen{$dep} = $dependencies{$field}{$dep};
	return 1;
    } else {
	# Since dependencies can be versionned, we have to
	# verify if the dependency is stronger than the
	# previously seen one
	if (vercmp($depseen{$dep}, $dependencies{$field}{$dep}) > 0) {
	    return 0;
	} else {
	    $depseen{$dep} = $dependencies{$field}{$dep};
	    return 1;
	}
    }
}

foreach my $field (reverse @depfields) {
    my $dep = "";
    if (exists $dependencies{$field} and scalar keys %{$dependencies{$field}}) {
	$dep = join ", ",
	    map {
		# Translate dependency templates into real dependencies
		if ($dependencies{$field}{$_}) {
		    s/#MINVER#/(>= $dependencies{$field}{$_})/g;
		} else {
		    s/#MINVER#//g;
		}
		s/\s+/ /g;
		$_;
	    } grep { filter_deps($_, $field) }
	    keys %{$dependencies{$field}};
    }
    if ($dep) {
	print $fh "$varnameprefix:$field=$dep\n";
    }
}

# Replace old file by new one
if (!$stdout) {
    close($fh);
    rename("$varlistfile.new",$varlistfile) ||
	syserr(_g("install new varlist file \`%s'"), $varlistfile);
}

##
## Functions
##

sub version {
    printf _g("Debian %s version %s.\n"), $progname, $version;

    printf _g("
Copyright (C) 1996 Ian Jackson.
Copyright (C) 2000 Wichert Akkerman.
Copyright (C) 2006 Frank Lichtenheld.
Copyright (C) 2007 Raphael Hertzog.
");

    printf _g("
This is free software; see the GNU General Public Licence version 2 or
later for copying conditions. There is NO warranty.
");
}

sub usage {
    printf _g(
"Usage: %s [<option> ...] <executable>|-e<executable> [<option> ...]

Positional options (order is significant):
  <executable>             include dependencies for <executable>,
  -e<executable>           (use -e if <executable> starts with \`-')
  -d<dependencyfield>      next executable(s) set shlibs:<dependencyfield>.

Options:
  -p<varnameprefix>        set <varnameprefix>:* instead of shlibs:*.
  -O                       print variable settings to stdout.
  -L<localshlibsfile>      shlibs override file, not debian/shlibs.local.
  -T<varlistfile>          update variables here, not debian/substvars.
  -t<type>                 set package type (default is deb).
  -x<package>              exclude package from the generated dependencies.
  --admindir=<directory>   change the administrative directory.
  -h, --help               show this help message.
      --version            show the version.

Dependency fields recognised are:
  %s
"), $progname, join("/",@depfields);
}

sub add_shlibs_dep {
    my ($soname, $pkg) = @_;
    print "Looking up shlibs dependency of $soname provided by '$pkg'\n" if $debug;
    foreach my $file ($shlibslocal, $shlibsoverride, @pkg_shlibs,
			"$admindir/info/$pkg.shlibs",
			$shlibsdefault)
    {
	next if not -e $file;
	my $dep = extract_from_shlibs($soname, $file);
	if (defined($dep)) {
	    print "Found $dep in $file\n" if $debug;
	    foreach (split(/,\s*/, $dep)) {
		$dependencies{$cur_field}{$_} = 1;
	    }
	    return 1;
	}
    }
    print "Found nothing\n" if $debug;
    return 0;
}

sub extract_from_shlibs {
    my ($soname, $shlibfile) = @_;
    my ($libname, $libversion);
    # Split soname in name/version
    if ($soname =~ /^(.*)\.so\.(.*)$/) {
	$libname = $1; $libversion = $2;
    } elsif ($soname =~ /^(.*)-(.*)\.so$/) {
	$libname = $1; $libversion = $2;
    } else {
	warning(_g("Can't extract name and version from library name \`%s'"),
	        $soname);
	return;
    }
    # Open shlibs file
    $shlibfile = "./$shlibfile" if $shlibfile =~ m/^\s/;
    open(SHLIBS, "<", $shlibfile) ||
        syserr(_g("unable to open shared libs info file \`%s'"), $shlibfile);
    my $dep;
    while (<SHLIBS>) {
	s/\s*\n$//;
	next if m/^\#/;
	if (!m/^\s*(?:(\S+):\s+)?(\S+)\s+(\S+)(?:\s+(\S.*\S))?\s*$/) {
	    warning(_g("shared libs info file \`%s' line %d: bad line \`%s'"),
	            $shlibfile, $., $_);
	    next;
	}
	my $depread = defined($4) ? $4 : '';
	if (($libname eq $2) && ($libversion eq $3)) {
	    # Define dep and end here if the package type explicitely
	    # matches. Otherwise if the packagetype is not specified, use
	    # the dep only as a default that can be overriden by a later
	    # line
	    if (defined($1)) {
		if ($1 eq $packagetype) {
		    $dep = $depread;
		    last;
		}
	    } else {
		$dep = $depread unless defined $dep;
	    }
	}
    }
    close(SHLIBS);
    return $dep;
}

sub find_symbols_file {
    my ($pkg, $soname) = @_;
    foreach my $file (@pkg_symbols,
	"/etc/dpkg/symbols/$pkg.symbols.$host_arch",
	"/etc/dpkg/symbols/$pkg.symbols",
	"$admindir/info/$pkg.symbols")
    {
	if (-e $file and symfile_has_soname($file, $soname)) {
	    return $file;
	}
    }
    return undef;
}

sub symfile_has_soname {
    my ($file, $soname) = @_;
    open(SYM_FILE, "<", $file) ||
        syserr(_g("cannot open file %s"), $file);
    my $result = 0;
    while (<SYM_FILE>) {
	if (/^\Q$soname\E /) {
	    $result = 1;
	    last;
	}
    }
    close(SYM_FILE);
    return $result;
}

# find_library ($soname, \@rpath, $format)
sub my_find_library {
    my ($lib, $rpath, $format, $execfile) = @_;
    my $file;

    # Create real RPATH in case $ORIGIN is used
    # Note: ld.so also supports $PLATFORM and $LIB but they are
    # used in real case (yet)
    my $libdir = relative_to_pkg_root($execfile);
    my $origin;
    if (defined $libdir) {
	$origin = "/$libdir";
	$origin =~ s{/+[^/]*$}{};
    }
    my @RPATH = ();
    foreach my $path (@{$rpath}) {
	if ($path =~ /\$ORIGIN|\$\{ORIGIN\}/) {
	    if (defined $origin) {
		$path =~ s/\$ORIGIN/$origin/g;
		$path =~ s/\$\{ORIGIN\}/$origin/g;
	    } else {
		warning(_g("\$ORIGIN is used in RPATH of %s and the corresponding " .
		"directory could not be identified due to lack of DEBIAN " .
		"sub-directory in the root of package's build tree"), $execfile);
	    }
	}
	push @RPATH, $path;
    }

    # Look into the packages we're currently building (but only those
    # that provides shlibs file...)
    # TODO: we should probably replace that by a cleaner way to look into
    # the various temporary build directories...
    my @copy = (@pkg_shlibs);
    foreach my $builddir (map { s{/DEBIAN/shlibs$}{}; $_ } @copy) {
	$file = find_library($lib, \@RPATH, $format, $builddir);
	return $file if defined($file);
    }

    # Fallback in the root directory if we have not found what we were
    # looking for in the packages
    $file = find_library($lib, \@RPATH, $format, "");
    return $file if defined($file);

    return undef;
}

sub find_packages {
    my @files = (@_);
    my $pkgmatch = {};
    my $pid = open(DPKG, "-|");
    syserr(_g("cannot fork for dpkg --search")) unless defined($pid);
    if (!$pid) {
	# Child process running dpkg --search and discarding errors
	close STDERR;
	open STDERR, ">", "/dev/null";
	$ENV{LC_ALL} = "C";
	exec("dpkg", "--search", "--", @files)
	    || syserr(_g("cannot exec dpkg"));
    }
    while(defined($_ = <DPKG>)) {
	chomp($_);
	if (m/^local diversion |^diversion by/) {
	    warning(_g("diversions involved - output may be incorrect"));
	    print(STDERR " $_\n")
		|| syserr(_g("write diversion info to stderr"));
	} elsif (m/^([^:]+): (\S+)$/) {
	    $pkgmatch->{$2} = [ split(/, /, $1) ];
	} else {
	    warning(_g("unknown output from dpkg --search: '%s'"), $_);
	}
    }
    close(DPKG);
    return $pkgmatch;
}

