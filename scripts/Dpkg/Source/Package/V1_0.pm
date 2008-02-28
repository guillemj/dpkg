# Copyright 2008 Raphaël Hertzog <hertzog@debian.org>

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

package Dpkg::Source::Package::V1_0;

use strict;
use warnings;

use base 'Dpkg::Source::Package';

use Dpkg;
use Dpkg::Gettext;
use Dpkg::ErrorHandling qw(error syserr warning usageerr subprocerr);
use Dpkg::Compression;
use Dpkg::Source::Archive;
use Dpkg::Source::Patch;
use Dpkg::Version qw(check_version);
use Dpkg::Exit;
use Dpkg::Source::Functions qw(erasedir);

use POSIX;
use File::Basename;
use File::Temp qw(tempfile);

sub extract {
    my ($self, $newdirectory) = @_;
    my $sourcestyle = $self->{'options'}{'sourcestyle'};
    my $fields = $self->{'fields'};

    $sourcestyle =~ y/X/p/;
    $sourcestyle =~ m/[pun]/ ||
	usageerr(_g("source handling style -s%s not allowed with -x"),
	         $sourcestyle);

    my $dscdir = $self->{'basedir'};

    check_version($fields->{'Version'});

    my $basename = $self->get_basename();
    my $basenamerev = $self->get_basename(1);

    # V1.0 only supports gzip compression
    my ($tarfile, $difffile);
    foreach my $file ($self->get_files()) {
	if ($file =~ /^(?:\Q$basename\E\.orig|\Q$basenamerev\E)\.tar\.gz$/) {
            error(_g("multiple tarfiles in v1.0 source package")) if $tarfile;
            $tarfile = $file;
	} elsif ($file =~ /^\Q$basenamerev\E\.diff\.gz$/) {
	    $difffile = $file;
	} else {
	    error(_g("unrecognized file for a %s source package: %s"),
                  "v1.0", $file);
	}
    }

    error(_g("no tarfile in Files field")) unless $tarfile;
    my $native = $difffile ? 0 : 1;
    if ($native) {
	warning(_g("native package with .orig.tar"))
            if $tarfile =~ /\.orig\.tar\.gz$/;
    } else {
	warning(_g("no upstream tarfile in Files field"))
	    unless defined $tarfile;
    }

    my $expectprefix = $newdirectory;
    $expectprefix .= '.orig' if $difffile;

    erasedir($newdirectory);
    if (-e $expectprefix) {
	rename($expectprefix, "$newdirectory.tmp-keep") ||
                syserr(_g("unable to rename `%s' to `%s'"), $expectprefix,
                       "$newdirectory.tmp-keep");
    }

    printf(_g("%s: unpacking %s")."\n", $progname, $tarfile);
    my $tar = Dpkg::Source::Archive->new(filename => "$dscdir$tarfile");
    $tar->extract($expectprefix);

    # for the first tar file:
    if ($tarfile and not $native)
    {
        # -sp: copy the .orig.tar.gz if required
        if ($sourcestyle =~ /p/) {
            stat("$dscdir$tarfile") ||
                syserr(_g("failed to stat `%s' to see if need to copy"),
                       "$dscdir$tarfile");

            my ($dsctardev, $dsctarino) = stat _;
            my $copy_required;

            if (stat($tarfile)) {
                my ($dumptardev, $dumptarino) = stat _;
                $copy_required = ($dumptardev != $dsctardev ||
                                  $dumptarino != $dsctarino);
            } else {
                unless ($! == ENOENT) {
                    syserr(_g("failed to check destination `%s' " .
                              "to see if need to copy"), $tarfile);
                }
                $copy_required = 1;
            }

            if ($copy_required) {
                system('cp', '--', "$dscdir$tarfile", $tarfile);
                subprocerr("cp $dscdir$tarfile to $tarfile") if $?;
            }
        }
        # -su: keep .orig directory unpacked
        elsif ($sourcestyle =~ /u/ and $expectprefix ne $newdirectory) {
            if (-e "$newdirectory.tmp-keep") {
                error(_g("unable to keep orig directory (already exists)"));
            }
            system('cp', '-ar', '--', $expectprefix, "$newdirectory.tmp-keep");
            subprocerr("cp $expectprefix to $newdirectory.tmp-keep") if $?;
        }
    }

    if ($newdirectory ne $expectprefix)
    {
	rename($expectprefix, $newdirectory) ||
	    syserr(_g("failed to rename newly-extracted %s to %s"),
	           $expectprefix, $newdirectory);

	# rename the copied .orig directory
	if (-e "$newdirectory.tmp-keep") {
	    rename("$newdirectory.tmp-keep", $expectprefix) ||
                    syserr(_g("failed to rename saved %s to %s"),
	                   "$newdirectory.tmp-keep", $expectprefix);
        }
    }

    if ($difffile) {
        my $patch = "$dscdir$difffile";
	printf(_g("%s: applying %s")."\n", $progname, $patch);
	my $patch_obj = Dpkg::Source::Patch->new(filename => $patch);
	$patch_obj->apply($newdirectory, force_timestamp => 1,
                          timestamp => time());
    }
}

sub build {
    my ($self, $dir) = @_;
    my $sourcestyle = $self->{'options'}{'sourcestyle'};
    my @argv = @{$self->{'options'}{'ARGV'}};
    my @tar_ignore = map { "--exclude=$_" } @{$self->{'options'}{'tar_ignore'}};
    my $diff_ignore_regexp = $self->{'options'}{'diff_ignore_regexp'};

    $dir =~ s{/+$}{}; # Strip trailing /

    if (scalar(@argv) > 1) {
        usageerr(_g("-b takes at most a directory and an orig source ".
                    "argument (with v1.0 source package)"));
    }

    $sourcestyle =~ y/X/A/;
    unless ($sourcestyle =~ m/[akpursnAKPUR]/) {
        usageerr(_g("source handling style -s%s not allowed with -b"),
		$sourcestyle);
    }

    my $sourcepackage = $self->{'fields'}{'Source'};
    my $basenamerev = $self->get_basename(1);
    my $basename = $self->get_basename();
    my $basedirname = $basename;
    $basedirname =~ s/_/-/;

    # Try to find a .orig tarball for the package
    my $origdir = "$dir.orig";
    my $origtargz = $self->get_basename() . ".orig.tar.gz";
    if (-e $origtargz) {
        unless (-f $origtargz) {
            error(_g("packed orig `%s' exists but is not a plain file"), $origtargz);
        }
    } else {
        $origtargz = undef;
    }

    if (@argv) {
	# We have a second-argument <orig-dir> or <orig-targz>, check what it
	# is to decide the mode to use
        my $origarg = shift(@argv);
        if (length($origarg)) {
            stat($origarg) ||
                syserr(_g("cannot stat orig argument %s"), $origarg);
            if (-d _) {
                $origdir = $origarg;
                $origdir =~ s{/*$}{};

                $sourcestyle =~ y/aA/rR/;
                unless ($sourcestyle =~ m/[ursURS]/) {
                    error(_g("orig argument is unpacked but source handling " .
                             "style -s%s calls for packed (.orig.tar.<ext>)"),
                          $sourcestyle);
                }
            } elsif (-f _) {
                $origtargz = $origarg;
                $sourcestyle =~ y/aA/pP/;
                unless ($sourcestyle =~ m/[kpsKPS]/) {
                    error(_g("orig argument is packed but source handling " .
                             "style -s%s calls for unpacked (.orig/)"),
                          $sourcestyle);
                }
            } else {
                error("orig argument $origarg is not a plain file or directory");
            }
        } else {
            $sourcestyle =~ y/aA/nn/;
            $sourcestyle =~ m/n/ ||
                error(_g("orig argument is empty (means no orig, no diff) " .
                         "but source handling style -s%s wants something"),
                      $sourcestyle);
        }
    } elsif ($sourcestyle =~ m/[aA]/) {
	# We have no explicit <orig-dir> or <orig-targz>, try to use
	# a .orig tarball first, then a .orig directory and fall back to
	# creating a native .tar.gz
	if ($origtargz) {
	    $sourcestyle =~ y/aA/pP/; # .orig.tar.<ext>
	} else {
	    if (stat($origdir)) {
		unless (-d _) {
                    error(_g("unpacked orig `%s' exists but is not a directory"),
		          $origdir);
                }
		$sourcestyle =~ y/aA/rR/; # .orig directory
	    } elsif ($! != ENOENT) {
		syserr(_g("unable to stat putative unpacked orig `%s'"), $origdir);
	    } else {
		$sourcestyle =~ y/aA/nn/; # Native tar.gz
	    }
	}
    }

    my ($dirname, $dirbase) = fileparse($dir);
    if ($dirname ne $basedirname) {
	warning(_g("source directory '%s' is not <sourcepackage>" .
	           "-<upstreamversion> '%s'"), $dir, $basedirname);
    }

    my ($tarname, $tardirname, $tardirbase, $origdirname);
    if ($sourcestyle ne 'n') {
	my ($origdirname, $origdirbase) = fileparse($origdir);

        if ($origdirname ne "$basedirname.orig") {
            warning(_g(".orig directory name %s is not <package>" .
	               "-<upstreamversion> (wanted %s)"),
	            $origdirname, "$basedirname.orig");
        }
        $tardirbase = $origdirbase;
        $tardirname = $origdirname;

	$tarname = $origtargz || "$basename.orig.tar.gz";
	unless ($tarname =~ /\Q$basename\E\.orig\.tar\.gz/) {
	    warning(_g(".orig.tar name %s is not <package>_<upstreamversion>" .
	               ".orig.tar (wanted %s)"),
	            $tarname, "$basename.orig.tar.gz");
	}
    } else {
	$tardirbase = $dirbase;
        $tardirname = $dirname;
	$tarname = "$basenamerev.tar.gz";
    }

    if ($sourcestyle =~ m/[nurUR]/) {
        if (stat($tarname)) {
            unless ($sourcestyle =~ m/[nUR]/) {
		error(_g("tarfile `%s' already exists, not overwriting, " .
		         "giving up; use -sU or -sR to override"), $tarname);
            }
        } elsif ($! != ENOENT) {
	    syserr(_g("unable to check for existence of `%s'"), $tarname);
        }

        printf(_g("%s: building %s in %s")."\n",
               $progname, $sourcepackage, $tarname);

	my ($ntfh, $newtar) = tempfile("$tarname.new.XXXXXX",
				       DIR => getcwd(), UNLINK => 0);
	my $tar = Dpkg::Source::Archive->new(filename => $newtar,
		    compression => get_compression_from_filename($tarname),
		    compression_level => $self->{'options'}{'comp_level'});
	$tar->create(options => \@tar_ignore, 'chdir' => $tardirbase);
	$tar->add_directory($tardirname);
	$tar->finish();
        rename($newtar, $tarname) ||
            syserr(_g("unable to rename `%s' (newly created) to `%s'"),
                   $newtar, $tarname);
	chmod(0666 &~ umask(), $tarname) ||
	    syserr(_g("unable to change permission of `%s'"), $tarname);
    } else {
        printf(_g("%s: building %s using existing %s")."\n",
               $progname, $sourcepackage, $tarname);
    }

    $self->add_file($tarname);

    if ($sourcestyle =~ m/[kpKP]/) {
        if (stat($origdir)) {
            unless ($sourcestyle =~ m/[KP]/) {
                error(_g("orig dir `%s' already exists, not overwriting, ".
                         "giving up; use -sA, -sK or -sP to override"),
                      $origdir);
            }
	    push @Dpkg::Exit::handlers, sub { erasedir($origdir) };
            erasedir($origdir);
	    pop @Dpkg::Exit::handlers;
        } elsif ($! != ENOENT) {
            syserr(_g("unable to check for existence of orig dir `%s'"),
                    $origdir);
        }

	my $tar = Dpkg::Source::Archive->new(filename => $origtargz);
	$tar->extract($origdir);
    }

    my $ur; # Unrepresentable changes
    if ($sourcestyle =~ m/[kpursKPUR]/) {
	my $diffname = "$basenamerev.diff.gz";
        printf(_g("%s: building %s in %s")."\n",
               $progname, $sourcepackage, $diffname);
	my ($ndfh, $newdiffgz) = tempfile("$diffname.new.XXXXXX",
					DIR => getcwd(), UNLINK => 0);
        my $diff = Dpkg::Source::Patch->new(filename => $newdiffgz,
                compression => get_compression_from_filename($diffname));
        $diff->create();
        $diff->add_diff_directory($origdir, $dir,
                basedirname => $basedirname,
                diff_ignore_regexp => $diff_ignore_regexp);
        $diff->finish() || $ur++;

	rename($newdiffgz, $diffname) ||
	    syserr(_g("unable to rename `%s' (newly created) to `%s'"),
	           $newdiffgz, $diffname);
	chmod(0666 &~ umask(), $diffname) ||
	    syserr(_g("unable to change permission of `%s'"), $diffname);

	$self->add_file($diffname);
    }

    if ($sourcestyle =~ m/[prPR]/) {
        erasedir($origdir);
    }

    if ($ur) {
        printf(STDERR _g("%s: unrepresentable changes to source")."\n",
               $progname);
        exit(1);
    }
}

# vim: set et sw=4 ts=8
1;
