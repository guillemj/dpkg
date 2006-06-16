#!/usr/bin/perl

$dpkglibdir= "."; # This line modified by Makefile
$version= '1.3.0'; # This line modified by Makefile

$controlfile= 'debian/control';
$changelogfile= 'debian/changelog';
$fileslistfile= 'debian/files';
$varlistfile= 'debian/substvars';
$uploadfilesdir= '..';
$sourcestyle= 'i';
$quiet= 0;

# Other global variables used:
# %f2p             - file to package map
# %p2f             - package to file map
#                    has entries for both "packagename" and "packagename architecture"
# %p2ver           - package to version map
# %f2sec           - file to section map
# %f2pri           - file to priority map
# %sourcedefault   - default values as taken from source (used for Section,
#                    Priority and Maintainer)
# $changedby       - person who created this package (as listed in changelog)

use POSIX;
use POSIX qw(:errno_h :signal_h);

push(@INC,$dpkglibdir);
require 'controllib.pl';

require 'dpkg-gettext.pl';
textdomain("dpkg-dev");

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
  -S                       source-only upload.
  -c<controlfile>          get control info from this file.
  -l<changelogfile>        get per-version info from this file.
  -f<fileslistfile>        get .deb files list from this file.
  -v<sinceversion>         include all changes later than version.
  -C<changesdescription>   use change description from this file.
  -m<maintainer>           override control's maintainer value.
  -e<maintainer>           override changelog's maintainer value.
  -u<uploadfilesdir>       directory with files (default is \`..').
  -si (default)            src includes orig for debian-revision 0 or 1.
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

$i=100;grep($fieldimps{$_}=$i--,
          qw(Format Date Source Binary Architecture Version
             Distribution Urgency Maintainer Changed-By Description 
	     Closes Changes Files));

while (@ARGV) {
    $_=shift(@ARGV);
    if (m/^-b$/) {
	$sourceonly && &usageerr(_g("cannot combine -b or -B and -S"));
        $binaryonly= 1;
    } elsif (m/^-B$/) {
	$sourceonly && &usageerr(_g("cannot combine -b or -B and -S"));
	$archspecific=1;
	$binaryonly= 1;
	printf STDERR _g("%s: arch-specific upload - not including arch-independent packages")."\n", $progname;
    } elsif (m/^-S$/) {
	$binaryonly && &usageerr(_g("cannot combine -b or -B and -S"));
	$sourceonly= 1;
    } elsif (m/^-s([iad])$/) {
        $sourcestyle= $1;
    } elsif (m/^-q$/) {
        $quiet= 1;
    } elsif (m/^-c/) {
        $controlfile= $';
    } elsif (m/^-l/) {
        $changelogfile= $';
    } elsif (m/^-C/) {
        $changesdescription= $';
    } elsif (m/^-f/) {
        $fileslistfile= $';
    } elsif (m/^-v/) {
        $since= $';
    } elsif (m/^-T/) {
        $varlistfile= $';
    } elsif (m/^-m/) {
        $forcemaint= $';
    } elsif (m/^-e/) {
        $forcechangedby= $';
    } elsif (m/^-F([0-9a-z]+)$/) {
        $changelogformat=$1;
    } elsif (m/^-D([^\=:]+)[=:]/) {
        $override{$1}= $';
    } elsif (m/^-u/) {
        $uploadfilesdir= $';
    } elsif (m/^-U([^\=:]+)$/) {
        $remove{$1}= 1;
    } elsif (m/^-V(\w[-:0-9A-Za-z]*)[=:]/) {
        $substvar{$1}= $';
    } elsif (m/^-(h|-help)$/) {
        &usage; exit(0);
    } elsif (m/^--version$/) {
        &version; exit(0);
    } else {
        &usageerr(sprintf(_g("unknown option \`%s'"), $_));
    }
}

&findarch;
&parsechangelog;
&parsecontrolfile;

if (not $sourceonly) {
    $fileslistfile="./$fileslistfile" if $fileslistfile =~ m/^\s/;
    open(FL,"< $fileslistfile") || &syserr(_g("cannot read files list file"));
    while(<FL>) {
	if (m/^(([-+.0-9a-z]+)_([^_]+)_([-\w]+)\.u?deb) (\S+) (\S+)$/) {
	    defined($p2f{"$2 $4"}) &&
		&warn(sprintf(_g("duplicate files list entry for package %s (line %d)"), $2, $.));
	    $f2p{$1}= $2;
	    $p2f{"$2 $4"}= $1;
	    $p2f{$2}= $1;
	    $p2ver{$2}= $3;
	    defined($f2sec{$1}) &&
		&warn(sprintf(_g("duplicate files list entry for file %s (line %d)"), $1, $.));
	    $f2sec{$1}= $5;
	    $f2pri{$1}= $6;
	    push(@fileslistfiles,$1);
	} elsif (m/^([-+.0-9a-z]+_[^_]+_([-\w]+)\.[a-z0-9.]+) (\S+) (\S+)$/) {
	    # A non-deb package
	    $f2sec{$1}= $3;
	    $f2pri{$1}= $4;
	    push(@archvalues,$2) unless !$2 || $archadded{$2}++;
	    push(@fileslistfiles,$1);
	} elsif (m/^([-+.,_0-9a-zA-Z]+) (\S+) (\S+)$/) {
	    defined($f2sec{$1}) &&
		&warn(sprintf(_g("duplicate files list entry for file %s (line %d)"), $1, $.));
	    $f2sec{$1}= $2;
	    $f2pri{$1}= $3;
	    push(@fileslistfiles,$1);
	} else {
	    &error(sprintf(_g("badly formed line in files list file, line %d"), $.));
	}
    }
    close(FL);
}

for $_ (keys %fi) {
    $v= $fi{$_};
    if (s/^C //) {
	if (m/^Source$/) { &setsourcepackage; }
	elsif (m/^Section$|^Priority$/i) { $sourcedefault{$_}= $v; }
	elsif (m/^Maintainer$/i) { $f{$_}= $v; }
	elsif (s/^X[BS]*C[BS]*-//i) { $f{$_}= $v; }
	elsif (m/|^X[BS]+-|^Standards-Version$/i) { }
	else { &unknown(_g('general section of control info file')); }
    } elsif (s/^C(\d+) //) {
	$i=$1; $p=$fi{"C$i Package"}; $a=$fi{"C$i Architecture"};
	if (!defined($p2f{$p}) && not $sourceonly) {
	    if ((debian_arch_eq('all', $a) && !$archspecific) ||
		debian_arch_is($arch, $a) ||
		grep(debian_arch_is($arch, $_), split(/\s+/, $a))) {
		&warn(sprintf(_g("package %s in control file but not in files list"), $p));
		next;
	    }
	} else {
	    $p2arch{$p}=$a;
	    $f=$p2f{$p};
	    if (m/^Description$/) {
		$v=$` if $v =~ m/\n/;
		if ($f =~ m/\.udeb$/) {
			push(@descriptions,sprintf("%-10s - %-.65s (udeb)",$p,$v));
		} else {
			push(@descriptions,sprintf("%-10s - %-.65s",$p,$v));
		}
	    } elsif (m/^Section$/) {
		$f2seccf{$f}= $v;
	    } elsif (m/^Priority$/) {
		$f2pricf{$f}= $v;
	    } elsif (s/^X[BS]*C[BS]*-//i) {
		$f{$_}= $v;
	    } elsif (m/^Architecture$/) {
		if (not $sourceonly) {
		    if (debian_arch_is($arch, $v) ||
			grep(debian_arch_is($arch, $_), split(/\s+/, $v))) {
			$v= $arch;
		    } elsif (!debian_arch_eq('all', $v)) {
			$v= '';
		    }
		} else {
		    $v = '';
		}
		push(@archvalues,$v) unless !$v || $archadded{$v}++;
	    } elsif (m/^(Package|Essential|Pre-Depends|Depends|Provides)$/ ||
		     m/^(Recommends|Suggests|Enhances|Optional|Conflicts|Replaces)$/ ||
		     m/^X[CS]+-/i) {
	    } else {
		&unknown(_g("package's section of control info file"));
	    }
	}
    } elsif (s/^L //) {
        if (m/^Source$/i) {
            &setsourcepackage;
        } elsif (m/^Maintainer$/i) {
	    $f{"Changed-By"}=$v;
        } elsif (m/^(Version|Changes|Urgency|Distribution|Date|Closes)$/i) {
            $f{$_}= $v;
        } elsif (s/^X[BS]*C[BS]*-//i) {
            $f{$_}= $v;
        } elsif (!m/^X[BS]+-/i) {
            &unknown(_g("parsed version of changelog"));
        }
    } elsif (m/^o:.*/) {
    } else {
        &internerr(sprintf(_g("value from nowhere, with key >%s< and value >%s<"), $_, $v));
    }
}

if ($changesdescription) {
    $changesdescription="./$changesdescription" if $changesdescription =~ m/^\s/;
    $f{'Changes'}= '';
    open(X,"< $changesdescription") || &syserr(_g("read changesdescription"));
    while(<X>) {
        s/\s*\n$//;
        $_= '.' unless m/\S/;
        $f{'Changes'}.= "\n $_";
    }
}

for $p (keys %p2f) {
    my ($pp, $aa) = (split / /, $p);
    defined($p2i{"C $pp"}) ||
        &warn(sprintf(_g("package %s listed in files list but not in control info"), $pp));
}

for $p (keys %p2f) {
    $f= $p2f{$p};
    $sec= $f2seccf{$f}; $sec= $sourcedefault{'Section'} if !length($sec);
    if (!length($sec)) { $sec='-'; &warn(sprintf(_g("missing Section for binary package %s; using '-'"), $p)); }
    $sec eq $f2sec{$f} || &error(sprintf(_g("package %s has section %s in ".
                                           "control file but %s in files list"),
                                 $p, $sec, $f2sec{$f}));
    $pri= $f2pricf{$f}; $pri= $sourcedefault{'Priority'} if !length($pri);
    if (!length($pri)) { $pri='-'; &warn("missing Priority for binary package $p; using '-'"); }
    $pri eq $f2pri{$f} || &error(sprintf(_g("package %s has priority %s in ".
                                           "control file but %s in files list"),
                                 $p, $pri, $f2pri{$f}));
}

&init_substvars;

if (!$binaryonly) {
    $sec= $sourcedefault{'Section'};
    if (!length($sec)) { $sec='-'; &warn(_g("missing Section for source files")); }
    $pri= $sourcedefault{'Priority'};
    if (!length($pri)) { $pri='-'; &warn(_g("missing Priority for source files")); }

    ($sversion = $substvar{'source:Version'}) =~ s/^\d+://;
    $dsc= "$uploadfilesdir/${sourcepackage}_${sversion}.dsc";
    open(CDATA,"< $dsc") || &error(sprintf(_g("cannot open .dsc file %s: %s"), $dsc, $!));
    push(@sourcefiles,"${sourcepackage}_${sversion}.dsc");
    
    &parsecdata('S',-1,"source control file $dsc");
    $files= $fi{'S Files'};
    for $file (split(/\n /,$files)) {
        next if $file eq '';
        $file =~ m/^([0-9a-f]{32})[ \t]+\d+[ \t]+([0-9a-zA-Z][-+:.,=0-9a-zA-Z_~]+)$/
            || &error(sprintf(_g("Files field contains bad line \`%s'"), $file));
        ($md5sum{$2},$file) = ($1,$2);
        push(@sourcefiles,$file);
    }
    for $f (@sourcefiles) { $f2sec{$f}= $sec; $f2pri{$f}= $pri; }
    
    if (($sourcestyle =~ m/i/ && $sversion !~ m/-(0|1|0\.1)$/ ||
         $sourcestyle =~ m/d/) &&
        grep(m/\.diff\.gz$/,@sourcefiles)) {
        $origsrcmsg= _g("not including original source code in upload");
        @sourcefiles= grep(!m/\.orig\.tar\.gz$/,@sourcefiles);
    } else {
	if ($sourcestyle =~ m/d/ && !grep(m/\.diff\.gz$/,@sourcefiles)) {
	    &warn(_g("Ignoring -sd option for native Debian package"));
	}
        $origsrcmsg= _g("including full source code in upload");
    }
} else {
    $origsrcmsg= _g("binary-only upload - not including any source code");
}

print(STDERR "$progname: $origsrcmsg\n") ||
    &syserr(_g("write original source message")) unless $quiet;

$f{'Format'}= $substvar{'Format'};

if (!length($f{'Date'})) {
    chop($date822=`date -R`); $? && subprocerr("date -R");
    $f{'Date'}= $date822;
}

$f{'Binary'}= join(' ',grep(s/C //,keys %p2i));

unshift(@archvalues,'source') unless $binaryonly;
$f{'Architecture'}= join(' ',@archvalues);

$f{'Description'}= "\n ".join("\n ",sort @descriptions);

$f{'Files'}= '';
for $f (@sourcefiles,@fileslistfiles) {
    next if ($archspecific && debian_arch_eq('all', $p2arch{$f2p{$f}}));
    next if $filedone{$f}++;
    $uf= "$uploadfilesdir/$f";
    open(STDIN,"< $uf") || &syserr(sprintf(_g("cannot open upload file %s for reading"), $uf));
    (@s=stat(STDIN)) || &syserr(sprintf(_g("cannot fstat upload file %s"), $uf));
    $size= $s[7]; $size || &warn(sprintf(_g("upload file %s is empty"), $uf));
    $md5sum=`md5sum`; $? && subprocerr(sprintf(_g("md5sum upload file %s"), $uf));
    $md5sum =~ m/^([0-9a-f]{32})\s*-?\s*$/i ||
        &failure(sprintf(_g("md5sum upload file %s gave strange output \`%s'"), $uf, $md5sum));
    $md5sum= $1;
    defined($md5sum{$f}) && $md5sum{$f} ne $md5sum &&
        &error(sprintf(_g("md5sum of source file %s (%s) is different ".
                          "from md5sum in %s (%s)"),
                       $uf, $md5sum, $dsc, $md5sum{$f}));
    $f{'Files'}.= "\n $md5sum $size $f2sec{$f} $f2pri{$f} $f";
}    

$f{'Source'}= $sourcepackage;
if ($f{'Version'} ne $substvar{'source:Version'}) {
    $f{'Source'} .= " ($substvar{'source:Version'})";
}

$f{'Maintainer'}= $forcemaint if length($forcemaint);
$f{'Changed-By'}= $forcechangedby if length($forcechangedby);

for $f (qw(Version Distribution Maintainer Changes)) {
    defined($f{$f}) || &error(sprintf(_g("missing information for critical output field %s"), $f));
}

for $f (qw(Urgency)) {
    defined($f{$f}) || &warn(sprintf(_g("missing information for output field %s"), $f));
}

for $f (keys %override) { $f{&capit($f)}= $override{$f}; }
for $f (keys %remove) { delete $f{&capit($f)}; }

&outputclose(0);
