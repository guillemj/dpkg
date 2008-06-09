#!/usr/bin/perl --

BEGIN { # Work-around for bug #479711 in perl
    $ENV{PERL_DL_NONLAZY} = 1;
}

use strict;
use warnings;

use POSIX qw(:errno_h);
use Dpkg;
use Dpkg::Gettext;

textdomain("dpkg");

# Global variables:

my $altdir = '/etc/alternatives';
# FIXME: this should not override the previous assignment.
$admindir = $admindir . '/alternatives';

my $verbosemode = 0;

my $action = '';      # Action to perform (display / install / remove / display / auto / config)
my $mode = 'auto';    # Update mode for alternative (manual / auto)
my $state;            # State of alternative:
                      #   expected: alternative with highest priority is the active alternative
                      #   expected-inprogress: busy selecting alternative with highest priority
                      #   unexpected: alternative another alternative is active / error during readlink
                      #   nonexistent: alternative-symlink does not exist

my %versionnum;       # Map from currently available versions into @versions and @priorities
my @versions;         # List of available versions for alternative
my @priorities;       # Map from @version-index to priority

my $best;
my $bestpri;
my $bestnum;

my $link;             # Link we are working with
my $linkname;

my $alink;            # Alternative we are managing (ie the symlink we're making/removing) (install only)
my $name;             # Name of the alternative (the symlink) we are processing
my $apath;            # Path of alternative we are offering
my $apriority;        # Priority of link (only when we are installing an alternative)
my %aslavelink;
my %aslavepath;
my %aslavelinkcount;

my $slink;
my $sname;
my $spath;
my @slavenames;       # List with names of slavelinks
my %slavenum;         # Map from name of slavelink to slave-index (into @slavelinks)
my @slavelinks;       # List of slavelinks (indexed by slave-index)
my %slavepath;        # Map from (@version-index,slavename) to slave-path
my %slavelinkcount;

sub version {
    printf _g("Debian %s version %s.\n"), $progname, $version;

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

<link> is the symlink pointing to %s/<name>.
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
  --verbose                verbose operation, more output.
  --quiet                  quiet operation, minimal output.
  --help                   show this help message.
  --version                show the version.
"), $progname, $altdir;
}

sub quit
{
    printf STDERR "%s: %s\n", $progname, "@_";
    exit(2);
}

sub badusage
{
    printf STDERR "%s: %s\n\n", $progname, "@_";
    &usage;
    exit(2);
}

sub read_link_group
{
    if (open(AF, "$admindir/$name")) {
	$mode = gl("update_mode");
	$mode eq 'auto' || $mode eq 'manual' || badfmt(_g("invalid update mode"));
	$link = gl("link");
	while (($sname = gl("sname")) ne '') {
	    push(@slavenames, $sname);
	    defined($slavenum{$sname}) && badfmt(sprintf(_g("duplicate slave %s"), $sname));
	    $slavenum{$sname} = $#slavenames;
	    $slink = gl("slink");
	    $slink eq $link && badfmt(sprintf(_g("slave link same as main link %s"), $link));
	    $slavelinkcount{$slink}++ && badfmt(sprintf(_g("duplicate slave link %s"), $slink));
	    push(@slavelinks, $slink);
	}
	while (($version = gl("version")) ne '') {
	    defined($versionnum{$version}) && badfmt(sprintf(_g("duplicate path %s"), $version));
	    if (-r $version) {
		push(@versions, $version);
		my $i;
		$versionnum{$version} = $i = $#versions;
		my $priority = gl("priority");
		$priority =~ m/^[-+]?\d+$/ || badfmt(sprintf(_g("priority %s %s"), $version, $priority));
		$priorities[$i] = $priority;
		for (my $j = 0; $j <= $#slavenames; $j++) {
		    $slavepath{$i,$j} = gl("spath");
		}
	    } else {
		# File not found - remove
		pr(sprintf(_g("Alternative for %s points to %s - which wasn't found.  Removing from list of alternatives."), $name, $version))
		    if $verbosemode > 0;
		gl("priority");
		for (my $j = 0; $j <= $#slavenames; $j++) {
		    gl("spath");
		}
	    }
	}
	close(AF);
	return 0;
    } elsif ($! != ENOENT) {
	quit(sprintf(_g("unable to open %s: %s"), "$admindir/$name", $!));
    } elsif ($! == ENOENT) {
	return 1;
    }
}

sub fill_missing_slavepaths()
{
    for (my $j = 0; $j <= $#slavenames; $j++) {
	for (my $i = 0; $i <= $#versions; $i++) {
	    $slavepath{$i,$j} ||= '';
	}
    }
}

sub find_best_version
{
    $best = '';
    for (my $i = 0; $i <= $#versions; $i++) {
	if ($best eq '' || $priorities[$i] > $bestpri) {
	    $best = $versions[$i];
	    $bestpri = $priorities[$i];
	    $bestnum = $i;
	}
    }
}

sub display_link_group
{
    pr(sprintf(_g("%s - status is %s."), $name, $mode));
    $linkname = readlink("$altdir/$name");

    if (defined($linkname)) {
	pr(sprintf(_g(" link currently points to %s"), $linkname));
    } elsif ($! == ENOENT) {
	pr(_g(" link currently absent"));
    } else {
	pr(sprintf(_g(" link unreadable - %s"), $!));
    }

    for (my $i = 0; $i <= $#versions; $i++) {
	pr(sprintf(_g("%s - priority %s"), $versions[$i], $priorities[$i]));
	for (my $j = 0; $j <= $#slavenames; $j++) {
	    my $tspath = $slavepath{$i, $j};
	    next unless length($tspath);
	    pr(sprintf(_g(" slave %s: %s"), $slavenames[$j], $tspath));
	}
    }

    if ($best eq '') {
	pr(_g("No versions available."));
    } else {
	pr(sprintf(_g("Current \`best' version is %s."), $best));
    }
}

sub list_link_group
{
    for (my $i = 0; $i <= $#versions; $i++) {
	pr("$versions[$i]");
    }
}

sub checked_alternative($$$)
{
    my ($name, $link, $path) = @_;

    $linkname = readlink($link);
    if (!defined($linkname) && $! != ENOENT) {
	pr(sprintf(_g("warning: %s is supposed to be a symlink to %s, \n".
	              "or nonexistent; however, readlink failed: %s"),
	           $link, "$altdir/$name", $!))
	    if $verbosemode > 0;
    } elsif (!defined($linkname) ||
            (defined($linkname) && $linkname ne "$altdir/$name")) {
	checked_rm("$link.dpkg-tmp");
	checked_symlink("$altdir/$name", "$link.dpkg-tmp");
	checked_mv("$link.dpkg-tmp", $link);
    }
    $linkname = readlink("$altdir/$name");
    if (defined($linkname) && $linkname eq $path) {
	pr(sprintf(_g("Leaving %s (%s) pointing to %s."), $name, $link, $path))
	    if $verbosemode > 0;
    } else {
	pr(sprintf(_g("Updating %s (%s) to point to %s."), $name, $link, $path))
	    if $verbosemode > 0;
    }
}

sub set_links($$)
{
    my ($spath, $preferred) = (@_);

    printf STDOUT _g("Using '%s' to provide '%s'.") . "\n", $spath, $name;
    checked_symlink("$spath","$altdir/$name.dpkg-tmp");
    checked_mv("$altdir/$name.dpkg-tmp", "$altdir/$name");

    # Link slaves...
    for (my $slnum = 0; $slnum < @slavenames; $slnum++) {
	my $slave = $slavenames[$slnum];
	if ($slavepath{$preferred, $slnum} ne '') {
	    checked_alternative($slave, $slavelinks[$slnum],
	                  $slavepath{$preferred, $slnum});
	    checked_symlink($slavepath{$preferred, $slnum},
	                    "$altdir/$slave.dpkg-tmp");
	    checked_mv("$altdir/$slave.dpkg-tmp", "$altdir/$slave");
	} else {
	    pr(sprintf(_g("Removing %s (%s), not appropriate with %s."), $slave,
	               $slavelinks[$slnum], $versions[$preferred]))
	        if $verbosemode > 0;
	    checked_rm("$altdir/$slave");
	}
    }
}

sub check_many_actions()
{
    return unless $action;
    badusage(sprintf(_g("two commands specified: %s and --%s"), $_, $action));
}

sub checked_rm($)
{
    my ($f) = @_;
    unlink($f) || $! == ENOENT ||
        quit(sprintf(_g("unable to remove %s: %s"), $f, $!));
}

#
# Main program
#

$| = 1;

while (@ARGV) {
    $_= shift(@ARGV);
    last if m/^--$/;
    if (!m/^--/) {
        &quit(sprintf(_g("unknown argument \`%s'"), $_));
    } elsif (m/^--help$/) {
        &usage; exit(0);
    } elsif (m/^--version$/) {
        &version; exit(0);
    } elsif (m/^--verbose$/) {
        $verbosemode= +1;
    } elsif (m/^--quiet$/) {
        $verbosemode= -1;
    } elsif (m/^--install$/) {
	check_many_actions();
        @ARGV >= 4 || &badusage(_g("--install needs <link> <name> <path> <priority>"));
        ($alink,$name,$apath,$apriority,@ARGV) = @ARGV;
        $apriority =~ m/^[-+]?\d+/ || &badusage(_g("priority must be an integer"));
	$action = 'install';
    } elsif (m/^--(remove|set)$/) {
	check_many_actions();
        @ARGV >= 2 || &badusage(sprintf(_g("--%s needs <name> <path>"), $1));
        ($name,$apath,@ARGV) = @ARGV;
	$action = $1;
    } elsif (m/^--(display|auto|config|list|remove-all)$/) {
	check_many_actions();
        @ARGV || &badusage(sprintf(_g("--%s needs <name>"), $1));
	$action = $1;
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
	$action = 'all';
    } else {
        &badusage(sprintf(_g("unknown option \`%s'"), $_));
    }
}

defined($name) && defined($aslavelink{$name}) &&
  badusage(sprintf(_g("name %s is both primary and slave"), $name));
defined($alink) && $aslavelinkcount{$alink} &&
  badusage(sprintf(_g("link %s is both primary and slave"), $alink));

$action ||
  badusage(_g("need --display, --config, --set, --install, --remove, --all, --remove-all or --auto"));
$action eq 'install' || !%aslavelink ||
  badusage(_g("--slave only allowed with --install"));

if ($action eq 'all') {
    &config_all();
    exit 0;
}

if (read_link_group()) {
    if ($action eq 'remove') {
	# FIXME: Be consistent for now with the case when we try to remove a
	# non-existing path from an existing link group file.
	exit 0;
    } elsif ($action ne 'install') {
	pr(sprintf(_g("No alternatives for %s."), $name));
	exit 1;
    }
}

if ($action eq 'display') {
    find_best_version();
    display_link_group();
    exit 0;
}

if ($action eq 'list') {
    list_link_group();
    exit 0;
}

find_best_version();

if ($action eq 'config') {
    config_alternatives($name);
}

if ($action eq 'set') {
    set_alternatives($name);
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
#   $mode        manual, auto
#   $state       expected, expected-inprogress, unexpected, nonexistent
#   $action      auto, install, remove, remove-all
# all independent

if ($action eq 'auto') {
    &pr(sprintf(_g("Setting up automatic selection of %s."), $name))
      if $verbosemode > 0;
    checked_rm("$altdir/$name.dpkg-tmp");
    checked_rm("$altdir/$name");
    $state= 'nonexistent';
    $mode = 'auto';
}

#   $mode        manual, auto
#   $state       expected, expected-inprogress, unexpected, nonexistent
#   $action      auto, install, remove
# action=auto <=> state=nonexistent

if ($state eq 'unexpected' && $mode eq 'auto') {
    &pr(sprintf(_g("%s has been changed (manually or by a script).\n".
                   "Switching to manual updates only."), "$altdir/$name"))
      if $verbosemode > 0;
    $mode = 'manual';
}

#   $mode        manual, auto
#   $state       expected, expected-inprogress, unexpected, nonexistent
#   $action      auto, install, remove
# action=auto <=> state=nonexistent
# state=unexpected => mode=manual

&pr(sprintf(_g("Checking available versions of %s, updating links in %s ...\n".
    "(You may modify the symlinks there yourself if desired - see \`man ln'.)"), $name, $altdir))
  if $verbosemode > 0;

if ($action eq 'install') {
    if (defined($link) && $link ne $alink) {
        &pr(sprintf(_g("Renaming %s link from %s to %s."), $name, $link, $alink))
          if $verbosemode > 0;
        rename_mv($link,$alink) || $! == &ENOENT ||
            &quit(sprintf(_g("unable to rename %s to %s: %s"), $link, $alink, $!));
    }
    $link= $alink;
    my $i;
    if (!defined($i= $versionnum{$apath})) {
        push(@versions,$apath);
        $versionnum{$apath}= $i= $#versions;
    }
    $priorities[$i]= $apriority;
    for $sname (keys %aslavelink) {
        my $j;
        if (!defined($j= $slavenum{$sname})) {
            push(@slavenames,$sname);
            $slavenum{$sname}= $j= $#slavenames;
        }
        my $oldslavelink = $slavelinks[$j];
        my $newslavelink = $aslavelink{$sname};
	$slavelinkcount{$oldslavelink}-- if defined($oldslavelink);
        $slavelinkcount{$newslavelink}++ &&
            &quit(sprintf(_g("slave link name %s duplicated"), $newslavelink));
	if (defined($oldslavelink) && $newslavelink ne $oldslavelink) {
            &pr(sprintf(_g("Renaming %s slave link from %s to %s."), $sname, $oldslavelink, $newslavelink))
              if $verbosemode > 0;
            rename_mv($oldslavelink,$newslavelink) || $! == &ENOENT ||
                &quit(sprintf(_g("unable to rename %s to %s: %s"), $oldslavelink, $newslavelink, $!));
        }
        $slavelinks[$j]= $newslavelink;
    }
    for (my $j = 0; $j <= $#slavenames; $j++) {
        $slavepath{$i,$j}= $aslavepath{$slavenames[$j]};
    }

    fill_missing_slavepaths();
}

if ($action eq 'remove') {
    my $hits = 0;
    if ($mode eq "manual" and $state ne "expected" and (map { $hits += $apath eq $_ } @versions) and $hits and $linkname eq $apath) {
	&pr(_g("Removing manually selected alternative - switching to auto mode"));
	$mode = "auto";
    }
    if (defined(my $i = $versionnum{$apath})) {
        my $k = $#versions;
        $versionnum{$versions[$k]}= $i;
        delete $versionnum{$versions[$i]};
        $versions[$i]= $versions[$k]; $#versions--;
        $priorities[$i]= $priorities[$k]; $#priorities--;
        for (my $j = 0; $j <= $#slavenames; $j++) {
            $slavepath{$i,$j}= $slavepath{$k,$j};
            delete $slavepath{$k,$j};
        }
    } else {
        &pr(sprintf(_g("Alternative %s for %s not registered, not removing."), $apath, $name))
          if $verbosemode > 0;
    }
}

if ($action eq 'remove-all') {
   $mode = "auto";
   my $k = $#versions;
   for (my $i = 0; $i <= $#versions; $i++) {
        $k--;
        delete $versionnum{$versions[$i]};
	$#priorities--;
        for (my $j = 0; $j <= $#slavenames; $j++) {
            $slavepath{$i,$j}= $slavepath{$k,$j};
            delete $slavepath{$k,$j};
        }
      }
   $#versions=$k;
 }


for (my $j = 0; $j <= $#slavenames; $j++) {
    my $i;
    for ($i = 0; $i <= $#versions; $i++) {
        last if $slavepath{$i,$j} ne '';
    }
    if ($i > $#versions) {
        &pr(sprintf(_g("Discarding obsolete slave link %s (%s)."), $slavenames[$j], $slavelinks[$j]))
          if $verbosemode > 0;
        checked_rm("$altdir/$slavenames[$j]");
        checked_rm($slavelinks[$j]);
        my $k = $#slavenames;
        $slavenum{$slavenames[$k]}= $j;
        delete $slavenum{$slavenames[$j]};
        $slavelinkcount{$slavelinks[$j]}--;
        $slavenames[$j]= $slavenames[$k]; $#slavenames--;
        $slavelinks[$j]= $slavelinks[$k]; $#slavelinks--;
        for (my $i = 0; $i <= $#versions; $i++) {
            $slavepath{$i,$j}= $slavepath{$i,$k};
            delete $slavepath{$i,$k};
        }
        $j--;
    }
}
        
if ($mode eq 'manual') {
    &pr(sprintf(_g("Automatic updates of %s are disabled, leaving it alone."), "$altdir/$name"))
      if $verbosemode > 0;
    &pr(sprintf(_g("To return to automatic updates use \`update-alternatives --auto %s'."), $name))
      if $verbosemode > 0;
} else {
    if ($state eq 'expected-inprogress') {
        &pr(sprintf(_g("Recovering from previous failed update of %s ..."), $name));
	checked_mv("$altdir/$name.dpkg-tmp", "$altdir/$name");
        $state= 'expected';
    }
}

#   $mode        manual, auto
#   $state       expected, expected-inprogress, unexpected, nonexistent
#   $action      auto, install, remove
# action=auto <=> state=nonexistent
# state=unexpected => mode=manual
# mode=auto => state!=expected-inprogress && state!=unexpected

open(AF,">$admindir/$name.dpkg-new") ||
    &quit(sprintf(_g("unable to open %s for write: %s"), "$admindir/$name.dpkg-new", $!));
paf($mode);
&paf($link);
for (my $j = 0; $j <= $#slavenames; $j++) {
    &paf($slavenames[$j]);
    &paf($slavelinks[$j]);
}

find_best_version();

&paf('');
for (my $i = 0; $i <= $#versions; $i++) {
    &paf($versions[$i]);
    &paf($priorities[$i]);
    for (my $j = 0; $j <= $#slavenames; $j++) {
        &paf($slavepath{$i,$j});
    }
}
&paf('');
close(AF) || &quit(sprintf(_g("unable to close %s: %s"), "$admindir/$name.dpkg-new", $!));

if ($mode eq 'auto') {
    if ($best eq '') {
        &pr(sprintf(_g("Last package providing %s (%s) removed, deleting it."), $name, $link))
          if $verbosemode > 0;
        checked_rm("$altdir/$name");
        checked_rm("$link");
        checked_rm("$admindir/$name.dpkg-new");
        checked_rm("$admindir/$name");
        exit(0);
    } else {
	checked_alternative($name, $link, $best);
        checked_rm("$altdir/$name.dpkg-tmp");
        symlink($best,"$altdir/$name.dpkg-tmp");
    }
}

checked_mv("$admindir/$name.dpkg-new", "$admindir/$name");

if ($mode eq 'auto') {
    checked_mv("$altdir/$name.dpkg-tmp", "$altdir/$name");
    for (my $j = 0; $j <= $#slavenames; $j++) {
        $sname= $slavenames[$j];
        $slink= $slavelinks[$j];
        $spath= $slavepath{$bestnum,$j};
        checked_rm("$altdir/$sname.dpkg-tmp");
        if ($spath eq '') {
            &pr(sprintf(_g("Removing %s (%s), not appropriate with %s."), $sname, $slink, $best))
              if $verbosemode > 0;
            checked_rm("$altdir/$sname");
            checked_rm("$slink");
        } else {
	    checked_alternative($sname, $slink, $spath);
	    checked_symlink("$spath", "$altdir/$sname.dpkg-tmp");
	    checked_mv("$altdir/$sname.dpkg-tmp", "$altdir/$sname");
        }
    }
}

sub config_message {
    if ($#versions < 0) {
	print "\n";
	printf _g("There is no program which provides %s.\n".
	          "Nothing to configure.\n"), $name;
	return -1;
    }
    if ($#versions == 0) {
	print "\n";
	printf _g("There is only 1 program which provides %s\n".
	          "(%s). Nothing to configure.\n"), $name, $versions[0];
	return -1;
    }
    print STDOUT "\n";
    printf(STDOUT _g("There are %s alternatives which provide \`%s'.\n\n".
                     "  Selection    Alternative\n".
                     "-----------------------------------------------\n"),
                  $#versions+1, $name);
    for (my $i = 0; $i <= $#versions; $i++) {
	printf(STDOUT "%s%s %8s    %s\n",
	    (readlink("$altdir/$name") eq $versions[$i]) ? '*' : ' ',
	    ($best eq $versions[$i]) ? '+' : ' ',
	    $i+1, $versions[$i]);
    }
    printf(STDOUT "\n"._g("Press enter to keep the default[*], or type selection number: "));
    return 0;
}

sub config_alternatives {
    my $preferred;
    do {
	return if config_message() < 0;
	$preferred=<STDIN>;
	chop($preferred);
    } until $preferred eq '' || $preferred>=1 && $preferred<=$#versions+1 &&
	($preferred =~ m/[0-9]*/);
    if ($preferred ne '') {
	$mode = "manual";
	$preferred--;
	my $spath = $versions[$preferred];

	set_links($spath, $preferred);
    }
}

sub set_alternatives {
   $mode = "manual";
   # Get prefered number
   my $preferred = -1;
   for (my $i = 0; $i <= $#versions; $i++) {
     if($versions[$i] eq $apath) {
       $preferred = $i;
       last;
     }
   }
   if($preferred == -1){
     &quit(sprintf(_g("Cannot find alternative `%s'."), $apath)."\n")
   }
   set_links($apath, $preferred);
}

sub pr { print(STDOUT "@_\n") || &quit(sprintf(_g("error writing stdout: %s"), $!)); }
sub paf {
    $_[0] =~ m/\n/ && &quit(sprintf(_g("newlines prohibited in update-alternatives files (%s)"), $_[0]));
    print(AF "$_[0]\n") || &quit(sprintf(_g("error writing stdout: %s"), $!));
}
sub gl {
    $!=0; $_= <AF>;
    defined($_) || quit(sprintf(_g("error or eof reading %s for %s (%s)"),
                                "$admindir/$name", $_[0], $!));
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
}
exit(0);

# vim: nowrap ts=8 sw=4
