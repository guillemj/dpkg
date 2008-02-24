package Dpkg::Source::Functions;

use strict;
use warnings;

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(erasedir);

use Dpkg::ErrorHandling qw(syserr subprocerr failure);
use Dpkg::Gettext;

use POSIX;

sub erasedir {
    my ($dir) = @_;
    if (not lstat($dir)) {
        return if $! == ENOENT;
        syserr(_g("cannot stat directory %s (before removal)"), $dir);
    }
    system 'rm','-rf','--',$dir;
    subprocerr("rm -rf $dir") if $?;
    if (not stat($dir)) {
        return if $! == ENOENT;
        syserr(_g("unable to check for removal of dir `%s'"), $dir);
    }
    failure(_g("rm -rf failed to remove `%s'"), $dir);
}

# vim: set et sw=4 ts=8
1;
