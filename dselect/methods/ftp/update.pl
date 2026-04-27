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

eval q{
    use Dpkg::ErrorHandling;
};
if ($@) {
    warn "Missing Dpkg modules required by the FTP access method.\n\n";
    exit 1;
}

use File::stat ();

use Dselect::Method;
use Dselect::Method::Ftp;

# Deal with arguments.
my $vardir = $ARGV[0];
my $method = $ARGV[1];
my $option = $ARGV[2];

if ($option eq 'manual') {
    print "Enter package file names or a blank line to finish\n";
    while (1) {
        print 'Enter package file name:';
        my $fn = <STDIN>;
        chomp $fn;
        if ($fn eq '') {
            exit 0;
        }
        if (-f $fn) {
            system('dpkg', '--merge-avail', $fn);
        } else {
            errormsg("cannot find '%s', try again", $fn);
        }
    }
}

#print "vardir: $vardir, method: $method, option: $option\n";

my $arch = qx(dpkg --print-architecture);
$arch = 'i386' if $?;
chomp $arch;
my $exit = 0;

# Get info from control file.
read_config("$vardir/methods/ftp/vars");

chdir "$vardir/methods/ftp";

print "Getting Packages files... (use Ctrl+C to stop)\n\n";

my @pkgfiles;
my $ftp;
my $packages_modified = 0;

sub download {
    foreach my $site (@{$CONFIG{site}}) {
        $ftp = do_connect(
            ftpsite => $site->[0],
            ftpdir => $site->[1],
            passive => $site->[3],
            username => $site->[4],
            password => $site->[5],
            useproxy => $CONFIG{use_auth_proxy},
            proxyhost => $CONFIG{proxyhost},
            proxylogname => $CONFIG{proxylogname},
            proxypassword => $CONFIG{proxypassword},
        );

        my @dists = @{$site->[2]};
        PACKAGE: foreach my $dist (@dists) {
            my $dir = "$dist/binary-$arch";
            my $must_get = 0;
            my $newest_pack_date;

            # Check existing Packages on remote site.
            print "\nChecking for Packages file... ";
            $newest_pack_date = do_mdtm($ftp, "$dir/Packages.gz");
            if (defined $newest_pack_date) {
                print "$dir/Packages.gz\n";
            } else {
                $dir = "$dist";
                $newest_pack_date = do_mdtm($ftp, "$dir/Packages.gz");
                if (defined $newest_pack_date) {
                    print "$dir/Packages.gz\n";
                } else {
                    errormsg('cannot find Packages.gz in %s or %s; ignoring',
                             "$dist/binary-$arch", $dist);
                    hint("the setup is probably wrong, check the distributions directories,\n" .
                         'and try with passive mode enabled/disabled (when using a proxy/firewall)');
                    next PACKAGE;
                }
            }

            # We now have $dir set to point to an existing Packages.gz file.

            # Check if we already have a Packages file (and get its date).
            $dist =~ tr/\//_/;
            my $file = "Packages.$site->[0].$dist";

            # If not.
            if (! -f $file) {
                # Must get one.
#               print "No Packages here; must get it.\n";
                $must_get = 1;
            } else {
                # Else check last modification date.
                my $st = File::stat::stat($file);
                if (! defined $st) {
                    $must_get = 1;
                } elsif ($newest_pack_date > $st->mtime) {
#                   print "Packages has changed; must get it.\n";
                    $must_get = 1;
                } elsif ($newest_pack_date < $st->mtime) {
                    print " Our file is newer than theirs; skipping.\n";
                } else {
                    print " Already up-to-date; skipping.\n";
                }
            }

            if ($must_get) {
                unlink 'Packages.gz';
                unlink 'Packages';
                my $size = 0;

                TRY_GET_PACKAGES: while (1) {
                    if ($size) {
                        print ' Continuing ';
                    } else {
                        print ' Getting ';
                    }
                    print "Packages file from $dir...\n";
                    eval {
                        if ($ftp->get("$dir/Packages.gz", 'Packages.gz', $size)) {
                            if (system('gunzip', 'Packages.gz')) {
                                subprocerr('gunzip Packages.gz');
                            }
                        } else {
                            error("cannot get '%s' from directory '%s'",
                                  'Packages.gz', $dir);
                        }
                    };
                    if ($@) {
                        $size = -s 'Packages.gz';
                        if (ref($ftp)) {
                            $ftp->abort();
                            $ftp->quit();
                        }
                        if (yesno('y', "Transfer failed at $size: retry at once")) {
                            $ftp = do_connect(
                                ftpsite => $site->[0],
                                ftpdir => $site->[1],
                                passive => $site->[3],
                                username => $site->[4],
                                password => $site->[5],
                                useproxy => $CONFIG{use_auth_proxy},
                                proxyhost => $CONFIG{proxyhost},
                                proxylogname => $CONFIG{proxylogname},
                                proxypassword => $CONFIG{proxypassword},
                            );

                            if ($newest_pack_date != do_mdtm($ftp, "$dir/Packages.gz")) {
                                print ("Packages file has changed !\n");
                                $size = 0;
                            }
                            next TRY_GET_PACKAGES;
                        } else {
                            error("cannot download '%s' file", 'Packages.gz');
                        }
                    }
                    last TRY_GET_PACKAGES;
                }

                if (! rename 'Packages', "Packages.$site->[0].$dist") {
                    error("cannot rename '%s' to '%s'",
                          'Packages', "Packages.$site->[0].$dist");
                } else {
                    # Set local Packages file to same date as the one it mirrors
                    # to allow comparison to work.
                    utime $newest_pack_date, $newest_pack_date, "Packages.$site->[0].$dist";
                    $packages_modified = 1;
                }
            }
            push @pkgfiles, "Packages.$site->[0].$dist";
        }
        $ftp->quit();
    }
}

eval {
    local $SIG{INT} = sub {
        error('interrupted!');
    };
    download();
};
if ($@) {
    $ftp->quit() if (ref($ftp));
    my $reason;
    if ($@ =~ /timeout/i) {
        $reason = 'connection timed out';
    } else {
        $reason = "$@";
    }
    errormsg('cannot download using FTP: %s', $reason);
    $exit = 1;
}

# Do not clear if nothing changed.
if ($packages_modified) {
    print <<'EOM';

It is a good idea to clear the available list of old packages.
However if you have only downloaded a Package files from non-main
distributions you might not want to do this.

EOM
    if (yesno('y', 'Do you want to clear available list')) {
        print "Clearing...\n";
        if (system('dpkg', '--clear-avail')) {
            subprocerr('dpkg --clear-avail');
        }
    }
}

if (! $packages_modified) {
    print "No Packages files was updated.\n";
} else {
    foreach my $file (@pkgfiles) {
        if (system('dpkg', '--merge-avail', $file)) {
            errormsg('%s subprocess failed', "dpkg --merge-avail $file");
            $exit = 1;
        }
    }
}
exit $exit;
