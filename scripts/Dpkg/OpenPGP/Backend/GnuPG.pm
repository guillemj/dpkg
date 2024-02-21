# Copyright © 2007, 2022 Guillem Jover <guillem@debian.org>
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

=encoding utf8

=head1 NAME

Dpkg::OpenPGP::Backend::GnuPG - OpenPGP backend for GnuPG

=head1 DESCRIPTION

This module provides a class that implements the OpenPGP backend
for GnuPG.

B<Note>: This is a private module, its API can change at any time.

=cut

package Dpkg::OpenPGP::Backend::GnuPG 0.01;

use strict;
use warnings;

use POSIX qw(:sys_wait_h);
use File::Temp;
use MIME::Base64;

use Dpkg::ErrorHandling;
use Dpkg::IPC;
use Dpkg::File;
use Dpkg::Path qw(find_command);
use Dpkg::OpenPGP::ErrorCodes;

use parent qw(Dpkg::OpenPGP::Backend);

sub DEFAULT_CMDV {
    return [ qw(gpgv-sq gpgv) ];
}

sub DEFAULT_CMDSTORE {
    return [ qw(gpg-agent) ];
}

sub DEFAULT_CMD {
    return [ qw(gpg-sq gpg) ];
}

sub has_backend_cmd {
    my $self = shift;

    return defined $self->{cmd} && defined $self->{cmdstore};
}

sub has_keystore {
    my $self = shift;

    return 0 if not defined $self->{cmdstore};
    return 1 if ($ENV{GNUPGHOME} && -e $ENV{GNUPGHOME}) ||
                ($ENV{HOME} && -e "$ENV{HOME}/.gnupg");
    return 0;
}

sub can_use_key {
    my ($self, $key) = @_;

    # With gpg, a secret key always requires gpg-agent (the key store).
    return $self->has_keystore();
}

sub has_verify_cmd {
    my $self = shift;

    return defined $self->{cmdv} || defined $self->{cmd};
}

sub get_trusted_keyrings {
    my $self = shift;

    my $keystore;
    if ($ENV{GNUPGHOME} && -e $ENV{GNUPGHOME}) {
        $keystore = $ENV{GNUPGHOME};
    } elsif ($ENV{HOME} && -e "$ENV{HOME}/.gnupg") {
        $keystore = "$ENV{HOME}/.gnupg";
    } else {
        return;
    }

    my @keyrings;
    foreach my $keyring (qw(trustedkeys.kbx trustedkeys.gpg)) {
        push @keyrings, "$keystore/$keyring" if -r "$keystore/$keyring";
    }
    return @keyrings;
}

# _pgp_* functions are strictly for applying or removing ASCII armor.
# See <https://datatracker.ietf.org/doc/html/rfc4880#section-6> for more
# details.
#
# Note that these _pgp_* functions are only necessary while relying on
# gpgv, and gpgv itself does not verify multiple signatures correctly
# (see https://bugs.debian.org/1010955).

sub _pgp_dearmor_data {
    my ($type, $data) = @_;

    # Note that we ignore an incorrect or absent checksum, following the
    # guidance of
    # <https://datatracker.ietf.org/doc/draft-ietf-openpgp-crypto-refresh/>.
    my $armor_regex = qr{
        -----BEGIN\ PGP\ \Q$type\E-----[\r\t ]*\n
        (?:[^:]+:\ [^\n]*[\r\t ]*\n)*
        [\r\t ]*\n
        ([a-zA-Z0-9/+\n]+={0,2})[\r\t ]*\n
        (?:=[a-zA-Z0-9/+]{4}[\r\t ]*\n)?
        -----END\ PGP\ \Q$type\E-----
    }xm;

    if ($data =~ m/$armor_regex/) {
        return decode_base64($1);
    }
    return;
}

sub _pgp_armor_checksum {
    my ($data) = @_;

    # From the upcoming revision to RFC 4880
    # <https://datatracker.ietf.org/doc/draft-ietf-openpgp-crypto-refresh/>.
    #
    # The resulting three-octet-wide value then gets base64-encoded into
    # four base64 ASCII characters.

    my $CRC24_INIT = 0xB704CE;
    my $CRC24_GENERATOR = 0x864CFB;

    my @bytes = unpack 'C*', $data;
    my $crc = $CRC24_INIT;
    for my $b (@bytes) {
        $crc ^= ($b << 16);
        for (1 .. 8) {
            $crc <<= 1;
            if ($crc & 0x1000000) {
                # Clear bit 25 to avoid overflow.
                $crc &= 0xffffff;
                $crc ^= $CRC24_GENERATOR;
            }
        }
    }
    my $sum = pack 'CCC', ($crc >> 16) & 0xff, ($crc >> 8) & 0xff, $crc & 0xff;
    return encode_base64($sum, q{});
}

sub _pgp_armor_data {
    my ($type, $data) = @_;

    my $out = encode_base64($data, q{}) =~ s/(.{1,64})/$1\n/gr;
    chomp $out;
    my $crc = _pgp_armor_checksum($data);
    my $armor = <<~"ARMOR";
        -----BEGIN PGP $type-----

        $out
        =$crc
        -----END PGP $type-----
        ARMOR
    return $armor;
}

sub armor {
    my ($self, $type, $in, $out) = @_;

    my $raw_data = file_slurp($in);
    my $data = _pgp_dearmor_data($type, $raw_data) // $raw_data;
    my $armor = _pgp_armor_data($type, $data);
    return OPENPGP_BAD_DATA unless defined $armor;
    file_dump($out, $armor);

    return OPENPGP_OK;
}

sub dearmor {
    my ($self, $type, $in, $out) = @_;

    my $armor = file_slurp($in);
    my $data = _pgp_dearmor_data($type, $armor);
    return OPENPGP_BAD_DATA unless defined $data;
    file_dump($out, $data);

    return OPENPGP_OK;
}

sub _gpg_exec
{
    my ($self, @exec) = @_;

    my ($stdout, $stderr);
    spawn(exec => \@exec, wait_child => 1, nocheck => 1, timeout => 10,
          to_string => \$stdout, error_to_string => \$stderr);
    if (WIFEXITED($?)) {
        my $status = WEXITSTATUS($?);
        print { *STDERR } "$stdout$stderr" if $status;
        return $status;
    } else {
        subprocerr("@exec");
    }
}

sub _gpg_options_weak_digests {
    my @gpg_weak_digests = map {
        (qw(--weak-digest), $_)
    } qw(SHA1 RIPEMD160);

    return @gpg_weak_digests;
}

sub _gpg_verify {
    my ($self, $signeddata, $sig, $data, @certs) = @_;

    return OPENPGP_MISSING_CMD if ! $self->has_verify_cmd();

    my $gpg_home = File::Temp->newdir('dpkg-gpg-verify.XXXXXXXX', TMPDIR => 1);
    my @cmd_opts = qw(--no-options --no-default-keyring --batch --quiet);
    my @gpg_opts;
    push @gpg_opts, _gpg_options_weak_digests();
    push @gpg_opts, '--homedir', $gpg_home;
    push @cmd_opts, @gpg_opts;

    my @exec;
    if ($self->{cmdv}) {
        push @exec, $self->{cmdv};
        push @exec, @gpg_opts;
        # We need to touch the trustedkeys.gpg keyring, otherwise gpgv will
        # emit an error about the trustedkeys.kbx file being of unknown type.
        file_touch("$gpg_home/trustedkeys.gpg");
    } else {
        push @exec, $self->{cmd};
        push @exec, @cmd_opts;
    }
    foreach my $cert (@certs) {
        my $certring = File::Temp->new(UNLINK => 1, SUFFIX => '.pgp');
        my $rc;
        # XXX: The internal dearmor() does not handle concatenated ASCII Armor,
        # but the old implementation handled such certificate keyrings, so to
        # avoid regressing for now, we fallback to use the GnuPG dearmor.
        if ($cert =~ m{\.kbx$}) {
            # Accept GnuPG apparent keybox-format keyrings as-is.
            $rc = 1;
        } elsif (defined $self->{cmd}) {
            $rc = $self->_gpg_exec($self->{cmd}, @cmd_opts, '--yes',
                                          '--output', $certring,
                                          '--dearmor', $cert);
        } else {
            $rc = $self->dearmor('PUBLIC KEY BLOCK', $cert, $certring);
        }
        $certring = $cert if $rc;
        push @exec, '--keyring', $certring;
    }
    push @exec, '--output', $data if defined $data;
    if (! $self->{cmdv}) {
        push @exec, '--verify';
    }
    push @exec, $sig if defined $sig;
    push @exec, $signeddata;

    my $rc = $self->_gpg_exec(@exec);
    return OPENPGP_NO_SIG if $rc;
    return OPENPGP_OK;
}

sub inline_verify {
    my ($self, $inlinesigned, $data, @certs) = @_;

    return $self->_gpg_verify($inlinesigned, undef, $data, @certs);
}

sub verify {
    my ($self, $data, $sig, @certs) = @_;

    return $self->_gpg_verify($data, $sig, undef, @certs);
}

sub inline_sign {
    my ($self, $data, $inlinesigned, $key) = @_;

    return OPENPGP_MISSING_CMD if ! $self->has_backend_cmd();

    my @exec = ($self->{cmd});
    push @exec, _gpg_options_weak_digests();
    push @exec, qw(--utf8-strings --textmode --armor);
    # Set conformance level.
    push @exec, '--openpgp';
    # Set secure algorithm preferences.
    push @exec, '--personal-digest-preferences', 'SHA512 SHA384 SHA256 SHA224';
    if ($key->type eq 'keyfile') {
        # Promote the keyfile keyhandle to a keystore, this way we share the
        # same gpg-agent and can get any password cached.
        my $gpg_home = File::Temp->newdir('dpkg-sign.XXXXXXXX', TMPDIR => 1);

        push @exec, '--homedir', $gpg_home;
        $self->_gpg_exec(@exec, qw(--quiet --no-tty --batch --import), $key->handle);
        $key->set('keystore', $gpg_home);
    } elsif ($key->type eq 'keystore') {
        push @exec, '--homedir', $key->handle;
    } else {
        push @exec, '--local-user', $key->handle;
    }
    push @exec, '--output', $inlinesigned;

    my $rc = $self->_gpg_exec(@exec, '--clearsign', $data);
    return OPENPGP_CMD_CANNOT_SIGN if $rc;
    return OPENPGP_OK;
}

=head1 CHANGES

=head2 Version 0.xx

This is a private module.

=cut

1;
