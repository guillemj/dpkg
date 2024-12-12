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

Dpkg::OpenPGP::Backend::SOP - OpenPGP backend for SOP

=head1 DESCRIPTION

This module provides a class that implements the OpenPGP backend
for the Stateless OpenPGP Command-Line Interface, as described in
L<https://datatracker.ietf.org/doc/draft-dkg-openpgp-stateless-cli/>.

B<Note>: This is a private module, its API can change at any time.

=cut

package Dpkg::OpenPGP::Backend::SOP 0.01;

use strict;
use warnings;

use POSIX qw(:sys_wait_h);

use Dpkg::ErrorHandling;
use Dpkg::IPC;
use Dpkg::OpenPGP::ErrorCodes;

use parent qw(Dpkg::OpenPGP::Backend);

# - Once "hop" implements the new SOP draft, add as alternative.
#   Ref: https://salsa.debian.org/clint/hopenpgp-tools/-/issues/4
# - Once the SOP MR !23 is finalized and merged, implement a way to select
#   whether the SOP instance supports the expected draft.
#   Ref: https://gitlab.com/dkg/openpgp-stateless-cli/-/merge_requests/23
# - Once the SOP issue #42 is resolved we can perhaps remove the alternative
#   dependencies and commands to check?
#   Ref: https://gitlab.com/dkg/openpgp-stateless-cli/-/issues/42

sub DEFAULT_CMD {
    return [ qw(sqop rsop gosop pgpainless-cli) ];
}

sub _sop_exec
{
    my ($self, $io, @exec) = @_;

    return OPENPGP_MISSING_CMD unless $self->{cmd};

    $io->{out} //= '/dev/null';
    my $stderr;
    spawn(exec => [ $self->{cmd}, @exec ],
          wait_child => 1, nocheck => 1, timeout => 10,
          from_file => $io->{in}, to_file => $io->{out},
          error_to_string => \$stderr);
    if (WIFEXITED($?)) {
        my $status = WEXITSTATUS($?);
        print { *STDERR } "$stderr" if $status;
        return $status;
    } else {
        subprocerr("$self->{cmd} @exec");
    }
}

sub armor
{
    my ($self, $type, $in, $out) = @_;

    # We ignore the $type, and let "sop" handle this automatically.
    return $self->_sop_exec({ in => $in, out => $out }, 'armor');
}

sub dearmor
{
    my ($self, $type, $in, $out) = @_;

    # We ignore the $type, and let "sop" handle this automatically.
    return $self->_sop_exec({ in => $in, out => $out }, 'dearmor');
}

sub inline_verify
{
    my ($self, $inlinesigned, $data, @certs) = @_;

    return $self->_sop_exec({ in => $inlinesigned, out => $data },
                            'inline-verify', @certs);
}

sub verify
{
    my ($self, $data, $sig, @certs) = @_;

    return $self->_sop_exec({ in => $data }, 'verify', $sig, @certs);
}

sub inline_sign
{
    my ($self, $data, $inlinesigned, $key) = @_;

    return OPENPGP_NEEDS_KEYSTORE if $key->needs_keystore();

    return $self->_sop_exec({ in => $data, out => $inlinesigned },
                            qw(inline-sign --as clearsigned --), $key->handle);
}

=head1 CHANGES

=head2 Version 0.xx

This is a private module.

=cut

1;
