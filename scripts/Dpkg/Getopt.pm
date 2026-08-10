# Copyright © 2014 Guillem Jover <guillem@debian.org>
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

Dpkg::Getopt - option parsing handling

=head1 DESCRIPTION

This module provides helper functions for option parsing, and complements
the system Getopt::Long module.

B<Note>: This is a private module, its API can change at any time.

=cut

package Dpkg::Getopt 0.02;

use v5.36;

our @EXPORT = qw(
    normalize_options
    parse_option_dir
    print_option_sep
    format_option_spec
    format_option_parts
    print_option
    print_version
);

use Exporter qw(import);

use Dpkg;
use Dpkg::Color;
use Dpkg::Gettext;
use Dpkg::ErrorHandling;

sub normalize_options
{
    my (%opts) = @_;
    my $norm = 1;
    my @args;

    @args = map {
        if ($norm and m/^(-[A-Za-z])(.+)$/) {
            ($1, $2)
        } elsif ($norm and m/^(--[A-Za-z-]+)=(.*)$/) {
            ($1, $2)
        } else {
            $norm = 0 if defined $opts{delim} and $_ eq $opts{delim};
            $_;
        }
    } @{$opts{args}};

    return @args;
}

sub parse_option_dir($opt, $dir)
{
    if (! length $dir) {
        usageerr(g_('missing directory for option %s'), $opt);
    }

    if (! -e $dir) {
        # TODO: Switch this warning into an error, after checking its impact.
        warning(g_('directory %s for %s does not exist'), $dir, $opt);
        return;
    }

    if (! -d $dir) {
        usageerr(g_('argument %s for %s is not a directory'), $dir, $opt);
    }

    $dir =~ s{/+$}{};

    return $dir;
}

sub print_option_sep()
{
    print "\n";
}

sub format_option_spec($spec)
{
    my $color_reset = color_get('reset');
    my $color_opt = color_get('bold');
    my $color_arg = color_get('italic');

    $spec =~ s{([][.|])}{$color_reset$1$color_opt}g;
    $spec =~ s{<}{$color_reset<$color_arg}g;
    $spec =~ s{>}{$color_reset>$color_opt}g;

    return "$color_opt$spec$color_reset";
}

sub format_option_parts($spec, $help)
{
    my $indent_type = $spec =~ m{^--} ? 6 : 2;
    my $indent_spec = ' ' x $indent_type;
    my $indent_help = ' ' x 10;

    $spec = format_option_spec($spec);

    return sprintf "%s%s\n%s%s.\n", $indent_spec, $spec, $indent_help, $help;
}

sub print_option($desc_fmt, @args)
{
    my $desc = sprintf $desc_fmt, @args;
    my ($spec, $help) = split /\n/, $desc, 2;

    printf format_option_spec($spec) . "\n$help";
}

sub print_version()
{
    printf g_("%s version %s\n"), $Dpkg::PROGNAME, $Dpkg::PROGVERSION;
}

=head1 CHANGES

=head2 Version 0.xx

This is a private module.

=cut

1;
