# Copyright © 2017 Guillem Jover <guillem@debian.org>
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

package Dpkg::OpenPGP;

use strict;
use warnings;

use Exporter qw(import);
use File::Copy;

use Dpkg::Gettext;
use Dpkg::ErrorHandling;
use Dpkg::Path qw(find_command);

our $VERSION = '0.01';
our @EXPORT = qw(
    openpgp_sig_to_asc
);

sub openpgp_sig_to_asc
{
    my ($sig, $asc) = @_;

    if (-e $sig) {
        my $is_openpgp_ascii_armor = 0;

        open my $fh_sig, '<', $sig or syserr(g_('cannot open %s'), $sig);
        while (<$fh_sig>) {
            if (m/^-----BEGIN PGP /) {
                $is_openpgp_ascii_armor = 1;
                last;
            }
        }
        close $fh_sig;

        if ($is_openpgp_ascii_armor) {
            notice(g_('signature file is already OpenPGP ASCII armor, copying'));
            copy($sig, $asc);
            return $asc;
        }

        if (not find_command('gpg')) {
            warning(g_('cannot OpenPGP ASCII armor signature file due to missing gpg'));
        }

        my @gpg_opts = qw(--no-options);

        open my $fh_asc, '>', $asc
            or syserr(g_('cannot create signature file %s'), $asc);
        open my $fh_gpg, '-|', 'gpg', @gpg_opts, '-o', '-', '--enarmor', $sig
            or syserr(g_('cannot execute %s program'), 'gpg');
        while (my $line = <$fh_gpg>) {
            next if $line =~ m/^Version: /;
            next if $line =~ m/^Comment: /;

            $line =~ s/ARMORED FILE/SIGNATURE/;

            print { $fh_asc } $line;
        }

        close $fh_gpg or subprocerr('gpg');
        close $fh_asc or syserr(g_('cannot write signature file %s'), $asc);

        return $asc;
    }

    return;
}

1;
