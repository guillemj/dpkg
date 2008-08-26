#!/usr/bin/perl

use strict;
use warnings;

use POSIX;
use POSIX qw(:errno_h :signal_h);
use English;
use Dpkg;
use Dpkg::Gettext;
use Dpkg::Checksums;
use Dpkg::ErrorHandling qw(warning error failure unknown internerr syserr
                           subprocerr usageerr);
use Dpkg::Arch qw(get_host_arch debarch_eq debarch_is);
use Dpkg::Fields qw(:list capit);
use Dpkg::Compression;
use Dpkg::Control;
use Dpkg::Cdata;
use Dpkg::Substvars;
use Dpkg::Vars;
use Dpkg::Changelog qw(parse_changelog);
use Dpkg::Version qw(parseversion compare_versions);

textdomain("dpkg-dev");

my @changes_fields = qw(Format Date Source Binary Architecture Version
                        Distribution Urgency Maintainer Changed-By
                        Description Closes Changes Checksums-Md5
                        Checksums-Sha1 Checksums-Sha256 Files);

my $controlfile = 'debian/control';
my $changelogfile = 'debian/changelog';
my $changelogformat;
my $fileslistfile = 'debian/files';
my $varlistfile = 'debian/substvars';
my $uploadfilesdir = '..';
my $sourcestyle = 'i';
my $quiet = 0;
my $host_arch = get_host_arch();
my $changes_format = "1.8";

my %f2p;           # - file to package map
my %p2f;           # - package to file map, has entries for "packagename"
my %pa2f;          # - likewise, has entries for "packagename architecture"
my %p2ver;         # - package to version map
my %p2arch;        # - package to arch map
my %f2sec;         # - file to section map
my %f2seccf;       # - likewise, from control file
my %f2pri;         # - file to priority map
my %f2pricf;       # - likewise, from control file
my %sourcedefault; # - default values as taken from source (used for Section,
                   #   Priority and Maintainer)

my @descriptions;
my @sourcefiles;
my @fileslistfiles;

my %checksum;      # - file to checksum map
my %size;          # - file to size map
my %remove;        # - fields to remove
my %override;
my %archadded;
my @archvalues;
my $dsc;
my $changesdescription;
my $forcemaint;
my $forcechangedby;
my $since;

my $substvars = Dpkg::Substvars->new();
$substvars->set("Format", $changes_format);

use constant SOURCE     => 1;
use constant ARCH_DEP   => 2;
use constant ARCH_INDEP => 4;
use constant BIN        => ARCH_DEP | ARCH_INDEP;
use constant ALL        => BIN | SOURCE;
my $include = ALL;

sub is_sourceonly() { return $include == SOURCE; }
sub is_binaryonly() { return !($include & SOURCE); }
sub binary_opt() { return (($include == BIN) ? '-b' :
			   (($include == ARCH_DEP) ? '-B' :
			    (($include == ARCH_INDEP) ? '-A' :
			     internerr("binary_opt called with include=$include"))));
}

sub version {
    printf _g("Debian %s version %s.\n"), $progname, $version;

    printf _g("
Copyright (C) 1996 Ian Jackson.
Copyright (C) 2000,2001 Wichert Akkerman.");

    printf _g("
This is free software; see the GNU General Public Licence version 2 or
later for copying conditions. There is NO warranty.
");
}

sub usage {
    printf _g(
"Usage: %s [<option> ...]

Options:
  -b                       binary-only build - no source files.
  -B                       arch-specific - no source or arch-indep files.
  -A                       only arch-indep - no source or arch-specific files.
  -S                       source-only upload.
  -c<controlfile>          get control info from this file.
  -l<changelogfile>        get per-version info from this file.
  -f<fileslistfile>        get .deb files list from this file.
  -v<sinceversion>         include all changes later than version.
  -C<changesdescription>   use change description from this file.
  -m<maintainer>           override control's maintainer value.
  -e<maintainer>           override changelog's maintainer value.
  -u<uploadfilesdir>       directory with files (default is \`..').
  -si (default)            src includes orig if new upstream.
  -sa                      source includes orig src.
  -sd                      source is diff and .dsc only.
  -q                       quiet - no informational messages on stderr.
  -F<changelogformat>      force change log format.
  -V<name>=<value>         set a substitution variable.
  -T<varlistfile>          read variables here, not debian/substvars.
  -D<field>=<value>        override or add a field and value.
  -U<field>                remove a field.
  -h, --help               show this help message.
      --version            show the version.
"), $progname;
}


while (@ARGV) {
    $_=shift(@ARGV);
    if (m/^-b$/) {
	is_sourceonly && &usageerr(_g("cannot combine %s and -S"), $_);
	$include = BIN;
    } elsif (m/^-B$/) {
	is_sourceonly && &usageerr(_g("cannot combine %s and -S"), $_);
	$include = ARCH_DEP;
	printf STDERR _g("%s: arch-specific upload - not including arch-independent packages")."\n", $progname;
    } elsif (m/^-A$/) {
	is_sourceonly && &usageerr(_g("cannot combine %s and -S"), $_);
	$include = ARCH_INDEP;
	printf STDERR _g("%s: arch-indep upload - not including arch-specific packages")."\n", $progname;
    } elsif (m/^-S$/) {
	is_binaryonly && &usageerr(_g("cannot combine %s and -S"), binary_opt);
	$include = SOURCE;
    } elsif (m/^-s([iad])$/) {
        $sourcestyle= $1;
    } elsif (m/^-q$/) {
        $quiet= 1;
    } elsif (m/^-c/) {
	$controlfile= $POSTMATCH;
    } elsif (m/^-l/) {
	$changelogfile= $POSTMATCH;
    } elsif (m/^-C/) {
	$changesdescription= $POSTMATCH;
    } elsif (m/^-f/) {
	$fileslistfile= $POSTMATCH;
    } elsif (m/^-v/) {
	$since= $POSTMATCH;
    } elsif (m/^-T/) {
	$varlistfile= $POSTMATCH;
	warning(_g("substvars support is deprecated (see README.feature-removal-schedule)"));
    } elsif (m/^-m/) {
	$forcemaint= $POSTMATCH;
    } elsif (m/^-e/) {
	$forcechangedby= $POSTMATCH;
    } elsif (m/^-F([0-9a-z]+)$/) {
        $changelogformat=$1;
    } elsif (m/^-D([^\=:]+)[=:]/) {
	$override{$1}= $POSTMATCH;
    } elsif (m/^-u/) {
	$uploadfilesdir= $POSTMATCH;
    } elsif (m/^-U([^\=:]+)$/) {
        $remove{$1}= 1;
    } elsif (m/^-V(\w[-:0-9A-Za-z]*)[=:]/) {
	$substvars->set($1, $POSTMATCH);
    } elsif (m/^-(h|-help)$/) {
        &usage; exit(0);
    } elsif (m/^--version$/) {
        &version; exit(0);
    } else {
        usageerr(_g("unknown option \`%s'"), $_);
    }
}

# Retrieve info from the current changelog entry
my %options = (file => $changelogfile);
$options{"changelogformat"} = $changelogformat if $changelogformat;
$options{"since"} = $since if $since;
my $changelog = parse_changelog(%options);
# Change options to retrieve info of the former changelog entry
delete $options{"since"};
$options{"count"} = 1;
$options{"offset"} = 1;
my ($prev_changelog, $bad_parser);
eval { # Do not fail if parser failed due to unsupported options
    $prev_changelog = parse_changelog(%options);
};
$bad_parser = 1 if ($@);
# Other initializations
my $control = Dpkg::Control->new($controlfile);
my $fields = Dpkg::Fields::Object->new();
$substvars->set_version_substvars($changelog->{"Version"});
$substvars->parse($varlistfile) if -e $varlistfile;

if (defined($prev_changelog) and
    compare_versions($changelog->{"Version"}, '<', $prev_changelog->{"Version"})) {
    warning(_g("the current version (%s) is smaller than the previous one (%s)"),
	$changelog->{"Version"}, $prev_changelog->{"Version"});
}

if (not is_sourceonly) {
    open(FL,"<",$fileslistfile) || &syserr(_g("cannot read files list file"));
    while(<FL>) {
	if (m/^(([-+.0-9a-z]+)_([^_]+)_([-\w]+)\.u?deb) (\S+) (\S+)$/) {
	    defined($p2f{"$2 $4"}) &&
		warning(_g("duplicate files list entry for package %s (line %d)"),
			$2, $NR);
	    $f2p{$1}= $2;
	    $pa2f{"$2 $4"}= $1;
	    $p2f{$2} ||= [];
	    push @{$p2f{$2}}, $1;
	    $p2ver{$2}= $3;
	    defined($f2sec{$1}) &&
		warning(_g("duplicate files list entry for file %s (line %d)"),
			$1, $NR);
	    $f2sec{$1}= $5;
	    $f2pri{$1}= $6;
	    push(@archvalues,$4) unless !$4 || $archadded{$4}++;
	    push(@fileslistfiles,$1);
	} elsif (m/^([-+.0-9a-z]+_[^_]+_([-\w]+)\.[a-z0-9.]+) (\S+) (\S+)$/) {
	    # A non-deb package
	    $f2sec{$1}= $3;
	    $f2pri{$1}= $4;
	    push(@archvalues,$2) unless !$2 || $archadded{$2}++;
	    push(@fileslistfiles,$1);
	} elsif (m/^([-+.,_0-9a-zA-Z]+) (\S+) (\S+)$/) {
	    defined($f2sec{$1}) &&
		warning(_g("duplicate files list entry for file %s (line %d)"),
			$1, $NR);
	    $f2sec{$1}= $2;
	    $f2pri{$1}= $3;
	    push(@fileslistfiles,$1);
	} else {
	    error(_g("badly formed line in files list file, line %d"), $NR);
	}
    }
    close(FL);
}

# Scan control info of source package
my $src_fields = $control->get_source();
foreach $_ (keys %{$src_fields}) {
    my $v = $src_fields->{$_};
    if (m/^Source$/) {
	set_source_package($v);
    } elsif (m/^Section$|^Priority$/i) {
	$sourcedefault{$_} = $v;
    } elsif (m/^Maintainer$/i) {
	$fields->{$_} = $v;
    } elsif (s/^X[BS]*C[BS]*-//i) { # Include XC-* fields
	$fields->{$_} = $v;
    } elsif (m/^X[BS]+-/i || m/^$control_src_field_regex$/i) {
	# Silently ignore valid fields
    } else {
	unknown(_g('general section of control info file'));
    }
}

# Scan control info of all binary packages
foreach my $pkg ($control->get_packages()) {
    my $p = $pkg->{"Package"};
    my $a = $pkg->{"Architecture"};
    my $d = $pkg->{"Description"} || "no description available";
    $d = $1 if $d =~ /^(.*)\n/;
    my $pkg_type = $pkg->{"Package-Type"} ||
                   tied(%$pkg)->get_custom_field("Package-Type") || "deb";

    my @f; # List of files for this binary package
    push @f, @{$p2f{$p}} if defined $p2f{$p};

    # Add description of all binary packages
    my $desc = sprintf("%-10s - %-.65s", $p, $d);
    $desc .= " (udeb)" if $pkg_type eq "udeb";
    push @descriptions, $desc;

    if (not defined($p2f{$p})) {
	# No files for this package... warn if it's unexpected
	if ((debarch_eq('all', $a) and ($include & ARCH_INDEP)) ||
	    (grep(debarch_is($host_arch, $_), split(/\s+/, $a))
		  and ($include & ARCH_DEP))) {
	    warning(_g("package %s in control file but not in files list"),
		    $p);
	}
	next; # and skip it
    }

    $p2arch{$p} = $a;

    foreach $_ (keys %{$pkg}) {
	my $v = $pkg->{$_};

	if (m/^Section$/) {
	    $f2seccf{$_} = $v foreach (@f);
	} elsif (m/^Priority$/) {
	    $f2pricf{$_} = $v foreach (@f);
	} elsif (s/^X[BS]*C[BS]*-//i) { # Include XC-* fields
	    $fields->{$_} = $v;
	} elsif (m/^Architecture$/) {
	    if (grep(debarch_is($host_arch, $_), split(/\s+/, $v))
		and ($include & ARCH_DEP)) {
		$v = $host_arch;
	    } elsif (!debarch_eq('all', $v)) {
		$v = '';
	    }
	    push(@archvalues,$v) unless !$v || $archadded{$v}++;
	} elsif (m/^$control_pkg_field_regex$/ || m/^X[BS]+-/i) {
	    # Silently ignore valid fields
	} else {
	    unknown(_g("package's section of control info file"));
	}
    }
}

# Scan fields of dpkg-parsechangelog
foreach $_ (keys %{$changelog}) {
    my $v = $changelog->{$_};
    if (m/^Source$/i) {
	set_source_package($v);
    } elsif (m/^Maintainer$/i) {
	$fields->{"Changed-By"} = $v;
    } elsif (m/^(Version|Changes|Urgency|Distribution|Date|Closes)$/i) {
	$fields->{$_} = $v;
    } elsif (s/^X[BS]*C[BS]*-//i) {
	$fields->{$_} = $v;
    } elsif (!m/^X[BS]+-/i) {
	unknown(_g("parsed version of changelog"));
    }
}

if ($changesdescription) {
    $fields->{'Changes'} = '';
    open(X,"<",$changesdescription) || &syserr(_g("read changesdescription"));
    while(<X>) {
        s/\s*\n$//;
        $_= '.' unless m/\S/;
        $fields->{'Changes'}.= "\n $_";
    }
}

for my $pa (keys %pa2f) {
    my ($pp, $aa) = (split / /, $pa);
    defined($control->get_pkg_by_name($pp)) ||
	warning(_g("package %s listed in files list but not in control info"),
	        $pp);
}

for my $p (keys %p2f) {
    my @f = @{$p2f{$p}};

    foreach my $f (@f) {
	my $sec = $f2seccf{$f};
	$sec ||= $sourcedefault{'Section'};
	if (!defined($sec)) {
	    $sec = '-';
	    warning(_g("missing Section for binary package %s; using '-'"), $p);
	}
	$sec eq $f2sec{$f} || error(_g("package %s has section %s in " .
				       "control file but %s in files list"),
				    $p, $sec, $f2sec{$f});
	my $pri = $f2pricf{$f};
	$pri ||= $sourcedefault{'Priority'};
	if (!defined($pri)) {
	    $pri = '-';
	    warning(_g("missing Priority for binary package %s; using '-'"), $p);
	}
	$pri eq $f2pri{$f} || error(_g("package %s has priority %s in " .
				       "control file but %s in files list"),
				    $p, $pri, $f2pri{$f});
    }
}

my $origsrcmsg;

if (!is_binaryonly) {
    my $sec = $sourcedefault{'Section'};
    if (!defined($sec)) {
	$sec = '-';
	warning(_g("missing Section for source files"));
    }
    my $pri = $sourcedefault{'Priority'};
    if (!defined($pri)) {
	$pri = '-';
	warning(_g("missing Priority for source files"));
    }

    (my $sversion = $substvars->get('source:Version')) =~ s/^\d+://;
    $dsc= "$uploadfilesdir/${sourcepackage}_${sversion}.dsc";
    open(CDATA, "<", $dsc) || syserr(_g("cannot open .dsc file %s"), $dsc);
    push(@sourcefiles,"${sourcepackage}_${sversion}.dsc");

    my $dsc_fields = parsecdata(\*CDATA, sprintf(_g("source control file %s"), $dsc),
				allow_pgp => 1);

    readallchecksums($dsc_fields, \%checksum, \%size);

    my $rx_fname = qr/[0-9a-zA-Z][-+:.,=0-9a-zA-Z_~]+/;
    my $files = $dsc_fields->{'Files'};
    for my $line (split(/\n /, $files)) {
	next if $line eq '';
	$line =~ m/^($check_regex{md5})[ \t]+(\d+)[ \t]+($rx_fname)$/
	    || error(_g("Files field contains bad line \`%s'"), $line);
	my ($md5sum,$size,$file) = ($1,$2,$3);
	if (exists($checksum{$file}{md5})
	    and $checksum{$file}{md5} ne $md5sum) {
	    error(_g("Conflicting checksums \`%s\' and \`%s' for file \`%s'"),
		  $checksum{$file}{md5}, $md5sum, $file);
	}
	if (exists($size{$file})
	    and $size{$file} != $size) {
	    error(_g("Conflicting sizes \`%u\' and \`%u' for file \`%s'"),
		  $size{$file}, $size, $file);
	}
	$checksum{$file}{md5} = $md5sum;
	$size{$file} = $size;
        push(@sourcefiles,$file);
    }
    for my $f (@sourcefiles) {
	$f2sec{$f} = $sec;
	$f2pri{$f} = $pri;
    }

    # Compare upstream version to previous upstream version to decide if
    # the .orig tarballs must be included
    my $include_tarball;
    if (defined($prev_changelog)) {
	my %cur = parseversion($changelog->{"Version"});
	my %prev = parseversion($prev_changelog->{"Version"});
	$include_tarball = ($cur{"version"} ne $prev{"version"}) ? 1 : 0;
    } else {
	if ($bad_parser) {
	    # The parser doesn't support extracting a previous version
	    # Fallback to version check
	    $include_tarball = ($sversion =~ /-(0|1|0\.1)$/) ? 1 : 0;
	} else {
	    # No previous entry means first upload, tarball required
	    $include_tarball = 1;
	}
    }

    if ((($sourcestyle =~ m/i/ && not($include_tarball)) ||
	 $sourcestyle =~ m/d/) &&
	grep(m/\.(debian\.tar|diff)\.$comp_regex$/,@sourcefiles)) {
	$origsrcmsg= _g("not including original source code in upload");
	@sourcefiles= grep(!m/\.orig\.tar\.$comp_regex$/,@sourcefiles);
    } else {
	if ($sourcestyle =~ m/d/ &&
	    !grep(m/\.(debian\.tar|diff)\.$comp_regex$/,@sourcefiles)) {
	    warning(_g("ignoring -sd option for native Debian package"));
	}
        $origsrcmsg= _g("including full source code in upload");
    }
} else {
    $origsrcmsg= _g("binary-only upload - not including any source code");
}

print(STDERR "$progname: $origsrcmsg\n") ||
    &syserr(_g("write original source message")) unless $quiet;

$fields->{'Format'} = $substvars->get("Format");

if (!defined($fields->{'Date'})) {
    chomp(my $date822 = `date -R`);
    $? && subprocerr("date -R");
    $fields->{'Date'}= $date822;
}

$fields->{'Binary'} = join(' ', map { $_->{'Package'} } $control->get_packages());

unshift(@archvalues,'source') unless is_binaryonly;
@archvalues = ('all') if $include == ARCH_INDEP;
@archvalues = grep {!debarch_eq('all',$_)} @archvalues
    unless $include & ARCH_INDEP;
$fields->{'Architecture'} = join(' ',@archvalues);

$fields->{'Description'} = "\n ".join("\n ",sort @descriptions);

$fields->{'Files'} = '';

my %filedone;

for my $f (@sourcefiles, @fileslistfiles) {
    next if ($include == ARCH_DEP and debarch_eq('all', $p2arch{$f2p{$f}}));
    next if ($include == ARCH_INDEP and not debarch_eq('all', $p2arch{$f2p{$f}}));
    next if $filedone{$f}++;
    my $uf = "$uploadfilesdir/$f";
    $checksum{$f} ||= {};
    getchecksums($uf, $checksum{$f}, \$size{$f});
    foreach my $alg (sort keys %{$checksum{$f}}) {
	$fields->{"Checksums-$alg"} .= "\n $checksum{$f}{$alg} $size{$f} $f";
    }
    $fields->{'Files'} .= "\n $checksum{$f}{md5} $size{$f} $f2sec{$f} $f2pri{$f} $f";
}

# redundant with the Files field
delete $fields->{"Checksums-Md5"};

$fields->{'Source'}= $sourcepackage;
if ($fields->{'Version'} ne $substvars->get('source:Version')) {
    $fields->{'Source'} .= " (" . $substvars->get('source:Version') . ")";
}

$fields->{'Maintainer'} = $forcemaint if defined($forcemaint);
$fields->{'Changed-By'} = $forcechangedby if defined($forcechangedby);

for my $f (qw(Version Distribution Maintainer Changes)) {
    defined($fields->{$f}) ||
        error(_g("missing information for critical output field %s"), $f);
}

for my $f (qw(Urgency)) {
    defined($fields->{$f}) ||
        warning(_g("missing information for output field %s"), $f);
}

for my $f (keys %override) {
    $fields->{$f} = $override{$f};
}
for my $f (keys %remove) {
    delete $fields->{$f};
}

tied(%{$fields})->set_field_importance(@changes_fields);
tied(%{$fields})->output(\*STDOUT); # Note: no substitution of variables

