package Dpkg::Exit;

use strict;
use warnings;

our @handlers = ();
sub exit_handler {
    &$_() foreach (reverse @handlers);
    exit(127);
}

$SIG{'INT'} = \&exit_handler;
$SIG{'HUP'} = \&exit_handler;
$SIG{'QUIT'} = \&exit_handler;

# vim: set et sw=4 ts=8
1;
