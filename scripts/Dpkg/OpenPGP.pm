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
use File::Temp;
use MIME::Base64;

use Dpkg::Gettext;
use Dpkg::ErrorHandling;
use Dpkg::IPC;
use Dpkg::File;
use Dpkg::Path qw(find_command);
use Dpkg::OpenPGP::ErrorCodes;

our $VERSION = '0.01';

sub new {
    my ($this, %opts) = @_;
    my $class = ref($this) || $this;

    my $self = {
        cmd => $opts{cmd} // 'auto',
        has_cmd => {},
    };
    bless $self, $class;

    if ($self->{cmd} eq 'auto') {
        foreach my $cmd (qw(gpg gpgv)) {
            $self->{has_cmd}{$cmd} = 1 if find_command($cmd);
        }
    } else {
        $self->{has_cmd}{$self->{cmd}} = 1 if find_command($self->{cmd});
    }

    return $self;
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

    return OPENPGP_MISSING_CMD unless $self->{has_cmd}{gpgv};

    my $gpg_home = File::Temp->newdir('dpkg-gpg-verify.XXXXXXXX', TMPDIR => 1);

    my @exec = qw(gpgv);
    push @exec, _gpg_options_weak_digests();
    push @exec, '--homedir', $gpg_home;
    foreach my $cert (@certs) {
        my $certring;
        if ($cert =~ m/\.asc/) {
            $certring = File::Temp->new(UNLINK => 1, SUFFIX => '.pgp');
            $self->dearmor('PUBLIC KEY BLOCK', $cert, $certring);
        } else {
            $certring = $cert;
        }
        push @exec, '--keyring', $certring;
    }
    push @exec, '--output', $data if defined $data;
    push @exec, $sig if defined $sig;
    push @exec, $signeddata;

    my $status = $self->_gpg_exec(@exec);
    return OPENPGP_NO_SIG if $status;
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

1;
