#! /usr/bin/perl
#
# update-rc.d	Perl script to update links in /etc/rc?.d
#
# Usage:
#		update-rc.d [-f] <basename> remove
#		update-rc.d <basename> [options]
#
# Options are:
#		start <codenumber> <runlevel> <runlevel> <runlevel> .
#		stop  <codenumber> <runlevel> <runlevel> <runlevel> .
#
#		defaults [<codenumber> | <startcode> <stopcode>]
#		(means       start <startcode> 2 3 4 5
#		 as well as  stop  <stopcode>  0 1 2 3 4 5 6
#		<codenumber> defaults to 20)
#
# Version:	@(#)update-rc.d  1.02  11-Jul-1996  miquels@cistron.nl
#
# Changes:      1.00 Wrote perl version directly derived from shell version.
#		1.01 Fixed problem when dangling symlinks are found in
#		     /etc/rc?.d/. The shell version just exits silently!
#		1.02 More misc bugs fixed caused by sh -> perl translation
#

$version= '1.3.2'; # This line modified by Makefile

chdir('/etc') || die "chdir /etc: $!\n";

$initd='init.d';

sub usage {
  print STDERR <<EOF;
Debian GNU/Linux update-rc.d $version.  Copyright (C) 1996 Miquel van
Smoorenburg.  This is free software; see the GNU General Public Licence
version 2 or later for copying conditions.  There is NO warranty.

update-rc.d: error: @_
usage: update-rc.d [-f] <basename> remove
       update-rc.d <basename> defaults [<cn> | <scn> <kcn>]
       update-rc.d <basename> start|stop <cn> <r> <r> .  ...
EOF
  &leave(1);
}


sub getinode {
	local @tmp;

	unless (@tmp = stat($_[0])) {
		print STDERR "stat($_[0]): $!\n";
		$tmp[1] = 0;
	}
	$tmp[1];
}

sub leave {
	eval $atexit if ($atexit ne '');
	exit($_[0]);
}

$force = 0;
if ($ARGV[0] eq '-f') {
	shift @ARGV;
	$force = 1;
}

&usage("too few arguments") if ($#ARGV < 1);

$bn = shift @ARGV;
$action = shift @ARGV;

if ($action eq 'remove') {
	&usage("remove must be only action") if ($#ARGV > 0);
	if (-f "$initd/$bn") {
		unless ($force) {
			print STDERR "update-rc.d: error: /etc/$initd/$bn exists during rc.d purge (use -f to force).\n";
			&leave(1);
		}
	} else {
		$atexit = "unlink('$initd/$bn');";
	}
	print  " Removing any system startup links to /etc/$initd/$bn ...\n";
	open(FD, ">>$initd/$bn");
	close FD;
	$own = &getinode("$initd/$bn");
	@files = split(/\s+/, `echo rc?.d/[SK]*`);
	foreach $f (@files) {
		$inode = &getinode($f);
		if ($inode == $own) {
			unless (unlink($f))  {
				print STDERR "unlink($f): $!\n";
				&leave(1);
			}
			print "   $f\n";
		}
	}
	&leave(0);
} elsif ($action eq 'defaults') {
	if ($#ARGV < 0) {
		$sn = $kn = 20;
	} elsif ($#ARGV == 0) {
		$sn = $kn = $ARGV[0];
	} elsif ($#ARGV == 1) {
		$sn = $ARGV[0];
		$kn = $ARGV[1];
	} else {
		&usage("defaults takes only one or two codenumbers");
	}
	@ARGV = ('start', "$sn", '2', '3', '4', '5', 'stop',
			  "$kn", '0', '1', '6');
} elsif ($action ne 'start' && $action ne 'stop') {
	&usage("unknown mode or add action $action");
}

unless (-f "$initd/$bn") {
	print STDERR "update-rc.d: warning /etc/$initd/$bn doesn't exist during rc.d setup.\n";
	exit(0);
}

$own = &getinode("$initd/$bn");

@files = split(/\s+/, `echo rc?.d/[SK]*`);
foreach $f (@files) {
	$inode = &getinode($f);
	if ($inode == $own) {
		print STDERR " System startup links pointing to /etc/$initd/$bn already exist.\n";
		exit(0);
	}
}


print " Adding system startup links pointing to /etc/$initd/$bn ...\n";
while ($#ARGV >= 1) {
	if ($ARGV[0] eq 'start') {
		$ks = 'S';
	} elsif ($ARGV[0] eq 'stop') {
		$ks = 'K';
	} else {
		&usage("unknown action $1");
	}
	shift @ARGV;
	$number = shift @ARGV;
	while ($#ARGV >= 0) {
		$_ = $ARGV[0];
		if (/^\.$/) {
			shift @ARGV;
			last;
		} elsif (/^.$/) {
			symlink("../$initd/$bn", "rc$_.d/$ks$number$bn") ||
				die "symlink: $!\n";
			print "   rc$_.d/$ks$number$bn -> ../$initd/$bn\n";
			shift @ARGV;
			next;
		} elsif (/^(start|stop)$/) {
			last;
		}
		&usage('runlevel is more than one character\n');
	}
}

if ($#ARGV >= 0) {
	&usage("surplus arguments, but not enough for an add action: @ARGV\n");
}

0;
