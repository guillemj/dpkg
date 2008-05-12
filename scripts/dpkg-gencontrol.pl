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
use Dpkg::Fields qw(:list capit);
use Dpkg::Control;
use Dpkg::Substvars;
use Dpkg::Vars;
use Dpkg::Changelog qw(parse_changelog);

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
my $oppackage;
my $substvars = Dpkg::Substvars->new();


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
        $substvars->set($1, $');
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

my %options = (file => $changelogfile);
$options{"changelogformat"} = $changelogformat if $changelogformat;
my $changelog = parse_changelog(%options);
$substvars->set_version_substvars($changelog->{"Version"});
$substvars->parse($varlistfile) if -e $varlistfile;
$substvars->set("binary:Version", $forceversion) if defined $forceversion;
my $control = Dpkg::Control->new($controlfile);
my $fields = Dpkg::Fields::Object->new();

my $pkg;

if (defined($oppackage)) {
    $pkg = $control->get_pkg_by_name($oppackage);
    defined($pkg) || error(_g("package %s not in control info"), $oppackage);
} else {
    my @packages = map { $_->{'Package'} } $control->get_packages();
    @packages==1 ||
        error(_g("must specify package since control info has many (%s)"),
              "@packages");
    $pkg = $control->get_pkg_by_idx(1);
}

my %pkg_dep_fields = map { $_ => 1 } @pkg_dep_fields;

# Scan source package
my $src_fields = $control->get_source();
foreach $_ (keys %{$src_fields}) {
    my $v = $src_fields->{$_};
    if (m/^(Origin|Bugs|Maintainer|Section|Priority|Homepage)$/) {
	$fields->{$_} = $v;
    } elsif (m/^Source$/) {
	set_source_package($v);
    } elsif (s/^X[CS]*B[CS]*-//i) { # Include XB-* fields
	$fields->{$_} = $v;
    } elsif (m/^X[CS]+-/i || m/^$control_src_field_regex$/i) {
	# Silently ignore valid fields
    } else {
	unknown(_g('general section of control info file'));
    }
}

# Scan binary package
foreach $_ (keys %{$pkg}) {
    my $v = $pkg->{$_};
    if (exists($pkg_dep_fields{$_})) {
	# Delay the parsing until later
    } elsif (m/^Architecture$/) {
	my $host_arch = get_host_arch();

	if (debarch_eq('all', $v)) {
	    $fields->{$_} = $v;
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
	    $fields->{$_} = $host_arch;
	}
    } elsif (m/^$control_pkg_field_regex$/) {
	$fields->{$_} = $v;
    } elsif (s/^X[CS]*B[CS]*-//i) { # Include XB-* fields
	$fields->{$_} = $v;
    } elsif (!m/^X[CS]+-/i) {
	unknown(_g("package's section of control info file"));
    }
}

# Scan fields of dpkg-parsechangelog
foreach $_ (keys %{$changelog}) {
    my $v = $changelog->{$_};

    if (m/^Source$/) {
	set_source_package($v);
    } elsif (m/^Version$/) {
	$sourceversion = $v;
	$fields->{$_} = $v unless defined($forceversion);
    } elsif (m/^(Maintainer|Changes|Urgency|Distribution|Date|Closes)$/) {
    } elsif (s/^X[CS]*B[CS]*-//i) {
	$fields->{$_} = $v;
    } elsif (!m/^X[CS]+-/i) {
	unknown(_g("parsed version of changelog"));
    }
}

$fields->{'Version'} = $forceversion if defined($forceversion);

# Process dependency fields in a second pass, now that substvars have been
# initialized.

my $facts = Dpkg::Deps::KnownFacts->new();
$facts->add_installed_package($fields->{'Package'}, $fields->{'Version'});
if (exists $pkg->{"Provides"}) {
    my $provides = Dpkg::Deps::parse($substvars->substvars($pkg->{"Provides"}),
                                     reduce_arch => 1, union => 1);
    if (defined $provides) {
	foreach my $subdep ($provides->get_deps()) {
	    if ($subdep->isa('Dpkg::Deps::Simple')) {
		$facts->add_provided_package($subdep->{package},
                        $subdep->{relation}, $subdep->{version},
                        $fields->{'Package'});
	    }
	}
    }
}

my (@seen_deps);
foreach my $field (@pkg_dep_fields) {
    if (exists $pkg->{$field}) {
	my $dep;
	my $field_value = $substvars->substvars($pkg->{$field});
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
            $dep->sort();
	}
	$fields->{$field} = $dep->dump();
	delete $fields->{$field} unless $fields->{$field}; # Delete empty field
    }
}

for my $f (qw(Package Version)) {
    defined($fields->{$f}) || error(_g("missing information for output field %s"), $f);
}
for my $f (qw(Maintainer Description Architecture)) {
    defined($fields->{$f}) || warning(_g("missing information for output field %s"), $f);
}
$oppackage = $fields->{'Package'};

my $package_type = $pkg->{'Package-Type'} ||
                   tied(%$pkg)->get_custom_field('Package-Type') || 'deb';

if ($package_type eq 'udeb') {
    delete $fields->{'Homepage'};
} else {
    for my $f (qw(Subarchitecture Kernel-Version Installer-Menu-Item)) {
        warning(_g("%s package with udeb specific field %s"), $package_type, $f)
            if defined($fields->{$f});
    }
}

my $verdiff = $fields->{'Version'} ne $substvars->get('source:Version') ||
              $fields->{'Version'} ne $sourceversion;
if ($oppackage ne $sourcepackage || $verdiff) {
    $fields->{'Source'} = $sourcepackage;
    $fields->{'Source'} .= " (" . $substvars->get('source:Version') . ")" if $verdiff;
}

if (!defined($substvars->get('Installed-Size'))) {
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
    $substvars->set('Installed-Size', $1);
}
if (defined($substvars->get('Extra-Size'))) {
    my $size = $substvars->get('Extra-Size') + $substvars->get('Installed-Size');
    $substvars->set('Installed-Size', $size);
}
if (defined($substvars->get('Installed-Size'))) {
    $fields->{'Installed-Size'} = $substvars->get('Installed-Size');
}

for my $f (keys %override) {
    $fields->{$f} = $override{$f};
}
for my $f (keys %remove) {
    delete $fields->{$f};
}

$fileslistfile="./$fileslistfile" if $fileslistfile =~ m/^\s/;
open(Y, ">", "$fileslistfile.new") || &syserr(_g("open new files list file"));
binmode(Y);
if (open(X, "<", $fileslistfile)) {
    binmode(X);
    while (<X>) {
        chomp;
        next if m/^([-+0-9a-z.]+)_[^_]+_([\w-]+)\.(a-z+) /
                && ($1 eq $oppackage)
	        && ($3 eq $package_type)
	        && (debarch_eq($2, $fields->{'Architecture'})
		    || debarch_eq($2, 'all'));
        print(Y "$_\n") || &syserr(_g("copy old entry to new files list file"));
    }
    close(X) || &syserr(_g("close old files list file"));
} elsif ($! != ENOENT) {
    &syserr(_g("read old files list file"));
}
my $sversion = $fields->{'Version'};
$sversion =~ s/^\d+://;
$forcefilename = sprintf("%s_%s_%s.%s", $oppackage, $sversion, $fields->{'Architecture'},
			 $package_type)
	   unless ($forcefilename);
print(Y $substvars->substvars(sprintf("%s %s %s\n", $forcefilename,
				      $fields->{'Section'} || '-',
				      $fields->{'Priority'} || '-')))
    || &syserr(_g("write new entry to new files list file"));
close(Y) || &syserr(_g("close new files list file"));
rename("$fileslistfile.new",$fileslistfile) || &syserr(_g("install new files list file"));

my $cf;
my $fh_output;
if (!$stdout) {
    $cf= "$packagebuilddir/DEBIAN/control";
    $cf= "./$cf" if $cf =~ m/^\s/;
    open($fh_output, ">", "$cf.new") ||
        syserr(_g("cannot open new output control file \`%s'"), "$cf.new");
} else {
    $fh_output = \*STDOUT;
}

tied(%{$fields})->set_field_importance(@control_fields);
tied(%{$fields})->output($fh_output, $substvars);

if (!$stdout) {
    close($fh_output);
    rename("$cf.new", "$cf") ||
        syserr(_g("cannot install output control file \`%s'"), $cf);
}


