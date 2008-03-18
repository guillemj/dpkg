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

package Dpkg::Source::Package::V2_0;

use strict;
use warnings;

use base 'Dpkg::Source::Package';

use Dpkg;
use Dpkg::Gettext;
use Dpkg::ErrorHandling qw(error errormsg syserr warning usageerr subprocerr info);
use Dpkg::Compression;
use Dpkg::Source::Archive;
use Dpkg::Source::Patch;
use Dpkg::Version qw(check_version);
use Dpkg::Exit;
use Dpkg::Source::Functions qw(erasedir);

use POSIX;
use File::Basename;
use File::Temp qw(tempfile tempdir);
use File::Path;
use File::Spec;

sub init_options {
    my ($self) = @_;
    $self->SUPER::init_options();
    $self->{'options'}{'include_removal'} = 0
        unless exists $self->{'options'}{'include_removal'};
    $self->{'options'}{'include_timestamp'} = 0
        unless exists $self->{'options'}{'include_timestamp'};
    $self->{'options'}{'include_binaries'} = 0
        unless exists $self->{'options'}{'include_binaries'};
}

sub parse_cmdline_option {
    my ($self, $opt) = @_;
    if ($opt =~ /^--include-removal$/) {
        $self->{'options'}{'include_removal'} = 1;
        return 1;
    } elsif ($opt =~ /^--include-timestamp$/) {
        $self->{'options'}{'include_timestamp'} = 1;
        return 1;
    } elsif ($opt =~ /^--include-binaries$/) {
        $self->{'options'}{'include_binaries'} = 1;
        return 1;
    }
    return 0;
}

sub do_extract {
    my ($self, $newdirectory) = @_;
    my $fields = $self->{'fields'};

    my $dscdir = $self->{'basedir'};

    check_version($fields->{'Version'});

    my $basename = $self->get_basename();
    my $basenamerev = $self->get_basename(1);

    my ($tarfile, $debianfile, %origtar, %seen);
    foreach my $file ($self->get_files()) {
        (my $uncompressed = $file) =~ s/\.$comp_regex$//;
        error(_g("duplicate files in %s source package: %s.*"), "v2.0",
              $uncompressed) if $seen{$uncompressed};
        $seen{$uncompressed} = 1;
        if ($file =~ /^\Q$basename\E\.orig\.tar\.$comp_regex$/) {
            $tarfile = $file;
        } elsif ($file =~ /^\Q$basename\E\.orig-(\w+)\.tar\.$comp_regex$/) {
            $origtar{$1} = $file;
        } elsif ($file =~ /^\Q$basenamerev\E\.debian\.tar\.$comp_regex$/) {
            $debianfile = $file;
        } else {
            error(_g("unrecognized file for a %s source package: %s"),
            "v2.0", $file);
        }
    }

    unless ($tarfile and $debianfile) {
        error(_g("missing orig.tar or debian.tar file in v2.0 source package"));
    }

    erasedir($newdirectory);

    # Extract main tarball
    info(_g("unpacking %s"), $tarfile);
    my $tar = Dpkg::Source::Archive->new(filename => "$dscdir$tarfile");
    $tar->extract($newdirectory, no_fixperms => 1);

    # Extract additional orig tarballs
    foreach my $subdir (keys %origtar) {
        my $file = $origtar{$subdir};
        info(_g("unpacking %s"), $file);
        if (-e "$newdirectory/$subdir") {
            warning(_g("required removal of `%s' installed by original tarball"), $subdir);
            erasedir("$newdirectory/$subdir");
        }
        $tar = Dpkg::Source::Archive->new(filename => "$dscdir$file");
        $tar->extract("$newdirectory/$subdir", no_fixperms => 1);
    }

    # Extract debian tarball after removing the debian directory
    info(_g("unpacking %s"), $debianfile);
    erasedir("$newdirectory/debian");
    $tar = Dpkg::Source::Archive->new(filename => "$dscdir$debianfile");
    $tar->extract($newdirectory, in_place => 1);

    # Apply patches (in a separate method as it might be overriden)
    $self->apply_patches($newdirectory);
}

sub get_autopatch_name {
    return "zz_debian-diff-auto";
}

sub get_patches {
    my ($self, $dir, $skip_auto) = @_;
    my @patches;
    my $pd = "$dir/debian/patches";
    my $auto_patch = $self->get_autopatch_name();
    if (-d $pd) {
        opendir(DIR, $pd) || syserr(_g("cannot opendir %s"), $pd);
        foreach my $patch (sort readdir(DIR)) {
            # patches match same rules as run-parts
            next unless $patch =~ /^[\w-]+$/ and -f "$pd/$patch";
            next if $skip_auto and $patch eq $auto_patch;
            push @patches, $patch;
        }
        closedir(DIR);
    }
    return @patches;
}

sub apply_patches {
    my ($self, $dir, $skip_auto) = @_;
    my $timestamp = time();
    foreach my $patch ($self->get_patches($dir, $skip_auto)) {
        my $path = File::Spec->catfile($dir, "debian", "patches", $patch);
        info(_g("applying %s"), $patch) unless $skip_auto;
        my $patch_obj = Dpkg::Source::Patch->new(filename => $path);
        $patch_obj->apply($dir, force_timestamp => 1,
                          timestamp => $timestamp,
                          add_options => [ '-E' ]);
    }
}

sub can_build {
    my ($self, $dir) = @_;
    foreach ($self->find_original_tarballs()) {
        return 1 if /\.orig\.tar\.$comp_regex$/;
    }
    return (0, _g("no orig.tar file found"));
}

sub prepare_build {
    my ($self, $dir) = @_;
    $self->{'diff_options'} = {
        diff_ignore_regexp => $self->{'options'}{'diff_ignore_regexp'},
        include_removal => $self->{'options'}{'include_removal'},
        include_timestamp => $self->{'options'}{'include_timestamp'},
    };
}

sub do_build {
    my ($self, $dir) = @_;
    my @argv = @{$self->{'options'}{'ARGV'}};
    my @tar_ignore = map { "--exclude=$_" } @{$self->{'options'}{'tar_ignore'}};
    my $include_binaries = $self->{'options'}{'include_binaries'};

    my ($dirname, $updir) = fileparse($dir);
    if (scalar(@argv)) {
        usageerr(_g("-b takes only one parameter with format `%s'"),
                 $self->{'fields'}{'Format'});
    }
    $self->prepare_build($dir);

    my $sourcepackage = $self->{'fields'}{'Source'};
    my $basenamerev = $self->get_basename(1);
    my $basename = $self->get_basename();
    my $basedirname = $basename;
    $basedirname =~ s/_/-/;

    # Identify original tarballs
    my ($tarfile, %origtar);
    my @origtarballs;
    foreach (sort $self->find_original_tarballs()) {
        if (/\.orig\.tar\.$comp_regex$/) {
            $tarfile = $_;
            push @origtarballs, $_;
            $self->add_file($_);
        } elsif (/\.orig-(\w+)\.tar\.$comp_regex$/) {
            $origtar{$1} = $_;
            push @origtarballs, $_;
            $self->add_file($_);
        }
    }

    error(_g("no orig.tar file found")) unless $tarfile;

    info(_g("building %s using existing %s"),
	 $sourcepackage, "@origtarballs");

    # Unpack a second copy for comparison
    my $tmp = tempdir("$dirname.orig.XXXXXX", DIR => $updir);
    push @Dpkg::Exit::handlers, sub { erasedir($tmp) };

    # Extract main tarball
    my $tar = Dpkg::Source::Archive->new(filename => $tarfile);
    $tar->extract($tmp);

    # Extract additional orig tarballs
    foreach my $subdir (keys %origtar) {
        my $file = $origtar{$subdir};
        $tar = Dpkg::Source::Archive->new(filename => $file);
        $tar->extract("$tmp/$subdir");
    }

    # Copy over the debian directory
    system("cp", "-a", "--", "$dir/debian", "$tmp/");
    subprocerr(_g("copy of the debian directory")) if $?;

    # Apply all patches except the last automatic one
    $self->apply_patches($tmp, 1);

    # Prepare handling of binary files
    my %auth_bin_files;
    my $incbin_file = File::Spec->catfile($dir, "debian", "source", "include-binaries");
    if (-f $incbin_file) {
        open(INC, "<", $incbin_file) || syserr(_g("can't read %s"), $incbin_file);
        while(defined($_ = <INC>)) {
            chomp; s/^\s*//; s/\s*$//;
            next if /^#/;
            $auth_bin_files{$_} = 1;
        }
        close(INC);
    }
    my @binary_files;
    my $handle_binary = sub {
        my ($self, $old, $new) = @_;
        my $relfn = File::Spec->abs2rel($new, $dir);
        # Include binaries if they are whitelisted or if
        # --include-binaries has been given
        if ($include_binaries or $auth_bin_files{$relfn}) {
            push @binary_files, $relfn;
        } else {
            errormsg(_g("cannot represent change to %s: %s"), $new,
                     _g("binary file contents changed"));
            errormsg(_g("add %s in debian/source/include-binaries if you want" .
                     " to store the modified binary in the debian tarball"),
                     $relfn);
            $self->register_error();
        }
    };

    # Create a patch
    my ($difffh, $tmpdiff) = tempfile("$basenamerev.diff.XXXXXX",
                                      DIR => $updir, UNLINK => 0);
    push @Dpkg::Exit::handlers, sub { unlink($tmpdiff) };
    my $diff = Dpkg::Source::Patch->new(filename => $tmpdiff,
                                        compression => "none");
    $diff->create();
    $diff->add_diff_directory($tmp, $dir, basedirname => $basedirname,
            %{$self->{'diff_options'}}, handle_binary_func => $handle_binary);
    error(_g("unrepresentable changes to source")) if not $diff->finish();
    # The previous auto-patch must be removed, it has not been used and it
    # will be recreated if it's still needed
    my $autopatch = File::Spec->catfile($dir, "debian", "patches",
                                        $self->get_autopatch_name());
    if (-e $autopatch) {
        unlink($autopatch) || syserr(_g("cannot remove %s"), $autopatch);
    }
    # Install the diff as the new autopatch
    if (not -s $tmpdiff) {
        unlink($tmpdiff) || syserr(_g("cannot remove %s"), $tmpdiff);
    } else {
        mkpath(File::Spec->catdir($dir, "debian", "patches"));
        rename($tmpdiff, $autopatch) ||
                syserr(_g("cannot rename %s to %s"), $tmpdiff, $autopatch);
    }
    $self->register_autopatch($dir);
    pop @Dpkg::Exit::handlers;

    # Remove the temporary directory
    erasedir($tmp);
    pop @Dpkg::Exit::handlers;

    # Update debian/source/include-binaries if needed
    if (scalar(@binary_files) and $include_binaries) {
        mkpath(File::Spec->catdir($dir, "debian", "source"));
        open(INC, ">>", $incbin_file) || syserr(_g("can't write %s"), $incbin_file);
        foreach my $binary (@binary_files) {
            unless ($auth_bin_files{$binary}) {
                print INC "$binary\n";
                info(_g("adding %s to %s"), $binary, "debian/source/include-binaries");
            }
        }
        close(INC);
    }
    # Create the debian.tar
    my $debianfile = "$basenamerev.debian.tar." . $self->{'options'}{'comp_ext'};
    info(_g("building %s in %s"), $sourcepackage, $debianfile);
    $tar = Dpkg::Source::Archive->new(filename => $debianfile);
    $tar->create(options => \@tar_ignore, 'chdir' => $dir);
    $tar->add_directory("debian");
    foreach my $binary (@binary_files) {
        $tar->add_file($binary);
    }
    $tar->finish();

    $self->add_file($debianfile);
}

sub register_autopatch {
    my ($self, $dir) = @_;
}

# vim:et:sw=4:ts=8
1;
