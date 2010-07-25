#
# git support for dpkg-source
#
# Copyright © 2007,2010 Joey Hess <joeyh@debian.org>.
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
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

package Dpkg::Source::Package::V3::git;

use strict;
use warnings;

our $VERSION = "0.02";

use base 'Dpkg::Source::Package';

use Cwd qw(abs_path getcwd);
use File::Basename;
use File::Temp qw(tempdir);

use Dpkg;
use Dpkg::Gettext;
use Dpkg::ErrorHandling;
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
    error(_g("This source package can only be manipulated using git, " .
             "which is not in the PATH."));
}

sub sanity_check {
    my $srcdir = shift;

    if (! -d "$srcdir/.git") {
        error(_g("source directory is not the top directory of a git " .
                 "repository (%s/.git not present), but Format git was " .
                 "specified"), $srcdir);
    }
    if (-s "$srcdir/.gitmodules") {
        error(_g("git repository %s uses submodules. This is not yet supported."),
              $srcdir);
    }

    return 1;
}

sub parse_cmdline_option {
    my ($self, $opt) = @_;
    return 1 if $self->SUPER::parse_cmdline_option($opt);
    if ($opt =~ /^--git-ref=(.*)$/) {
        push @{$self->{'options'}{'git-ref'}}, $1;
        return 1;
    } elsif ($opt =~ /^--git-depth=(\d+)$/) {
        $self->{'options'}{'git-depth'} = $1;
        return 1;
    }
    return 0;
}

sub can_build {
    my ($self, $dir) = @_;
    return (-d "$dir/.git", _g("doesn't contain a git repository"));
}

sub do_build {
    my ($self, $dir) = @_;
    my $diff_ignore_regexp = $self->{'options'}{'diff_ignore_regexp'};

    $dir =~ s{/+$}{}; # Strip trailing /
    my ($dirname, $updir) = fileparse($dir);
    my $basenamerev = $self->get_basename(1);

    sanity_check($dir);

    my $old_cwd = getcwd();
    chdir($dir) || syserr(_g("unable to chdir to `%s'"), $dir);

    # Check for uncommitted files.
    # To support dpkg-source -i, get a list of files
    # equivalent to the ones git status finds, and remove any
    # ignored files from it.
    my @ignores = "--exclude-per-directory=.gitignore";
    my $core_excludesfile = `git config --get core.excludesfile`;
    chomp $core_excludesfile;
    if (length $core_excludesfile && -e $core_excludesfile) {
        push @ignores, "--exclude-from=$core_excludesfile";
    }
    if (-e ".git/info/exclude") {
        push @ignores, "--exclude-from=.git/info/exclude";
    }
    open(GIT_LS_FILES, '-|', "git", "ls-files", "--modified", "--deleted",
         "-z", "--others", @ignores) || subprocerr("git ls-files");
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

    # If a depth was specified, need to create a shallow clone and
    # bundle that.
    my $tmp;
    my $shallowfile;
    if ($self->{'options'}{'git-depth'}) {
        chdir($old_cwd) ||
                syserr(_g("unable to chdir to `%s'"), $old_cwd);
        $tmp = tempdir("$dirname.git.XXXXXX", DIR => $updir);
        push @Dpkg::Exit::handlers, sub { erasedir($tmp) };
        my $clone_dir = "$tmp/repo.git";
        # file:// is needed to avoid local cloning, which does not
        # create a shallow clone.
        info(_g("creating shallow clone with depth %s"),
                $self->{'options'}{'git-depth'});
        system("git", "clone", "--depth=".$self->{'options'}{'git-depth'},
                "--quiet", "--bare", "file://" . abs_path($dir), $clone_dir);
        $? && subprocerr("git clone");
        chdir($clone_dir) ||
                syserr(_g("unable to chdir to `%s'"), $clone_dir);
        $shallowfile = "$basenamerev.gitshallow";
        system("cp", "-f", "shallow", "$old_cwd/$shallowfile");
        $? && subprocerr("cp shallow");
    }

    # Create the git bundle.
    my $bundlefile = "$basenamerev.git";
    my @bundle_arg=$self->{'options'}{'git-ref'} ?
        (@{$self->{'options'}{'git-ref'}}) : "--all";
    info(_g("bundling: %s"), join(" ", @bundle_arg));
    system("git", "bundle", "create", "$old_cwd/$bundlefile",
           @bundle_arg,
           "HEAD", # ensure HEAD is included no matter what
           "--", # avoids ambiguity error when referring to eg, a debian branch
    );
    $? && subprocerr("git bundle");

    chdir($old_cwd) ||
        syserr(_g("unable to chdir to `%s'"), $old_cwd);

    if (defined $tmp) {
        erasedir($tmp);
        pop @Dpkg::Exit::handlers;
    }

    $self->add_file($bundlefile);
    if (defined $shallowfile) {
        $self->add_file($shallowfile);
    }
}

sub do_extract {
    my ($self, $newdirectory) = @_;
    my $fields = $self->{'fields'};

    my $dscdir = $self->{'basedir'};
    my $basenamerev = $self->get_basename(1);

    my @files = $self->get_files();
    my ($bundle, $shallow);
    foreach my $file (@files) {
        if ($file =~ /^\Q$basenamerev\E\.git$/) {
            if (! defined $bundle) {
                $bundle = $file;
            } else {
                error(_g("format v3.0 (git) uses only one .git file"));
            }
        } elsif ($file =~ /^\Q$basenamerev\E\.gitshallow$/) {
            if (! defined $shallow) {
                $shallow = $file;
            } else {
                error(_g("format v3.0 (git) uses only one .gitshallow file"));
            }
        } else {
            error(_g("format v3.0 (git) unknown file: %s", $file));
        }
    }
    if (! defined $bundle) {
        error(_g("format v3.0 (git) expected %s"), "$basenamerev.git");
    }

    erasedir($newdirectory);

    # Extract git bundle.
    info(_g("cloning %s"), $bundle);
    system("git", "clone", "--quiet", $dscdir.$bundle, $newdirectory);
    $? && subprocerr("git bundle");

    if (defined $shallow) {
        # Move shallow info file into place, so git does not
        # try to follow parents of shallow refs.
        info(_g("setting up shallow clone"));
        system("cp", "-f",  $dscdir.$shallow, "$newdirectory/.git/shallow");
        $? && subprocerr("cp");
    }

    sanity_check($newdirectory);
}

1;
