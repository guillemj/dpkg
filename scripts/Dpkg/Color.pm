# Copyright © 2015-2026 Guillem Jover <guillem@debian.org>
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

Dpkg::Color - color output handling

=head1 DESCRIPTION

This module provides functions to handle colored output.

B<Note>: This is a private module, its API can change at any time.

=cut

package Dpkg::Color 0.01;

use v5.36;

our @EXPORT = qw(
    color_setup
    color_get
    colored_str
);

use Exporter qw(import);

sub color_setup
{
    my $mode = $ENV{'DPKG_COLORS'} // 'auto';
    my $use_color;

    if ($mode eq 'auto') {
        ## no critic (InputOutput::ProhibitInteractiveTest)
        $use_color = 1 if -t *STDOUT or -t *STDERR;
    } elsif ($mode eq 'always') {
        $use_color = 1;
    } else {
        $use_color = 0;
    }

    require Term::ANSIColor if $use_color;
}

sub color_get($color)
{
    state $use_color = color_setup();

    if ($use_color) {
        return Term::ANSIColor::color($color);
    } else {
        return q{};
    }
}

sub colored_str($str, $color)
{
    state $use_color = color_setup();

    if ($use_color) {
        return Term::ANSIColor::colored($str, $color);
    } else {
        return $str;
    }
}

=head1 CHANGES

=head2 Version 0.xx

This is a private module.

=cut

1;
