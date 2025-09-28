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

=encoding utf8

=head1 NAME

Dselect::Method::Ftp - dselect FTP method support

=head1 DESCRIPTION

This module provides support functions for the FTP method.

B<Note>: This is a private module, its API can change at any time.

=cut

package Dselect::Method::Ftp 0.01;

use v5.36;

our @EXPORT = qw(
    do_connect
    do_mdtm
);

use Exporter qw(import);
use Carp;

eval q{
    use Net::FTP;
    use Data::Dumper;
};
if ($@) {
    warn "Missing Net::FTP modules required by the FTP access method.\n\n";
    exit 1;
}

sub do_connect {
    my (%opts) = @_;

    my ($rpass, $remotehost, $remoteuser, $ftp);

    TRY_CONNECT: while (1) {
        my $exit = 0;

        if ($opts{useproxy}) {
            $remotehost = $opts{proxyhost};
            $remoteuser = $opts{username} . '@' . $opts{ftpsite};
        } else {
            $remotehost = $opts{ftpsite};
            $remoteuser = $opts{username};
        }
        print "Connecting to $opts{ftpsite}...\n";
        $ftp = Net::FTP->new($remotehost,
            Passive => $opts{passive},
        );
        if (! $ftp || ! $ftp->ok) {
            print "Failed to connect\n";
            $exit = 1;
        }
        if (! $exit) {
#           $ftp->debug(1);
            if ($opts{useproxy}) {
                print "Login on $opts{proxyhost}...\n";
                $ftp->_USER($opts{proxylogname});
                $ftp->_PASS($opts{proxypassword});
            }
            print "Login as $opts{username}...\n";
            if ($opts{password} eq '?') {
                print 'Enter password for ftp: ';
                system('stty', '-echo');
                $rpass = <STDIN>;
                chomp $rpass;
                print "\n";
                system('stty', 'echo');
            } else {
                $rpass = $opts{password};
            }
            if (! $ftp->login($remoteuser, $rpass)) {
                print $ftp->message() . "\n";
                $exit = 1;
            }
        }
        if (! $exit) {
            print "Setting transfer mode to binary...\n";
            if (! $ftp->binary()) {
                print $ftp->message . "\n";
                $exit = 1;
            }
        }
        if (! $exit) {
            print "Cd to '$opts{ftpdir}'...\n";
            if (! $ftp->cwd($opts{ftpdir})) {
                print $ftp->message . "\n";
                $exit = 1;
            }
        }

        if ($exit) {
            if (yesno ('y', 'Retry connection at once')) {
                next TRY_CONNECT;
            } else {
                die 'error';
            }
        }

        last TRY_CONNECT;
    }

#   if (! $ftp->pasv()) {
#       print $ftp->message . "\n";
#       die 'error';
#   }

    return $ftp;
}

## Support for MDTM.

# Assume server supports MDTM - will be adjusted if needed.
my $has_mdtm = 1;

my %months = (
    Jan => 0,
    Feb => 1,
    Mar => 2,
    Apr => 3,
    May => 4,
    Jun => 5,
    Jul => 6,
    Aug => 7,
    Sep => 8,
    Oct => 9,
    Nov => 10,
    Dec => 11,
);

my $ls_l_regex = qr<
    # Perms, Links, User, Group, Size.
    ([^ ]+\ *){5}
    # Blanks.
    [^ ]+
    # Month name (abbreviated).
    \ ([A-Z][a-z]{2})
    # Day of month.
    \ ([0-9 ][0-9])
    # Filename.
    \ ([0-9 ][0-9][:0-9][0-9]{2})
>x;

sub do_mdtm {
    my ($ftp, $file) = @_;
    my $time;

#   if ($has_mdtm) {
        $time = $ftp->mdtm($file);
#       my $code = $ftp->code();
#       my $message = $ftp->message();
#       print " [ $code: $message ] ";
        # Codes:
        #   500 Command not understood (SUN firewall).
        #   502 MDTM not implemented.
        if ($ftp->code() == 502 ||
            $ftp->code() == 500) {
            $has_mdtm = 0;
        } elsif (! $ftp->ok()) {
            return;
        }
#   }

    if (! $has_mdtm) {
        require Time::Local;

        my @files = $ftp->dir($file);
        # Codes:
        #   550 No such file or directory.
        if (($#files == -1) ||
            ($ftp->code == 550)) {
            return;
        }

#       my $code = $ftp->code();
#       my $message = $ftp->message();
#       print " [ $code: $message ] ";

#       print "[$#files]";

        # Get the date components from the output of 'ls -l'.
        if ($files[0] =~ $ls_l_regex) {
            my ($year, $year_or_time);
            my ($month, $month_name);
            my ($day, $hours, $minutes);

            # What we can read.
            $month_name = $2;
            $day = 0 + $3;
            $year_or_time = $4;

            # Translate the month name into number.
            $month = $months{$month_name};

            # Recognize time or year, and compute missing one.
            if ($year_or_time =~ /([0-9]{2}):([0-9]{2})/) {
                $hours = 0 + $1;
                $minutes = 0 + $2;
                my @this_date = gmtime(time());
                my $this_month = $this_date[4];
                my $this_year = $this_date[5];
                if ($month > $this_month) {
                    $year = $this_year - 1;
                } else {
                    $year = $this_year;
                }
            } elsif ($year_or_time =~ / [0-9]{4}/) {
                $hours = 0;
                $minutes = 0;
                $year = $year_or_time - 1900;
            } else {
                die 'cannot parse year-or-time';
            }

            # Build a system time.
            $time = Time::Local::timegm(0, $minutes, $hours, $day, $month, $year);
        } else {
            die 'regex match failed on LIST output';
        }
    }

    return $time;
}

=head1 CHANGES

=head2 Version 0.xx

This is a private module.

=cut

1;
