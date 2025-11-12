#!/usr/bin/perl
#
# Copyright © 1996 Andy Guy <andy@cyteen.org>
# Copyright © 1998 Martin Schulze <joey@infodrom.north.de>
# Copyright © 1999, 2009 Raphaël Hertzog <hertzog@debian.org>
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
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

use v5.36;

use File::Path qw(make_path remove_tree);
use File::Basename;

eval q{
    use File::Find;
    use Data::Dumper;

    use Dpkg::File;
    use Dpkg::Version;
};
if ($@) {
    warn "Missing Dpkg modules required by the FTP access method.\n\n";
    exit 1;
}

use Dselect::Method;
use Dselect::Method::Ftp;

my $ftp;

# Exit value.
my $exit = 0;

# Deal with arguments.
my $vardir = $ARGV[0];
my $method = $ARGV[1];
my $option = $ARGV[2];

if ($option eq 'manual') {
    print "manual mode not supported yet\n";
    exit 1;
}
#print "vardir: $vardir, method: $method, option: $option\n";

my $methdir = "$vardir/methods/ftp";

# Get info from control file.
read_config("$methdir/vars");

chdir "$methdir";
make_path("$methdir/$CONFIG{dldir}", { mode => 0o755 });


# Read md5sums already calculated.
my %md5sums;
if (-f "$methdir/md5sums") {
    my $code = file_slurp("$methdir/md5sums");
    my $VAR1; ## no critic (Variables::ProhibitUnusedVariables)
    my $res = eval $code;
    if ($@) {
        die "cannot eval $methdir/md5sums content: $@\n";
    }
    if (ref($res)) {
        %md5sums = %{$res}
    }
}

# Get a stanza.
#
# Returns a ref to a hash containing flds->fld contents, white space from
# the ends of lines is removed and newlines added (no trailing newline).
# If something unexpected happens then it dies.
sub get_stanza {
    my $fh = shift;
    my %flds;
    my $fld;
    while (<$fh>) {
        if (length != 0) {
            FLDLOOP: while (1) {
                if (/^(\S+):\s*(.*)\s*$/) {
                    $fld = lc($1);
                    $flds{$fld} = $2;
                    while (<$fh>) {
                        if (length == 0) {
                            return %flds;
                        } elsif (/^(\s.*)$/) {
                            $flds{$fld} = $flds{$fld} . "\n" . $1;
                        } else {
                            next FLDLOOP;
                        }
                    }
                    return %flds;
                } else {
                    die "expected a start of field line, but got:\n$_";
                }
            }
        }
    }
    return %flds;
}

# Process status file.
#
# Create curpkgs hash with version (no version implies not currently installed)
# of packages we want.
print "Processing status file...\n";
my %curpkgs;
sub procstatus {
    my (%flds, $fld);
    open(my $status_fh, '<', "$vardir/status") or
        die 'Could not open status file';
    while (%flds = get_stanza($status_fh), %flds) {
        if ($flds{'status'} =~ /^install ok/) {
            my $cs = (split(/ /, $flds{'status'}))[2];
            if (($cs eq 'not-installed') ||
                ($cs eq 'half-installed') ||
                ($cs eq 'config-files')) {
                $curpkgs{$flds{'package'}} = '';
            } else {
                $curpkgs{$flds{'package'}} = $flds{'version'};
            }
        }
    }
    close($status_fh);
}
procstatus();

# Process package files, looking for packages to install.
#
# Create a hash of these packages pkgname => version, filenames...
# filename => md5sum, size
# for all packages.
my %pkgs;
my %pkgfiles;
sub procpkgfile {
    my $fn = shift;
    my $site = shift;
    my $dist = shift;
    my (@files, @sizes, @md5sums, $pkg, $ver, $nfs, $fld);
    my %flds;

    open(my $pkgfile_fh, '<', $fn) or die "could not open package file $fn";
    while (%flds = get_stanza($pkgfile_fh), %flds) {
        $pkg = $flds{'package'};
        $ver = $curpkgs{$pkg};
        @files = split(/[\s\n]+/, $flds{'filename'});
        @sizes = split(/[\s\n]+/, $flds{'size'});
        @md5sums = split(/[\s\n]+/, $flds{'md5sum'});
        if (defined($ver) &&
            (($ver eq '') || version_compare($ver, $flds{'version'}) < 0)) {
            $pkgs{$pkg} = [ $flds{'version'}, [ @files ], $site ];
            $curpkgs{$pkg} = $flds{'version'};
        }
        $nfs = scalar(@files);
        if (($nfs != scalar(@sizes)) || ($nfs != scalar(@md5sums))) {
            print "Different number of filenames, sizes and md5sums for $flds{'package'}\n";
        } else {
            my $i = 0;
            foreach my $fl (@files) {
                $pkgfiles{$fl} = [ $md5sums[$i], $sizes[$i], $site, $dist ];
                $i++;
            }
        }
    }
    close $pkgfile_fh or die "cannot close package file $fn: $!\n";
}

print "\nProcessing Package files...\n";
my ($i, $j);
$i = 0;
foreach my $site (@{$CONFIG{site}}) {
    $j = 0;
    foreach my $dist (@{$site->[2]}) {
        my $fn = $dist;
        $fn =~ tr{/}{_};
        $fn = "Packages.$site->[0].$fn";
        if (-f $fn) {
            print " $site->[0] $dist...\n";
            procpkgfile($fn, $i, $j);
        } else {
            print "Could not find packages file for $site->[0] $dist distribution (re-run Update)\n"
        }
        $j++;
    }
    $i++;
}

my $dldir = $CONFIG{dldir};
# Compute the MD5 digest for a file.
sub md5sum {
    my $fn = shift;
    my $m = qx(md5sum $fn);
    $m = (split(' ', $m))[0];
    $md5sums{"$dldir/$fn"} = $m;
    return $m;
}

# Construct list of files to get hash of filenames => size of downloaded part
# query user for each partial file.
print "\nConstructing list of files to get...\n";
my %downloads;
my ($dir, @info, @files, $csize, $size);
my $totsize = 0;
foreach my $pkg (keys(%pkgs)) {
    @files = @{$pkgs{$pkg}[1]};
    foreach my $fn (@files) {
        # Look for a partial file.
        if (-f "$dldir/$fn.partial") {
            rename "$dldir/$fn.partial", "$dldir/$fn";
        }
        $dir = dirname($fn);
        if (! -d "$dldir/$dir") {
            make_path("$dldir/$dir", { mode => 0o755 });
        }
        @info = @{$pkgfiles{$fn}};
        $csize = int($info[1] / 1024) + 1;
        if (-f "$dldir/$fn") {
            $size = -s "$dldir/$fn";
            if ($info[1] > $size) {
                # Partial download.
                if (yesno('y', "continue file: $fn (" . nb($size) . '/' .
                               nb($info[1]) . ')')) {
                    $downloads{$fn} = $size;
                    $totsize += $csize - int($size / 1024);
                } else {
                    $downloads{$fn} = 0;
                    $totsize += $csize;
                }
            } else {
                # Check md5sum digest.
                if (! exists $md5sums{"$dldir/$fn"}) {
                  $md5sums{"$dldir/$fn"} = md5sum("$dldir/$fn");
                }
                if ($md5sums{"$dldir/$fn"} eq $info[0]) {
                    print "already got: $fn\n";
                } else {
                    print "corrupted: $fn\n";
                    $downloads{$fn} = 0;
                }
            }
        } else {
            my $ffn = $fn;
            $ffn =~ s/binary-[^\/]+/.../;
            print 'want: ' .
                  $CONFIG{site}[$pkgfiles{$fn}[2]][0] . " $ffn (${csize}k)\n";
            $downloads{$fn} = 0;
            $totsize += $csize;
        }
    }
}

my $avsp = qx(df -Pk $dldir| awk '{ print \$4}' | tail -n 1);
chomp $avsp;

print "\nApproximate total space required: ${totsize}k\n";
print "Available space in $dldir: ${avsp}k\n";

#$avsp = qx(df -k $::dldir| paste -s | awk '{ print \$11});
#chomp $avsp;

if ($totsize == 0) {
    print 'Nothing to get.';
} else {
    if ($totsize > $avsp) {
        print "Space required is greater than available space,\n";
        print "you will need to select which items to get.\n";
    }
    # Ask user which files to get.
    if (($totsize > $avsp) ||
        yesno('n', 'Do you want to select the files to get')) {
        $totsize = 0;
        my @files = sort(keys(%downloads));
        my $def = 'y';
        foreach my $fn (@files) {
            my @info = @{$pkgfiles{$fn}};
            my $csize = int($info[1] / 1024) + 1;
            my $rsize = int(($info[1] - $downloads{$fn}) / 1024) + 1;
            if ($rsize + $totsize > $avsp) {
                print "no room for: $fn\n";
                delete $downloads{$fn};
            } elsif (yesno($def, $downloads{$fn}
                           ? "download: $fn ${rsize}k/${csize}k (total = ${totsize}k)"
                           : "download: $fn ${rsize}k (total = ${totsize}k)")) {
                $def = 'y';
                $totsize += $rsize;
            } else {
                $def = 'n';
                delete $downloads{$fn};
            }
        }
    }
}

sub download {
    my $i = 0;

    foreach my $site (@{$CONFIG{site}}) {
        my @getfiles = grep { $pkgfiles{$_}[2] == $i } keys %downloads;
        # Directory to add before $fn.
        my @pre_dist = ();

        # Scan distributions for looking at "(../)+/dir/dir".
        my ($n, $cp);
        $cp = -1;
        foreach (@{$site->[2]}) {
            $cp++;
            $pre_dist[$cp] = '';
            $n = (s{\.\./}{../}g);
            next if (! $n);
            if (m<^((?:\.\./){$n}(?:[^/]+/){$n})>) {
                $pre_dist[$cp] = $1;
            }
        }

        if (! @getfiles) {
            $i++;
            next;
        }

        $ftp = do_connect(
            ftpsite => $site->[0],
            ftpdir => $site->[1],
            passive => $site->[3],
            username =>  $site->[4],
            password => $site->[5],
            useproxy => $CONFIG{use_auth_proxy},
            proxyhost => $CONFIG{proxyhost},
            proxylogname => $CONFIG{proxylogname},
            proxypassword => $CONFIG{proxypassword},
        );

        local $SIG{INT} = sub { die "Interrupted !\n"; };

        my ($rsize, $res, $pre);
        foreach my $fn (@getfiles) {
            $pre = $pre_dist[$pkgfiles{$fn}[3]] || '';
            if ($downloads{$fn}) {
                $rsize = ${pkgfiles{$fn}}[1] - $downloads{$fn};
                print "getting: $pre$fn (" . nb($rsize) . '/' .
                      nb($pkgfiles{$fn}[1]) . ")\n";
            } else {
                print "getting: $pre$fn (". nb($pkgfiles{$fn}[1]) . ")\n";
            }
            $res = $ftp->get("$pre$fn", "$dldir/$fn", $downloads{$fn});
            if (! $res) {
                my $r = $ftp->code();
                print $ftp->message() . "\n";
                if (! ($r == 550 || $r == 450)) {
                    return 1;
                } else {
                    # Try to find another file or this package.
                    print "Looking for another version of the package...\n";
                    my ($dir, $package) = ($fn =~ m{^(.*)/([^/]+)_[^/]+.deb$});
                    my $list = $ftp->ls("$pre$dir");
                    if ($ftp->ok() && ref($list)) {
                        foreach my $file (@{$list}) {
                            if ($file =~ m/($dir\/\Q$package\E_[^\/]+.deb)/i) {
                                print "Package found : $file\n";
                                print "getting: $file (size not known)\n";
                                $res = $ftp->get($file, "$dldir/$1");
                                if (! $res) {
                                    $r = $ftp->code();
                                    print $ftp->message() . "\n";
                                    return 1 if ($r != 550 and $r != 450);
                                }
                            }
                        }
                    }
                }
            }
            # Fully got, remove it from list in case we have to re-download.
            delete $downloads{$fn};
        }
        $ftp->quit();
        $i++;
    }
    return 0;
}

# Download stuff (protect from Ctrl+C).
if ($totsize != 0) {
    if (yesno('y', "\nDo you want to download the required files")) {
        DOWNLOAD_TRY: while (1) {
            print "Downloading files... (use Ctrl+C to stop)\n";
            eval {
                if ((download() == 1) &&
                    yesno('y', "\nDo you want to retry downloading at once")) {
                    next DOWNLOAD_TRY;
                }
            };
            if ($@ =~ /Interrupted|Timeout/i) {
                # Close the FTP connection if needed.
                if ((ref($ftp) =~ /Net::FTP/) and ($@ =~ /Interrupted/i)) {
                    $ftp->abort();
                    $ftp->quit();
                    undef $ftp;
                }
                print "FTP ERROR\n";
                if (yesno('y', "\nDo you want to retry downloading at once")) {
                    # Get the first $fn that foreach would give:
                    #   this is the one that got interrupted.
                    my $fn;
                    MY_ITER: foreach my $ffn (keys(%downloads)) {
                        $fn = $ffn;
                        last MY_ITER;
                    }
                    my $size = -s "$dldir/$fn";
                    # Partial download.
                    if (yesno('y', "continue file: $fn (at $size)")) {
                        $downloads{$fn} = $size;
                    } else {
                        $downloads{$fn} = 0;
                    }
                    next DOWNLOAD_TRY;
                } else {
                    $exit = 1;
                    last DOWNLOAD_TRY;
                }
            } elsif ($@) {
                print "An error occurred ($@) : stopping download\n";
            }
            last DOWNLOAD_TRY;
        }
    }
}

# Remove duplicate packages (keep latest versions).
#
# Move half downloaded files out of the way delete corrupted files.
print "\nProcessing downloaded files...(for corrupt/old/partial)\n";
# package => version
my %vers;
# package-version => files...
my %files;

# Check a deb or split deb file.
#
# Return 1 if it a deb file.
# Return 2 if it is a split deb file.
# Else return 0.
sub chkdeb {
    my ($fn) = @_;
    # Check to see if it is a .deb file.
    if (! system "dpkg-deb --info $fn >/dev/null 2>&1 && dpkg-deb --contents $fn >/dev/null 2>&1") {
        return 1;
    } elsif (! system "dpkg-split --info $fn >/dev/null 2>&1") {
        return 2;
    }
    return 0;
}
sub getdebinfo {
    my ($fn) = @_;
    my $type = chkdeb($fn);
    my ($pkg, $ver);
    if ($type == 1) {
        open(my $pkgfile_fh, '-|', "dpkg-deb --field $fn")
            or die "cannot create pipe for 'dpkg-deb --field $fn'";
        my %fields = get_stanza($pkgfile_fh);
        close($pkgfile_fh);
        $pkg = $fields{'package'};
        $ver = $fields{'version'};
        return $pkg, $ver;
    } elsif ($type == 2) {
        open(my $pkgfile_fh, '-|', "dpkg-split --info $fn")
            or die "cannot create pipe for 'dpkg-split --info $fn'";
        while (<$pkgfile_fh>) {
            if (/Part of package:\s*(\S+)/) {
                $pkg = $1;
            }
            if (/\.\.\. version:\s*(\S+)/) {
                $ver = $1;
            }
        }
        close($pkgfile_fh);
        return $pkg, $ver;
    }
    print "could not figure out type of $fn\n";
    return $pkg, $ver;
}

# Process deb file to make sure we only keep latest versions.
sub prcdeb {
    my ($dir, $fn) = @_;
    my ($pkg, $ver) = getdebinfo($fn);
    if (! defined($pkg) || ! defined($ver)) {
        print "could not get package info from file\n";
        return 0;
    }
    if ($vers{$pkg}) {
        my $ver_rel = version_compare($vers{$pkg}, $ver);
        if ($ver_rel == 0) {
            $files{$pkg . $ver} = [ $files{$pkg . $ver }, "$dir/$fn" ];
        } elsif ($ver_rel > 0) {
            print "old version\n";
            unlink $fn;
        } else {
            # Otherwise $ver is gt current version.
            foreach my $c (@{$files{$pkg . $vers{$pkg}}}) {
                print "replaces: $c\n";
                unlink "$vardir/methods/ftp/$dldir/$c";
            }
            $vers{$pkg} = $ver;
            $files{$pkg . $ver} = [ "$dir/$fn" ];
        }
    } else {
        $vers{$pkg} = $ver;
        $files{$pkg . $ver} = [ "$dir/$fn" ];
    }
}

sub prcfile {
    my $fn = $_;
    if (-f $fn and $fn ne '.') {
        my $dir = '.';
        if (length($File::Find::dir) > length($dldir)) {
            $dir = substr($File::Find::dir, length($dldir) + 1);
        }
        print "$dir/$fn\n";
        if (defined($pkgfiles{"$dir/$fn"})) {
            my @info = @{$pkgfiles{"$dir/$fn"}};
            my $size = -s $fn;
            if ($size == 0) {
                print "zero length file\n";
                unlink $fn;
            } elsif ($size < $info[1]) {
                print "partial file\n";
                rename $fn, "$fn.partial";
            } elsif (((exists $md5sums{"$dldir/$fn"}) and
                      ($md5sums{"$dldir/$fn"} ne $info[0])) or
                     (md5sum($fn) ne $info[0])) {
                print "corrupt file\n";
                unlink $fn;
            } else {
                prcdeb($dir, $fn);
            }
        } elsif ($fn =~ /.deb$/) {
            if (chkdeb($fn)) {
                prcdeb($dir, $fn);
            } else {
                print "corrupt file\n";
                unlink $fn;
            }
        } else {
            print "non-debian file\n";
        }
    }
}
find(\&prcfile, "$dldir/");

# Install ".debs".
if (yesno('y', "\nDo you want to install the files fetched")) {
    print "Installing files...\n";
    # Installing pre-dependent package before.
    my (@flds, $package, @filename, $r);
    while (@flds = qx(dpkg --predep-package), $? == 0) {
        foreach my $field (@flds) {
            $field =~ s/\s*\n//;
            $package = $field if $field =~ s/^Package: //i;
            @filename = split / +/, $field if $field =~ s/^Filename: //i;
        }
        @filename = map { "$dldir/$_" } @filename;
        next if (! @filename);
        $r = system('dpkg', '-iB', '--', @filename);
        if ($r) {
            print "DPKG ERROR\n";
            $exit = 1;
        }
    }
    # Installing other packages after.
    $r = system('dpkg', '-iGREOB', $dldir);
    if ($r) {
        print "DPKG ERROR\n";
        $exit = 1;
    }
}

sub removeinstalled {
    my $fn = $_;
    if (-f $fn and $fn ne '.') {
        my $dir = '.';
        if (length($File::Find::dir) > length($dldir)) {
            $dir = substr($File::Find::dir, length($dldir) + 1);
        }
        if ($fn =~ /.deb$/) {
            my ($pkg, $ver) = getdebinfo($fn);
            if (! defined($pkg) || ! defined($ver)) {
                print "Could not get info for: $dir/$fn\n";
            } elsif ($curpkgs{$pkg} &&
                     version_compare($ver, $curpkgs{$pkg}) <= 0) {
                print "deleting: $dir/$fn\n";
                unlink $fn;
            } else {
                print "leaving: $dir/$fn\n";
            }
        } else {
            print "non-debian: $dir/$fn\n";
        }
    }
}

# Remove .debs that have been installed (query user).
#
# First need to reprocess status file.
if (yesno('y', "\nDo you wish to delete the installed package (.deb) files?")) {
    print "Removing installed files...\n";
    %curpkgs = ();
    procstatus();
    find(\&removeinstalled, "$dldir/");
}

# Remove whole ./debian directory if user wants to.
if (yesno('n', "\nDo you want to remove $dldir directory?")) {
    remove_tree($dldir);
}

# Store useful md5sums.
foreach my $file (keys %md5sums) {
    next if -f $file;
    delete $md5sums{$file};
}
file_dump("$methdir/md5sums", Dumper(\%md5sums));

exit $exit;
