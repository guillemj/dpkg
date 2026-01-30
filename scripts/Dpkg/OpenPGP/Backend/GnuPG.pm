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

use v5.36;

use POSIX qw(:sys_wait_h);
use File::Basename;
use File::Temp;
use File::Copy;

use Dpkg::Gettext;
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
    foreach my $keyring (qw(trustedkeys.gpg trustedkeys.kbx)) {
        push @keyrings, "$keystore/$keyring" if -r "$keystore/$keyring";
    }
    return @keyrings;
}

sub _gpg_exec
{
    my ($self, @exec) = @_;

    my ($stdout, $stderr);
    spawn(
        exec => \@exec,
        wait_child => 1,
        no_check => 1,
        timeout => 10,
        to_string => \$stdout,
        error_to_string => \$stderr,
    );
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

sub _file_read_header($file, $size)
{
    my $header;

    open my $fh, '<', $file
        or syserr(g_('cannot open %s'), $file);
    my $rc = read $fh, $header, $size;
    if (! defined $rc) {
        syserr(g_('cannot read %s'), $file);
    } elsif ($rc == 0) {
        error(g_('unexpected empty file %s'), $file);
    } elsif ($rc != $size) {
        error(g_('partial read %s (%d bytes of %d total)'), $file, $rc, $size);
    }
    close $fh;

    return $header;
}

sub _file_is_keybox($file)
{
    my $header = _file_read_header($file, 32);

    my ($lead, $magic) = unpack 'a8a4', $header;

    return $magic eq 'KBXf';
}

# https://www.rfc-editor.org/rfc/rfc9580.html#name-packet-headers
use constant {
    PKT_FORMAT_MASK => 0b11000000,
    PKT_FORMAT_NEW  => 0b11000000,
    PKT_FORMAT_OLD  => 0b10000000,

    PKT_OLD_LEN_TYPE_MASK => 0b11,
};

# https://www.rfc-editor.org/rfc/rfc9580.html#name-packet-types
use constant {
    PKT_ID_SECKEY => 5,
    PKT_ID_PUBKEY => 6,
};

sub _file_is_librepgp($file)
{
    return 0 if -z $file;

    my $header = _file_read_header($file, 32);

    my ($ctb, @bytes) = unpack 'C8', $header;
    my ($length, $version);

    my $format = $ctb & PKT_FORMAT_MASK;
    my $type_id;
    if ($format == PKT_FORMAT_NEW) {
        $type_id = $ctb ^ $format;
        if ($bytes[0] < 192) {
            $length = 1;
        } elsif ($bytes[0] < 224) {
            $length = 2;
        } elsif ($bytes[0] < 255) {
            $length = 1;
        } elsif ($bytes[0] == 255) {
            $length = 5;
        }
    } elsif ($format == PKT_FORMAT_OLD) {
        $type_id = ($ctb ^ $format) >> 2;
        $length = $ctb & PKT_OLD_LEN_TYPE_MASK;
        if ($length == 0) {
            $length = 1;
        } elsif ($length == 1) {
            $length = 2;
        } elsif ($length == 2) {
            $length = 4;
        } else {
            warning(g_('old OpenPGP packet in %s with indeterminate length'),
                    $file);
            return 0;
        }
    }

    if ($type_id == PKT_ID_SECKEY || $type_id == PKT_ID_PUBKEY) {
        $version = $bytes[$length];
    } else {
        warning(g_('unknown OpenPGP packet type %0x in %s'), $ctb, $file);
        return 0;
    }

    debug(1, 'pgp-packet file=%s ctb=%0x format=%0b id=%d len=%0x version=%0x',
          $file, $ctb, $format, $type_id, $length, $version);

    return $version == 5;
}

sub _gpg_verify {
    my ($self, $signeddata, $sig, $data, @certs) = @_;

    return OPENPGP_MISSING_CMD if ! $self->has_verify_cmd();

    my $gpg_home = File::Temp->newdir(
        TEMPLATE => 'dpkg-gpg-verify.XXXXXXXX',
        TMPDIR => 1,
    );

    my @exec;
    if ($self->{cmdv}) {
        push @exec, $self->{cmdv};
        # We need to touch the trustedkeys.gpg keyring, otherwise gpgv will
        # emit an error about the trustedkeys.kbx file being of unknown type.
        file_touch("$gpg_home/trustedkeys.gpg");
    } else {
        push @exec, $self->{cmd};
        push @exec, qw(--no-options --no-default-keyring --batch --quiet);
    }
    push @exec, _gpg_options_weak_digests();
    push @exec, '--homedir', $gpg_home;
    foreach my $cert (@certs) {
        my $certring = File::Temp->new(
            UNLINK => 1,
            SUFFIX => '.pgp',
        );
        my $rc;
        if ($cert =~ m{\.kbx$} || _file_is_keybox($cert)) {
            # Accept GnuPG apparent or real keybox-format keyrings as-is, but
            # warn that they are deprecated.
            $rc = 1;
            warning(g_('using GnuPG specific KeyBox formatted keyring %s is deprecated; ' .
                       'use an OpenPGP formatted keyring instead'),
                    $cert);
        } else {
            # Note that these _pgp_* functions are only necessary while
            # relying on gpgv, and gpgv itself does not verify multiple
            # signatures correctly (see https://bugs.debian.org/1010955).
            $rc = $self->dearmor('PUBLIC KEY BLOCK', $cert, $certring);

            if (_file_is_librepgp($certring)) {
                warning(g_('found non-interoperable LibrePGP artifact in %s, ' .
                           'only OpenPGP is supported'), $cert);
            }
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

    return OPENPGP_MISSING_KEYRINGS if @certs == 0;

    return $self->_gpg_verify($inlinesigned, undef, $data, @certs);
}

sub verify {
    my ($self, $data, $sig, @certs) = @_;

    return OPENPGP_MISSING_KEYRINGS if @certs == 0;

    return $self->_gpg_verify($data, $sig, undef, @certs);
}

sub _gpg_fixup_newline {
    my $origfile = shift;

    my $signdir = File::Temp->newdir(
        TEMPLATE => 'dpkg-sign.XXXXXXXX',
        TMPDIR => 1,
    );
    my $signfile = $signdir . q(/) . basename($origfile);

    copy($origfile, $signfile);

    # Make sure the file to sign ends with a newline, as GnuPG does not adhere
    # to the OpenPGP specification (see <https://dev.gnupg.org/T7106>).
    open my $signfh, '>>', $signfile
        or syserr(g_('cannot open %s'), $signfile);
    print { $signfh } "\n";
    close $signfh
        or syserr(g_('cannot close %s'), $signfile);

    # Return the dir object so that it is kept in scope in the caller, and
    # thus not cleaned up within this function.
    return ($signdir, $signfile);
}

sub inline_sign {
    my ($self, $data, $inlinesigned, $key) = @_;

    return OPENPGP_MISSING_CMD if ! $self->has_backend_cmd();

    my ($signdir, $signfile);
    if ($self->{cmd} !~ m{/gpg-sq$}) {
        ($signdir, $signfile) = _gpg_fixup_newline($data);
    } else {
        $signfile = $data;
    }

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
        my $gpg_home = File::Temp->newdir(
            TEMPLATE => 'dpkg-sign.XXXXXXXX',
            TMPDIR => 1,
        );

        push @exec, '--homedir', $gpg_home;
        $self->_gpg_exec(@exec, qw(--quiet --no-tty --batch --import), $key->handle);
        $key->set('keystore', $gpg_home);
    } elsif ($key->type eq 'keystore') {
        push @exec, '--homedir', $key->handle;
    } else {
        push @exec, '--local-user', $key->handle;
    }
    push @exec, '--output', $inlinesigned;

    my $rc = $self->_gpg_exec(@exec, '--clearsign', $signfile);
    return OPENPGP_CMD_CANNOT_SIGN if $rc;
    return OPENPGP_OK;
}

=head1 CHANGES

=head2 Version 0.xx

This is a private module.

=cut

1;
