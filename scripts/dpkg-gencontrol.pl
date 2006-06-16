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

require 'dpkg-gettext.pl';
textdomain("dpkg-dev");

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
    } elsif (m/^-p(.*)/) {
        &error(sprintf(_g("Illegal package name \`%s'"), $1));
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
        &usageerr(sprintf(_g("unknown option \`%s'"), $_));
    }
}

&findarch;
&parsechangelog;
&parsesubstvars;
&parsecontrolfile;
            
if (length($oppackage)) {
    defined($p2i{"C $oppackage"}) || &error(sprintf(_g("package %s not in control info"), $oppackage));
    $myindex= $p2i{"C $oppackage"};
} else {
    @packages= grep(m/^C /,keys %p2i);
    @packages==1 ||
        &error(sprintf(_g("must specify package since control info has many (%s)"), "@packages"));
    $myindex=1;
}

#print STDERR "myindex $myindex\n";

my %pkg_dep_fields = map { $_ => 1 } @pkg_dep_fields;

for $_ (keys %fi) {
    $v= $fi{$_};
    if (s/^C //) {
#print STDERR "G key >$_< value >$v<\n";
        if (m/^Origin|Bugs|Maintainer$/) { $f{$_}=$v; }
        elsif (m/^Source$/) { &setsourcepackage; }
        elsif (s/^X[CS]*B[CS]*-//i) { $f{$_}= $v; }
	elsif (m/^X[CS]+-|^(Standards-Version|Uploaders)$|^Build-(Depends|Conflicts)(-Indep)?$/i) { }
	elsif (m/^Section$|^Priority$/) { $spdefault{$_}= $v; }
        else { $_ = "C $_"; &unknown(_g('general section of control info file')); }
    } elsif (s/^C$myindex //) {
#print STDERR "P key >$_< value >$v<\n";
        if (m/^(Package|Description|Essential|Optional)$/) {
            $f{$_}= $v;
        } elsif (exists($pkg_dep_fields{$_})) {
        } elsif (m/^Section$|^Priority$/) {
            $spvalue{$_}= $v;
        } elsif (m/^Architecture$/) {
            if (debian_arch_eq('all', $v)) {
                $f{$_}= $v;
            } elsif (debian_arch_is($arch, $v)) {
                $f{$_}= $arch;
            } else {
                @archlist= split(/\s+/,$v);
		my @invalid_archs = grep m/[^\w-]/, @archlist;
		&warn(sprintf(ngettext(
		                  "`%s' is not a legal architecture string.",
		                  "`%s' are not legal architecture strings.",
		                  scalar(@invalid_archs)),
		              join("' `", @invalid_archs)))
		    if @invalid_archs >= 1;
                grep(debian_arch_is($arch, $_), @archlist) ||
                    &error(sprintf(_g("current build architecture %s does not".
                                      " appear in package's list (%s)"),
                                   $arch, "@archlist"));
                $f{$_}= $arch;
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
            &setsourcepackage;
        } elsif (m/^Version$/) {
            $sourceversion= $v;
            $f{$_}= $v unless length($forceversion);
        } elsif (m/^(Maintainer|Changes|Urgency|Distribution|Date|Closes)$/) {
        } elsif (s/^X[CS]*B[CS]*-//i) {
            $f{$_}= $v;
        } elsif (!m/^X[CS]+-/i) {
            $_ = "L $_"; &unknown(_g("parsed version of changelog"));
        }
    } elsif (m/o:/) {
    } else {
        &internerr(sprintf(_g("value from nowhere, with key >%s< and value >%s<"), $_, $v));
    }
}

$f{'Version'}= $forceversion if length($forceversion);

&init_substvars;

for $_ (keys %fi) {
    $v= $fi{$_};
    if (s/^C //) {
    } elsif (s/^C$myindex //) {
        if (m/^(Package|Description|Essential|Optional)$/) {
        } elsif (exists($pkg_dep_fields{$_})) {
           my $dep = parsedep(substvars($v), 1, 1);
           &error(sprintf(_g("error occurred while parsing %s"), $_)) unless defined $dep;
            $f{$_}= showdep($dep, 0);
        } elsif (m/^Section$|^Priority$/) {
        } elsif (m/^Architecture$/) {
        } elsif (s/^X[CS]*B[CS]*-//i) {
        } elsif (!m/^X[CS]+-/i) {
        }
    } elsif (m/^C\d+ /) {
    } elsif (s/^L //) {
    } elsif (m/o:/) {
    } else {
    }
}


for $f (qw(Section Priority)) {
    $spvalue{$f}= $spdefault{$f} unless length($spvalue{$f});
    $f{$f}= $spvalue{$f} if length($spvalue{$f});
}

for $f (qw(Package Version)) {
    defined($f{$f}) || &error(sprintf(_g("missing information for output field %s"), $f));
}
for $f (qw(Maintainer Description Architecture)) {
    defined($f{$f}) || &warn(sprintf(_g("missing information for output field %s"), $f));
}
$oppackage= $f{'Package'};

$verdiff = $f{'Version'} ne $substvar{'source:Version'} or
           $f{'Version'} ne $sourceversion;
if ($oppackage ne $sourcepackage || $verdiff) {
    $f{'Source'}= $sourcepackage;
    $f{'Source'}.= " ($substvar{'source:Version'})" if $verdiff;
}

if (!defined($substvar{'Installed-Size'})) {
    defined($c= open(DU,"-|")) || &syserr(_g("fork for du"));
    if (!$c) {
        chdir("$packagebuilddir") || &syserr(sprintf(_g("chdir for du to \`%s'"), $packagebuilddir));
        exec("du","-k","-s",".") or &syserr(_g("exec du"));
    }
    $duo=''; while (<DU>) { $duo.=$_; }
    close(DU); $? && &subprocerr(sprintf(_g("du in \`%s'"), $packagebuilddir));
    $duo =~ m/^(\d+)\s+\.$/ || &failure(sprintf(_g("du gave unexpected output \`%s'"), $duo));
    $substvar{'Installed-Size'}= $1;
}
if (defined($substvar{'Extra-Size'})) {
    $substvar{'Installed-Size'} += $substvar{'Extra-Size'};
}
if (length($substvar{'Installed-Size'})) {
    $f{'Installed-Size'}= $substvar{'Installed-Size'};
}

for $f (keys %override) { $f{&capit($f)}= $override{$f}; }
for $f (keys %remove) { delete $f{&capit($f)}; }

$fileslistfile="./$fileslistfile" if $fileslistfile =~ m/^\s/;
open(Y,"> $fileslistfile.new") || &syserr(_g("open new files list file"));
binmode(Y);
chown(@fowner, "$fileslistfile.new") 
		|| &syserr(_g("chown new files list file"));
if (open(X,"< $fileslistfile")) {
    binmode(X);
    while (<X>) {
        chomp;
        next if m/^([-+0-9a-z.]+)_[^_]+_([\w-]+)\.deb /
                && ($1 eq $oppackage)
                && (debian_arch_eq($2, $f{'Architecture'})
		    || debian_arch_eq($2, 'all'));
        print(Y "$_\n") || &syserr(_g("copy old entry to new files list file"));
    }
    close(X) || &syserr(_g("close old files list file"));
} elsif ($! != ENOENT) {
    &syserr(_g("read old files list file"));
}
$sversion=$f{'Version'};
$sversion =~ s/^\d+://;
$forcefilename=sprintf("%s_%s_%s.deb", $oppackage,$sversion,$f{'Architecture'})
	   unless ($forcefilename);
print(Y &substvars(sprintf("%s %s %s\n", $forcefilename, 
                           &spfileslistvalue('Section'), &spfileslistvalue('Priority'))))
    || &syserr(_g("write new entry to new files list file"));
close(Y) || &syserr(_g("close new files list file"));
rename("$fileslistfile.new",$fileslistfile) || &syserr(_g("install new files list file"));

if (!$stdout) {
    $cf= "$packagebuilddir/DEBIAN/control";
    $cf= "./$cf" if $cf =~ m/^\s/;
    open(STDOUT,"> $cf.new") ||
        &syserr(sprintf(_g("cannot open new output control file \`%s'"), "$cf.new"));
    binmode(STDOUT);
}
&outputclose(1);
if (!$stdout) {
    rename("$cf.new","$cf") || &syserr(sprintf(_g("cannot install output control file \`%s'"), $cf));
}

sub spfileslistvalue {
    $r= $spvalue{$_[0]};
    $r= '-' if !length($r);
    return $r;
}
