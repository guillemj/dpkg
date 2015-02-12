# Copied from /usr/share/perl5/Debconf/Gettext.pm
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY AUTHORS AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHORS OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.

package Dpkg::Gettext;

use strict;
use warnings;

our $VERSION = '1.01';
our @EXPORT = qw(g_ P_ textdomain ngettext _g);

use Exporter qw(import);

=encoding utf8

=head1 NAME

Dpkg::Gettext - convenience wrapper around Locale::gettext

=head1 DESCRIPTION

The Dpkg::Gettext module is a convenience wrapper over the Locale::gettext
module, to guarantee we always have working gettext functions, and to add
some commonly used aliases.

=head1 FUNCTIONS

=over 4

=item my $trans = g_($msgid)

Calls gettext() on the $msgid and returns its translation for the current
locale. If gettext() is not available, simply returns $msgid.

=item my $trans = P_($msgid, $msgid_plural, $n)

Calls ngettext(), returning the correct translation for the plural form
dependent on $n. If gettext() is not available, returns $msgid if $n is 1
or $msgid_plural otherwise.

=back

=cut

BEGIN {
    eval 'use Locale::gettext';
    if ($@) {
        eval q{
            sub g_ {
                return shift;
            }
            sub textdomain {
            }
            sub ngettext {
                my ($msgid, $msgid_plural, $n) = @_;
                if ($n == 1) {
                    return $msgid;
                } else {
                    return $msgid_plural;
                }
            }
            sub P_ {
                return ngettext(@_);
            }
        };
    } else {
        eval q{
            sub g_ {
                return gettext(shift);
            }
            sub P_ {
                return ngettext(@_);
            }
        };
    }
}

# XXX: Backwards compatibility, to be removed on VERSION 2.00.
sub _g ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
{
    my $msgid = shift;

    require Carp;
    Carp::carp('obsolete _g() function, please use g_() instead');

    return g_($msgid);
}

=head1 CHANGES

=head2 Version 1.01

New function: g_().

Deprecated function: _g().

=head2 Version 1.00

Mark the module as public.

=cut

1;
