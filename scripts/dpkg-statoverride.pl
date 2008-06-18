#! /usr/bin/perl

BEGIN { # Work-around for bug #479711 in perl
    $ENV{PERL_DL_NONLAZY} = 1;
}

use strict;
use warnings;

use POSIX;
use POSIX qw(:errno_h :signal_h);
use Dpkg;
use Dpkg::Gettext;

textdomain("dpkg");

my $verbose = 1;
my $doforce = 0;
my $doupdate = 0;
my $mode = "";

my %owner;
my %group;
my %mode;

sub version {
	printf _g("Debian %s version %s.\n"), $progname, $version;

	printf _g("
Copyright (C) 2000 Wichert Akkerman.");

	printf _g("
This is free software; see the GNU General Public Licence version 2 or
later for copying conditions. There is NO warranty.
");
}

sub usage {
	printf _g(
"Usage: %s [<option> ...] <command>

Commands:
  --add <owner> <group> <mode> <file>
                           add a new entry into the database.
  --remove <file>          remove file from the database.
  --list [<glob-pattern>]  list current overrides in the database.

Options:
  --admindir <directory>   set the directory with the statoverride file.
  --update                 immediately update file permissions.
  --force                  force an action even if a sanity check fails.
  --quiet                  quiet operation, minimal output.
  --help                   show this help message.
  --version                show the version.
"), $progname;
}

sub CheckModeConflict {
	return unless $mode;
	badusage(sprintf(_g("two commands specified: %s and --%s"), $_, $mode));
}

while (@ARGV) {
	$_=shift(@ARGV);
	last if m/^--$/;
	if (!m/^-/) {
		unshift(@ARGV,$_); last;
	} elsif (m/^--help$/) {
		&usage; exit(0);
	} elsif (m/^--version$/) {
		&version; exit(0);
	} elsif (m/^--update$/) {
		$doupdate=1;
	} elsif (m/^--quiet$/) {
		$verbose=0;
	} elsif (m/^--force$/) {
		$doforce=1;
	} elsif (m/^--admindir$/) {
		@ARGV || &badusage(sprintf(_g("--%s needs a <directory> argument"), "admindir"));
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
		&badusage(sprintf(_g("unknown option \`%s'"), $_));
	}
}

my $dowrite = 0;
my $exitcode = 0;

&badusage(_g("no mode specified")) unless $mode;
&ReadOverrides;

if ($mode eq "add") {
	@ARGV==4 || &badusage(_g("--add needs four arguments"));

	my $user = $ARGV[0];
	my $uid = 0;
	my $gid = 0;

	if ($user =~ m/^#([0-9]+)$/) {
	    $uid=$1;
	    &badusage(sprintf(_g("illegal user %s"), $user)) if ($uid<0);
	} else {
	    my ($name, $pw);
	    (($name,$pw,$uid)=getpwnam($user)) || &badusage(sprintf(_g("non-existing user %s"), $user));
	}

	my $group = $ARGV[1];
	if ($group =~ m/^#([0-9]+)$/) {
	    $gid=$1;
	    &badusage(sprintf(_g("illegal group %s"), $group)) if ($gid<0);
	} else {
	    my ($name, $pw);
	    (($name,$pw,$gid)=getgrnam($group)) || &badusage(sprintf(_g("non-existing group %s"), $group));
	}

	my $mode = $ARGV[2];
	(($mode<0) or (oct($mode)>07777) or ($mode !~ m/\d+/)) && &badusage(sprintf(_g("illegal mode %s"), $mode));
	my $file = $ARGV[3];
	$file =~ m/\n/ && &badusage(_g("file may not contain newlines"));
	$file =~ s,/+$,, && print STDERR _g("stripping trailing /")."\n";

	if (defined $owner{$file}) {
		printf STDERR _g("An override for \"%s\" already exists, "), $file;
		if ($doforce) {
			print STDERR _g("but --force specified so will be ignored.")."\n";
		} else {
			print STDERR _g("aborting")."\n";
			exit(3);
		}
	}
	$owner{$file}=$user;
	$group{$file}=$group;
	$mode{$file}=$mode;
	$dowrite=1;

	if ($doupdate) {
	    if (not -e $file) {
		printf STDERR _g("warning: --update given but %s does not exist")."\n", $file;
	    } else {
		chown ($uid,$gid,$file) || warn sprintf(_g("failed to chown %s: %s"), $file, $!)."\n";
		chmod (oct($mode),$file) || warn sprintf(_g("failed to chmod %s: %s"), $file, $!)."\n";
	    }
	}
} elsif ($mode eq "remove") {
	@ARGV==1 || &badusage(sprintf(_g("--%s needs a single argument"), "remove"));
	my $file = $ARGV[0];
	$file =~ s,/+$,, && print STDERR _g("stripping trailing /")."\n";
	if (not defined $owner{$file}) {
		print STDERR _g("No override present.")."\n";
		exit(0) if ($doforce); 
		exit(2);
	}
	delete $owner{$file};
	delete $group{$file};
	delete $mode{$file};
	$dowrite=1;
	print(STDERR _g("warning: --update is useless for --remove")."\n") if ($doupdate);
} elsif ($mode eq "list") {
	my (@list, @ilist);

	@ilist= @ARGV ? @ARGV : ('*');
	while (defined($_=shift(@ilist))) {
		s/\W/\\$&/g;
		s/\\\?/./g;
		s/\\\*/.*/g;
		s,/+$,, && print STDERR _g("stripping trailing /")."\n";
		push(@list,"^$_\$");
	}

	my $pattern = join('|', @list);
	$exitcode=1;
	for my $file (keys %owner) {
		next unless ($file =~ m/$pattern/o);
		$exitcode=0;
		print "$owner{$file} $group{$file} $mode{$file} $file\n";
	}
}

&WriteOverrides if ($dowrite);

exit($exitcode);

sub ReadOverrides {
	open(SO,"$admindir/statoverride") || &quit(sprintf(_g("cannot open statoverride: %s"), $!));
	while (<SO>) {
		my ($owner,$group,$mode,$file);
		chomp;

		($owner,$group,$mode,$file)=split(' ', $_, 4);
		die sprintf(_g("Multiple overrides for \"%s\", aborting"), $file)
			if defined $owner{$file};
		$owner{$file}=$owner;
		$group{$file}=$group;
		$mode{$file}=$mode;
	}
	close(SO);
}


sub WriteOverrides {
	my ($file);

	open(SO,">$admindir/statoverride-new") || &quit(sprintf(_g("cannot open new statoverride file: %s"), $!));
	foreach $file (keys %owner) {
		print SO "$owner{$file} $group{$file} $mode{$file} $file\n";
	}
	close(SO);
	chmod(0644, "$admindir/statoverride-new");
	unlink("$admindir/statoverride-old") ||
		$! == ENOENT || &quit(sprintf(_g("error removing statoverride-old: %s"), $!));
	link("$admindir/statoverride","$admindir/statoverride-old") ||
		$! == ENOENT || &quit(sprintf(_g("error creating new statoverride-old: %s"), $!));
	rename("$admindir/statoverride-new","$admindir/statoverride")
		|| &quit(sprintf(_g("error installing new statoverride: %s"), $!));
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

# vi: ts=8 sw=8 ai si cindent
