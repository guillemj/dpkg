# Copyright © 2021-2022 Guillem Jover <guillem@debian.org>
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

Dpkg::OpenPGP::Backend::Sequoia - OpenPGP backend for Sequoia

=head1 DESCRIPTION

This module provides a class that implements the OpenPGP backend
for Sequoia-PGP.

B<Note>: This is a private module, its API can change at any time.

=cut

package Dpkg::OpenPGP::Backend::Sequoia 0.01;

use strict;
use warnings;

use POSIX qw(:sys_wait_h);

use Dpkg::ErrorHandling;
use Dpkg::IPC;
use Dpkg::OpenPGP::ErrorCodes;

use parent qw(Dpkg::OpenPGP::Backend);

sub DEFAULT_CMD {
    return [ qw(sq) ];
}

sub _sq_exec
{
    my ($self, @exec) = @_;

    my ($stdout, $stderr);
    spawn(exec => [ $self->{cmd}, @exec ],
          wait_child => 1, nocheck => 1, timeout => 10,
          to_string => \$stdout, error_to_string => \$stderr);
    if (WIFEXITED($?)) {
        my $status = WEXITSTATUS($?);
        print { *STDERR } "$stdout$stderr" if $status;
        return $status;
    } else {
        subprocerr("$self->{cmd} @exec");
    }
}

sub armor
{
    my ($self, $type, $in, $out) = @_;

    return OPENPGP_MISSING_CMD unless $self->{cmd};

    # We ignore the $type, and let "sq" handle this automatically.
    my $rc = $self->_sq_exec(qw(toolbox armor --output), $out, $in);
    return OPENPGP_BAD_DATA if $rc;
    return OPENPGP_OK;
}

sub dearmor
{
    my ($self, $type, $in, $out) = @_;

    return OPENPGP_MISSING_CMD unless $self->{cmd};

    # We ignore the $type, and let "sq" handle this automatically.
    my $rc = $self->_sq_exec(qw(toolbox dearmor --output), $out, $in);
    return OPENPGP_BAD_DATA if $rc;
    return OPENPGP_OK;
}

sub inline_verify
{
    my ($self, $inlinesigned, $data, @certs) = @_;

    return OPENPGP_MISSING_CMD unless $self->{cmd};

    my @opts;
    push @opts, map { ('--signer-file', $_) } @certs;
    push @opts, '--output', $data if defined $data;

    my $rc = $self->_sq_exec(qw(verify), @opts, $inlinesigned);
    return OPENPGP_NO_SIG if $rc;
    return OPENPGP_OK;
}

sub verify
{
    my ($self, $data, $sig, @certs) = @_;

    return OPENPGP_MISSING_CMD unless $self->{cmd};

    my @opts;
    push @opts, map { ('--signer-file', $_) } @certs;
    push @opts, '--detached', $sig;

    my $rc = $self->_sq_exec(qw(verify), @opts, $data);
    return OPENPGP_NO_SIG if $rc;
    return OPENPGP_OK;
}

sub inline_sign
{
    my ($self, $data, $inlinesigned, $key) = @_;

    return OPENPGP_MISSING_CMD unless $self->{cmd};
    return OPENPGP_NEEDS_KEYSTORE if $key->needs_keystore();

    my @opts;
    push @opts, '--cleartext-signature';
    push @opts, '--signer-file', $key->handle;
    push @opts, '--output', $inlinesigned;

    my $rc = $self->_sq_exec('sign', @opts, $data);
    return OPENPGP_KEY_CANNOT_SIGN if $rc;
    return OPENPGP_OK;
}

=head1 CHANGES

=head2 Version 0.xx

This is a private module.

=cut

1;
