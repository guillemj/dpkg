#!/usr/bin/perl

use strict;
use warnings;

use POSIX;
use POSIX qw(:errno_h);
use Dpkg;
use Dpkg::Gettext;
use Dpkg::ErrorHandling qw(warning error failure unknown internerr syserr
                           subprocerr usageerr);
use Dpkg::Arch qw(get_host_arch debarch_eq debarch_is);
use Dpkg::Deps qw(@pkg_dep_fields %dep_field_type);
use Dpkg::Fields qw(capit set_field_importance);

push(@INC,$dpkglibdir);
require 'controllib.pl';

our %substvar;
our (%f, %fi);
our %p2i;
our $sourcepackage;

textdomain("dpkg-dev");

my @control_fields = (qw(Package Package-Type Source Version Kernel-Version
                         Architecture Subarchitecture Installer-Menu-Item
                         Essential Origin Bugs Maintainer Installed-Size),
                      @pkg_dep_fields,
                      qw(Section Priority Homepage Description Tag));

my $controlfile = 'debian/control';
my $changelogfile = 'debian/changelog';
my $changelogformat;
my $fileslistfile = 'debian/files';
my $varlistfile = 'debian/substvars';
my $packagebuilddir = 'debian/tmp';

my $sourceversion;
my $forceversion;
my $forcefilename;
my $stdout;
my %remove;
my %override;
my (%spvalue, %spdefault);
my $oppackage;
my $package_type = 'deb';


sub version {
    printf _g("Debian %s version %s.\n"), $progname, $version;

    printf _g("
Copyright (C) 1996 Ian Jackson.
Copyright (C) 2000,2002 Wichert Akkerman.");

    printf _g("
This is free software; see the GNU General Public Licence version 2 or
later for copying conditions. There is NO warranty.
");
}

sub usage {
    printf _g(
"Usage: %s [<option> ...]

Options:
  -p<package>              print control file for package.
  -c<controlfile>          get control info from this file.
  -l<changelogfile>        get per-version info from this file.
  -F<changelogformat>      force change log format.
  -v<forceversion>         set version of binary package.
  -f<fileslistfile>        write files here instead of debian/files.
  -P<packagebuilddir>      temporary build dir instead of debian/tmp.
  -n<filename>             assume the package filename will be <filename>.
  -O                       write to stdout, not .../DEBIAN/control.
  -is, -ip, -isp, -ips     deprecated, ignored for compatibility.
  -D<field>=<value>        override or add a field and value.
  -U<field>                remove a field.
  -V<name>=<value>         set a substitution variable.
  -T<varlistfile>          read variables here, not debian/substvars.
  -h, --help               show this help message.
      --version            show the version.
"), $progname;
}


while (@ARGV) {
    $_=shift(@ARGV);
    if (m/^-p([-+0-9a-z.]+)$/) {
        $oppackage= $1;
    } elsif (m/^-p(.*)/) {
        error(_g("Illegal package name \`%s'"), $1);
    } elsif (m/^-c/) {
        $controlfile= $';
    } elsif (m/^-l/) {
        $changelogfile= $';
    } elsif (m/^-P/) {
        $packagebuilddir= $';
    } elsif (m/^-f/) {
        $fileslistfile= $';
    } elsif (m/^-v(.+)$/) {
        $forceversion= $1;
    } elsif (m/^-O$/) {
        $stdout= 1;
    } elsif (m/^-i[sp][sp]?$/) {
	# ignored for backwards compatibility
    } elsif (m/^-F([0-9a-z]+)$/) {
        $changelogformat=$1;
    } elsif (m/^-D([^\=:]+)[=:]/) {
        $override{$1}= $';
    } elsif (m/^-U([^\=:]+)$/) {
        $remove{$1}= 1;
    } elsif (m/^-V(\w[-:0-9A-Za-z]*)[=:]/) {
        $substvar{$1}= $';
    } elsif (m/^-T/) {
        $varlistfile= $';
    } elsif (m/^-n/) {
        $forcefilename= $';
    } elsif (m/^-(h|-help)$/) {
        &usage; exit(0);
    } elsif (m/^--version$/) {
        &version; exit(0);
    } else {
        usageerr(_g("unknown option \`%s'"), $_);
    }
}

parsechangelog($changelogfile, $changelogformat);
parsesubstvars($varlistfile);
parsecontrolfile($controlfile);

my $myindex;

if (defined($oppackage)) {
    defined($p2i{"C $oppackage"}) ||
        error(_g("package %s not in control info"), $oppackage);
    $myindex= $p2i{"C $oppackage"};
} else {
    my @packages = grep(m/^C /, keys %p2i);
    @packages==1 ||
        error(_g("must specify package since control info has many (%s)"),
              "@packages");
    $myindex=1;
}

#print STDERR "myindex $myindex\n";

my %pkg_dep_fields = map { $_ => 1 } @pkg_dep_fields;

for $_ (keys %fi) {
    my $v = $fi{$_};

    if (s/^C //) {
#print STDERR "G key >$_< value >$v<\n";
	if (m/^(Origin|Bugs|Maintainer)$/) {
	    $f{$_} = $v;
	} elsif (m/^Homepage$/) {
	    # Binary package stanzas can override these fields
	    $f{$_} = $v if !defined($f{$_});
	} elsif (m/^Source$/) {
	    setsourcepackage($v);
	}
        elsif (s/^X[CS]*B[CS]*-//i) { $f{$_}= $v; }
	elsif (m/^X[CS]+-/i ||
	       m/^Build-(Depends|Conflicts)(-Indep)?$/i ||
	       m/^(Standards-Version|Uploaders)$/i ||
	       m/^Vcs-(Browser|Arch|Bzr|Cvs|Darcs|Git|Hg|Mtn|Svn)$/i) {
	}
	elsif (m/^Section$|^Priority$/) { $spdefault{$_}= $v; }
        else { $_ = "C $_"; &unknown(_g('general section of control info file')); }
    } elsif (s/^C$myindex //) {
#print STDERR "P key >$_< value >$v<\n";
        if (m/^(Package|Package-Type|Description|Homepage|Tag|Essential)$/ ||
            m/^(Subarchitecture|Kernel-Version|Installer-Menu-Item)$/) {
            $f{$_}= $v;
        } elsif (exists($pkg_dep_fields{$_})) {
	    # Delay the parsing until later
        } elsif (m/^Section$|^Priority$/) {
            $spvalue{$_}= $v;
        } elsif (m/^Architecture$/) {
	    my $host_arch = get_host_arch();

            if (debarch_eq('all', $v)) {
                $f{$_}= $v;
            } else {
		my @archlist = split(/\s+/, $v);
		my @invalid_archs = grep m/[^\w-]/, @archlist;
		warning(ngettext("`%s' is not a legal architecture string.",
		                 "`%s' are not legal architecture strings.",
		                 scalar(@invalid_archs)),
		        join("' `", @invalid_archs))
		    if @invalid_archs >= 1;
		grep(debarch_is($host_arch, $_), @archlist) ||
		    error(_g("current host architecture '%s' does not " .
		             "appear in package's architecture list (%s)"),
		          $host_arch, "@archlist");
		$f{$_} = $host_arch;
            }
        } elsif (s/^X[CS]*B[CS]*-//i) {
            $f{$_}= $v;
        } elsif (!m/^X[CS]+-/i) {
            $_ = "C$myindex $_"; &unknown(_g("package's section of control info file"));
        }
    } elsif (m/^C\d+ /) {
#print STDERR "X key >$_< value not shown<\n";
    } elsif (s/^L //) {
#print STDERR "L key >$_< value >$v<\n";
        if (m/^Source$/) {
	    setsourcepackage($v);
        } elsif (m/^Version$/) {
            $sourceversion= $v;
	    $f{$_} = $v unless defined($forceversion);
        } elsif (m/^(Maintainer|Changes|Urgency|Distribution|Date|Closes)$/) {
        } elsif (s/^X[CS]*B[CS]*-//i) {
            $f{$_}= $v;
        } elsif (!m/^X[CS]+-/i) {
            $_ = "L $_"; &unknown(_g("parsed version of changelog"));
        }
    } elsif (m/o:/) {
    } else {
        internerr(_g("value from nowhere, with key >%s< and value >%s<"), $_, $v);
    }
}

$f{'Version'} = $forceversion if defined($forceversion);

&init_substvars;
init_substvar_arch();

# Process dependency fields in a second pass, now that substvars have been
# initialized.

my $facts = Dpkg::Deps::KnownFacts->new();
$facts->add_installed_package($f{'Package'}, $f{'Version'});
if (exists $fi{"C$myindex Provides"}) {
    my $provides = Dpkg::Deps::parse(substvars($fi{"C$myindex Provides"}),
                                     reduce_arch => 1, union => 1);
    if (defined $provides) {
	foreach my $subdep ($provides->get_deps()) {
	    if ($subdep->isa('Dpkg::Deps::Simple')) {
		$facts->add_provided_package($subdep->{package},
                        $subdep->{relation}, $subdep->{version},
                        $f{'Package'});
	    }
	}
    }
}

my (@seen_deps);
foreach my $field (@pkg_dep_fields) {
    my $key = "C$myindex $field";
    if (exists $fi{$key}) {
	my $dep;
	my $field_value = substvars($fi{$key});
	if ($dep_field_type{$field} eq 'normal') {
	    $dep = Dpkg::Deps::parse($field_value, use_arch => 1,
                                     reduce_arch => 1);
	    error(_g("error occurred while parsing %s"), $field_value) unless defined $dep;
	    $dep->simplify_deps($facts, @seen_deps);
	    # Remember normal deps to simplify even further weaker deps
	    push @seen_deps, $dep if $dep_field_type{$field} eq 'normal';
	} else {
	    $dep = Dpkg::Deps::parse($field_value, use_arch => 1,
                                     reduce_arch => 1, union => 1);
	    error(_g("error occurred while parsing %s"), $field_value) unless defined $dep;
	    $dep->simplify_deps($facts);
	}
	$dep->sort();
	$f{$field} = $dep->dump();
	delete $f{$field} unless $f{$field}; # Delete empty field
    }
}


for my $f (qw(Section Priority)) {
    $spvalue{$f} = $spdefault{$f} unless defined($spvalue{$f});
    $f{$f} = $spvalue{$f} if defined($spvalue{$f});
}

for my $f (qw(Package Version)) {
    defined($f{$f}) || error(_g("missing information for output field %s"), $f);
}
for my $f (qw(Maintainer Description Architecture)) {
    defined($f{$f}) || warning(_g("missing information for output field %s"), $f);
}
$oppackage= $f{'Package'};

$package_type = $f{'Package-Type'} if (defined($f{'Package-Type'}));

if ($package_type ne 'udeb') {
    for my $f (qw(Subarchitecture Kernel-Version Installer-Menu-Item)) {
        warning(_g("%s package with udeb specific field %s"), $package_type, $f)
            if defined($f{$f});
    }
}

my $verdiff = $f{'Version'} ne $substvar{'source:Version'} ||
              $f{'Version'} ne $sourceversion;
if ($oppackage ne $sourcepackage || $verdiff) {
    $f{'Source'}= $sourcepackage;
    $f{'Source'}.= " ($substvar{'source:Version'})" if $verdiff;
}

if (!defined($substvar{'Installed-Size'})) {
    defined(my $c = open(DU, "-|")) || syserr(_g("fork for du"));
    if (!$c) {
        chdir("$packagebuilddir") ||
            syserr(_g("chdir for du to \`%s'"), $packagebuilddir);
        exec("du","-k","-s",".") or &syserr(_g("exec du"));
    }
    my $duo = '';
    while (<DU>) {
	$duo .= $_;
    }
    close(DU);
    $? && subprocerr(_g("du in \`%s'"), $packagebuilddir);
    $duo =~ m/^(\d+)\s+\.$/ ||
        failure(_g("du gave unexpected output \`%s'"), $duo);
    $substvar{'Installed-Size'}= $1;
}
if (defined($substvar{'Extra-Size'})) {
    $substvar{'Installed-Size'} += $substvar{'Extra-Size'};
}
if (defined($substvar{'Installed-Size'})) {
    $f{'Installed-Size'}= $substvar{'Installed-Size'};
}

for my $f (keys %override) {
    $f{capit($f)} = $override{$f};
}
for my $f (keys %remove) {
    delete $f{capit($f)};
}

$fileslistfile="./$fileslistfile" if $fileslistfile =~ m/^\s/;
open(Y,"> $fileslistfile.new") || &syserr(_g("open new files list file"));
binmode(Y);
chown(getfowner(), "$fileslistfile.new") 
		|| &syserr(_g("chown new files list file"));
if (open(X,"< $fileslistfile")) {
    binmode(X);
    while (<X>) {
        chomp;
        next if m/^([-+0-9a-z.]+)_[^_]+_([\w-]+)\.(a-z+) /
                && ($1 eq $oppackage)
	        && ($3 eq $package_type)
	        && (debarch_eq($2, $f{'Architecture'})
		    || debarch_eq($2, 'all'));
        print(Y "$_\n") || &syserr(_g("copy old entry to new files list file"));
    }
    close(X) || &syserr(_g("close old files list file"));
} elsif ($! != ENOENT) {
    &syserr(_g("read old files list file"));
}
my $sversion = $f{'Version'};
$sversion =~ s/^\d+://;
$forcefilename = sprintf("%s_%s_%s.%s", $oppackage, $sversion, $f{'Architecture'},
			 $package_type)
	   unless ($forcefilename);
print(Y &substvars(sprintf("%s %s %s\n", $forcefilename, 
                           &spfileslistvalue('Section'), &spfileslistvalue('Priority'))))
    || &syserr(_g("write new entry to new files list file"));
close(Y) || &syserr(_g("close new files list file"));
rename("$fileslistfile.new",$fileslistfile) || &syserr(_g("install new files list file"));

my $cf;
if (!$stdout) {
    $cf= "$packagebuilddir/DEBIAN/control";
    $cf= "./$cf" if $cf =~ m/^\s/;
    open(STDOUT,"> $cf.new") ||
        syserr(_g("cannot open new output control file \`%s'"), "$cf.new");
    binmode(STDOUT);
}

set_field_importance(@control_fields);
outputclose($varlistfile);

if (!$stdout) {
    rename("$cf.new", "$cf") ||
        syserr(_g("cannot install output control file \`%s'"), $cf);
}

sub spfileslistvalue {
    my $r = $spvalue{$_[0]};
    $r = '-' if !defined($r);
    return $r;
}
