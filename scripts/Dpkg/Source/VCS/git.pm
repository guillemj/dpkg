#!/usr/bin/perl
# git support for dpkg-source
package Dpkg::Source::VCS::git;

use strict;
use warnings;

use Dpkg;
use Dpkg::Gettext;

push (@INC, $dpkglibdir);
require 'controllib.pl';

# Called before a tarball is created, must add all files that should be in
# it.
sub prep_tar {
	my $srcdir=shift;
	my $tardir=shift;
	
	if (! -e "$srcdir/.git") {
		main::error(sprintf(_g("%s is not a git repository, but Format git was specified"), $srcdir));
	}

	# check for uncommitted files
	open(GIT_STATUS, "LANG=C cd $srcdir && git status |") ||
		main::subprocerr("cd $srcdir && git status");
	my $clean=0;
	my $status="";
	while (<GIT_STATUS>) {
		if (/^\Qnothing to commit (working directory clean)\E$/) {
			$clean=1;
		}
		$status.="git-status: $_";
	}
	close GIT_STATUS;
	# git-status exits 1 if there are uncommitted changes or if
	# the repo is clean, and 0 if there are uncommitted changes
	# listed in the index.
	main::subprocerr("cd $srcdir && git status") if ($? && $? >> 8 != 1);
	if (! $clean) {
		print $status;
		main::warnerror(_g("working directory is not clean"));
	}

	# garbage collect the repo
	system("cd $srcdir && git-gc --prune");
	$? && main::subprocerr("cd $srcdir && git-gc --prune");

	# TODO support for creating a shallow clone for those cases where
	# uploading the whole repo history is not desired
	
	system("cp -a $srcdir/.git $tardir");
	$? && main::subprocerr("cp -a $srcdir/.git $tardir");
}

# Called after a tarball is unpacked, to check out the working copy.
sub post_unpack_tar {
	my $srcdir=shift;
	
	if (! -e "$srcdir/.git") {
		main::error(sprintf(_g("%s is not a git repository"), $srcdir));
	}

	# disable git hooks, as unpacking a source package should not
	# involve running code
	foreach my $hook (glob("$srcdir/.git/hooks/*")) {
		if (-x $hook) {
			main::warning(sprintf(_g("executable bit set on %s; clearing"), $hook));
			chmod(0644 &~ umask(), $hook) ||
				&syserr(sprintf(_g("unable to change permission of `%s'"), $hook));
		}
	}

	# XXX git-reset should be made to run in quiet mode here, but
	# lacks a good way to do it. Bug filed.
	system("cd $srcdir && git-reset --hard");
	$? && main::subprocerr("cd $srcdir && git-reset --hard");
}

1
