#! /usr/bin/perl
#
# dpkg-shlibdeps
# $Id: dpkg-shlibdeps.pl,v 1.19.2.2 2004/04/25 17:11:41 keybuk Exp $

my $dpkglibdir="/usr/lib/dpkg";
my $version="1.4.1.19"; # This line modified by Makefile

use English;
use POSIX qw(:errno_h :signal_h);

my $shlibsoverride= '/etc/dpkg/shlibs.override';
my $shlibsdefault= '/etc/dpkg/shlibs.default';
my $shlibslocal= 'debian/shlibs.local';
my $shlibsppdir= '/var/lib/dpkg/info';
my $shlibsppext= '.shlibs';
my $varnameprefix= 'shlibs';
my $dependencyfield= 'Depends';
my $varlistfile= 'debian/substvars';
my $packagetype= 'deb';

my @depfields= qw(Suggests Recommends Depends Pre-Depends);
my %depstrength;
my $i=0; grep($depstrength{$_}= ++$i, @depfields);

push(@INC,$dpkglibdir);
require 'controllib.pl';

#use strict;
#use warnings;

sub usageversion {
    print STDERR
"Debian dpkg-shlibdeps $version.
Copyright (C) 1996 Ian Jackson.
Copyright (C) 2000 Wichert Akkerman.
Copyright (C) 2006 Frank Lichtenheld.
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
       -t<type>               set package type (default is deb)
Dependency fields recognised are ".join("/",@depfields)."
";
}

my ($stdout, @exec, @execf);
foreach (@ARGV) {
    if (m/^-T/) {
	$varlistfile= $POSTMATCH;
    } elsif (m/^-p(\w[-:0-9A-Za-z]*)$/) {
	$varnameprefix= $1;
    } elsif (m/^-L/) {
	$shlibslocal= $POSTMATCH;
    } elsif (m/^-O$/) {
	$stdout= 1;
    } elsif (m/^-h$/) {
	usageversion; exit(0);
    } elsif (m/^-d/) {
	$dependencyfield= capit($POSTMATCH);
	defined($depstrength{$dependencyfield}) ||
	    &warn("unrecognised dependency field \`$dependencyfield'");
    } elsif (m/^-e/) {
	push(@exec,$POSTMATCH); push(@execf,$dependencyfield);
    } elsif (m/^-t/) {
	$packagetype= $POSTMATCH;
    } elsif (m/^-/) {
	usageerr("unknown option \`$_'");
    } else {
	push(@exec,$_); push(@execf,$dependencyfield);
    }
}

@exec || usageerr("need at least one executable");

sub isbin {
    open (F, $_[0]) || die("unable to open '$_[0]' for test");
    my $d;
    if (read (F, $d, 4) != 4) {
       die ("unable to read first four bytes of '$_[0]' as magic number");
    }
    if ($d =~ /^\177ELF$/) { # ELF binary
       return 1;
    } elsif (unpack ('N', $d) == 0x8086010B) { # obsd dyn bin
       return 1;
    } elsif (unpack ('N', $d) ==   0x86010B) { # obsd stat bin
       return 1;
    } elsif ($d =~ /^\#\!..$/) { # shell script
       return 0;
    } elsif (unpack ('N', $d) == 0xcafebabe) { # JAVA binary
       return 0;
    } else {
       die("unrecognized file type for '$_[0]'");
    }
}

my @librarypaths = qw( /lib /usr/lib /lib64 /usr/lib64 );
my %librarypaths = map { $_ => 'default' } @librarypaths;

if ($ENV{LD_LIBRARY_PATH}) {
    foreach (reverse split( /:/, $ENV{LD_LIBRARY_PATH} )) {
	s,/+$,,;
	unless (exists $librarypaths{$_}) {
	    $librarypaths{$_} = 'env';
	    unshift @librarypaths, $_;
	}
    }
}

open CONF, '</etc/ld.so.conf' or
    warn( "couldn't open /etc/ld.so.conf: $!" );
while( <CONF> ) {
    next if /^\s*$/;
    chomp;
    s,/+$,,;
    unless (exists $librarypaths{$_}) {
	$librarypaths{$_} = 'conf';
	push @librarypaths, $_;
    }
}
close CONF;

my (%rpaths, %format);
my (@libfiles, @libname, @libsoname, @libf);
for ($i=0;$i<=$#exec;$i++) {
    if (!isbin ($exec[$i])) { next; }

    # Now we get the direct deps of the program
    defined(my $c= open(P,"-|")) || syserr("cannot fork for objdump");
    if (!$c) {
	exec("objdump","-p","--",$exec[$i]);
	syserr("cannot exec objdump");
    }
    while (<P>) {
	chomp;
	if (/^\s*\S+:\s*file\s+format\s+(\S+)\s*$/) {
	    $format{$execf[$i]} = $1;
	} elsif (m,^\s*NEEDED\s+,) {
	    if (m,^\s*NEEDED\s+((\S+)\.so\.(\S+))$,) {
		push(@libname,$2); push(@libsoname,$3);
		push(@libf,$execf[$i]);
		push(@libfiles,$1);
	    } elsif (m,^\s*NEEDED\s+((\S+)-(\S+)\.so)$,) {
		push(@libname,$2); push(@libsoname,$3);
		push(@libf,$execf[$i]);
		push(@libfiles,$1);
	    } else {
		m,^\s*NEEDED\s+(\S+)$,;
		&warn("format of \`NEEDED $1' not recognized");
	    }
	} elsif (/^\s*RPATH\s+(\S+)\s*$/) {
	    push @{$rpaths{$execf[$i]}}, $1;
	}
    }
    close(P) or subprocerr("objdump on \`$exec[$i]'");
}

# Now: See if it is in this package.  See if it is in any other package.
my @curshlibs;
sub searchdir {
    my $dir = shift;
    if(opendir(DIR, $dir)) {
	my @dirents = readdir(DIR);
	closedir(DIR);
	for (@dirents) {
	    if ( -f "$dir/$_/DEBIAN/shlibs" ) {
		push(@curshlibs, "$dir/$_/DEBIAN/shlibs");
		next;
	    } elsif ( $_ !~ /^\./ && ! -e "$dir/$_/DEBIAN" &&
		      -d "$dir/$_" && ! -l "$dir/$_" ) {
		&searchdir("$dir/$_");
	    }
	}
    }
}

my $searchdir = $exec[0];
my $curpackdir = "debian/tmp";
do { $searchdir =~ s,/[^/]*$,,; } while($searchdir =~ m,/,
					&& ! -d "$searchdir/DEBIAN");
if ($searchdir =~ m,/,) {
    $curpackdir = $searchdir;
    $searchdir =~ s,/[^/]*,,;
    &searchdir($searchdir);
}

if (1 || $#curshlibs >= 0) {
  PRELIB:
    for ($i=0;$i<=$#libname;$i++) {
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

my %pathpackages;
if ($#libfiles >= 0) {
    # what does this line do? -- djpig
    grep(s/\[\?\*/\\$&/g, @libname);
    defined(my $c= open(P,"-|")) || syserr("cannot fork for dpkg --search");
    if (!$c) {
	close STDERR; # we don't need to see dpkg's errors
	open STDERR, "> /dev/null";
	$ENV{LC_ALL} = "C";
	exec("dpkg","--search","--",@libfiles);
	syserr("cannot exec dpkg");
    }
    while (<P>) {
	chomp;
	if (m/^local diversion |^diversion by/) {
	    &warn("diversions involved - output may be incorrect");
	    print(STDERR " $_\n") || syserr("write diversion info to stderr");
	} elsif (m=^(\S+(, \S+)*): (\S+)$=) {
	    push @{$pathpackages{$LAST_PAREN_MATCH}}, split(/, /, $1);
	} else {
	    &warn("unknown output from dpkg --search: \`$_'");
	}
    }
    close(P);
}

 LIB:
    for ($i=0;$i<=$#libname;$i++) {
	my $file = $libfiles[$i];
	my @packages;
	foreach my $rpath (@{$rpaths{$libf[$i]}}) {
	    if (exists $pathpackages{"$rpath/$file"}
		&& format_matches($libf[$i],"$rpath/$file")) {
		push @packages, @{$pathpackages{"$rpath/$file"}};
	    }
	}
	foreach my $path (@librarypaths) {
	    if (exists $pathpackages{"$path/$file"}
		&& format_matches($libf[$i],"$path/$file")) {
		push @packages, @{$pathpackages{"$path/$file"}};
	    }
	}
	if (!@packages) {
	    &warn("could not find any packages for $libfiles[$i]");
	} else {
	    for my $p (@packages) {
		scanshlibsfile("$shlibsppdir/$p$shlibsppext",
			       $libname[$i],$libsoname[$i],$libf[$i])
		    && next LIB;
	    }
	}
	scanshlibsfile($shlibsdefault,$libname[$i],$libsoname[$i],$libf[$i])
	    && next;
	&warn("unable to find dependency information for ".
	      "shared library $libname[$i] (soname $libsoname[$i], ".
	      "path $libfiles[$i], dependency field $libf[$i])");
    }

sub format_matches {
    my ($file1, $file2) = @_;
    my ($format1, $format2) = (get_format($file1),get_format($file2));
    return $format1 eq $format2;
}

sub get_format {
    my ($file) = @_;

    if ($format{$file}) {
	return $format{$file};
    } else {
	defined(my $c= open(P,"-|")) || syserr("cannot fork for objdump");
	if (!$c) {
	    exec("objdump","-a","--",$file);
	    syserr("cannot exec objdump");
	}
	while (<P>) {
	    chomp;
	    if (/^\s*\S+:\s*file\s+format\s+(\S+)\s*$/) {
		$format{$file} = $1;
		return $format{$file};
	    }
	}
	close(P) or subprocerr("objdump on \`$file'");
    }
}

my (%predefdepfdep, %unkdepfdone, %unkdepf);
sub scanshlibsfile {
    my ($fn,$ln,$lsn,$lf) = @_;
    my ($da,$dk);
    $fn= "./$fn" if $fn =~ m/^\s/;
    if (!open(SLF,"< $fn")) {
        $! == ENOENT || syserr("unable to open shared libs info file \`$fn'");
        return 0;
    }

    while (<SLF>) {
        s/\s*\n$//; next if m/^\#/;
        if (!m/^\s*(?:(\S+):\s+)?(\S+)\s+(\S+)/) {
            &warn("shared libs info file \`$fn' line $.: bad line \`$_'");
            next;
        }
        next if defined $1 && $1 ne $packagetype;
        next if $2 ne $ln || $3 ne $lsn;
        return 1 if $fn eq "$curpackdir/DEBIAN/shlibs";
        $da= $POSTMATCH;
        last if defined $1; # exact match, otherwise keep looking
    }
    close(SLF);

    return 0 unless defined $da;

    for my $dv (split(/,/,$da)) {
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

my $fh;
if (!$stdout) {
    open(Y,"> $varlistfile.new") ||
        syserr("open new substvars file \`$varlistfile.new'");
    unless ($REAL_USER_ID) {
	chown(@fowner, "$varlistfile.new") ||
	    syserr("chown of \`$varlistfile.new'");
    }
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
my %defdepf;
for my $dv (sort keys %predefdepfdep) {
    my $lf= $predefdepfdep{$dv};
    $defdepf{$lf}.= ', ' if length($defdepf{$lf});
    $defdepf{$lf}.= $dv;
}
for my $lf (reverse @depfields) {
    next unless defined($defdepf{$lf});
    print($fh "$varnameprefix:$lf=$defdepf{$lf}\n")
        || syserr("write output entry");
}
for my $lf (sort keys %unkdepf) {
    print($fh "$varnameprefix:$lf=$unkdepf{$lf}\n")
        || syserr("write userdef output entry");
}
close($fh) || syserr("close output");
if (!$stdout) {
    rename("$varlistfile.new",$varlistfile) ||
        syserr("install new varlist file \`$varlistfile'");
}
