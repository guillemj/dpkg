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

	# check for uncommitted files
	open(GIT_STATUS, "LANG=C cd $srcdir && git status |") ||
		subprocerr("cd $srcdir && git status");
	my $clean=0;
	my $status="";
	while (<GIT_STATUS>) {
		if (/^\Qnothing to commit (working directory clean)\E$/) {
			$clean=1;
		}
		$status.=$_;
	}
	close GIT_STATUS;
	# git-status exits 1 if there are uncommitted changes or if
	# the repo is clean, and 0 if there are uncommitted changes
	# listed in the index.
	if ($? && $? >> 8 != 1) {
		print $status;
		warnerror("working directory is not clean (use -W to override this check)");
	}
	# garbage collect the repo
	system("cd $srcdir && git-gc --prune");
	$? && subprocerr("cd $srcdir && git-gc --prune");
	# TODO support for creating a shallow clone for those cases where
	# uploading the whole repo history is not desired
	system("cp -a $srcdir/.git $tardir");
	$? && subprocerr("cp -a $srcdir/.git $tardir");
}

# Called after a tarball is unpacked, to check out the working copy.
sub post_unpack_tar {
	my $srcdir=shift;
	
	# TODO disable git hooks
	# XXX git should be made to run in quiet mode here, but
	# lacks a good way to do it. Bug filed.
	system("cd $srcdir && git-reset --hard");
	$? && subprocerr("cd $srcdir && git-reset --hard");
}

1
