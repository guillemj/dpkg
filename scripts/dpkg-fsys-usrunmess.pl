#!/usr/bin/perl
#
# dpkg-fsys-usrunmess - Undoes the merged-/usr-via-aliased-dirs mess
#
# Copyright © 2020-2021 Guillem Jover <guillem@debian.org>
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
# along with this program.  If not, see <https://www.gnu.org/licenses/>

use strict;
use warnings;
use feature qw(state);

our ($PROGNAME) = $0 =~ m{(?:.*/)?([^/]*)};
our $PROGVERSION = '1.21.x';
our $ADMINDIR = '/var/lib/dpkg/';

use POSIX;
use File::Temp qw(tempdir);
use File::Find;
use Getopt::Long qw(:config posix_default bundling_values no_ignorecase);

eval q{
    pop @INC if $INC[-1] eq '.';
    use File::FcntlLock;
};
if ($@) {
    fatal('missing File::FcntlLock module; please install libfile-fcntllock-perl');
}

my $opt_noact = length $ENV{DPKG_USRUNMESS_NOACT} ? 1 : 0;
my $opt_prompt = 0;
my $opt_prevent = -1;

my @options_spec = (
    'help|?' => sub { usage(); exit 0; },
    'version' => sub { version(); exit 0; },
    'dry-run|no-act|n' => \$opt_noact,
    'prompt|p' => \$opt_prompt,
    'prevention!' => \$opt_prevent,
);

{
    local $SIG{__WARN__} = sub { usageerr($_[0]) };
    GetOptions(@options_spec);
}

# Set a known umask.
umask 0022;

my @aliased_dirs;

#
# Scan all dirs under / and check whether any are aliased to /usr.
#

foreach my $path (glob '/*') {
    debug("checking symlink? $path");
    next unless -l $path;
    debug("checking merged-usr symlink? $path");
    my $symlink = readlink $path;
    next unless $symlink eq "usr$path" or $symlink eq "/usr$path";
    debug("merged-usr breakage, queueing $path");
    push @aliased_dirs, $path;
}

if (@aliased_dirs == 0) {
    print "System is fine, no aliased directories found, congrats!\n";
    exit 0;
}

#
# dpkg consistency checks
#

debug('checking dpkg database consistency');
system(qw(dpkg --audit)) == 0
    or fatal("cannot audit the dpkg database: $!");

debug('checking whether dpkg has been interrupted');
if (glob "$ADMINDIR/updates/*") {
    fatal('dpkg is in an inconsistent state, please fix that');
}

$opt_prevent = prompt('Generate and install a regression prevention package')
    if $opt_prevent < 0;

if ($opt_prevent) {
    debug('building regression prevention measures');
    my $tmpdir = tempdir(CLEANUP => 1, TMPDIR => 1);
    my $pkgdir = "$tmpdir/pkg";
    my $pkgfile = "$tmpdir/dpkg-fsys-usrunmess.deb";

    mkdir "$pkgdir" or fatal('cannot create temporary package directory');
    mkdir "$pkgdir/DEBIAN" or fatal('cannot create temporary directory');
    open my $ctrl_fh, '>', "$pkgdir/DEBIAN/control"
        or fatal('cannot create temporary control file');
    print { $ctrl_fh } <<"CTRL";
Package: dpkg-fsys-usrunmess
Version: $PROGVERSION
Architecture: all
Protected: yes
Multi-Arch: foreign
Section: admin
Priority: optional
Maintainer: Dpkg Developers <debian-dpkg\@lists.debian.org>
Installed-Size: 5
Conflicts: usrmerge
Provides: usrmerge (= 25)
Replaces: usrmerge
Description: prevention measure to avoid unsuspected filesystem breakage
 This package will prevent automatic migration of the filesystem to the
 broken merge-/usr-via-aliased-dirs via the usrmerge package.
 .
 This package was generated and installed by the dpkg-fsys-usrunmess(8)
 program.

CTRL
    close $ctrl_fh or fatal('cannot write temporary control file');

    system(('dpkg-deb', '-b', $pkgdir, $pkgfile)) == 0
        or fatal('cannot create prevention package');

    if (not $opt_noact) {
        system(('dpkg', '-GBi', $pkgfile)) == 0
            or fatal('cannot install prevention package');
    }
} else {
    print "Will not generate and install a regression prevention package.\n";
}

my $aliased_regex = '^(' . join('|', @aliased_dirs) . ')/';

#
# Get a list of all paths (including diversion) under the aliased dirs.
#

my @search_args;
my %aliased_pathnames;
foreach my $dir (@aliased_dirs) {
    push @search_args, "$dir/*";
}

# We also need to track /usr/lib/modules to then be able to compute its
# complement when looking for untracked kernel module files under aliased
# dirs.
my %usr_mod_pathnames;
push @search_args, '/usr/lib/modules/*';

open my $fh_paths, '-|', 'dpkg-query', '--search', @search_args
    or fatal("cannot execute dpkg-query --search: $!");
while (<$fh_paths>) {
    if (m/^diversion by [^ ]+ from: .*$/) {
        # Ignore.
    } elsif (m/^diversion by [^ ]+ to: (.*)$/) {
        if (-e $1) {
            add_pathname($1, 'diverted pathname');
        }
    } elsif (m/^.*: (.*)$/) {
        add_pathname($1, 'pathname');
    }
}
close $fh_paths;

#
# Get a list of all update-alternatives under the aliased dirs.
#

my @selections = qx(update-alternatives --get-selections);
foreach my $selection (@selections) {
    my $name = (split(' ', $selection))[0];
    my $slaves = 0;

    open my $fh_alts, '-|', 'update-alternatives', '--query', $name
        or fatal("cannot execute update-alternatives --query: $!");
    while (<$fh_alts>) {
        if (m/^\s*$/) {
            last;
        } elsif (m/^Link: (.*)$/) {
            add_pathname($1, 'alternative link');
        } elsif (m/^Slaves:\s*$/) {
            $slaves = 1;
        } elsif ($slaves and m/^\s\S+\s(\S+)$/) {
            add_pathname($1, 'alternative slave');
        } else {
            $slaves = 0;
        }
    }
    close $fh_alts;
}

#
# Unfortunately we need to special case untracked kernel module files,
# as these are required for system booting. To reduce potentially moving
# undesired non-kernel module files (such as apache, python or ruby ones),
# we only look for sub-dirs starting with a digit, which should match for
# both Linux and kFreeBSD modules, and also for the modprobe.conf filename.
#

find({
    no_chdir => 1,
    wanted => sub {
        my $path = $_;

        if (exists $aliased_pathnames{$path}) {
            # Ignore pathname already handled.
        } elsif (exists $usr_mod_pathnames{"/usr$path"}) {
            # Ignore pathname owned elsewhere.
        } elsif ($path eq '/lib/modules' or
                 $path eq '/lib/modules/modprobe.conf' or
                 $path =~ m{^/lib/modules/[0-9]}) {
            add_pathname($path, 'untracked modules');
        }
    },
}, '/lib/modules');


my $sroot = '/.usrunmess';
my @relabel;

#
# Create a shadow hierarchy under / for the new unmessed dir:
#

debug("creating shadow dir = $sroot");
mkdir $sroot
    or sysfatal("cannot create directory $sroot");
foreach my $dir (@aliased_dirs) {
    debug("creating shadow dir = $sroot$dir");
    mkdir "$sroot$dir"
        or sysfatal("cannot create directory $sroot$dir");
    chmod 0755, "$sroot$dir"
        or sysfatal("cannot chmod 0755 $sroot$dir");
    chown 0, 0, "$sroot$dir"
        or sysfatal("cannot chown 0 0 $sroot$dir");
    push @relabel, "$sroot$dir";
}

#
# Populate the split dirs with hardlinks or copies of the objects from
# their counter-parts in /usr.
#

foreach my $pathname (sort keys %aliased_pathnames) {
    my (@meta) = lstat $pathname
        or sysfatal("cannot lstat object $pathname for shadow hierarchy");

    if (-d _) {
        my $mode = $meta[2];
        my ($uid, $gid) = @meta[4, 5];
        my ($atime, $mtime, $ctime) = @meta[8, 9, 10];

        debug("creating shadow dir = $sroot$pathname");
        mkdir "$sroot$pathname"
            or sysfatal("cannot mkdir $sroot$pathname");
        chmod $mode, "$sroot$pathname"
            or sysfatal("cannot chmod $mode $sroot$pathname");
        chown $uid, $gid, "$sroot$pathname"
            or sysfatal("cannot chown $uid $gid $sroot$pathname");
        utime $atime, $mtime, "$sroot$pathname"
            or sysfatal("cannot utime $atime $mtime $sroot$pathname");
        push @relabel, "$sroot$pathname";
    } elsif (-f _) {
        debug("creating shadow file = $sroot$pathname");
        copy("/usr$pathname", "$sroot$pathname");
    } elsif (-l _) {
        my $target = readlink "/usr$pathname";

        debug("creating shadow symlink = $sroot$pathname");
        symlink $target, "$sroot$pathname"
            or sysfatal("cannot symlink $target to $sroot$pathname");
        push @relabel, "$sroot$pathname";
    } else {
        fatal("unhandled object type for '$pathname'");
    }
}

#
# Prompt at the point of no return, if the user requested it.
#

if ($opt_prompt) {
    if (!prompt("Shadow hierarchy created at '$sroot', ready to proceed")) {
        print "Aborting migration, shadow hierarchy left in place.\n";
        exit 0;
    }
}

#
# Mark all packages as half-configured so that we can force a mass
# reconfiguration, to trigger any code in maintainer scripts that might
# create files.
#
# XXX: We do this manually by editing the status file.
# XXX: We do this for packages that might not have maintscripts, or might
#      not involve affected directories.
#

debug('marking all dpkg packages as half-configured');
if (not $opt_noact) {
    open my $fh_lock, '>', "$ADMINDIR/lock"
        or sysfatal('cannot open dpkg database lock file');
    my $fs = File::FcntlLock->new(l_type => F_WRLCK);
    $fs->lock($fh_lock, F_SETLKW)
        or sysfatal('cannot get a write lock on dpkg database');

    my $file_db = "$ADMINDIR/status";
    my $file_dbnew = $file_db . '.new';

    open my $fh_dbnew, '>', $file_dbnew
        or sysfatal('cannot open new dpkg database');
    open my $fh_db, '<', $file_db
        or sysfatal('cannot open dpkg database');
    while (<$fh_db>) {
        if (m/^Status: /) {
            s/ installed$/ half-configured/;
        }
        print { $fh_dbnew } $_;
    }
    close $fh_db;
    $fh_dbnew->flush() or sysfatal('cannot flush new dpkg database');
    $fh_dbnew->sync() or sysfatal('cannot fsync new dpkg database');
    close $fh_dbnew or sysfatal('cannot close new dpkg database');

    rename $file_dbnew, $file_db
        or sysfatal('cannot rename new dpkg database');
}

#
# Replace things as quickly as possible:
#

foreach my $dir (@aliased_dirs) {
    debug("making dir backup = $dir.aliased");
    if (not $opt_noact) {
        rename $dir, "$dir.aliased"
            or sysfatal("cannot make backup directory $dir.aliased");
    }

    debug("renaming $sroot$dir to $dir");
    if (not $opt_noact) {
        rename "$sroot$dir", $dir
            or sysfatal("cannot install fixed directory $dir");
    }
}

mac_relabel();

#
# Cleanup backup directories.
#

foreach my $dir (@aliased_dirs) {
    debug("removing backup = $dir.aliased");
    if (not $opt_noact) {
        unlink "$dir.aliased"
            or sysfatal("cannot cleanup backup directory $dir.aliased");
    }
}

my %deferred_dirnames;

#
# Cleanup moved objects.
#

foreach my $pathname (sort keys %aliased_pathnames) {
    my (@meta) = lstat $pathname
        or sysfatal("cannot lstat object $pathname for cleanup");

    if (-d _) {
        # Skip directories as this might be shared by a proper path under the
        # aliased hierearchy. And so that we can remove them in reverse order.
        debug("deferring merged dir cleanup = /usr$pathname");
        $deferred_dirnames{"/usr$pathname"} = 1;
    } else {
        debug("cleaning up pathname = /usr$pathname");
        next if $opt_noact;
        unlink "/usr$pathname"
            or sysfatal("cannot unlink object /usr$pathname");
    }
}

#
# Cleanup deferred directories.
#

debug("cleaning up shadow deferred dir = $sroot");
my $arg_max = POSIX::sysconf(POSIX::_SC_ARG_MAX) // POSIX::_POSIX_ARG_MAX;
my @batch_dirs;
my $batch_size = 0;

foreach my $dir (keys %deferred_dirnames) {
    my $dir_size = length($dir) + 1;
    if ($batch_size + $dir_size < $arg_max) {
        $batch_size += length($dir) + 1;
        push @batch_dirs, $dir;

    } else {
        next;
    }
    next if length $batch_size == 0;

    open my $fh_dirs, '-|', 'dpkg-query', '--search', @batch_dirs
        or fatal("cannot execute dpkg-query --search: $!");
    while (<$fh_dirs>) {
        if (m/^.*: (.*)$/) {
            # If the directory is known by its aliased name, it should not be
            # cleaned up.
            if (exists $deferred_dirnames{$1}) {
                delete $deferred_dirnames{$1};
            }
        }
    }
    close $fh_dirs;

    @batch_dirs = ();
    $batch_size = 0;
}

my @dirs_linger;

if (not $opt_noact) {
    foreach my $dirname (reverse sort keys %deferred_dirnames) {
        next if rmdir $dirname;
        warning("cannot remove shadow directory $dirname: $!");

        push @dirs_linger, $dirname;
    }
}

if (not $opt_noact) {
    debug("cleaning up shadow root dir = $sroot");
    rmdir $sroot
        or warning("cannot remove shadow directory $sroot: $!");
}

#
# Re-configure all packages, so that postinst maintscripts are executed.
#

my $policypath = '/usr/sbin/dpkg-fsys-usrunmess-policy-rc.d';

debug('installing local policy-rc.d');
if (not $opt_noact) {
    open my $policyfh, '>', $policypath
        or sysfatal("cannot create $policypath");
    print { $policyfh } <<'POLICYRC';
#!/bin/sh
echo "$0: Denied action $2 for service $1"
exit 101
POLICYRC
    close $policyfh or fatal("cannot write $policypath");

    my @alt = (qw(/usr/sbin/policy-rc.d policy-rc.d), $policypath, qw(1000));
    system(qw(update-alternatives --install), @alt) == 0
        or fatal("cannot register $policypath");

    system(qw(update-alternatives --set policy-rc.d), $policypath) == 0
        or fatal("cannot select alternative $policypath");
}

debug('reconfiguring all packages');
if (not $opt_noact) {
    local $ENV{DEBIAN_FRONTEND} = 'noninteractive';
    system(qw(dpkg --configure --pending)) == 0
        or fatal("cannot reconfigure packages: $!");
}

debug('removing local policy-rc.d');
if (not $opt_noact) {
    system(qw(update-alternatives --remove policy-rc.d), $policypath) == 0
        or fatal("cannot unregister $policypath: $!");

    unlink $policypath
        or warning("cannot remove $policypath");

    # Restore the selections we saved initially.
    open my $altfh, '|-', qw(update-alternatives --set-selections)
        or fatal('cannot restore alternatives state');
    print { $altfh } $_ foreach @selections;
    close $altfh or fatal('cannot restore alternatives state');
}

print "\n";

if (@dirs_linger) {
    warning('lingering directories that could not be removed:');
    foreach my $dir (@dirs_linger) {
        warning("  $dir");
    }
}

print "Done, hierarchy unmessed, congrats!\n";
print "Rebooting now is very strongly advised.\n";

print "(Note: you might need to run 'hash -r' in your shell.)\n";

1;

##
## Functions
##

sub debug
{
    my $msg = shift;

    print { *STDERR } "D: $msg\n";
}

sub warning
{
    my $msg = shift;

    warn "warning: $msg\n";
}

sub fatal
{
    my $msg = shift;

    die "error: $msg\n";
}

sub sysfatal
{
    my $msg = shift;

    fatal("$msg: $!");
}

sub copy
{
    my ($src, $dst) = @_;

    # Try to hardlink first.
    return if link $src, $dst;

    # If we are on different filesystems, try a copy.
    if ($! == POSIX::EXDEV) {
        # XXX: This will not preserve hardlinks, these would get restored
        # after the next package upgrade.
        system('cp', '-a', $src, $dst) == 0
            or fatal("cannot copy file $src to $dst: $?");
    } else {
        sysfatal("cannot link file $src to $dst");
    }
}

sub mac_relabel
{
    my $has_cmd = 0;
    foreach my $path (split /:/, $ENV{PATH}) {
        if (-x "$path/restorecon") {
            $has_cmd = 1;
            last;
        }
    }
    return unless $has_cmd;

    foreach my $pathname (@relabel) {
        system('restorecon', $pathname) == 0
            or fatal("cannot restore MAC context for $pathname: $?");
    }
}

sub add_pathname
{
    my ($pathname, $origin) = @_;

    if ($pathname =~ m{^/usr/lib/modules/}) {
        debug("tracking $origin = $pathname");
        $usr_mod_pathnames{$pathname} = 1;
    } elsif ($pathname =~ m/$aliased_regex/) {
        debug("adding $origin = $pathname");
        $aliased_pathnames{$pathname} = 1;
    }
}

sub prompt
{
    my $query = shift;

    print "$query (y/N)? ";
    my $reply = <STDIN>;
    chomp $reply;

    return 0 if $reply ne 'y' and $reply ne 'yes';
    return 1;
}

sub version()
{
    printf "Debian %s version %s.\n", $PROGNAME, $PROGVERSION;
}

sub usage
{
    printf
'Usage: %s [<option>...]'
    . "\n\n" .
'Options:
  -p, --prompt         prompt before the point of no return.
      --prevention     enable regression prevention package installation.
      --no-prevention  disable regression prevention package installation.
  -n, --no-act         just check and create the new structure, no switch.
      --dry-run        ditto.
  -?, --help           show this help message.
      --version        show the version.'
    . "\n", $PROGNAME;
}

sub usageerr
{
    my $msg = shift;

    state $printforhelp = 'Use --help for program usage information.';

    $msg = sprintf $msg, @_ if @_;
    warn "$PROGNAME: error: $msg\n";
    warn "$printforhelp\n";
    exit 2;
}
