#!/usr/bin/perl
#
# See man2pod.mk for its usage.
#

use strict;
use warnings;
use utf8;
use open qw(:encoding(UTF-8) :std);
use v5.20;

my $verbatim = 0;
my $verbatim_indent;
my $inlist = 0;
my $item = 0;

sub block_ini
{
    if (not $inlist) {
        print "\n=over\n\n";
        $inlist++;
    }
}

sub block_end
{
    while ($inlist) {
        print "\n=back\n\n";
        $inlist--;
    }
}

sub markup_font
{
    my ($font, $text) = @_;

    return $font eq 'R' ? $text : "$font<$text>";
}

while (<>) {
    my $comment = 0;

    chomp;

    # Squeeze whitespace.
    s/^\s+$//;

    # Strip noop commands.
    s/\\&//g;

    # Map comments.
    if (s/^\.\\"/#/) {
        $comment = 1;
    }

    # Escape <>.
    if (!$comment && !$verbatim) {
        s/>/E®®gt>/g;
        s/</E<lt>/g;
        s/®®/</g;
    }
    # Map fonts.
    s/\\fB/B</g;
    s/\\fI/I</g;
    s/\\fR/>/g;
    s/\\fP/>/g;

    # Map characters.
    s/\\\(bu/*/g;
    s/•/*/g;
    s/\\\(dq/"/g;

    # Unescape backslash.
    s/\\ / /g;
    s/\\e/®®/g;
    s/\\\\/®®/g;
    s/\\//g;
    s/®®/\\/g;

    # Skip lines.
    next if m/^\.nh$/;
    next if m/^\.ad/;

    # Map blank lines.
    if (m/^\.(|sp|br)$/) {
        print "\n";
        next;
    }

    # Handle verbatim markers.
    if (m/^\.nf/) {
        $verbatim = 1;
        print "\n";
        # This is the markup inside verbatim block hack.
        say "Z<>";
        next;
    }
    if (m/^\.EX/) {
        $verbatim = 1;
        print "\n";
        next;
    }
    if (m/^\.(fi|EE)/) {
        $verbatim = 0;
        $verbatim_indent = undef;
        print "\n";
        next;
    }

    # Map paragraph markers.
    if (m/^\.(P|PP|LP)$/) {
        print "\n";
        block_end();
        next;
    }
    if (m/^\.(TH|SH|SS) /) {
        block_end();
    }

    # Map disabled blocks.
    s/^\.ig/\n=begin disabled\n/;
    s/^\.\.$/\n=end disabled\n/;

    # Map indentation blocks.
    s/^\.RS(\s+\d+)?$/\n=over\n/;
    s/^\.RE$/\n=back\n/;
    s/^\.in\s+\+(\d+)$/\n=over\n/;
    s/^\.in\s+-\d+$/\n=back\n/;

    # Map paragraph types.
    if (m/^\.(TP|TQ|HP|IP)/) {
        s/^\.TP( \d)?/\n=item / and $item = 2;
        s/^\.TQ/\n=item / and $item = 2;

        s/^\.HP(\s+\d*)?$// and $item = 1;
        s/^\.IP(\s+\d*)?$// and $item = 1;
        s/^\.IP "([^"]*)"(?:\s+\d*)?$/\n=item $1/ and $item = 1;
        s/^\.IP ([^\s]*)(?:\s+\d*)?$/\n=item $1/ and $item = 1;

        block_ini();
    }

    s/^\.TH .*$/=encoding utf8\n/;
    s/^\.SH (.*)/\n=head1 $1\n/;
    s/^\.SS (.*)/\n=head2 $1\n/;

    if (m/^\.([IB]) (.*)$/) {
        my ($font_a, $words) = ($1, $2);

        $_ = markup_font($font_a,
                         join(' ', ($words =~ m/(?|"(.*?)"|(\S+))/g)));
    } elsif (m/^\.([RIB])([RIB]) (.*)$/) {
        my ($font_a, $font_b, $words) = ($1, $2, $3);

        my $i = 0;
        $_ = join '', map {
            if (++$i % 2) {
                markup_font($font_a, $_);
            } else {
                markup_font($font_b, $_);
            }
        } ($words =~ m/(?|"(.*?)"|(\S+))/g);
    } elsif (m/^\.[A-Z]+/i) {
        warn "warning: unhandled command ($_) at line $.\n";
    }

    # Handle verbatim block indentation.
    if ($verbatim) {
        my $current_indent = 1;

        if (m/^(\s+)[^\s]/) {
            $current_indent = length $1;
            $verbatim_indent //= $current_indent;
        }

        if (length == 0) {
            say;
        } else {
            $verbatim_indent //= 1;

            if ($verbatim_indent < $current_indent) {
                say;
            } else {
                say " " x $verbatim_indent . $_;
            }
      }
      next;
    }

    # Handle item lists.
    if ($item == 2) {
        print;
        $item--;
    } elsif ($item == 1) {
        say;
        print "\n";
        $item--;
    } else {
        say;
    }
}

block_end();

1;
