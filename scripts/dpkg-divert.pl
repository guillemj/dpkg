#!/usr/bin/perl --

$version= '1.0.11'; # This line modified by Makefile
$admindir= "/var/lib/dpkg"; # This line modified by Makefile
$dpkglibdir= "../utils"; # This line modified by Makefile

$enoent=`$dpkglibdir/enoent` || die "Cannot get ENOENT value from $dpkglibdir/enoent: $!";
sub ENOENT { $enoent; }

sub showversion {
    print("Debian dpkg-divert $version.\n") || &quit("failed to write version: $!");
}

sub usage {
    &showversion;
    print STDERR <<EOF
Copyright (C) 1995 Ian Jackson.
Copyright (C) 2000,2001 Wichert Akkerman.

This is free software; see the GNU General Public Licence version 2 or later
for copying conditions. There is NO warranty.

Usage:

 dpkg-divert [options] [--add] <file>               - add a diversion
 dpkg-divert [options] --remove <file>              - remove the diversion
 dpkg-divert [options] --list [<glob-pattern>]      - show file diversions
 dpkg-divert [options] --truename <file>            - return the diverted file

Options: 
    --package <package>        name of the package whose copy of <file>
                               will not be diverted.
    --local                    all packages' versions are diverted.
    --divert <divert-to>       the name used by other packages' versions.
    --rename                   actually move the file aside (or back).
    --quiet                    quiet operation, minimal output
    --test                     don't do anything, just demonstrate
    --help                     print this help screen and exit
    --version                  output version and exit
    --admindir <directory>     set the directory with the diversions file

When adding, default is --local and --divert <original>.distrib.
When removing, --package or --local and --divert must match if specified.
Package preinst/postrm scripts should always specify --package and --divert.
EOF
        || &quit("failed to write usage: $!");
}

$testmode= 0;
$dorename= 0;
$verbose= 1;
$mode='';
$|=1;

sub checkmanymodes {
    return unless $mode;
    &badusage("two modes specified: $_ and --$mode");
}

while (@ARGV) {
    $_= shift(@ARGV);
    last if m/^--$/;
    if (!m/^-/) {
        unshift(@ARGV,$_); last;
    } elsif (m/^--help$/) {
        &usage; exit(0);
    } elsif (m/^--version$/) {
        &showversion; exit(0);
    } elsif (m/^--test$/) {
        $testmode= 1;
    } elsif (m/^--rename$/) {
        $dorename= 1;
    } elsif (m/^--quiet$/) {
        $verbose= 0;
    } elsif (m/^--local$/) {
        $package= ':';
    } elsif (m/^--add$/) {
        &checkmanymodes;
        $mode= 'add';
    } elsif (m/^--remove$/) {
        &checkmanymodes;
        $mode= 'remove';
    } elsif (m/^--list$/) {
        &checkmanymodes;
        $mode= 'list';
    } elsif (m/^--truename$/) {
        &checkmanymodes;
        $mode= 'truename';
    } elsif (m/^--divert$/) {
        @ARGV || &badusage("--divert needs a divert-to argument");
        $divertto= shift(@ARGV);
        $divertto =~ m/\n/ && &badusage("divert-to may not contain newlines");
    } elsif (m/^--package$/) {
        @ARGV || &badusage("--package needs a package argument");
        $package= shift(@ARGV);
        $package =~ m/\n/ && &badusage("package may not contain newlines");
    } elsif (m/^--admindir$/) {
        @ARGV || &badusage("--admindir needs a directory argument");
        $admindir= shift(@ARGV);
    } else {
        &badusage("unknown option \`$_'");
    }
}

$mode='add' unless $mode;

open(O,"$admindir/diversions") || &quit("cannot open diversions: $!");
while(<O>) {
    s/\n$//; push(@contest,$_);
    $_=<O>; s/\n$// || &badfmt("missing altname");
    push(@altname,$_);
    $_=<O>; s/\n$// || &badfmt("missing package");
    push(@package,$_);
}
close(O);

if ($mode eq 'add') {
    @ARGV == 1 || &badusage("--add needs a single argument");
    $file= $ARGV[0];
    $file =~ m#^/# || &badusage("filename \"$file\" is not absolute");
    $file =~ m/\n/ && &badusage("file may not contain newlines");
	-d $file && &badusage("Cannot divert directories");
    $divertto= "$file.distrib" unless defined($divertto);
    $divertto =~ m#^/# || &badusage("filename \"$divertto\" is not absolute");
    $package= ':' unless defined($package);
    for ($i=0; $i<=$#contest; $i++) {
        if ($contest[$i] eq $file || $altname[$i] eq $file ||
            $contest[$i] eq $divertto || $altname[$i] eq $divertto) {
            if ($contest[$i] eq $file && $altname[$i] eq $divertto &&
                $package[$i] eq $package) {
                print "Leaving \`",&infon($i),"'\n" if $verbose > 0;
                exit(0);
            }
            &quit("\`".&infoa."' clashes with \`".&infon($i)."'");
        }
    }
    push(@contest,$file);
    push(@altname,$divertto);
    push(@package,$package);
    print "Adding \`",&infon($#contest),"'\n" if $verbose > 0;
    &checkrename($file,$divertto);
    &save;
    &dorename($file,$divertto);
    exit(0);
} elsif ($mode eq 'remove') {
    @ARGV == 1 || &badusage("--remove needs a single argument");
    $file= $ARGV[0];
    for ($i=0; $i<=$#contest; $i++) {
        next unless $file eq $contest[$i];
        &quit("mismatch on divert-to\n  when removing \`".&infoa."'\n  found \`".
              &infon($i)."'") if defined($divertto) && $altname[$i] ne $divertto;
        &quit("mismatch on package\n  when removing \`".&infoa."'\n  found \`".
              &infon($i)."'") if defined($package) && $package[$i] ne $package;
        print "Removing \`",&infon($i),"'\n" if $verbose > 0;
        $orgfile= $contest[$i];
        $orgdivertto= $altname[$i];
        @contest= (($i > 0 ? @contest[0..$i-1] : ()),
                   ($i < $#contest ? @contest[$i+1..$#contest] : ()));
        @altname= (($i > 0 ? @altname[0..$i-1] : ()),
                   ($i < $#altname ? @altname[$i+1..$#altname] : ()));
        @package= (($i > 0 ? @package[0..$i-1] : ()),
                   ($i < $#package ? @package[$i+1..$#package] : ()));
	$dorename = 1;
        &checkrename($orgdivertto,$orgfile);
        &dorename($orgdivertto,$orgfile);
        &save;
        exit(0);
    }
    print "No diversion \`",&infoa,"', none removed\n" if $verbose > 0;
    exit(0);
} elsif ($mode eq 'list') {
    @ilist= @ARGV ? @ARGV : ('*');
    while (defined($_=shift(@ilist))) {
        s/\W/\\$&/g;
        s/\\\?/./g;
        s/\\\*/.*/g;
        push(@list,"^$_\$");
    }
    $pat= join('|',@list);
    for ($i=0; $i<=$#contest; $i++) {
        next unless ($contest[$i] =~ m/$pat/o ||
                     $altname[$i] =~ m/$pat/o ||
                     $package[$i] =~ m/$pat/o);
        print &infon($i),"\n";
    }
    exit(0);
} elsif ($mode eq 'truename') {
    @ARGV == 1 || &badusage("--truename needs a single argument");
    $file= $ARGV[0];
    for ($i=0; $i<=$#contest; $i++) {
	next unless $file eq $contest[$i];
	print $altname[$i], "\n";
	exit(0);
    }
    print $file, "\n";
    exit(0);
} else {
    &quit("internal error - bad mode \`$mode'");
}

sub infol {
    return (($_[2] eq ':' ? "local " : length($_[2]) ? "" : "any ").
            "diversion of $_[0]".
            (length($_[1]) ? " to $_[1]" : "").
            (length($_[2]) && $_[2] ne ':' ? " by $_[2]" : ""));
}

sub checkrename {
    return unless $dorename;
    ($rsrc,$rdest) = @_;
    (@ssrc= lstat($rsrc)) || $! == &ENOENT ||
        &quit("cannot stat old name \`$rsrc': $!");
    (@sdest= lstat($rdest)) || $! == &ENOENT ||
        &quit("cannot stat new name \`$rdest': $!");
    # Unfortunately we have to check for write access in both
    # places, just having +w is not enough, since people do
    # mount things RO, and we need to fail before we start
    # mucking around with things. So we open a file with the
    # same name as the diversions but with an extension that
    # (hopefully) wont overwrite anything. If it succeeds, we
    # assume a writable filesystem.
    foreach $file ($rsrc,$rdest) {
	if (open (TMP, ">> ${file}.dpkg-devert.tmp")) {
		close TMP;
		unlink ("${file}.dpkg-devert.tmp");
	} elsif ($! == ENOENT) {
		$dorename = !$dorename;
	} else {
		&quit("error checking \`$file': $!");
	}
    }
    if (@ssrc && @sdest &&
        !($ssrc[0] == $sdest[0] && $ssrc[1] == $sdest[1])) {
        &quit("rename involves overwriting \`$rdest' with\n".
              "  different file \`$rsrc', not allowed");
    }
}

sub dorename {
    return unless $dorename;
    return if $testmode;
    if (@ssrc) {
        if (@sdest) {
            unlink($rsrc) || &quit("rename: remove duplicate old link \`$rsrc': $!");
        } else {
            rename($rsrc,$rdest) || &quit("rename: rename \`$rsrc' to \`$rdest': $!");
        }
    }
}            
    
sub save {
    return if $testmode;
    open(N,"> $admindir/diversions-new") || &quit("create diversions-new: $!");
    chmod 0644, "$admindir/diversions-new";
    for ($i=0; $i<=$#contest; $i++) {
        print(N "$contest[$i]\n$altname[$i]\n$package[$i]\n")
            || &quit("write diversions-new: $!");
    }
    close(N) || &quit("close diversions-new: $!");
    unlink("$admindir/diversions-old") ||
        $! == &ENOENT || &quit("remove old diversions-old: $!");
    link("$admindir/diversions","$admindir/diversions-old") ||
        $! == &ENOENT || &quit("create new diversions-old: $!");
    rename("$admindir/diversions-new","$admindir/diversions")
        || &quit("install new diversions: $!");
}

sub infoa { &infol($file,$divertto,$package); }
sub infon { &infol($contest[$i],$altname[$i],$package[$i]); }

sub quit { print STDERR "dpkg-divert: @_\n"; exit(2); }
sub badusage { print STDERR "dpkg-divert: @_\n\n"; print("You need --help.\n"); exit(2); }
sub badfmt { &quit("internal error: $admindir/diversions corrupt: $_[0]"); }
