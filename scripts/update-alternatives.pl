#!/usr/bin/perl --

$admindir= "/var/lib/dpkg"; # This line modified by Makefile
$dpkglibdir= "../utils"; # This line modified by Makefile
$version= '0.93.80'; # This line modified by Makefile
push (@INC, $dpkglibdir);
require 'dpkg-gettext.pl';
textdomain("dpkg");

($0) = $0 =~ m:.*/(.+):;

# Global variables:
#  $alink            Alternative we are managing (ie the symlink we're making/removing) (install only)
#  $name             Name of the alternative (the symlink) we are processing
#  $apath            Path of alternative we are offering            
#  $apriority        Priority of link (only when we are installing an alternative)
#  $mode             action to perform (display / install / remove / display / auto / config)
#  $manual           update-mode for alternative (manual / auto)
#  $state            State of alternative:
#                       expected: alternative with highest priority is the active alternative
#                       expected-inprogress: busy selecting alternative with highest priority
#                       unexpected: alternative another alternative is active / error during readlink
#                       nonexistent: alternative-symlink does not exist
#  $link             Link we are working with
#  @slavenames       List with names of slavelinks
#  %slavenum         Map from name of slavelink to slave-index (into @slavelinks)
#  @slavelinks       List of slavelinks (indexed by slave-index)
#  %versionnum       Map from currently available versions into @versions and @priorities
#  @versions         List of available versions for alternative
#  %priorities       Map from @version-index to priority
#  %slavepath        Map from (@version-index,slavename) to slave-path

$enoent=`$dpkglibdir/enoent` || die sprintf(_g("Cannot get ENOENT value from %s: %s"), "$dpkglibdir/enoent", $!);
sub ENOENT { $enoent; }

sub version {
    printf _g("Debian %s version %s.\n"), $0, $version;

    printf _g("
Copyright (C) 1995 Ian Jackson.
Copyright (C) 2000-2002 Wichert Akkerman.");

    printf _g("
This is free software; see the GNU General Public Licence version 2 or
later for copying conditions. There is NO warranty.
");
}

sub usage {
    printf _g(
"Usage: %s [<option> ...] <command>

Commands:
  --install <link> <name> <path> <priority>
    [--slave <link> <name> <path>] ...
                           add a group of alternatives to the system.
  --remove <name> <path>   remove <path> from the <name> group alternative.
  --remove-all <name>      remove <name> group from the alternatives system.
  --auto <name>            switch the master link <name> to automatic mode.
  --display <name>         display information about the <name> group.
  --list <name>            display all targets of the <name> group.
  --config <name>          show alternatives for the <name> group and ask the
                           user to select which one to use.
  --set <name> <path>      set <path> as alternative for <name>.
  --all                    call --config on all alternatives.

<link> is the symlink pointing to /etc/alternatives/<name>.
  (e.g. /usr/bin/pager)
<name> is the master name for this link group.
  (e.g. pager)
<path> is the location of one of the alternative target files.
  (e.g. /usr/bin/less)
<priority> is an integer; options with higher numbers have higher priority in
  automatic mode.

Options:
  --altdir <directory>     change the alternatives directory.
  --admindir <directory>   change the administrative directory.
  --test                   don't do anything, just demonstrate.
  --verbose                verbose operation, more output.
  --quiet                  quiet operation, minimal output.
  --help                   show this help message.
  --version                show the version.
"), $0;
}

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

$altdir= '/etc/alternatives';
$admindir= $admindir . '/alternatives';
$testmode= 0;
$verbosemode= 0;
$mode='';
$manual= 'auto';
$|=1;

sub checkmanymodes {
    return unless $mode;
    &badusage(sprintf(_g("two modes specified: %s and --%s"), $_, $mode));
}

while (@ARGV) {
    $_= shift(@ARGV);
    last if m/^--$/;
    if (!m/^--/) {
        &quit(sprintf(_g("unknown argument \`%s'"), $_));
    } elsif (m/^--help$/) {
        &usage; exit(0);
    } elsif (m/^--version$/) {
        &version; exit(0);
    } elsif (m/^--test$/) {
        $testmode= 1;
    } elsif (m/^--verbose$/) {
        $verbosemode= +1;
    } elsif (m/^--quiet$/) {
        $verbosemode= -1;
    } elsif (m/^--install$/) {
        &checkmanymodes;
        @ARGV >= 4 || &badusage(_g("--install needs <link> <name> <path> <priority>"));
        ($alink,$name,$apath,$apriority,@ARGV) = @ARGV;
        $apriority =~ m/^[-+]?\d+/ || &badusage(_g("priority must be an integer"));
        $mode= 'install';
    } elsif (m/^--(remove|set)$/) {
        &checkmanymodes;
        @ARGV >= 2 || &badusage(sprintf(_g("--%s needs <name> <path>"), $1));
        ($name,$apath,@ARGV) = @ARGV;
        $mode= $1;
    } elsif (m/^--(display|auto|config|list|remove-all)$/) {
        &checkmanymodes;
        @ARGV || &badusage(sprintf(_g("--%s needs <name>"), $1));
        $mode= $1;
        $name= shift(@ARGV);
    } elsif (m/^--slave$/) {
        @ARGV >= 3 || &badusage(_g("--slave needs <link> <name> <path>"));
        ($slink,$sname,$spath,@ARGV) = @ARGV;
        defined($aslavelink{$sname}) && &badusage(sprintf(_g("slave name %s duplicated"), $sname));
        $aslavelinkcount{$slink}++ && &badusage(sprintf(_g("slave link %s duplicated"), $slink));
        $aslavelink{$sname}= $slink;
        $aslavepath{$sname}= $spath;
    } elsif (m/^--altdir$/) {
        @ARGV || &badusage(sprintf(_g("--%s needs a <directory> argument"), "altdir"));
        $altdir= shift(@ARGV);
    } elsif (m/^--admindir$/) {
        @ARGV || &badusage(sprintf(_g("--%s needs a <directory> argument"), "admindir"));
        $admindir= shift(@ARGV);
    } elsif (m/^--all$/) {
        $mode = 'all';
    } else {
        &badusage(sprintf(_g("unknown option \`%s'"), $_));
    }
}

defined($aslavelink{$name}) && &badusage(sprintf(_g("name %s is both primary and slave"), $name));
$aslavelinkcount{$alink} && &badusage(sprintf(_g("link %s is both primary and slave"), $alink));

$mode || &badusage(_g("need --display, --config, --set, --install, --remove, --all, --remove-all or --auto"));
$mode eq 'install' || !%aslavelink || &badusage(_g("--slave only allowed with --install"));

if ($mode eq 'all') {
    &config_all();
}

if (open(AF,"$admindir/$name")) {
    $manual= &gl("manflag");
    $manual eq 'auto' || $manual eq 'manual' || &badfmt(_g("manflag"));
    $link= &gl("link");
    while (($sname= &gl("sname")) ne '') {
        push(@slavenames,$sname);
        defined($slavenum{$sname}) && &badfmt(sprintf(_g("duplicate slave %s"), $sname));
        $slavenum{$sname}= $#slavenames;
        $slink= &gl("slink");
        $slink eq $link && &badfmt(sprintf(_g("slave link same as main link %s"), $link));
        $slavelinkcount{$slink}++ && &badfmt(sprintf(_g("duplicate slave link %s"), $slink));
        push(@slavelinks,$slink);
    }
    while (($version= &gl("version")) ne '') {
        defined($versionnum{$version}) && &badfmt(sprintf(_g("duplicate path %s"), $version));
       if ( -r $version ) {
           push(@versions,$version);
           $versionnum{$version}= $i= $#versions;
           $priority= &gl("priority");
           $priority =~ m/^[-+]?\d+$/ || &badfmt(sprintf(_g("priority %s %s"), $version, $priority));
           $priorities[$i]= $priority;
           for ($j=0; $j<=$#slavenames; $j++) {
               $slavepath{$i,$j}= &gl("spath");
           }
       } else {
           # File not found - remove
           &pr(sprintf(_g("Alternative for %s points to %s - which wasn't found.  Removing from list of alternatives."), $name, $version))
             if $verbosemode > 0;
           &gl("priority");
           for ($j=0; $j<=$#slavenames; $j++) {
               &gl("spath");
           }
       }
    }
    close(AF);
    $dataread=1;
} elsif ($! != &ENOENT) {
    &quit(sprintf(_g("unable to open %s: %s"), "$admindir/$name", $!));
}

if ($mode eq 'display') {
    if (!$dataread) {
        &pr(sprintf(_g("No alternatives for %s."), $name));
	exit 1;
    } else {
        &pr(sprintf(_g("%s - status is %s."), $name, $manual));
        if (defined($linkname= readlink("$altdir/$name"))) {
            &pr(sprintf(_g(" link currently points to %s"), $linkname));
        } elsif ($! == &ENOENT) {
            &pr(_g(" link currently absent"));
        } else {
            &pr(sprintf(_g(" link unreadable - %s"), $!));
        }
        $best= '';
        for ($i=0; $i<=$#versions; $i++) {
            if ($best eq '' || $priorities[$i] > $bestpri) {
                $best= $versions[$i]; $bestpri= $priorities[$i];
            }
            &pr(sprintf(_g("%s - priority %s"), $versions[$i], $priorities[$i]));
            for ($j=0; $j<=$#slavenames; $j++) {
                next unless length($tspath= $slavepath{$i,$j});
                &pr(sprintf(_g(" slave %s: %s"), $slavenames[$j], $tspath));
            }
        }
        if ($best eq '') {
            &pr(_g("No versions available."));
        } else {
            &pr(sprintf(_g("Current \`best' version is %s."), $best));
        }
    }
    exit 0;
}

if ($mode eq 'list') {
    if ($dataread) {
	for ($i = 0; $i<=$#versions; $i++) {
	    &pr("$versions[$i]");
	}
    }
    exit 0;
}

$best= '';
for ($i=0; $i<=$#versions; $i++) {
    if ($best eq '' || $priorities[$i] > $bestpri) {
        $best= $versions[$i]; $bestpri= $priorities[$i];
    }
}

if ($mode eq 'config') {
    if (!$dataread) {
	&pr(sprintf(_g("No alternatives for %s."), $name));
    } else {
	&config_alternatives($name);
    }
}

if ($mode eq 'set') {
    if (!$dataread) {
	&pr(sprintf(_g("No alternatives for %s."), $name));
    } else {
	&set_alternatives($name);
    }
}

if (defined($linkname= readlink("$altdir/$name"))) {
    if ($linkname eq $best) {
        $state= 'expected';
    } elsif (defined(readlink("$altdir/$name.dpkg-tmp"))) {
        $state= 'expected-inprogress';
    } else {
        $state= 'unexpected';
    }
} elsif ($! == &ENOENT) {
    $state= 'nonexistent';
} else {
    $state= 'unexpected';
}

# Possible values for:
#   $manual      manual, auto
#   $state       expected, expected-inprogress, unexpected, nonexistent
#   $mode        auto, install, remove, remove-all
# all independent

if ($mode eq 'auto') {
    &pr(sprintf(_g("Setting up automatic selection of %s."), $name))
      if $verbosemode > 0;
    unlink("$altdir/$name.dpkg-tmp") || $! == &ENOENT ||
        &quit(sprintf(_g("unable to remove %s: %s"), "$altdir/$name.dpkg-tmp", $!));
    unlink("$altdir/$name") || $! == &ENOENT ||
        &quit(sprintf(_g("unable to remove %s: %s"), "$altdir/$name", $!));
    $state= 'nonexistent';
    $manual= 'auto';
}

#   $manual      manual, auto
#   $state       expected, expected-inprogress, unexpected, nonexistent
#   $mode        auto, install, remove
# mode=auto <=> state=nonexistent

if ($state eq 'unexpected' && $manual eq 'auto') {
    &pr(sprintf(_g("%s has been changed (manually or by a script).\n".
                   "Switching to manual updates only."), "$altdir/$name"))
      if $verbosemode > 0;
    $manual= 'manual';
}

#   $manual      manual, auto
#   $state       expected, expected-inprogress, unexpected, nonexistent
#   $mode        auto, install, remove
# mode=auto <=> state=nonexistent
# state=unexpected => manual=manual

&pr(sprintf(_g("Checking available versions of %s, updating links in %s ...\n".
    "(You may modify the symlinks there yourself if desired - see \`man ln'.)"), $name, $altdir))
  if $verbosemode > 0;

if ($mode eq 'install') {
    if ($link ne $alink && $link ne '') {
        &pr(sprintf(_g("Renaming %s link from %s to %s."), $name, $link, $alink))
          if $verbosemode > 0;
        rename_mv($link,$alink) || $! == &ENOENT ||
            &quit(sprintf(_g("unable to rename %s to %s: %s"), $link, $alink, $!));
    }
    $link= $alink;
    if (!defined($i= $versionnum{$apath})) {
        push(@versions,$apath);
        $versionnum{$apath}= $i= $#versions;
    }
    $priorities[$i]= $apriority;
    for $sname (keys %aslavelink) {
        if (!defined($j= $slavenum{$sname})) {
            push(@slavenames,$sname);
            $slavenum{$sname}= $j= $#slavenames;
        }
        $oldslavelink= $slavelinks[$j];
        $newslavelink= $aslavelink{$sname};
        $slavelinkcount{$oldslavelink}-- if $oldslavelink ne '';
        $slavelinkcount{$newslavelink}++ &&
            &quit(sprintf(_g("slave link name %s duplicated"), $newslavelink));
        if ($newslavelink ne $oldslavelink && $oldslavelink ne '') {
            &pr(sprintf(_g("Renaming %s slave link from %s to %s."), $sname, $oldslavelink, $newslavelink))
              if $verbosemode > 0;
            rename_mv($oldslavelink,$newslavelink) || $! == &ENOENT ||
                &quit(sprintf(_g("unable to rename %s to %s: %s"), $oldslavelink, $newslavelink, $!));
        }
        $slavelinks[$j]= $newslavelink;
    }
    for ($j=0; $j<=$#slavenames; $j++) {
        $slavepath{$i,$j}= $aslavepath{$slavenames[$j]};
    }
}

if ($mode eq 'remove') {
    if ($manual eq "manual" and $state ne "expected" and (map { $hits += $apath eq $_ } @versions) and $hits and $linkname eq $apath) {
	&pr(_g("Removing manually selected alternative - switching to auto mode"));
	$manual= "auto";
    }
    if (defined($i= $versionnum{$apath})) {
        $k= $#versions;
        $versionnum{$versions[$k]}= $i;
        delete $versionnum{$versions[$i]};
        $versions[$i]= $versions[$k]; $#versions--;
        $priorities[$i]= $priorities[$k]; $#priorities--;
        for ($j=0; $j<=$#slavenames; $j++) {
            $slavepath{$i,$j}= $slavepath{$k,$j};
            delete $slavepath{$k,$j};
        }
    } else {
        &pr(sprintf(_g("Alternative %s for %s not registered, not removing."), $apath, $name))
          if $verbosemode > 0;
    }
}

if ($mode eq 'remove-all') {
   $manual= "auto";
   $k= $#versions;
   for ($i=0; $i<=$#versions; $i++) {
        $k--;
        delete $versionnum{$versions[$i]};
	$#priorities--;
        for ($j=0; $j<=$#slavenames; $j++) {
            $slavepath{$i,$j}= $slavepath{$k,$j};
            delete $slavepath{$k,$j};
        }
      }
   $#versions=$k;
 }


for ($j=0; $j<=$#slavenames; $j++) {
    for ($i=0; $i<=$#versions; $i++) {
        last if $slavepath{$i,$j} ne '';
    }
    if ($i > $#versions) {
        &pr(sprintf(_g("Discarding obsolete slave link %s (%s)."), $slavenames[$j], $slavelinks[$j]))
          if $verbosemode > 0;
        unlink("$altdir/$slavenames[$j]") || $! == &ENOENT ||
            &quit(sprintf(_g("unable to remove %s: %s"), "$altdir/$slavenames[$j]", $!));
        unlink($slavelinks[$j]) || $! == &ENOENT ||
            &quit(sprintf(_g("unable to remove %s: %s"), $slavelinks[$j], $!));
        $k= $#slavenames;
        $slavenum{$slavenames[$k]}= $j;
        delete $slavenum{$slavenames[$j]};
        $slavelinkcount{$slavelinks[$j]}--;
        $slavenames[$j]= $slavenames[$k]; $#slavenames--;
        $slavelinks[$j]= $slavelinks[$k]; $#slavelinks--;
        for ($i=0; $i<=$#versions; $i++) {
            $slavepath{$i,$j}= $slavepath{$i,$k};
            delete $slavepath{$i,$k};
        }
        $j--;
    }
}
        
if ($manual eq 'manual') {
    &pr(sprintf(_g("Automatic updates of %s are disabled, leaving it alone."), "$altdir/$name"))
      if $verbosemode > 0;
    &pr(sprintf(_g("To return to automatic updates use \`update-alternatives --auto %s'."), $name))
      if $verbosemode > 0;
} else {
    if ($state eq 'expected-inprogress') {
        &pr(sprintf(_g("Recovering from previous failed update of %s ..."), $name));
        rename_mv("$altdir/$name.dpkg-tmp","$altdir/$name") ||
            &quit(sprintf(_g("unable to rename %s to %s: %s"), "$altdir/$name.dpkg-tmp", "$altdir/$name", $!));
        $state= 'expected';
    }
}

#   $manual      manual, auto
#   $state       expected, expected-inprogress, unexpected, nonexistent
#   $mode        auto, install, remove
# mode=auto <=> state=nonexistent
# state=unexpected => manual=manual
# manual=auto => state!=expected-inprogress && state!=unexpected

open(AF,">$admindir/$name.dpkg-new") ||
    &quit(sprintf(_g("unable to open %s for write: %s"), "$admindir/$name.dpkg-new", $!));
&paf($manual);
&paf($link);
for ($j=0; $j<=$#slavenames; $j++) {
    &paf($slavenames[$j]);
    &paf($slavelinks[$j]);
}
&paf('');
$best= '';
for ($i=0; $i<=$#versions; $i++) {
    if ($best eq '' || $priorities[$i] > $bestpri) {
        $best= $versions[$i]; $bestpri= $priorities[$i]; $bestnum= $i;
    }
    &paf($versions[$i]);
    &paf($priorities[$i]);
    for ($j=0; $j<=$#slavenames; $j++) {
        &paf($slavepath{$i,$j});
    }
}
&paf('');
close(AF) || &quit(sprintf(_g("unable to close %s: %s"), "$admindir/$name.dpkg-new", $!));

if ($manual eq 'auto') {
    if ($best eq '') {
        &pr(sprintf(_g("Last package providing %s (%s) removed, deleting it."), $name, $link))
          if $verbosemode > 0;
        unlink("$altdir/$name") || $! == &ENOENT ||
            &quit(sprintf(_g("unable to remove %s: %s"), "$altdir/$name", $!));
        unlink("$link") || $! == &ENOENT ||
            &quit(sprintf(_g("unable to remove %s: %s"), "$link", $!));
        unlink("$admindir/$name.dpkg-new") ||
            &quit(sprintf(_g("unable to remove %s: %s"), "$admindir/$name.dpkg-new", $!));
        unlink("$admindir/$name") || $! == &ENOENT ||
            &quit(sprintf(_g("unable to remove %s: %s"), "$admindir/$name", $!));
        exit(0);
    } else {
        if (!defined($linkname= readlink($link)) && $! != &ENOENT) {
            &pr(sprintf(_g("warning: %s is supposed to be a symlink to %s\n".
                " (or nonexistent); however, readlink failed: %s"), $link, "$altdir/$name", $!))
              if $verbosemode > 0;
        } elsif ($linkname ne "$altdir/$name") {
            unlink("$link.dpkg-tmp") || $! == &ENOENT ||
                &quit(sprintf(_g("unable to ensure %s nonexistent: %s"), "$link.dpkg-tmp", $!));
            symlink("$altdir/$name","$link.dpkg-tmp") ||
                &quit(sprintf(_g("unable to make %s a symlink to %s: %s"), "$link.dpkg-tmp", "$altdir/$name", $!));
            rename_mv("$link.dpkg-tmp",$link) ||
                &quit(sprintf(_g("unable to install %s as %s: %s"), "$link.dpkg-tmp", $link, $!));
        }
        if (defined($linkname= readlink("$altdir/$name")) && $linkname eq $best) {
            &pr(sprintf(_g("Leaving %s (%s) pointing to %s."), $name, $link, $best))
              if $verbosemode > 0;
        } else {
            &pr(sprintf(_g("Updating %s (%s) to point to %s."), $name, $link, $best))
              if $verbosemode > 0;
        }
        unlink("$altdir/$name.dpkg-tmp") || $! == &ENOENT ||
            &quit(sprintf(_g("unable to ensure %s nonexistent: %s"), "$altdir/$name.dpkg-tmp", $!));
        symlink($best,"$altdir/$name.dpkg-tmp");
    }
}

rename_mv("$admindir/$name.dpkg-new","$admindir/$name") ||
    &quit(sprintf(_g("unable to rename %s to %s: %s"), "$admindir/$name.dpkg-new", "$admindir/$name", $!));

if ($manual eq 'auto') {
    rename_mv("$altdir/$name.dpkg-tmp","$altdir/$name") ||
        &quit(sprintf(_g("unable to install %s as %s: %s"), "$altdir/$name.dpkg-tmp", "$altdir/$name", $!));
    for ($j=0; $j<=$#slavenames; $j++) {
        $sname= $slavenames[$j];
        $slink= $slavelinks[$j];
        if (!defined($linkname= readlink($slink)) && $! != &ENOENT) {
            &pr(sprintf(_g("warning: %s is supposed to be a slave symlink to\n".
                " %s, or nonexistent; however, readlink failed: %s"), $slink, "$altdir/$sname", $!))
              if $verbosemode > 0;
        } elsif ($linkname ne "$altdir/$sname") {
            unlink("$slink.dpkg-tmp") || $! == &ENOENT ||
                &quit(sprintf(_g("unable to ensure %s nonexistent: %s"), "$slink.dpkg-tmp", $!));
            symlink("$altdir/$sname","$slink.dpkg-tmp") ||
                &quit(sprintf(_g("unable to make %s a symlink to %s: %s"), "$slink.dpkg-tmp", "$altdir/$sname", $!));
            rename_mv("$slink.dpkg-tmp",$slink) ||
                &quit(sprintf(_g("unable to install %s as %s: %s"), "$slink.dpkg-tmp", $slink, $!));
        }
        $spath= $slavepath{$bestnum,$j};
        unlink("$altdir/$sname.dpkg-tmp") || $! == &ENOENT ||
            &quit(sprintf(_g("unable to ensure %s nonexistent: %s"), "$altdir/$sname.dpkg-tmp", $!));
        if ($spath eq '') {
            &pr(sprintf(_g("Removing %s (%s), not appropriate with %s."), $sname, $slink, $best))
              if $verbosemode > 0;
            unlink("$altdir/$sname") || $! == &ENOENT ||
                &quit(sprintf(_g("unable to remove %s: %s"), "$altdir/$sname", $!));
	    unlink("$slink") || $! == &ENOENT ||
	        &quit(sprintf(_g("unable to remove %s: %s"), $slink, $!));
        } else {
            if (defined($linkname= readlink("$altdir/$sname")) && $linkname eq $spath) {
                &pr(sprintf(_g("Leaving %s (%s) pointing to %s."), $sname, $slink, $spath))
                  if $verbosemode > 0;
            } else {
                &pr(sprintf(_g("Updating %s (%s) to point to %s."), $sname, $slink, $spath))
                  if $verbosemode > 0;
            }
            symlink("$spath","$altdir/$sname.dpkg-tmp") ||
                &quit(sprintf(_g("unable to make %s a symlink to %s: %s"), "$altdir/$sname.dpkg-tmp", $spath, $!));
            rename_mv("$altdir/$sname.dpkg-tmp","$altdir/$sname") ||
                &quit(sprintf(_g("unable to install %s as %s: %s"), "$altdir/$sname.dpkg-tmp", "$altdir/$sname", $!));
        }
    }
}

sub config_message {
    if ($#versions == 0) {
	print "\n";
	printf _g("There is only 1 program which provides %s\n".
	          "(%s). Nothing to configure.\n"), $name, $versions[0];
	return;
    }
    print STDOUT "\n";
    printf(STDOUT _g("There are %s alternatives which provide \`%s'.\n\n".
                     "  Selection    Alternative\n".
                     "-----------------------------------------------\n"),
                  $#versions+1, $name);
    for ($i=0; $i<=$#versions; $i++) {
	printf(STDOUT "%s%s %8s    %s\n",
	    (readlink("$altdir/$name") eq $versions[$i]) ? '*' : ' ',
	    ($best eq $versions[$i]) ? '+' : ' ',
	    $i+1, $versions[$i]);
    }
    printf(STDOUT "\n"._g("Press enter to keep the default[*], or type selection number: "));
}

sub config_alternatives {
    do {
	&config_message;
	if ($#versions == 0) { return; }
	$preferred=<STDIN>;
	chop($preferred);
    } until $preferred eq '' || $preferred>=1 && $preferred<=$#versions+1 &&
	($preferred =~ m/[0-9]*/);
    if ($preferred ne '') {
    	$manual = "manual";
	$preferred--;
	printf STDOUT _g("Using \`%s' to provide \`%s'.")."\n", $versions[$preferred], $name;
	my $spath = $versions[$preferred];
	symlink("$spath","$altdir/$name.dpkg-tmp") ||
	    &quit(sprintf(_g("unable to make %s a symlink to %s: %s"), "$altdir/$name.dpkg-tmp", $spath, $!));
	rename_mv("$altdir/$name.dpkg-tmp","$altdir/$name") ||
	    &quit(sprintf(_g("unable to install %s as %s: %s"), "$altdir/$name.dpkg-tmp", "$altdir/$name", $!));
	# Link slaves...
	for( my $slnum = 0; $slnum < @slavenames; $slnum++ ) {
	    my $slave = $slavenames[$slnum];
	    if ($slavepath{$preferred,$slnum} ne '') {
		checked_symlink($slavepath{$preferred,$slnum},
			"$altdir/$slave.dpkg-tmp");
		checked_mv("$altdir/$slave.dpkg-tmp", "$altdir/$slave");
	    } else {
		&pr(sprintf(_g("Removing %s (%s), not appropriate with %s."), $slave, $slavelinks[$slnum], $versions[$preferred]))
		    if $verbosemode > 0;
		unlink("$altdir/$slave") || $! == &ENOENT ||
		    &quit(sprintf(_g("unable to remove %s: %s"), "$altdir/$slave", $!));
	    }
	}

    }
}

sub set_alternatives {
   $manual = "manual";
   # Get prefered number
   $preferred = -1;
   for ($i=0; $i<=$#versions; $i++) {
     if($versions[$i] eq $apath) {
       $preferred = $i;
       last;
     }
   }
   if($preferred == -1){
     &quit(sprintf(_g("Cannot find alternative `%s'."), $apath)."\n")
   }
   printf STDOUT _g("Using \`%s' to provide \`%s'.")."\n", $apath, $name;
   symlink("$apath","$altdir/$name.dpkg-tmp") ||
     &quit(sprintf(_g("unable to make %s a symlink to %s: %s"), "$altdir/$name.dpkg-tmp", $apath, $!));
   rename_mv("$altdir/$name.dpkg-tmp","$altdir/$name") ||
     &quit(sprintf(_g("unable to install %s as %s: %s"), "$altdir/$name.dpkg-tmp", "$altdir/$name", $!));
   # Link slaves...
   for( $slnum = 0; $slnum < @slavenames; $slnum++ ) {
     $slave = $slavenames[$slnum];
     if ($slavepath{$preferred,$slnum} ne '') {
       checked_symlink($slavepath{$preferred,$slnum},
		       "$altdir/$slave.dpkg-tmp");
       checked_mv("$altdir/$slave.dpkg-tmp", "$altdir/$slave");
     } else {
       &pr(sprintf(_g("Removing %s (%s), not appropriate with %s."), $slave, $slavelinks[$slnum], $versions[$preferred]))
	 if $verbosemode > 0;
       unlink("$altdir/$slave") || $! == &ENOENT ||
	 &quit(sprintf(_g("unable to remove %s: %s"), "$altdir/$slave", $!));
     }
   }
}

sub pr { print(STDOUT "@_\n") || &quit(sprintf(_g("error writing stdout: %s"), $!)); }
sub paf {
    $_[0] =~ m/\n/ && &quit(sprintf(_g("newlines prohibited in update-alternatives files (%s)"), $_[0]));
    print(AF "$_[0]\n") || &quit(sprintf(_g("error writing stdout: %s"), $!));
}
sub gl {
    $!=0; $_= <AF>;
    length($_) || &quit(sprintf(_g("error or eof reading %s for %s (%s)"), "$admindir/$name", $_[0], $!));
    s/\n$// || &badfmt(sprintf(_g("missing newline after %s"), $_[0]));
    $_;
}
sub badfmt {
    &quit(sprintf(_g("internal error: %s corrupt: %s"), "$admindir/$name", $_[0]));
}
sub rename_mv {
    return (rename($_[0], $_[1]) || (system(("mv", $_[0], $_[1])) == 0));
}
sub checked_symlink {
    my ($filename, $linkname) = @_;
    symlink($filename, $linkname) ||
	&quit(sprintf(_g("unable to make %s a symlink to %s: %s"), $linkname, $filename, $!));
}
sub checked_mv {
    my ($source, $dest) = @_;
    rename_mv($source, $dest) ||
	&quit(sprintf(_g("unable to install %s as %s: %s"), $source, $dest, $!));
}
sub config_all {
    opendir ADMINDIR, $admindir or die sprintf(_g("Serious problem: %s"), $!);
    my @filenames = grep !/^\.\.?$/, readdir ADMINDIR;
    close ADMINDIR;
    foreach my $name (@filenames) {
        system "$0 --config $name";
        exit $? if $?;
    }
    exit(0);
}
exit(0);

# vim: nowrap ts=8 sw=4
