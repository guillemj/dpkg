#!/usr/bin/perl

$dpkglibdir= ".";
$version= '1.3.6'; # This line modified by Makefile

use POSIX;
use POSIX qw(:errno_h :signal_h);

$shlibsoverride= '/etc/dpkg/shlibs.override';
$shlibsdefault= '/etc/dpkg/shlibs.default';
$shlibslocal= 'debian/shlibs.local';
$shlibsppdir= '/var/lib/dpkg/info';
$shlibsppext= '.shlibs';
$varnameprefix= 'shlibs';
$dependencyfield= 'Depends';
$varlistfile= 'debian/substvars';

@depfields= qw(Suggests Recommends Depends Pre-Depends);

push(@INC,$dpkglibdir);
require 'controllib.pl';

sub usageversion {
    print STDERR
"Debian GNU/Linux dpkg-shlibdeps $version.  Copyright (C) 1996
Ian Jackson.  This is free software; see the GNU General Public Licence
version 2 or later for copying conditions.  There is NO warranty.

Usage:
  dpkg-shlibdeps [<option> ...] <executable>|-e<executable> [<option>] ...
Positional arguments/options (order is significant):
       <executable>           } include dependencies for <executable>
       -e<executable>         }  (use -e if <executable> starts with \`-')
       -d<dependencyfield>    next executable(s) set shlibs:<dependencyfield>
Overall options (have global effect no matter where placed):
       -p<varnameprefix>      set <varnameprefix>:* instead of shlibs:*.
       -O                     print variable settings to stdout
       -L<localshlibsfile>    shlibs override file, not debian/shlibs.local
       -T<varlistfile>        update variables here, not debian/substvars
Dependency fields recognised are ".join("/",@depfields)."
";
}

$i=0; grep($depstrength{$_}= ++$i, @depfields);

while (@ARGV) {
    $_=shift(@ARGV);
    if (m/^-T/) {
        $varlistfile= $';
    } elsif (m/^-p(\w[-:0-9A-Za-z]*)$/) {
        $varnameprefix= $1;
    } elsif (m/^-L/) {
        $shlibslocal= $';
    } elsif (m/^-O$/) {
        $stdout= 1;
    } elsif (m/^-h$/) {
        usageversion; exit(0);
    } elsif (m/^-d/) {
        $dependencyfield= capit($');
        defined($depstrength{$dependencyfield}) ||
            &warn("unrecognised dependency field \`$dependencyfield'");
    } elsif (m/^-e/) {
        push(@exec,$'); push(@execf,$dependencyfield);
    } elsif (m/^-/) {
        usageerr("unknown option \`$_'");
    } else {
        push(@exec,$_); push(@execf,$dependencyfield);
    }
}

@exec || usageerr("need at least one executable");

for ($i=0;$i<=$#exec;$i++) {
    defined($c= open(P,"-|")) || syserr("cannot fork for ldd");
    if (!$c) { exec("ldd","--",$exec[$i]); syserr("cannot exec ldd"); }
    $nthisldd=0;
    while (<P>) {
        s/\n$//;
        if (m,^\t(\S+)\.so\.(\S+) \=\> (/\S+)$,) {
            push(@libname,$1); push(@libsoname,$2); push(@libpath,$3);
            push(@libf,$execf[$i]);
            push(@libpaths,$3) if !$libpathadded{$3}++;
            $nthisldd++;
        } else {
            &warn("unknown output from ldd on \`$exec[$i]': \`$_'");
        }
    }
    close(P); $? && subprocerr("ldd on \`$exec[$i]'");
    $nthisldd || &warn("ldd on \`$exec[$i]' gave nothing on standard output");
}

grep(s/\[\?\*/\\$&/g, @libpaths);
defined($c= open(P,"-|")) || syserr("cannot fork for dpkg --search");
if (!$c) { exec("dpkg","--search","--",@libpaths); syserr("cannot exec dpkg"); }
while (<P>) {
    s/\n$//;
    if (m/^local diversion |^diversion by/) {
        &warn("diversions involved - output may be incorrect");
        print(STDERR " $_\n") || syserr("write diversion info to stderr");
    } elsif (m=^(\S+(, \S+)*): (/.+)$=) {
        $pathpackages{$+}= $1;
    } else {
        &warn("unknown output from dpkg --search: \`$_'");
    }
}
close(P); $? && subprocerr("dpkg --search");

for ($i=0;$i<=$#libname;$i++) {
    scanshlibsfile($shlibslocal,$libname[$i],$libsoname[$i],$libf[$i]) && next;
    scanshlibsfile($shlibsoverride,$libname[$i],$libsoname[$i],$libf[$i]) && next;
    if (!defined($pathpackages{$libpath[$i]})) {
        &warn("could not find any packages for $libpath[$i]".
              " ($libname[$i].so.$libsoname[$i])");
    } else {
        @packages= split(/, /,$pathpackages{$libpath[$i]});
        for $p (@packages) {
            scanshlibsfile("$shlibsppdir/$p$shlibsppext",
                           $libname[$i],$libsoname[$i],$libf[$i]) && next;
        }
    }
    scanshlibsfile($shlibsdefault,$libname[$i],$libsoname[$i],$libf[$i]) && next;
    &warn("unable to find dependency information for ".
          "shared library $libname[$i] (soname $libsoname[$i], path $libpath[$i], ".
          "dependency field $libf[$i])");
}

sub scanshlibsfile {
    my ($fn,$ln,$lsn,$lf) = @_;
    my ($da,$dv,$dk);
    $fn= "./$fn" if $fn =~ m/^\s/;
    if (!open(SLF,"< $fn")) {
        $! == ENOENT || syserr("unable to open shared libs info file \`$fn'");
#print STDERR "scanshlibsfile($fn,$ln,$lsn,$lf) ... ENOENT\n";
        return 0;
    }
#print STDERR "scanshlibsfile($fn,$ln,$lsn,$lf) ...\n";
    while (<SLF>) {
        s/\s*\n$//; next if m/^\#/;
        if (!m/^\s*(\S+)\s+(\S+)/) {
            &warn("shared libs info file \`$fn' line $.: bad line \`$_'");
            next;
        }
        next if $1 ne $ln || $2 ne $lsn;
        $da= $';
        for $dv (split(/,/,$da)) {
            $dv =~ s/^\s+//; $dv =~ s/\s+$//;
            if (defined($depstrength{$lf})) {
                if (!defined($predefdepfdep{$dv}) ||
                    $depstrength{$predefdepfdep{$dv}} < $depstrength{$lf}) {
                    $predefdepfdep{$dv}= $lf;
                }
            } else {
                $dk= "$lf: $dv";
                if (!defined($unkdepfdone{$dk})) {
                    $unkdepfdone{$dk}= 1;
                    $unkdepf{$lf}.= ', ' if length($unkdepf{$lf});
                    $unkdepf{$lf}.= $dv;
                }
            }
        }
        return 1;
    }
    close(SLF);
    return 0;
}

if (!$stdout) {
    $varlistfile="./$varlistfile" if $fileslistfile =~ m/^\s/;
    open(Y,"> $varlistfile.new") ||
        syserr("open new substvars file \`$varlistfile.new'");
    if (open(X,"< $varlistfile")) {
        while (<X>) {
            s/\n$//;
            next if m/^(\w[-:0-9A-Za-z]*):/ && $1 eq $varnameprefix;
            print(Y "$_\n") ||
                syserr("copy old entry to new varlist file \`$varlistfile.new'");
        }
    } elsif ($! != ENOENT) {
        syserr("open old varlist file \`$varlistfile' for reading");
    }
    $fh= 'Y';
} else {
    $fh= 'STDOUT';
}
for $dv (sort keys %predefdepfdep) {
    $lf= $predefdepfdep{$dv};
    $defdepf{$lf}.= ', ' if length($defdepf{$lf});
    $defdepf{$lf}.= $dv;
}
for $lf (reverse @depfields) {
    next unless defined($defdepf{$lf});
    print($fh "$varnameprefix:$lf=$defdepf{$lf}\n")
        || syserr("write output entry");
}
for $lf (sort keys %unkdepf) {
    print($fh "$varnameprefix:$lf=$unkdepf{$lf}\n")
        || syserr("write userdef output entry");
}
close($fh) || syserr("close output");
if (!$stdout) {
    rename("$varlistfile.new",$varlistfile) ||
        syserr("install new varlist file \`$varlistfile'");
}
