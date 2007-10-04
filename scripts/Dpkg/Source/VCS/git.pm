#!/usr/bin/perl
#
# git support for dpkg-source
#
# Copyright © 2007 Joey Hess <joeyh@debian.org>.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307 USA
package Dpkg::Source::VCS::git;

use strict;
use warnings;
use Cwd;
use Dpkg;
use Dpkg::Gettext;

push (@INC, $dpkglibdir);
require 'controllib.pl';

# Remove variables from the environment that might cause git to do
# something unexpected.
delete $ENV{GIT_DIR};
delete $ENV{GIT_INDEX_FILE};
delete $ENV{GIT_OBJECT_DIRECTORY};
delete $ENV{GIT_ALTERNATE_OBJECT_DIRECTORIES};
delete $ENV{GIT_WORK_TREE};

# Called before a tarball is created, to prepare the tar directory.
sub prep_tar {
	my $srcdir=shift;
	my $tardir=shift;
	
	if (! -e "$srcdir/.git") {
		main::error(sprintf(_g("%s is not a git repository, but Format git was specified"), $srcdir));
	}

	# Check for uncommitted files.
	open(GIT_STATUS, "LANG=C cd $srcdir && git status |") ||
		main::subprocerr("cd $srcdir && git status");
	my $clean=0;
	my $status="";
	while (<GIT_STATUS>) {
		if (/^\Qnothing to commit (working directory clean)\E$/) {
			$clean=1;
		}
		else {
			$status.="git-status: $_";
		}
	}
	close GIT_STATUS;
	# git-status exits 1 if there are uncommitted changes or if
	# the repo is clean, and 0 if there are uncommitted changes
	# listed in the index.
	if ($? && $? >> 8 != 1) {
		main::subprocerr("cd $srcdir && git status");
	}
	if (! $clean) {
		print $status;
		main::error(_g("uncommitted changed in working directory"));
	}

	# garbage collect the repo
	system("cd $srcdir && git-gc --prune");
	$? && main::subprocerr("cd $srcdir && git-gc --prune");

	# TODO support for creating a shallow clone for those cases where
	# uploading the whole repo history is not desired
	
	system("cp -a $srcdir/.git $tardir");
	$? && main::subprocerr("cp -a $srcdir/.git $tardir");

	# As an optimisation, remove the index. It will be recreated by git
	# reset during unpack. It's probably small, but you never know, this
	# might save a lot of space.
	unlink("$tardir/.git/index"); # error intentionally ignored
}

# Called after a tarball is unpacked, to check out the working copy.
sub post_unpack_tar {
	my $srcdir=shift;
	
	if (! -e "$srcdir/.git") {
		main::error(sprintf(_g("%s is not a git repository"), $srcdir));
	}

	# Disable git hooks, as unpacking a source package should not
	# involve running code.
	foreach my $hook (glob("$srcdir/.git/hooks/*")) {
		if (-x $hook) {
			main::warning(sprintf(_g("executable bit set on %s; clearing"), $hook));
			chmod(0644 &~ umask(), $hook) ||
				main::syserr(sprintf(_g("unable to change permission of `%s'"), $hook));
		}
	}
	
	# This is a paranoia measure, since the index is not normally
	# provided by possible-untrusted third parties, remove it if
	# present (git-rebase will recreate it).
	unlink("$srcdir/.git/index") ||
		main::syserr(sprintf(_g("unable to remove `%s'"), "$srcdir/.git/index"));

	# Comment out potentially probamatic or annoying stuff in
	# .git/config.
	my $safe_fields=qr/^(
		core\.autocrlf			|
		branch\..*			|
		remote\..*			|
		core\.repositoryformatversion	|
		core.filemode			|
		core.bare
		)$/x;
	my $removed="";
	# This needs to be an absolute path, for some reason.
	my $configfile=Cwd::abs_path("$srcdir/.git/config");
	open(GIT_CONFIG, "git-config --file $configfile -l |") ||
		main::subprocerr("git-config");
	my @config=<GIT_CONFIG>;
	close(GIT_CONFIG) || main::syserr("git-config exited nonzero");
	foreach (@config) {
		chomp;
		my ($field, $value)=split(/=/, $_, 2);
		if ($field !~ /$safe_fields/) {
			system("git-config", "--file", $configfile,
				"--unset-all", $field);
			$? && main::subprocerr("git-config --file $configfile --unset-all $field");
			$removed.="# $_\n";
		}
	}
	if ($removed) {
		open(GIT_CONFIG, ">>", $configfile) ||
			main::syserr(sprintf(_g("unstable to append to %s", $configfile)));
		print GIT_CONFIG "\n# "._g("The following setting(s) were disabled by dpkg-source").":\n";
		print GIT_CONFIG $removed;
		close GIT_CONFIG;
		main::warning(_g(_g("modifying .git/config to comment out some settings")));
	}

	# Note that git-reset is used to repopulate the WC with files.
	# git-clone isn't used because the repo might be an unclonable
	# shallow copy. git-reset also recreates the index.
	# XXX git-reset should be made to run in quiet mode here, but
	# lacks a good way to do it. Bug filed.
	system("cd $srcdir && git-reset --hard");
	$? && main::subprocerr("cd $srcdir && git-reset --hard");
}

1
