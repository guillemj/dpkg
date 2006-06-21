#!/usr/bin/perl --

$version= '1.0.11'; # This line modified by Makefile
$admindir= "/var/lib/dpkg"; # This line modified by Makefile
$dpkglibdir= "../utils"; # This line modified by Makefile
($0) = $0 =~ m:.*/(.+):;

push (@INC, $dpkglibdir);
require 'dpkg-gettext.pl';
textdomain("dpkg");

$enoent=`$dpkglibdir/enoent` || die sprintf(_g("Cannot get ENOENT value from %s: %s"), "$dpkglibdir/enoent", $!);
sub ENOENT { $enoent; }

sub version {
    printf _g("Debian %s version %s.\n"), $0, $version;

    printf _g("
Copyright (C) 1995 Ian Jackson.
Copyright (C) 2000,2001 Wichert Akkerman.");

    printf _g("
This is free software; see the GNU General Public Licence version 2 or
later for copying conditions. There is NO warranty.
");
}

sub usage {
    printf(_g(
"Usage: %s [<option> ...] <command>

Commands:
  [--add] <file>           add a diversion.
  --remove <file>          remove the diversion.
  --list [<glob-pattern>]  show file diversions.
  --truename <file>        return the diverted file.

Options:
  --package <package>      name of the package whose copy of <file> will not
                             be diverted.
  --local                  all packages' versions are diverted.
  --divert <divert-to>     the name used by other packages' versions.
  --rename                 actually move the file aside (or back).
  --admindir <directory>   set the directory with the diversions file.
  --test                   don't do anything, just demonstrate.
  --quiet                  quiet operation, minimal output.
  --help                   show this help message.
  --version                show the version.

When adding, default is --local and --divert <original>.distrib.
When removing, --package or --local and --divert must match if specified.
Package preinst/postrm scripts should always specify --package and --divert.
"), $0);
}

$testmode= 0;
$dorename= 0;
$verbose= 1;
$mode='';
$|=1;

sub checkmanymodes {
    return unless $mode;
    &badusage(sprintf(_g("two modes specified: %s and --%s"), $_, $mode));
}

while (@ARGV) {
    $_= shift(@ARGV);
    last if m/^--$/;
    if (!m/^-/) {
        unshift(@ARGV,$_); last;
    } elsif (m/^--help$/) {
        &usage; exit(0);
    } elsif (m/^--version$/) {
        &version; exit(0);
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
        @ARGV || &badusage(sprintf(_g("--%s needs a divert-to argument"), "divert"));
        $divertto= shift(@ARGV);
        $divertto =~ m/\n/ && &badusage(_g("divert-to may not contain newlines"));
    } elsif (m/^--package$/) {
        @ARGV || &badusage(sprintf(_g("--%s needs a <package> argument"), "package"));
        $package= shift(@ARGV);
        $package =~ m/\n/ && &badusage(_g("package may not contain newlines"));
    } elsif (m/^--admindir$/) {
        @ARGV || &badusage(sprintf(_g("--%s needs a <directory> argument"), "admindir"));
        $admindir= shift(@ARGV);
    } else {
        &badusage(sprintf(_g("unknown option \`%s'"), $_));
    }
}

$mode='add' unless $mode;

open(O,"$admindir/diversions") || &quit(sprintf(_g("cannot open diversions: %s"), $!));
while(<O>) {
    s/\n$//; push(@contest,$_);
    $_=<O>; s/\n$// || &badfmt(_g("missing altname"));
    push(@altname,$_);
    $_=<O>; s/\n$// || &badfmt(_g("missing package"));
    push(@package,$_);
}
close(O);

if ($mode eq 'add') {
    @ARGV == 1 || &badusage(sprintf(_g("--%s needs a single argument"), "add"));
    $file= $ARGV[0];
    $file =~ m#^/# || &badusage(sprintf(_g("filename \"%s\" is not absolute"), $file));
    $file =~ m/\n/ && &badusage(_g("file may not contain newlines"));
	-d $file && &badusage(_g("Cannot divert directories"));
    $divertto= "$file.distrib" unless defined($divertto);
    $divertto =~ m#^/# || &badusage(sprintf(_g("filename \"%s\" is not absolute"), $divertto));
    $package= ':' unless defined($package);
    for ($i=0; $i<=$#contest; $i++) {
        if ($contest[$i] eq $file || $altname[$i] eq $file ||
            $contest[$i] eq $divertto || $altname[$i] eq $divertto) {
            if ($contest[$i] eq $file && $altname[$i] eq $divertto &&
                $package[$i] eq $package) {
                printf(_g("Leaving \`%s'")."\n", &infon($i)) if $verbose > 0;
                exit(0);
            }
            &quit(sprintf(_g("\`%s' clashes with \`%s'"), &infoa, &infon($i)));
        }
    }
    push(@contest,$file);
    push(@altname,$divertto);
    push(@package,$package);
    printf(_g("Adding \`%s'")."\n", &infon($#contest)) if $verbose > 0;
    &checkrename($file,$divertto);
    &save;
    &dorename($file,$divertto);
    exit(0);
} elsif ($mode eq 'remove') {
    @ARGV == 1 || &badusage(sprintf(_g("--%s needs a single argument"), "remove"));
    $file= $ARGV[0];
    for ($i=0; $i<=$#contest; $i++) {
        next unless $file eq $contest[$i];
        &quit(sprintf(_g("mismatch on divert-to\n  when removing \`%s'\n  found \`%s'"), &infoa, &infon($i)))
              if defined($divertto) && $altname[$i] ne $divertto;
        &quit(sprintf(_g("mismatch on package\n  when removing \`%s'\n  found \`%s'"), &infoa, &infon($i)))
              if defined($package) && $package[$i] ne $package;
        printf(_g("Removing \`%s'")."\n", &infon($i)) if $verbose > 0;
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
    printf(_g("No diversion \`%s', none removed")."\n", &infoa) if $verbose > 0;
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
    @ARGV == 1 || &badusage(sprintf(_g("--%s needs a single argument"), "truename"));
    $file= $ARGV[0];
    for ($i=0; $i<=$#contest; $i++) {
	next unless $file eq $contest[$i];
	print $altname[$i], "\n";
	exit(0);
    }
    print $file, "\n";
    exit(0);
} else {
    &quit(sprintf(_g("internal error - bad mode \`%s'"), $mode));
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
        &quit(sprintf(_g("cannot stat old name \`%s': %s"), $rsrc, $!));
    (@sdest= lstat($rdest)) || $! == &ENOENT ||
        &quit(sprintf(_g("cannot stat new name \`%s': %s"), $rdest, $!));
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
		&quit(sprintf(_g("error checking \`%s': %s"), $file, $!));
	}
    }
    if (@ssrc && @sdest &&
        !($ssrc[0] == $sdest[0] && $ssrc[1] == $sdest[1])) {
        &quit(sprintf(_g("rename involves overwriting \`%s' with\n".
              "  different file \`%s', not allowed"), $rdest, $rsrc));
    }
}

sub dorename {
    return unless $dorename;
    return if $testmode;
    if (@ssrc) {
        if (@sdest) {
            unlink($rsrc) || &quit(sprintf(_g("rename: remove duplicate old link \`%s': %s"), $rsrc, $!));
        } else {
            rename($rsrc,$rdest) || &quit(sprintf(_g("rename: rename \`%s' to \`%s': %s"), $rsrc, $rdest, $!));
        }
    }
}            
    
sub save {
    return if $testmode;
    open(N,"> $admindir/diversions-new") || &quit(sprintf(_g("create diversions-new: %s"), $!));
    chmod 0644, "$admindir/diversions-new";
    for ($i=0; $i<=$#contest; $i++) {
        print(N "$contest[$i]\n$altname[$i]\n$package[$i]\n")
            || &quit(sprintf(_g("write diversions-new: %s"), $!));
    }
    close(N) || &quit(sprintf(_g("close diversions-new: %s"), $!));
    unlink("$admindir/diversions-old") ||
        $! == &ENOENT || &quit(sprintf(_g("remove old diversions-old: %s"), $!));
    link("$admindir/diversions","$admindir/diversions-old") ||
        $! == &ENOENT || &quit(sprintf(_g("create new diversions-old: %s"), $!));
    rename("$admindir/diversions-new","$admindir/diversions")
        || &quit(sprintf(_g("install new diversions: %s"), $!));
}

sub infoa { &infol($file,$divertto,$package); }
sub infon { &infol($contest[$i],$altname[$i],$package[$i]); }

sub quit
{
    printf STDERR "%s: %s\n", $0, "@_";
    exit(2);
}

sub badusage
{
    printf STDERR "%s: %s\n\n", $0, "@_";
    &usage;
    exit(2);
}

sub badfmt { &quit(sprintf(_g("internal error: %s corrupt: %s"), "$admindir/diversions", $_[0])); }
