#!/usr/bin/perl
#
# git support for dpkg-source
#
# Copyright © 2007 Joey Hess <joeyh@debian.org>.
# Copyright © 2008 Frank Lichtenheld <djpig@debian.org>
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
package Dpkg::Source::Package::V3::git;

use strict;
use warnings;

use base 'Dpkg::Source::Package';

use Cwd;
use File::Basename;
use File::Find;
use File::Temp qw(tempdir);

use Dpkg;
use Dpkg::Gettext;
use Dpkg::Compression;
use Dpkg::ErrorHandling qw(error warning subprocerr syserr info);
use Dpkg::Version qw(check_version);
use Dpkg::Source::Archive;
use Dpkg::Exit;
use Dpkg::Source::Functions qw(erasedir);

our $CURRENT_MINOR_VERSION = "0";

# Remove variables from the environment that might cause git to do
# something unexpected.
delete $ENV{GIT_DIR};
delete $ENV{GIT_INDEX_FILE};
delete $ENV{GIT_OBJECT_DIRECTORY};
delete $ENV{GIT_ALTERNATE_OBJECT_DIRECTORIES};
delete $ENV{GIT_WORK_TREE};

sub import {
    foreach my $dir (split(/:/, $ENV{PATH})) {
        if (-x "$dir/git") {
            return 1;
        }
    }
    error(_g("This source package can only be manipulated using git, which is not in the PATH."));
}

sub sanity_check {
    my $srcdir = shift;

    if (! -d "$srcdir/.git") {
        error(_g("source directory is not the top directory of a git repository (%s/.git not present), but Format git was specified"),
              $srcdir);
    }
    if (-s "$srcdir/.gitmodules") {
        error(_g("git repository %s uses submodules. This is not yet supported."),
              $srcdir);
    }

    # Symlinks from .git to outside could cause unpack failures, or
    # point to files they shouldn't, so check for and don't allow.
    if (-l "$srcdir/.git") {
        error(_g("%s is a symlink"), "$srcdir/.git");
    }
    my $abs_srcdir = Cwd::abs_path($srcdir);
    find(sub {
        if (-l $_) {
            if (Cwd::abs_path(readlink($_)) !~ /^\Q$abs_srcdir\E(\/|$)/) {
                error(_g("%s is a symlink to outside %s"),
                      $File::Find::name, $srcdir);
            }
        }
    }, "$srcdir/.git");

    return 1;
}

# Returns a hash of arrays of git config values.
sub read_git_config {
    my $file = shift;

    my %ret;
    open(GIT_CONFIG, '-|', "git", "config", "--file", $file, "--null", "-l") ||
        subprocerr("git config");
    local $/ = "\0";
    while (<GIT_CONFIG>) {
        chomp;
        my ($key, $value) = split(/\n/, $_, 2);
        push @{$ret{$key}}, $value;
    }
    close(GIT_CONFIG) || syserr(_g("git config exited nonzero"));

    return \%ret;
}

sub can_build {
    my ($self, $dir) = @_;
    return (-d "$dir/.git", _g("doesn't contain a git repository"));
}

sub do_build {
    my ($self, $dir) = @_;
    my @argv = @{$self->{'options'}{'ARGV'}};
#TODO: warn here?
#    my @tar_ignore = map { "--exclude=$_" } @{$self->{'options'}{'tar_ignore'}};
    my $diff_ignore_regexp = $self->{'options'}{'diff_ignore_regexp'};

    $dir =~ s{/+$}{}; # Strip trailing /
    my ($dirname, $updir) = fileparse($dir);

    if (scalar(@argv)) {
        usageerr(_g("-b takes only one parameter with format `%s'"),
                 $self->{'fields'}{'Format'});
    }

    my $sourcepackage = $self->{'fields'}{'Source'};
    my $basenamerev = $self->get_basename(1);
    my $basename = $self->get_basename();
    my $basedirname = $basename;
    $basedirname =~ s/_/-/;

    sanity_check($dir);

    my $old_cwd = getcwd();
    chdir($dir) ||
	syserr(_g("unable to chdir to `%s'"), $dir);

    # Check for uncommitted files.
    # To support dpkg-source -i, get a list of files
    # equivalent to the ones git status finds, and remove any
    # ignored files from it.
    my @ignores = "--exclude-per-directory=.gitignore";
    my $core_excludesfile = `git config --get core.excludesfile`;
    chomp $core_excludesfile;
    if (length $core_excludesfile && -e $core_excludesfile) {
	push @ignores, "--exclude-from='$core_excludesfile'";
    }
    if (-e ".git/info/exclude") {
	push @ignores, "--exclude-from=.git/info/exclude";
    }
    open(GIT_LS_FILES, '-|', "git", "ls-files", "--modified", "--deleted",
	 "-z", "--others", @ignores) ||
	     subprocerr("git ls-files");
    my @files;
    { local $/ = "\0";
      while (<GIT_LS_FILES>) {
	  chomp;
	  if (! length $diff_ignore_regexp ||
	      ! m/$diff_ignore_regexp/o) {
	      push @files, $_;
	  }
      }
    }
    close(GIT_LS_FILES) || syserr(_g("git ls-files exited nonzero"));
    if (@files) {
	error(_g("uncommitted, not-ignored changes in working directory: %s"),
	      join(" ", @files));
    }

    # git clone isn't used to copy the repo because the it might be an
    # unclonable shallow copy.
    chdir($old_cwd) ||
	syserr(_g("unable to chdir to `%s'"), $old_cwd);

    my $tmp = tempdir("$dirname.git.XXXXXX", DIR => $updir);
    push @Dpkg::Exit::handlers, sub { erasedir($tmp) };
    my $tardir = "$tmp/$dirname";
    mkdir($tardir) ||
	syserr(_g("cannot create directory %s"), $tardir);

    system("cp", "-a", "$dir/.git", $tardir);
    $? && subprocerr("cp -a $dir/.git $tardir");
    chdir($tardir) ||
	syserr(_g("unable to chdir to `%s'"), $tardir);

    # TODO support for creating a shallow clone for those cases where
    # uploading the whole repo history is not desired

    # Clean up the new repo to save space.
    # First, delete the whole reflog, which is not needed in a
    # distributed source package.
    system("rm", "-rf", ".git/logs");
    $? && subprocerr("rm -rf .git/logs");
    system("git", "gc", "--prune");
    $? && subprocerr("git gc --prune");

    # .git/gitweb is created and used by git instaweb and should not be
    # transferwed by source package.
    system("rm", "-rf", ".git/gitweb");
    $? && subprocerr("rm -rf .git/gitweb");

    # As an optimisation, remove the index. It will be recreated by git
    # reset during unpack. It's probably small, but you never know, this
    # might save a lot of space. (Also, the index file may not be
    # portable.)
    unlink(".git/index"); # error intentionally ignored

    chdir($old_cwd) ||
	syserr(_g("unable to chdir to `%s'"), $old_cwd);

    # Create the tar file
    my $debianfile = "$basenamerev.git.tar." . $self->{'options'}{'comp_ext'};
    info(_g("building %s in %s"),
	 $sourcepackage, $debianfile);
    my $tar = Dpkg::Source::Archive->new(filename => $debianfile,
					 compression => $self->{'options'}{'compression'},
					 compression_level => $self->{'options'}{'comp_level'});
    $tar->create('chdir' => $tmp);
    $tar->add_directory($dirname);
    $tar->finish();

    erasedir($tmp);
    pop @Dpkg::Exit::handlers;

    $self->add_file($debianfile);
}

# Called after a tarball is unpacked, to check out the working copy.
sub do_extract {
    my ($self, $newdirectory) = @_;
    my $fields = $self->{'fields'};

    my $dscdir = $self->{'basedir'};

    check_version($fields->{'Version'});

    my $basename = $self->get_basename();
    my $basenamerev = $self->get_basename(1);

    my @files = $self->get_files();
    if (@files > 1) {
	error(_g("format v3.0 uses only one source file"));
    }
    my $tarfile = $files[0];
    if ($tarfile !~ /^\Q$basenamerev\E\.git\.tar\.$comp_regex$/) {
	error(_g("expected %s, got %s"),
	      "$basenamerev.git.tar.$comp_regex", $tarfile);
    }

    erasedir($newdirectory);

    # Extract main tarball
    info(_g("unpacking %s"), $tarfile);
    my $tar = Dpkg::Source::Archive->new(filename => "$dscdir$tarfile");
    $tar->extract($newdirectory);

    sanity_check($newdirectory);

    my $old_cwd = getcwd();
    chdir($newdirectory) ||
	syserr(_g("unable to chdir to `%s'"), $newdirectory);

    # Disable git hooks, as unpacking a source package should not
    # involve running code.
    foreach my $hook (glob("./.git/hooks/*")) {
	if (-x $hook) {
	    warning(_g("executable bit set on %s; clearing"), $hook);
	    chmod(0666 &~ umask(), $hook) ||
		syserr(_g("unable to change permission of `%s'"), $hook);
	}
    }

    # This is a paranoia measure, since the index is not normally
    # provided by possibly-untrusted third parties, remove it if
    # present (git will recreate it as needed).
    if (-e ".git/index" || -l ".git/index") {
	unlink(".git/index") ||
	    syserr(_g("unable to remove `%s'"), ".git/index");
    }

    # Comment out potentially probamatic or annoying stuff in
    # .git/config.
    my $safe_fields = qr/^(
		core\.autocrlf			|
		branch\..*			|
		remote\..*			|
		core\.repositoryformatversion	|
		core\.filemode			|
		core\.logallrefupdates		|
		core\.bare
		)$/x;
    my %config = %{read_git_config(".git/config")};
    foreach my $field (keys %config) {
	if ($field =~ /$safe_fields/) {
	    delete $config{$field};
	}
	else {
	    system("git", "config", "--file", ".git/config",
		   "--unset-all", $field);
	    $? && subprocerr("git config --file .git/config --unset-all $field");
	}
    }
    if (%config) {
	warning(_g("modifying .git/config to comment out some settings"));
	open(GIT_CONFIG, ">>", ".git/config") ||
	    syserr(_g("unable to append to %s"), ".git/config");
	print GIT_CONFIG "\n# "._g("The following setting(s) were disabled by dpkg-source").":\n";
	foreach my $field (sort keys %config) {
	    foreach my $value (@{$config{$field}}) {
		if (defined($value)) {
		    print GIT_CONFIG "# $field=$value\n";
		} else {
		    print GIT_CONFIG "# $field\n";
		}
	    }
	}
	close GIT_CONFIG;
    }

    # .git/gitweb is created and used by git instaweb and should not be
    # transferwed by source package.
    system("rm", "-rf", ".git/gitweb");
    $? && subprocerr("rm -rf .git/gitweb");

    # git checkout is used to repopulate the WC with files
    # and recreate the index.
    system("git", "checkout", "-f");
    $? && subprocerr("git checkout -f");

    chdir($old_cwd) ||
	syserr(_g("unable to chdir to `%s'"), $old_cwd);
}

1;
