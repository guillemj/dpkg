#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use open qw(:encoding(UTF-8) :std);
use v5.20;

while (<>) {
    chomp;

    # Strip noop commands.
    s/\\\\&//g;

    # Unescape backslash.
    s/\\\\ / /g;
    s/\\\\e/®®/g;
    s/\\\\/®®/g;
    s/®®/\\\\/g;

    s/(\s+)>/>$1/g;

    s/I<( +)>/S<$1>/g;
    s/B<( +)>/S<$1>/g;

    s/I< {2,}([^ >]*)>/  $1/g;
    s/B< {2,}([^ >]*)>/  $1/g;

    s/I< / I</g;
    s/B< / B</g;

    say;
}

1;
