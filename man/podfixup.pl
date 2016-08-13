#!/usr/bin/perl

use strict;
use warnings;
use v5.20;

while (<>) {
    chomp;

    s/(\s+)>/>$1/g;

    s/I<( +)>/S<$1>/g;
    s/B<( +)>/S<$1>/g;

    s/I< {2,}([^ >]*)>/  $1/g;
    s/B< {2,}([^ >]*)>/  $1/g;

    s/=item I< /=item S< >I</g;
    s/=item B< /=item S< >B</g;
    s/=item ( +)/=item S<$1>/g;
    s/=item ( +)/=item S<$1>/g;

    s/I< / I</g;
    s/B< / B</g;

    say;
}

1;
