#!/usr/bin/perl

$dpkglibdir= "."; # This line modified by Makefile
$version= '1.3.0'; # This line modified by Makefile

$controlfile= 'debian/control';
$changelogfile= 'debian/changelog';
$fileslistfile= 'debian/files';
$varlistfile= 'debian/substvars';
$packagebuilddir= 'debian/tmp';

use POSIX;
use POSIX qw(:errno_h);

push(@INC,$dpkglibdir);
require 'controllib.pl';

sub usageversion {
    print STDERR
"Debian dpkg-gencontrol $version. 
Copyright 1996 Ian Jackson.
Copyright 2000,2002 Wichert Akkerman.
This is free software; see the GNU General Public Licence version 2 or later
for copying conditions.  There is NO warranty.

Usage: dpkg-gencontrol [options ...]

Options:  -p<package>            print control file for package
          -c<controlfile>        get control info from this file
          -l<changelogfile>      get per-version info from this file
          -F<changelogformat>    force change log format
          -v<forceversion>       set version of binary package
          -f<fileslistfile>      write files here instead of debian/files
          -P<packagebuilddir>    temporary build dir instead of debian/tmp
	  -n<filename>           assume the package filename will be <filename>
          -O                     write to stdout, not .../DEBIAN/control
          -is                    include section field
          -ip                    include priority field
          -isp|-ips              include both section and priority
          -D<field>=<value>      override or add a field and value
          -U<field>              remove a field
          -V<name>=<value>       set a substitution variable
          -T<varlistfile>        read variables here, not debian/substvars
          -h                     print this message
";
}

$i=100;grep($fieldimps{$_}=$i--,
          qw(Package Version Section Priority Architecture Essential
             Pre-Depends Depends Recommends Suggests Enhances Optional 
	     Conflicts Replaces Provides Installed-Size Origin Maintainer
	     Bugs Source Description Build-Depends Build-Depends-Indep
	     Build-Conflicts Build-Conflicts-Indep ));

while (@ARGV) {
    $_=shift(@ARGV);
    if (m/^-p([-+0-9a-z.]+)$/) {
        $oppackage= $1;
    } elsif (m/^-p/) {
        &usageerr("Illegal package name \`$1'");
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
    } elsif (m/^-is$/) {
        $spinclude{'Section'}=1;
    } elsif (m/^-ip$/) {
        $spinclude{'Priority'}=1;
    } elsif (m/^-isp$/ || m/^-ips$/) {
        $spinclude{'Section'}=1;
        $spinclude{'Priority'}=1;
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
    } elsif (m/^-h$/) {
        &usageversion; exit(0);
    } else {
        &usageerr("unknown option \`$_'");
    }
}

&findarch;
&parsechangelog;
&parsecontrolfile;
            
if (length($oppackage)) {
    defined($p2i{"C $oppackage"}) || &error("package $oppackage not in control info");
    $myindex= $p2i{"C $oppackage"};
} else {
    @packages= grep(m/^C /,keys %p2i);
    @packages==1 ||
        &error("must specify package since control info has many (@packages)");
    $myindex=1;
}

#print STDERR "myindex $myindex\n";

for $_ (keys %fi) {
    $v= $fi{$_};
    if (s/^C //) {
#print STDERR "G key >$_< value >$v<\n";
        if (m/^Origin|Bugs|Maintainer$/) { $f{$_}=$v; }
        elsif (m/^Source$/) { &setsourcepackage; }
        elsif (s/^X[CS]*B[CS]*-//i) { $f{$_}= $v; }
	elsif (m/^X[CS]+-|^(Standards-Version|Uploaders)$|^Build-(Depends|Conflicts)(-Indep)?$/i) { }
	elsif (m/^Section$|^Priority$/) { $spdefault{$_}= $v; }
        else { &unknown('general section of control info file'); }
    } elsif (s/^C$myindex //) {
#print STDERR "P key >$_< value >$v<\n";
        if (m/^(Package|Description|Essential|Pre-Depends|Depends)$/ ||
            m/^(Recommends|Suggests|Enhances|Optional|Conflicts|Provides|Replaces)$/) {
            $f{$_}= $v;
        } elsif (m/^Section$|^Priority$/) {
            $spvalue{$_}= $v;
        } elsif (m/^Architecture$/) {
            if ($v eq 'all') {
                $f{$_}= $v;
            } elsif ($v eq 'any') {
                $f{$_}= $arch;
            } else {
                @archlist= split(/\s+/,$v);
                grep($arch eq $_, @archlist) ||
                    &error("current build architecture $arch does not".
                           " appear in package's list (@archlist)");
                $f{$_}= $arch;
            }
        } elsif (s/^X[CS]*B[CS]*-//i) {
            $f{$_}= $v;
        } elsif (!m/^X[CS]+-/i) {
            &unknown("package's section of control info file");
        }
    } elsif (m/^C\d+ /) {
#print STDERR "X key >$_< value not shown<\n";
    } elsif (s/^L //) {
#print STDERR "L key >$_< value >$v<\n";
        if (m/^Source$/) {
            &setsourcepackage;
        } elsif (m/^Version$/) {
            $sourceversion= $v;
            $f{$_}= $v unless length($forceversion);
        } elsif (m/^(Maintainer|Changes|Urgency|Distribution|Date|Closes)$/) {
        } elsif (s/^X[CS]*B[CS]*-//i) {
            $f{$_}= $v;
        } elsif (!m/^X[CS]+-/i) {
            &unknown("parsed version of changelog");
        }
    } else {
        &internerr("value from nowhere, with key >$_< and value >$v<");
    }
}

$f{'Version'}= $forceversion if length($forceversion);
$version= $f{'Version'};
$origversion= $version; $origversion =~ s/-[^-]+$//;
$substvar{"dpkg:UpstreamVersion"}=$origversion;
$substvar{"dpkg:Version"}=$version;

for $f (qw(Section Priority)) {
    $spvalue{$f}= $spdefault{$f} unless length($spvalue{$f});
    $f{$f}= $spvalue{$f} if $spinclude{$f} && length($spvalue{$f});
}

for $f (qw(Package Version)) {
    defined($f{$f}) || &error("missing information for output field $f");
}
for $f (qw(Maintainer Description Architecture)) {
    defined($f{$f}) || &warn("missing information for output field $f");
}
$oppackage= $f{'Package'};

$verdiff= $f{'Version'} ne $sourceversion;
if ($oppackage ne $sourcepackage || $verdiff) {
    $f{'Source'}= $sourcepackage;
    $f{'Source'}.= " ($sourceversion)" if $verdiff;
}

if (!defined($substvar{'Installed-Size'})) {
    defined($c= open(DU,"-|")) || &syserr("fork for du");
    if (!$c) {
        chdir("$packagebuilddir") || &syserr("chdir for du to \`$packagebuilddir'");
        exec("du","-k","-s","."); &syserr("exec du");
    }
    $duo=''; while (<DU>) { $duo.=$_; }
    close(DU); $? && &subprocerr("du in \`$packagebuilddir'");
    $duo =~ m/^(\d+)\s+\.$/ || &failure("du gave unexpected output \`$duo'");
    $substvar{'Installed-Size'}= $1;
}
if (defined($substvar{'Extra-Size'})) {
    $substvar{'Installed-Size'} += $substvar{'Extra-Size'};
}
if (length($substvar{'Installed-Size'})) {
    $f{'Installed-Size'}= $substvar{'Installed-Size'};
}

$fileslistfile="./$fileslistfile" if $fileslistfile =~ m/^\s/;
open(Y,"> $fileslistfile.new") || &syserr("open new files list file");
chown(@fowner, "$fileslistfile.new") 
		|| &syserr("chown new files list file");
if (open(X,"< $fileslistfile")) {
    while (<X>) {
        chomp;
        next if m/^([-+0-9a-z.]+)_[^_]+_(\w+)\.deb /
                && ($1 eq $oppackage) && ($2 eq $arch || $2 eq 'all');
        print(Y "$_\n") || &syserr("copy old entry to new files list file");
    }
} elsif ($! != ENOENT) {
    &syserr("read old files list file");
}
$sversion=$f{'Version'};
$sversion =~ s/^\d+://;
$forcefilename=sprintf("%s_%s_%s.deb", $oppackage,$sversion,$f{'Architecture'})
	   unless ($forcefilename);
print(Y &substvars(sprintf("%s %s %s\n", $forcefilename, 
                           &spfileslistvalue('Section'), &spfileslistvalue('Priority'))))
    || &syserr("write new entry to new files list file");
close(Y) || &syserr("close new files list file");
rename("$fileslistfile.new",$fileslistfile) || &syserr("install new files list file");

for $f (keys %override) { $f{&capit($f)}= $override{$f}; }
for $f (keys %remove) { delete $f{&capit($f)}; }

if (!$stdout) {
    $cf= "$packagebuilddir/DEBIAN/control";
    $cf= "./$cf" if $cf =~ m/^\s/;
    open(STDOUT,"> $cf.new") ||
        &syserr("cannot open new output control file \`$cf.new'");
}
&outputclose(1);
if (!$stdout) {
    rename("$cf.new","$cf") || &syserr("cannot install output control file \`$cf'");
}

sub spfileslistvalue {
    $r= $spvalue{$_[0]};
    $r= '-' if !length($r);
    return $r;
}
