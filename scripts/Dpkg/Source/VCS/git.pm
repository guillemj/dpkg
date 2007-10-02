#!/usr/bin/perl
# git support for dpkg-source
package Dpkg::Source::VCS::git;

use strict;
use warnings;

use Dpkg;
use Dpkg::Gettext;

push (@INC, $dpkglibdir);
require 'controllib.pl';

sub populate_tarball {
	my $srcdir=shift;
	my $tardir=shift;

	# TODO check for uncommitted files
	# TODO run git-gc --prune first
	# TODO support for creating a shallow clone for those cases where
	# uploading the whole repo history is not desired
	system("cp -a $srcdir/.git $tardir");
	$? && subprocerr("cp -a $srcdir/.git $tardir");
}

sub initialize_repo {
	my $srcdir=shift;
	
	# TODO disable git hooks
	# XXX git should be made to run in quiet mode here, but
	# lacks a good way to do it. Bug filed.
	system("cd $srcdir && git-reset --hard");
	$? && subprocerr("cd $srcdir && git-reset --hard");
}

1
