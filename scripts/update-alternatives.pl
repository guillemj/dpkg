#!/usr/bin/perl --

$admindir= "/var/lib/dpkg"; # This line modified by Makefile
$dpkglibdir= "../utils"; # This line modified by Makefile
$version= '0.93.80'; # This line modified by Makefile

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

$enoent=`$dpkglibdir/enoent` || die "Cannot get ENOENT value from $dpkglibdir/enoent: $!";
sub ENOENT { $enoent; }

sub usageversion {
    print(STDERR <<END)
Debian update-alternatives $version.
Copyright (C) 1995 Ian Jackson.
Copyright (C) 2000-2002 Wichert Akkerman
This is free software; see the GNU General Public Licence
version 2 or later for copying conditions.  There is NO warranty.

Usage: update-alternatives --install <link> <name> <path> <priority>
                          [--slave <link> <name> <path>] ...
       update-alternatives --remove <name> <path>
       update-alternatives --auto <name>
       update-alternatives --display <name>
       update-alternatives --list <name>
       update-alternatives --config <name>
<name> is the name in /etc/alternatives.
<path> is the name referred to.
<link> is the link pointing to /etc/alternatives/<name>.
<priority> is an integer; options with higher numbers are chosen.

Options:  --verbose|--quiet  --test  --help  --version
          --altdir <directory>  --admindir <directory>
END
        || &quit("failed to write usage: $!");
}
sub quit { print STDERR "update-alternatives: @_\n"; exit(2); }
sub badusage { print STDERR "update-alternatives: @_\n\n"; &usageversion; exit(2); }

$altdir= '/etc/alternatives';
$admindir= $admindir . '/alternatives';
$testmode= 0;
$verbosemode= 0;
$mode='';
$manual= 'auto';
$|=1;

sub checkmanymodes {
    return unless $mode;
    &badusage("two modes specified: $_ and --$mode");
}

while (@ARGV) {
    $_= shift(@ARGV);
    last if m/^--$/;
    if (!m/^--/) {
        &quit("unknown argument \`$_'");
    } elsif (m/^--(help|version)$/) {
        &usageversion; exit(0);
    } elsif (m/^--test$/) {
        $testmode= 1;
    } elsif (m/^--verbose$/) {
        $verbosemode= +1;
    } elsif (m/^--quiet$/) {
        $verbosemode= -1;
    } elsif (m/^--install$/) {
        &checkmanymodes;
        @ARGV >= 4 || &badusage("--install needs <link> <name> <path> <priority>");
        ($alink,$name,$apath,$apriority,@ARGV) = @ARGV;
        $apriority =~ m/^[-+]?\d+/ || &badusage("priority must be an integer");
        $mode= 'install';
    } elsif (m/^--remove$/) {
        &checkmanymodes;
        @ARGV >= 2 || &badusage("--remove needs <name> <path>");
        ($name,$apath,@ARGV) = @ARGV;
        $mode= 'remove';
    } elsif (m/^--(display|auto|config|list)$/) {
        &checkmanymodes;
        @ARGV || &badusage("--$1 needs <name>");
        $mode= $1;
        $name= shift(@ARGV);
    } elsif (m/^--slave$/) {
        @ARGV >= 3 || &badusage("--slave needs <link> <name> <path>");
        ($slink,$sname,$spath,@ARGV) = @ARGV;
        defined($aslavelink{$sname}) && &badusage("slave name $sname duplicated");
        $aslavelinkcount{$slink}++ && &badusage("slave link $slink duplicated");
        $aslavelink{$sname}= $slink;
        $aslavepath{$sname}= $spath;
    } elsif (m/^--altdir$/) {
        @ARGV || &badusage("--altdir needs a <directory> argument");
        $altdir= shift(@ARGV);
    } elsif (m/^--admindir$/) {
        @ARGV || &badusage("--admindir needs a <directory> argument");
        $admindir= shift(@ARGV);
    } else {
        &badusage("unknown option \`$_'");
    }
}

defined($aslavelink{$name}) && &badusage("name $name is both primary and slave");
$aslavelinkcount{$alink} && &badusage("link $link is both primary and slave");

$mode || &badusage("need --display, --config, --install, --remove or --auto");
$mode eq 'install' || !%slavelink || &badusage("--slave only allowed with --install");

if (open(AF,"$admindir/$name")) {
    $manual= &gl("manflag");
    $manual eq 'auto' || $manual eq 'manual' || &badfmt("manflag");
    $link= &gl("link");
    while (($sname= &gl("sname")) ne '') {
        push(@slavenames,$sname);
        defined($slavenum{$sname}) && &badfmt("duplicate slave $tsname");
        $slavenum{$sname}= $#slavenames;
        $slink= &gl("slink");
        $slink eq $link && &badfmt("slave link same as main link $link");
        $slavelinkcount{$slink}++ && &badfmt("duplicate slave link $slink");
        push(@slavelinks,$slink);
    }
    while (($version= &gl("version")) ne '') {
        defined($versionnum{$version}) && &badfmt("duplicate path $tver");
       if ( -r $version ) {
           push(@versions,$version);
           $versionnum{$version}= $i= $#versions;
           $priority= &gl("priority");
           $priority =~ m/^[-+]?\d+$/ || &badfmt("priority $version $priority");
           $priorities[$i]= $priority;
           for ($j=0; $j<=$#slavenames; $j++) {
               $slavepath{$i,$j}= &gl("spath");
           }
       } else {
           # File not found - remove
           &pr("Alternative for $name points to $version - which wasn't found.  Removing from list of alternatives.")
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
    &quit("failed to open $admindir/$name: $!");
}

if ($mode eq 'display') {
    if (!$dataread) {
        &pr("No alternatives for $name.");
	exit 1;
    } else {
        &pr("$name - status is $manual.");
        if (defined($linkname= readlink("$altdir/$name"))) {
            &pr(" link currently points to $linkname");
        } elsif ($! == &ENOENT) {
            &pr(" link currently absent");
        } else {
            &pr(" link unreadable - $!");
        }
        $best= '';
        for ($i=0; $i<=$#versions; $i++) {
            if ($best eq '' || $priorities[$i] > $bestpri) {
                $best= $versions[$i]; $bestpri= $priorities[$i];
            }
            &pr("$versions[$i] - priority $priorities[$i]");
            for ($j=0; $j<=$#slavenames; $j++) {
                next unless length($tspath= $slavepath{$i,$j});
                &pr(" slave $slavenames[$j]: $tspath");
            }
        }
        if ($best eq '') {
            &pr("No versions available.");
        } else {
            &pr("Current \`best' version is $best.");
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
	&pr("No alternatives for $name.");
    } else {
	&config_alternatives($name);
    }
}

if (defined($linkname= readlink("$altdir/$name"))) {
    if ($linkname eq $best) {
        $state= 'expected';
    } elsif (defined($linkname2= readlink("$altdir/$name.dpkg-tmp"))) {
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
#   $mode        auto, install, remove
# all independent

if ($mode eq 'auto') {
    &pr("Setting up automatic selection of $name.")
      if $verbosemode > 0;
    unlink("$altdir/$name.dpkg-tmp") || $! == &ENOENT ||
        &quit("unable to remove $altdir/$name.dpkg-tmp: $!");
    unlink("$altdir/$name") || $! == &ENOENT ||
        &quit("unable to remove $altdir/$name.dpkg-tmp: $!");
    $state= 'nonexistent';
    $manual= 'auto';
}

#   $manual      manual, auto
#   $state       expected, expected-inprogress, unexpected, nonexistent
#   $mode        auto, install, remove
# mode=auto <=> state=nonexistent

if ($state eq 'unexpected' && $manual eq 'auto') {
    &pr("$altdir/$name has been changed (manually or by a script).\n".
        "Switching to manual updates only.")
      if $verbosemode > 0;
    $manual= 'manual';
}

#   $manual      manual, auto
#   $state       expected, expected-inprogress, unexpected, nonexistent
#   $mode        auto, install, remove
# mode=auto <=> state=nonexistent
# state=unexpected => manual=manual

&pr("Checking available versions of $name, updating links in $altdir ...\n".
    "(You may modify the symlinks there yourself if desired - see \`man ln'.)")
  if $verbosemode > 0;

if ($mode eq 'install') {
    if ($link ne $alink && $link ne '') {
        &pr("Renaming $name link from $link to $alink.")
          if $verbosemode > 0;
        rename_mv($link,$alink) || $! == &ENOENT ||
            &quit("unable to rename $link to $alink: $!");
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
            &quit("slave link name $newslavelink duplicated");
        if ($newslavelink ne $oldslavelink && $oldslavelink ne '') {
            &pr("Renaming $sname slave link from $oldslavelink to $newslavelink.")
              if $verbosemode > 0;
            rename_mv($oldslavelink,$newslavelink) || $! == &ENOENT ||
                &quit("unable to rename $oldslavelink to $newslavelink: $!");
        }
        $slavelinks[$j]= $newslavelink;
    }
    for ($j=0; $j<=$#slavenames; $j++) {
        $slavepath{$i,$j}= $aslavepath{$slavenames[$j]};
    }
}

if ($mode eq 'remove') {
    if ($manual eq "manual" and $state eq "expected") {
    	&pr("Removing manually selected alternative - switching to auto mode");
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
        &pr("Alternative $apath for $name not registered, not removing.")
          if $verbosemode > 0;
    }
}

for ($j=0; $j<=$#slavenames; $j++) {
    for ($i=0; $i<=$#versions; $i++) {
        last if $slavepath{$i,$j} ne '';
    }
    if ($i > $#versions) {
        &pr("Discarding obsolete slave link $slavenames[$j] ($slavelinks[$j]).")
          if $verbosemode > 0;
        unlink("$altdir/$slavenames[$j]") || $! == &ENOENT ||
            &quit("unable to remove $slavenames[$j]: $!");
        unlink($slavelinks[$j]) || $! == &ENOENT ||
            &quit("unable to remove $slavelinks[$j]: $!");
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
    &pr("Automatic updates of $altdir/$name are disabled, leaving it alone.")
      if $verbosemode > 0;
    &pr("To return to automatic updates use \`update-alternatives --auto $name'.")
      if $verbosemode > 0;
} else {
    if ($state eq 'expected-inprogress') {
        &pr("Recovering from previous failed update of $name ...");
        rename_mv("$altdir/$name.dpkg-tmp","$altdir/$name") ||
            &quit("unable to rename $altdir/$name.dpkg-tmp to $altdir/$name: $!");
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
    &quit("unable to open $admindir/$name.dpkg-new for write: $!");
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
close(AF) || &quit("unable to close $admindir/$name.dpkg-new: $!");

if ($manual eq 'auto') {
    if ($best eq '') {
        &pr("Last package providing $name ($link) removed, deleting it.")
          if $verbosemode > 0;
        unlink("$altdir/$name") || $! == &ENOENT ||
            &quit("unable to remove $altdir/$name: $!");
        unlink("$link") || $! == &ENOENT ||
            &quit("unable to remove $altdir/$name: $!");
        unlink("$admindir/$name.dpkg-new") ||
            &quit("unable to remove $admindir/$name.dpkg-new: $!");
        unlink("$admindir/$name") || $! == &ENOENT ||
            &quit("unable to remove $admindir/$name: $!");
        exit(0);
    } else {
        if (!defined($linkname= readlink($link)) && $! != &ENOENT) {
            &pr("warning: $link is supposed to be a symlink to $altdir/$name\n".
                " (or nonexistent); however, readlink failed: $!")
              if $verbosemode > 0;
        } elsif ($linkname ne "$altdir/$name") {
            unlink("$link.dpkg-tmp") || $! == &ENOENT ||
                &quit("unable to ensure $link.dpkg-tmp nonexistent: $!");
            symlink("$altdir/$name","$link.dpkg-tmp") ||
                &quit("unable to make $link.dpkg-tmp a symlink to $altdir/$name: $!");
            rename_mv("$link.dpkg-tmp",$link) ||
                &quit("unable to install $link.dpkg-tmp as $link: $!");
        }
        if (defined($linkname= readlink("$altdir/$name")) && $linkname eq $best) {
            &pr("Leaving $name ($link) pointing to $best.")
              if $verbosemode > 0;
        } else {
            &pr("Updating $name ($link) to point to $best.")
              if $verbosemode > 0;
        }
        unlink("$altdir/$name.dpkg-tmp") || $! == &ENOENT ||
            &quit("unable to ensure $altdir/$name.dpkg-tmp nonexistent: $!");
        symlink($best,"$altdir/$name.dpkg-tmp");
    }
}

rename_mv("$admindir/$name.dpkg-new","$admindir/$name") ||
    &quit("unable to rename $admindir/$name.dpkg-new to $admindir/$name: $!");

if ($manual eq 'auto') {
    rename_mv("$altdir/$name.dpkg-tmp","$altdir/$name") ||
        &quit("unable to install $altdir/$name.dpkg-tmp as $altdir/$name");
    for ($j=0; $j<=$#slavenames; $j++) {
        $sname= $slavenames[$j];
        $slink= $slavelinks[$j];
        if (!defined($linkname= readlink($slink)) && $! != &ENOENT) {
            &pr("warning: $slink is supposed to be a slave symlink to\n".
                " $altdir/$sname, or nonexistent; however, readlink failed: $!")
              if $verbosemode > 0;
        } elsif ($linkname ne "$altdir/$sname") {
            unlink("$slink.dpkg-tmp") || $! == &ENOENT ||
                &quit("unable to ensure $slink.dpkg-tmp nonexistent: $!");
            symlink("$altdir/$sname","$slink.dpkg-tmp") ||
                &quit("unable to make $slink.dpkg-tmp a symlink to $altdir/$sname: $!");
            rename_mv("$slink.dpkg-tmp",$slink) ||
                &quit("unable to install $slink.dpkg-tmp as $slink: $!");
        }
        $spath= $slavepath{$bestnum,$j};
        unlink("$altdir/$sname.dpkg-tmp") || $! == &ENOENT ||
            &quit("unable to ensure $altdir/$sname.dpkg-tmp nonexistent: $!");
        if ($spath eq '') {
            &pr("Removing $sname ($slink), not appropriate with $best.")
              if $verbosemode > 0;
            unlink("$altdir/$sname") || $! == &ENOENT ||
                &quit("unable to remove $altdir/$sname: $!");
	    unlink("$slink") || $! == &ENOENT ||
	        &quit("unable to remove $slink: $!");
        } else {
            if (defined($linkname= readlink("$altdir/$sname")) && $linkname eq $spath) {
                &pr("Leaving $sname ($slink) pointing to $spath.")
                  if $verbosemode > 0;
            } else {
                &pr("Updating $sname ($slink) to point to $spath.")
                  if $verbosemode > 0;
            }
            symlink("$spath","$altdir/$sname.dpkg-tmp") ||
                &quit("unable to make $altdir/$sname.dpkg-tmp a symlink to $spath: $!");
            rename_mv("$altdir/$sname.dpkg-tmp","$altdir/$sname") ||
                &quit("unable to install $altdir/$sname.dpkg-tmp as $altdir/$sname: $!");
        }
    }
}

sub config_message {
    if ($#versions == 0) {
	print "\nThere is only 1 program which provides $name\n";
	print "($versions[0]). Nothing to configure.\n";
	return;
    }
    printf(STDOUT "\nThere are %s alternatives which provide \`$name'.\n\n", $#versions+1);
    printf(STDOUT "  Selection    Alternative\n");
    printf(STDOUT "-----------------------------------------------\n");
    for ($i=0; $i<=$#versions; $i++) {
	printf(STDOUT "%s%s    %s        %s\n", 
	    (readlink("$altdir/$name") eq $versions[$i]) ? '*' : ' ',
	    ($best eq $versions[$i]) ? '+' : ' ',
	    $i+1, $versions[$i]);
    }
    printf(STDOUT "\nEnter to keep the default[*], or type selection number: ");
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
	print STDOUT "Using \`$versions[$preferred]' to provide \`$name'.\n";
	my $spath = $versions[$preferred];
	symlink("$spath","$altdir/$name.dpkg-tmp") ||
	    &quit("unable to make $altdir/$name.dpkg-tmp a symlink to $spath: $!");
	rename_mv("$altdir/$name.dpkg-tmp","$altdir/$name") ||
	    &quit("unable to install $altdir/$name.dpkg-tmp as $altdir/$name: $!");
	# Link slaves...
	for( my $slnum = 0; $slnum < @slavenames; $slnum++ ) {
	    my $slave = $slavenames[$slnum];
	    if ($slavepath{$preferred,$slnum} ne '') {
		checked_symlink($slavepath{$preferred,$slnum},
			"$altdir/$slave.dpkg-tmp");
		checked_mv("$altdir/$slave.dpkg-tmp", "$altdir/$slave");
	    } else {
		&pr("Removing $slave ($slavelinks[$slnum]), not appropriate with $versions[$preferred].")
		    if $verbosemode > 0;
		unlink("$altdir/$slave") || $! == &ENOENT ||
		    &quit("unable to remove $altdir/$slave: $!");
	    }
	}

    }
}

sub pr { print(STDOUT "@_\n") || &quit("error writing stdout: $!"); }
sub paf {
    $_[0] =~ m/\n/ && &quit("newlines prohibited in update-alternatives files ($_[0])");
    print(AF "$_[0]\n") || &quit("error writing stdout: $!");
}
sub gl {
    $!=0; $_= <AF>;
    length($_) || &quit("error or eof reading $admindir/$name for $_[0] ($!)");
    s/\n$// || &badfmt("missing newline after $_[0]");
    $_;
}
sub badfmt {
    &quit("internal error: $admindir/$name corrupt: $_[0]");
}
sub rename_mv {
    return (rename($_[0], $_[1]) || (system(("mv", $_[0], $_[1])) == 0));
}
sub checked_symlink {
    my ($filename, $linkname) = @_;
    symlink($filename, $linkname) ||
	&quit("unable to make $linkname a symlink to $filename: $!");
}
sub checked_mv {
    my ($source, $dest) = @_;
    rename_mv($source, $dest) ||
	&quit("unable to install $source as $dest: $!");
}

exit(0);

# vim: nowrap ts=8 sw=4
