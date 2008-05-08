package Dpkg::Source::Functions;

use strict;
use warnings;

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(erasedir fixperms is_binary);

use Dpkg::ErrorHandling qw(syserr subprocerr failure);
use Dpkg::Gettext;
use Dpkg::IPC;

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

sub fixperms {
    my ($dir) = @_;
    my ($mode, $modes_set, $i, $j);
    # Unfortunately tar insists on applying our umask _to the original
    # permissions_ rather than mostly-ignoring the original
    # permissions.  We fix it up with chmod -R (which saves us some
    # work) but we have to construct a u+/- string which is a bit
    # of a palaver.  (Numeric doesn't work because we need [ugo]+X
    # and [ugo]=<stuff> doesn't work because that unsets sgid on dirs.)
    $mode = 0777 & ~umask;
    for ($i = 0; $i < 9; $i += 3) {
        $modes_set .= ',' if $i;
        $modes_set .= qw(u g o)[$i/3];
        for ($j = 0; $j < 3; $j++) {
            $modes_set .= $mode & (0400 >> ($i+$j)) ? '+' : '-';
            $modes_set .= qw(r w X)[$j];
        }
    }
    system('chmod', '-R', $modes_set, '--', $dir);
    subprocerr("chmod -R $modes_set $dir") if $?;
}

sub is_binary($) {
    my ($file) = @_;

    # Use diff to check if it's a binary file
    my $diffgen;
    my $diff_pid = fork_and_exec(
        'exec' => [ 'diff', '-u', '--', '/dev/null', $file ],
        'env' => { LC_ALL => 'C', LANG => 'C', TZ => 'UTC0' },
        'to_pipe' => \$diffgen
    );
    my $result = 0;
    while (<$diffgen>) {
        if (m/^binary/i) {
            $result = 1;
            last;
        } elsif (m/^[-+\@ ]/) {
            $result = 0;
            last;
        }
    }
    close($diffgen) or syserr("close on diff pipe");
    wait_child($diff_pid, nocheck => 1, cmdline => "diff -u -- /dev/null $file");
    return $result;
}

# vim: set et sw=4 ts=8
1;
