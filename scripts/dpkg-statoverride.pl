#! /usr/bin/perl

use POSIX;
use POSIX qw(:errno_h :signal_h);

$admindir= "/var/lib/dpkg"; # This line modified by Makefile
$version= '1.3.0'; # This line modified by Makefile

$verbose= 1;
$doforce= 0;
$doupdate= 0;
$mode= "";

sub UsageVersion {
	print STDERR <<EOF || &quit("failed to write usage: $!");
Debian dpkg-statoverride $version.
Copyright (C) 2000 Wichert Akkerman.

This is free software; see the GNU General Public Licence version 2 or later
for copying conditions.  There is NO warranty.

Usage:

  dpkg-statoverride [options] --add <owner> <group> <mode> <file>
  dpkg-statoverride [options] --remove <file>
  dpkg-statoverride [options] --list [<glob-pattern>]

Options:
  --update                 immediately update file permissions
  --force                  force an action even if a sanity check fails
  --quiet                  quiet operation, minimal output
  --help                   print this help screen and exit
  --admindir <directory>   set the directory with the statoverride file
EOF
}

sub CheckModeConflict {
	return unless $mode;
	&badusage("two modes specified: $_ and --$mode");
}

while (@ARGV) {
	$_=shift(@ARGV);
	last if m/^--$/;
	if (!m/^-/) {
		unshift(@ARGV,$_); last;
	} elsif (m/^--help$/) {
		&UsageVersion; exit(0);
	} elsif (m/^--update$/) {
		$doupdate=1;
	} elsif (m/^--quiet$/) {
		$verbose=0;
	} elsif (m/^--force$/) {
		$doforce=1;
	} elsif (m/^--admindir$/) {
		@ARGV || &badusage("--admindir needs a directory argument");
		$admindir= shift(@ARGV);
	} elsif (m/^--add$/) {
		&CheckModeConflict;
		$mode= 'add';
	} elsif (m/^--remove$/) {
		&CheckModeConflict;
		$mode= 'remove';
	} elsif (m/^--list$/) {
		&CheckModeConflict;
		$mode= 'list';
	} else {
		&badusage("unknown option \`$_'");
	}
}

$dowrite=0;
$exitcode=0;

&badusage("no mode specified") unless $mode;
&ReadOverrides;

if ($mode eq "add") {
	@ARGV==4 || &badusage("--add needs four arguments");

	$user=$ARGV[0];
	if ($user =~ m/^#([0-9]+)$/) {
	    $uid=$1;
	    &badusage("illegal user $user") if ($uid<0);
	} else {
	    (($name,$pw,$uid)=getpwnam($user)) || &badusage("non-existing user $user");
	}

	$group=$ARGV[1];
	if ($group =~ m/^#([0-9]+)$/) {
	    $gid=$1;
	    &badusage("illegal group $group") if ($gid<0);
	} else {
	    (($name,$pw,$gid)=getgrnam($group)) || &badusage("non-existing group $group");
	}

	$mode= $ARGV[2];
	(($mode<0) or (oct($mode)>07777) or ($mode !~ m/\d+/)) && &badusage("illegal mode $mode");
	$file= $ARGV[3];
	$file =~ m/\n/ && &badusage("file may not contain newlines");
	$file =~ s,/+$,, && print STDERR "stripping trailing /\n";

	if (defined $owner{$file}) {
		print STDERR "An override for \"$file\" already exists, ";
		if ($doforce) {
			print STDERR "but --force specified so lets ignore it.\n";
		} else {
			print STDERR "aborting\n";
			exit(3);
		}
	}
	$owner{$file}=$user;
	$group{$file}=$group;
	$mode{$file}=$mode;
	$dowrite=1;

	if ($doupdate) {
	    if (not -e $file) {
		print STDERR "warning: --update given but $file does not exist\n";
	    } else {
		chown ($uid,$gid,$file) || warn "failed to chown $file: $!\n";
		chmod (oct($mode),$file) || warn "failed to chmod $file: $!\n";
	    }
	}
} elsif ($mode eq "remove") {
	@ARGV==1 || &badusage("--remove needs one arguments");
	$file=$ARGV[0];
	$file =~ s,/+$,, && print STDERR "stripping trailing /\n";
	if (not defined $owner{$file}) {
		print STDERR "No override present.\n";
		exit(0) if ($doforce); 
		exit(2);
	}
	delete $owner{$file};
	delete $group{$file};
	delete $mode{$file};
	$dowrite=1;
	print STDERR "warning: --update is useless for --remove\n" if ($doupdate);
} elsif ($mode eq "list") {
	my (@list,@ilist,$pattern,$file);
	
	@ilist= @ARGV ? @ARGV : ('*');
	while (defined($_=shift(@ilist))) {
		s/\W/\\$&/g;
		s/\\\?/./g;
		s/\\\*/.*/g;
		s,/+$,, && print STDERR "stripping trailing /\n";
		push(@list,"^$_\$");
	}
	$pat= join('|',@list);
	$exitcode=1;
	for $file (keys %owner) {
		next unless ($file =~ m/$pat/o);
		$exitcode=0;
		print "$owner{$file} $group{$file} $mode{$file} $file\n";
	}
}

&WriteOverrides if ($dowrite);

exit($exitcode);

sub ReadOverrides {
	open(SO,"$admindir/statoverride") || &quit("cannot open statoverride: $!");
	while (<SO>) {
		my ($owner,$group,$mode,$file);
		chomp;

		($owner,$group,$mode,$file)=split(' ', $_, 4);
		die "Multiple overrides for \"$file\", aborting"
			if defined $owner{$file};
		$owner{$file}=$owner;
		$group{$file}=$group;
		$mode{$file}=$mode;
	}
	close(SO);
}


sub WriteOverrides {
	my ($file);

	open(SO,">$admindir/statoverride-new") || &quit("cannot open new statoverride file: $!");
	foreach $file (keys %owner) {
		print SO "$owner{$file} $group{$file} $mode{$file} $file\n";
	}
	close(SO);
	chmod(0644, "$admindir/statoverride-new");
	unlink("$admindir/statoverride-old") ||
		$! == ENOENT || &quit("error removing statoverride-old: $!");
	link("$admindir/statoverride","$admindir/statoverride-old") ||
		$! == ENOENT || &quit("error creating new statoverride-old: $!");
	rename("$admindir/statoverride-new","$admindir/statoverride")
		|| &quit("error installing new statoverride: $!");
}


sub quit { print STDERR "dpkg-statoverride: @_\n"; exit(2); }
sub badusage { print STDERR "dpkg-statoverride: @_\n\n"; print("You need --help.\n"); exit(2); }

# vi: ts=8 sw=8 ai si cindent
