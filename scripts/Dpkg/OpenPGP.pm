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

use POSIX qw(:sys_wait_h);
use Exporter qw(import);
use File::Temp;
use File::Copy;

use Dpkg::Gettext;
use Dpkg::ErrorHandling;
use Dpkg::IPC;
use Dpkg::Path qw(find_command);

our $VERSION = '0.01';
our @EXPORT = qw(
    openpgp_sig_to_asc
);

sub _armor_gpg {
    my ($sig, $asc) = @_;

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

        if (find_command('gpg')) {
            return _armor_gpg($sig, $asc);
        } else {
            warning(g_('cannot OpenPGP ASCII armor signature file due to missing gpg'));
        }
    }

    return;
}

sub _exec_openpgp
{
    my ($opts, $exec, $errmsg) = @_;

    my ($stdout, $stderr);
    spawn(exec => $exec, wait_child => 1, nocheck => 1, timeout => 10,
          to_string => \$stdout, error_to_string => \$stderr);
    if (WIFEXITED($?)) {
        my $status = WEXITSTATUS($?);
        print { *STDERR } "$stdout$stderr" if $status;
        if ($status == 1 or ($status && $opts->{require_valid_signature})) {
            error($errmsg);
        } elsif ($status) {
            warning($errmsg);
        }
    } else {
        subprocerr("@{$exec}");
    }
}

sub _gpg_options_weak_digests {
    my @gpg_weak_digests = map {
        (qw(--weak-digest), $_)
    } qw(SHA1 RIPEMD160);

    return @gpg_weak_digests;
}

sub _gpg_options_common {
    my @opts = (
        qw(--no-options --no-default-keyring -q),
        _gpg_options_weak_digests(),
    );

    return @opts;
}

sub _gpg_import_keys {
    my ($opts, $keyring, @keys) = @_;

    my $gpghome = File::Temp->newdir('dpkg-gpg-import-keys.XXXXXXXX', TMPDIR => 1);

    my @exec = qw(gpg);
    push @exec, _gpg_options_common();
    push @exec, '--homedir', $gpghome;
    push @exec, '--keyring', $keyring;
    push @exec, '--import';

    foreach my $key (@keys) {
        my $errmsg = sprintf g_('cannot import key %s into %s'), $key, $keyring;
        _exec_openpgp($opts, [ @exec, $key ], $errmsg);
    }
}

sub import_key {
    my ($opts, $asc) = @_;

    $opts->{require_valid_signature} //= 1;

    if (find_command('gpg')) {
        _gpg_import_keys($opts, $opts->{keyring}, $asc);
    } elsif ($opts->{require_valid_signature}) {
        error(g_('cannot import key in %s since GnuPG is not installed'),
              $asc);
    } else {
        warning(g_('cannot import key in %s since GnuPG is not installed'),
                $asc);
    }

    return;
}

sub _gpg_verify {
    my ($opts, $data, $sig, @certs) = @_;

    my $gpghome = File::Temp->newdir('dpkg-gpg-verify.XXXXXXXX', TMPDIR => 1);

    my @exec = qw(gpgv);
    push @exec, _gpg_options_weak_digests();
    push @exec, '--homedir', $gpghome;
    foreach my $keyring (@certs) {
        push @exec, '--keyring', $keyring;
    }
    push @exec, $sig if defined $sig;
    push @exec, $data;

    my $errmsg = sprintf g_('cannot verify signature for %s'), $data;
    _exec_openpgp($opts, \@exec, $errmsg);
}

sub inline_verify {
    my ($opts, $data, @certs) = @_;

    $opts->{require_valid_signature} //= 1;

    if (find_command('gpgv')) {
        _gpg_verify($opts, $data, undef, @certs);
    } elsif ($opts->{require_valid_signature}) {
        error(g_('cannot verify inline signature on %s since GnuPG is not installed'),
              $data);
    } else {
        warning(g_('cannot verify inline signature on %s since GnuPG is not installed'),
                $data);
    }

    return;
}

sub verify {
    my ($opts, $data, $sig, @certs) = @_;

    $opts->{require_valid_signature} //= 1;

    if (find_command('gpgv')) {
        _gpg_verify($opts, $data, $sig, @certs);
    } elsif ($opts->{require_valid_signature}) {
        error(g_('cannot verify signature on %s since GnuPG is not installed'),
              $sig);
    } else {
        warning(g_('cannot verify signature on %s since GnuPG is not installed'),
                $sig);
    }

    return;
}

1;
