#! /usr/bin/perl
#
# dpkg-shlibdeps
# $Id$

$dpkglibdir="/usr/lib/dpkg";
$version="1.4.1.19"; # This line modified by Makefile

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
"Debian dpkg-shlibdeps $version.
Copyright (C) 1996 Ian Jackson.
Copyright (C) 2000 Wichert Akkerman.
This is free software; see the GNU General Public Licence version 2 or
later for copying conditions.  There is NO warranty.

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

sub isbin {
    open (F, $_[0]) || die("unable to open '$_[0]' for test");
    if (read (F, $d, 4) != 4) {
       die ("unable to read first four bytes of '$_[0]' as magic number");
    }
    if ($d =~ /^\177ELF$/) { # ELF binary
       return 1;
    } elsif (unpack ('N', $d) == 2156265739) { # obsd dyn bin
       return 1;
    } elsif (unpack ('N', $d) == 8782091) { # obsd stat bin
       return 1;
    } elsif ($d =~ /^\#\!..$/) { # shell script
       return 0;
    } elsif (unpack ('N', $d) == 0xcafebabe) { # JAVA binary
       return 0;
    } else {
       die("unrecognized file type for '$_[0]'");
    }
}

for ($i=0;$i<=$#exec;$i++) {
    if (!isbin ($exec[$i])) { next; }
    
    # First we get an ldd output to see what libs + paths we have at out
    # disposal.
    my %so2path = ();
    defined($c= open(P,"-|")) || syserr("cannot fork for ldd");
    if (!$c) { exec("ldd","--",$exec[$i]); syserr("cannot exec ldd"); }
    while (<P>) {
	if (m,^\s+(\S+)\s+=>\s+(\S+)\s+\(0x.+\)?$,) {
	    $so2path{$1} = $2;
	}
    }
    close(P); $? && subprocerr("ldd on \`$exec[$i]'");

    # Now we get the direct deps of the program. We then check back with
    # the ldd output from above to see what our path is.
    defined($c= open(P,"-|")) || syserr("cannot fork for objdump");
    if (!$c) { exec("objdump","-p","--",$exec[$i]); syserr("cannot exec objdump"); }
    while (<P>) {
	chomp;
	if (m,^\s*NEEDED\s+,) {
	    if (m,^\s*NEEDED\s+((\S+)\.so\.(\S+))$,) {
		push(@libname,$2); push(@libsoname,$3);
		push(@libf,$execf[$i]);
		&warn("could not find path for $1") unless defined($so2path{$1});
		push(@libfiles,$so2path{$1});
	    } elsif (m,^\s*NEEDED\s+((\S+)-(\S+)\.so)$,) {
		push(@libname,$2); push(@libsoname,$3);
		push(@libf,$execf[$i]);
		&warn("could not find path for $1") unless defined($so2path{$1});
		push(@libfiles,$so2path{$1});
	    } else {
		m,^\s*NEEDED\s+(\S+)$,;
		&warn("format of $1 not recognized");
	    }
	}
    }
    close(P); $? && subprocerr("objdump on \`$exec[$i]'");
}

# Now: See if it is in this package.  See if it is in any other package.
sub searchdir {
    my $dir = shift;
    if(opendir(DIR, $dir)) {
	my @dirents = readdir(DIR);
	closedir(DIR);
	for (@dirents) {
	    if ( -f "$dir/$_/DEBIAN/shlibs" ) {
		push(@curshlibs, "$dir/$_/DEBIAN/shlibs");
		next;
	    } elsif ( $_ !~ /^\./ && -d "$dir/$_" && ! -l "$dir/$_" ) {
		&searchdir("$dir/$_");
	    }
	}
    }
}

$searchdir = $exec[0];
$curpackdir = "debian/tmp";
do { $searchdir =~ s,/[^/]*$,,; } while($searchdir =~ m,/, && ! -d "$searchdir/DEBIAN");
if ($searchdir =~ m,/,) {
    $curpackdir = $searchdir;
    $searchdir =~ s,/[^/]*,,;
    &searchdir($searchdir);
}

if (1 || $#curshlibs >= 0) {
    PRELIB: for ($i=0;$i<=$#libname;$i++) {
	if(scanshlibsfile($shlibslocal,$libname[$i],$libsoname[$i],$libf[$i])
	    || scanshlibsfile($shlibsoverride,$libname[$i],$libsoname[$i],$libf[$i])) {
	    splice(@libname, $i, 1);
	    splice(@libsoname, $i, 1);
	    splice(@libf, $i, 1);
	    splice(@libfiles, $i, 1);
	    $i--;
	    next PRELIB;
	}
	for my $shlibsfile (@curshlibs) {
	    if(scanshlibsfile($shlibsfile, $libname[$i], $libsoname[$i], $libf[$i])) {
		splice(@libname, $i, 1);
		splice(@libsoname, $i, 1);
		splice(@libf, $i, 1);
		splice(@libfiles, $i, 1);
		$i--;
		next PRELIB;
	    }
	}
    }
}

if ($#libfiles >= 0) {
    grep(s/\[\?\*/\\$&/g, @libname);
    defined($c= open(P,"-|")) || syserr("cannot fork for dpkg --search");
    if (!$c) {
        close STDERR; # we don't need to see dpkg's errors
	open STDERR, "> /dev/null";
        exec("dpkg","--search","--",map {"$_"} @libfiles); syserr("cannot exec dpkg");
    }
    while (<P>) {
       chomp;
       if (m/^local diversion |^diversion by/) {
           &warn("diversions involved - output may be incorrect");
           print(STDERR " $_\n") || syserr("write diversion info to stderr");
       } elsif (m=^(\S+(, \S+)*): (\S+)$=) {
           push @{$pathpackages{$+}}, split(/, /, $1);
       } else {
           &warn("unknown output from dpkg --search: \`$_'");
       }
    }
    close(P); 
}

LIB: for ($i=0;$i<=$#libname;$i++) {
    if (!defined($pathpackages{$libfiles[$i]})) {
        &warn("could not find any packages for $libfiles[$i]".
              " ($libname[$i].so.$libsoname[$i])");
    } else {
        for $p (@{$pathpackages{$libfiles[$i]}}) {
            scanshlibsfile("$shlibsppdir/$p$shlibsppext",
                           $libname[$i],$libsoname[$i],$libf[$i])
                && next LIB;
        }
    }
    scanshlibsfile($shlibsdefault,$libname[$i],$libsoname[$i],$libf[$i]) && next;
    &warn("unable to find dependency information for ".
          "shared library $libname[$i] (soname $libsoname[$i], path $libfiles[$i], ".
          "dependency field $libf[$i])");
}

sub scanshlibsfile {
    my ($fn,$ln,$lsn,$lf) = @_;
    my ($da,$dv,$dk);
    $fn= "./$fn" if $fn =~ m/^\s/;
    if (!open(SLF,"< $fn")) {
        $! == ENOENT || syserr("unable to open shared libs info file \`$fn'");
        return 0;
    }

    while (<SLF>) {
        s/\s*\n$//; next if m/^\#/;
        if (!m/^\s*(\S+)\s+(\S+)/) {
            &warn("shared libs info file \`$fn' line $.: bad line \`$_'");
            next;
        }
        next if $1 ne $ln || $2 ne $lsn;
        return 1 if $fn eq "$curpackdir/DEBIAN/shlibs";
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
    open(Y,"> $varlistfile.new") ||
        syserr("open new substvars file \`$varlistfile.new'");
    chown(@fowner, "$varlistfile.new") ||
	syserr("chown of \`$varlistfile.new'");
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
