#!/usr/bin/perl --

use Text::Wrap;

# fixme: --dirfile option
# fixme: sort entries
# fixme: send to FSF ?

$version= '0.93.42.2'; # This line modified by Makefile
sub version {
        $file = $_[0];
        print $file <<END;
Debian install-info $version.  Copyright (C) 1994,1995
Ian Jackson.  This is free software; see the GNU General Public Licence
version 2 or later for copying conditions.  There is NO warranty.
END
}

sub usage {
    $file = $_[0];
    print $file <<END;
usage: install-info [--version] [--help] [--debug] [--maxwidth=nnn]
             [--section regexp title] [--infodir=xxx] [--align=nnn]
             [--calign=nnn] [--quiet] [--menuentry=xxx] [--info-dir=xxx]
             [--keep-old] [--description=xxx] [--test]
             [--remove | --remove-exactly ] [--dir-file]
             [--]
             filename
END
}

$infodir='/usr/share/info';
$maxwidth=79;
$Text::Wrap::columns=$maxwidth;
$backup='/var/backups/infodir.bak';
$default='/usr/share/base-files/info.dir';

$menuentry="";
$description="";
$sectionre="";
$sectiontitle="";
$infoentry="";
$quiet=0;
$nowrite=0;
$keepold=0;
$debug=0;
$remove=0;

my $remove_exactly;

$0 =~ m|[^/]+$|; $name= $&;

while ($ARGV[0] =~ m/^--/) {
    $_= shift(@ARGV);
    last if $_ eq '--';
    if ($_ eq '--version') {
        &version(STDOUT); exit 0;
    } elsif ($_ eq '--quiet') {
        $quiet=1;
    } elsif ($_ eq '--test') {
        $nowrite=1;
    } elsif ($_ eq '--keep-old') {
        $keepold=1;
    } elsif ($_ eq '--remove') {
        $remove=1;
    } elsif ($_ eq '--remove-exactly') {
        $remove=1;
        $remove_exactly=1;
    } elsif ($_ eq '--help') {
        &usage(STDOUT); exit 0;
    } elsif ($_ eq '--debug') {
        open(DEBUG,">&STDERR") || die "Could not open stderr for output! $!\n";
	$debug=1;
    } elsif ($_ eq '--section') {
        if (@ARGV < 2) {
            print STDERR "$name: --section needs two more args\n";
            &usage(STDERR); exit 1;
        }
        $sectionre= shift(@ARGV);
        $sectiontitle= shift(@ARGV);
    } elsif (m/^--(c?align|maxwidth)=([0-9]+)$/) {
	warn( "$name: $1 deprecated(ignored)\n" );
    } elsif (m/^--infodir=/) {
        $infodir=$';
    } elsif (m/^--info-file=/) {
        $filename=$';
    } elsif (m/^--menuentry=/) {
        $menuentry=$';
    } elsif (m/^--info-dir=/) {
        $infodir=$';
    } elsif (m/^--description=/) {
        $description=$';
    } elsif (m/^--dir-file=/) { # for compatibility with GNU install-info
	$infodir=$';
    } else {
        print STDERR "$name: unknown option \`$_'\n"; &usage(STDERR); exit 1;
    }
}

if (!@ARGV) { &version(STDERR); print STDERR "\n"; &usage(STDERR); exit 1; }

if ( !$filename ) {
	$filename= shift(@ARGV);
	$name = "$name($filename)";
}
if (@ARGV) { print STDERR "$name: too many arguments\n"; &usage(STDERR); exit 1; }

if ($remove) {
    print STDERR "$name: --section ignored with --remove\n" if length($sectiontitle);
    print STDERR "$name: --description ignored with --remove\n" if length($description);
}

print STDERR "$name: test mode - dir file will not be updated\n"
    if $nowrite && !$quiet;

umask(umask(0777) & ~0444);

if($remove_exactly) {
    $remove_exactly = $filename;
}

$filename =~ m|[^/]+$|; $basename= $&; $basename =~ s/(\.info)?(\.gz)?$//;

# The location of the info files from the dir entry, i.e. (emacs-20/emacs).
my $fileinentry;

&dprint("infodir='$infodir'  filename='$filename'  maxwidth='$maxwidth'\nmenuentry='$menuentry'  basename='$basename'\ndescription='$description'  remove=$remove");

if (!$remove) {

    if (!-f $filename && -f "$filename.gz" || $filename =~ s/\.gz$//) {
        $filename= "gzip -cd <$filename.gz |";  $pipeit= 1;
    } else {
        $filename= "< $filename";
    }

    if (!length($description)) {
        
        open(IF,"$filename") || die "$name: read $filename: $!\n";
        $asread='';
        while(<IF>) {
	    m/^START-INFO-DIR-ENTRY$/ && last;
	    m/^INFO-DIR-SECTION (.+)$/ && do {
		$sectiontitle = $1		unless ($sectiontitle);
		$sectionre = '^'.quotemeta($1)	unless ($sectionre);
	    }
	}
        while(<IF>) { last if m/^END-INFO-DIR-ENTRY$/; $asread.= $_; }
	if ($pipeit) {
	    while (<IF>) {};
	}

        close(IF); &checkpipe;
        if ($asread =~ m/(\*\s*[^:]+:\s*\(([^\)]+)\).*\. *.*\n){2}/) {
            $infoentry= $asread;
            $multiline= 1;
            $fileinentry = $2;
            &dprint("multiline '$asread'");
        } elsif ($asread =~ m/^\*\s*([^:]+):(\s*\(([^\)]+)\)\.|:)\s*/) {
            $menuentry= $1;
            $description= $';
            $fileinentry = $3;
            &dprint("infile menuentry '$menuentry' description '$description'");
        } elsif (length($asread)) {
            print STDERR <<END;
$name: warning, ignoring confusing INFO-DIR-ENTRY in file.
END
        }
    }

    if (length($infoentry)) {

        $infoentry =~ m/\n/;
        print "$`\n" unless $quiet;
        $infoentry =~ m/^\*\s*([^:]+):\s*\(([^\)]+)\)/ || 
            die "$name: Invalid info entry\n"; # internal error
        $sortby= $1;
        $fileinentry= $2;

    } else {
        
        if (!length($description)) {
            open(IF,"$filename") || die "$name: read $filename: $!\n";
            $asread='';
            while(<IF>) {
                if (m/^\s*[Tt]his file documents/) {
                    $asread=$';
                    last;
                }
            }
            if (length($asread)) {
                while(<IF>) { last if m/^\s*$/; $asread.= $_; }
                $description= $asread;
            }
	    if ($pipeit) {
		while (<IF>) {};
	    }
            close(IF); &checkpipe;
        }

        if (!length($description)) {
            print STDERR "
No \`START-INFO-DIR-ENTRY' and no \`This file documents'.
$name: unable to determine description for \`dir' entry - giving up
";
            exit 1;
        }

        $description =~ s/^\s*(.)//;  $_=$1;  y/a-z/A-Z/;
        $description= $_ . $description;

        if (!length($menuentry)) {
            $menuentry= $basename;  $menuentry =~ s/\Winfo$//;
            $menuentry =~ s/^.//;  $_=$&;  y/a-z/A-Z/;
            $menuentry= $_ . $menuentry;
        }

        &dprint("menuentry='$menuentry'  description='$description'");

        if($fileinentry) {
            $cprefix= sprintf("* %s: (%s).", $menuentry, $fileinentry);
        } else {
            $cprefix= sprintf("* %s: (%s).", $menuentry, $basename);
        }

        $align--; $calign--;
        $lprefix= length($cprefix);
        if ($lprefix < $align) {
            $cprefix .= ' ' x ($align - $lprefix);
            $lprefix= $align;
        }
        $prefix= "\n". (' 'x $calign);
        $cwidth= $maxwidth+1;

        for $_ (split(/\s+/,$description)) {
            $l= length($_);
            $cwidth++; $cwidth += $l;
            if ($cwidth > $maxwidth) {
                $infoentry .= $cprefix;
                $cwidth= $lprefix+1+$l;
                $cprefix= $prefix; $lprefix= $calign;
            }
            $infoentry.= ' '; $infoentry .= $_;
        }

        $infoentry.= "\n";
        print $infoentry unless $quiet;
        $sortby= $menuentry;  $sortby =~ y/A-Z/a-z/;

    }
}

if (!$nowrite && ( ! -e "$infodir/dir" || ! -s "$infodir/dir" )) {
    if (-r $backup) {
	print STDERR "$name: no file $infodir/dir, retrieving backup file $backup.\n";
	if (system ("cp $backup $infodir/dir")) {
	    print STDERR "$name: copying $backup to $infodir/dir failed, giving up: $!\n";
	    exit 1;
	}
    } else {
        if (-r $default) {
	    print STDERR "$name: no backup file $backup available, retrieving default file.\n";
	    
	    if (system("cp $default $infodir/dir")) {
		print STDERR "$name: copying $default to $infodir/dir failed, giving up: $!\n";
	exit 1;
    }
	} else {
	    print STDERR "$name: no backup file $backup available.\n";
	    print STDERR "$name: no default file $default available, giving up.\n";
	    exit 1;
	}
    }
}

if (!$nowrite && !link("$infodir/dir","$infodir/dir.lock")) {
    print STDERR "$name: failed to lock dir for editing! $!\n".
        ($! =~ m/exists/i ? "try deleting $infodir/dir.lock ?\n" : '');
}

open(OLD,"$infodir/dir") || &ulquit("open $infodir/dir: $!");
@work= <OLD>;
eof(OLD) || &ulquit("read $infodir/dir: $!");
close(OLD) || &ulquit("close $infodir/dir after read: $!");
while (($#work >= 0) && ($work[$#work] !~ m/\S/)) { $#work--; }

while (@work) {
    $_= shift(@work);
    push(@head,$_);
    last if (m/^\*\s*Menu:/i);
}

if (!$remove) {

    my $target_entry;

    if($fileinentry) {
        $target_entry = $fileinentry;
    } else {
        $target_entry = $basename;
    }

    for ($i=0; $i<=$#work; $i++) {
        next unless $work[$i] =~ m/^\*\s*[^:]+:\s*\(([^\)]+)\).*\.\s/;
        last if $1 eq $target_entry || $1 eq "$target_entry.info";
    }
    for ($j=$i; $j<=$#work+1; $j++) {
        next if $work[$j] =~ m/^\s+\S/;
        last unless $work[$j] =~ m/^\* *[^:]+: *\(([^\)]+)\).*\.\s/;
        last unless $1 eq $target_entry || $1 eq "$target_entry.info";
    }

    if ($i < $j) {
        if ($keepold) {
            print "$name: existing entry for \`$target_entry' not replaced\n" unless $quiet;
            $nowrite=1;
        } else {
            print "$name: replacing existing dir entry for \`$target_entry'\n" unless $quiet;
        }
        $mss= $i;
        @work= (@work[0..$i-1], @work[$j..$#work]);
    } elsif (length($sectionre)) {
        $mss= -1;
        for ($i=0; $i<=$#work; $i++) {
            $_= $work[$i];
            next if m/^\*/;
            next unless m/$sectionre/io;
            $mss= $i+1; last;
        }
        if ($mss < 0) {
            print "$name: creating new section \`$sectiontitle'\n" unless $quiet;
            for ($i= $#work; $i>=0 && $work[$i] =~ m/\S/; $i--) { }
            if ($i <= 0) { # We ran off the top, make this section and Misc.
                print "$name: no sections yet, creating Miscellaneous section too.\n"
                    unless $quiet;
                @work= ("\n", "$sectiontitle\n", "\n", "Miscellaneous:\n", @work);
                $mss= 1;
            } else {
                @work= (@work[0..$i], "$sectiontitle\n", "\n", @work[$i+1..$#work]);
                $mss= $i+1;
            }
        }
        while ($mss <= $#work) {
            $work[$mss] =~ m/\S/ || last;
            $work[$mss] =~ m/^\* *([^:]+):/ || ($mss++, next);
            last if $multiline;
            $_=$1;  y/A-Z/a-z/;
            last if $_ gt $sortby;
            $mss++;
        }
    } else {
        print "$name: no section specified for new entry, placing at end\n"
            unless $quiet;
        $mss= $#work+1;
    }

    @work= (@work[0..$mss-1], map("$_\n",split(/\n/,$infoentry)), @work[$mss..$#work]);
    
} else {

    my $target_entry;

    if($remove_exactly) {
        $target_entry = $remove_exactly;
    } else {
        $target_entry = $basename;
    }

    for ($i=0; $i<=$#work; $i++) {
        next unless $work[$i] =~ m/^\* *([^:]+): *\((\w[^\)]*)\)/;
        $tme= $1; $tfile= $2; $match= $&;
        next unless $tfile eq $target_entry;
        last if !length($menuentry);
        $tme =~ y/A-Z/a-z/;
        last if $tme eq $menuentry;
    }
    for ($j=$i; $j<=$#work+1; $j++) {
        next if $work[$j] =~ m/^\s+\S/;
        last unless $work[$j] =~ m/^\* *([^:]+): *\((\w[^\)]*)\)/;
        $tme= $1; $tfile= $2;
        last unless $tfile eq $target_entry;
        next if !length($menuentry);
        $tme =~ y/A-Z/a-z/;
        last unless $tme eq $menuentry;
    }

    if ($i < $j) {
        &dprint("i=$i \$work[\$i]='$work[$i]' j=$j \$work[\$j]='$work[$j]'");
        print "$name: deleting entry \`$match ...'\n" unless $quiet;
        $_= $work[$i-1];
        unless (m/^\s/ || m/^\*/ || m/^$/ ||
                $j > $#work || $work[$j] !~ m/^\s*$/) {
            s/:?\s+$//;
            if ($keepold) {
                print "$name: empty section \`$_' not removed\n" unless $quiet;
            } else {
                $i--; $j++;
                print "$name: deleting empty section \`$_'\n" unless $quiet;
            }
        }
        @work= (@work[0..$i-1], @work[$j..$#work]);
    } else {
        print "$name: no entry for file \`$target_entry'".
              (length($menuentry) ? " and menu entry \`$menuentry'": '').
              ".\n"
            unless $quiet;
    }
}
$length = 0;

$j = -1;
for ($i=0; $i<=$#work; $i++) {
	$_ = $work[$i];
	chomp;
	if ( m/^(\* *[^:]+: *\(\w[^\)]*\)[^.]*\.)[ \t]*(.*)/ ) {
		$length = length($1) if ( length($1) > $length );
		$work[++$j] = $_;
	} elsif ( m/^[ \t]+(.*)/ ) {
		$work[$j] = "$work[$j] $1";
	} else {
		$work[++$j] = $_;
	}
}
@work = @work[0..$j];

my $descalign=40;

@newwork = ();
foreach ( @work ) {
	if ( m/^(\* *[^:]+: *\(\w[^\)]*\)[^.]*\.)[ \t]*(.*)/ ||
		m/^([ \t]+)(.*)/ ) {
		if (length $1 >= $descalign) {
			push @newwork, $1;
			$_=(" " x $descalign) . $2;
		}
		else {
			$_ = $1 . (" " x ($descalign - length $1)) . $2;
		}
		push @newwork, split( "\n", wrap('', " " x $descalign, $_ ) );
	} else {
		push @newwork, $_;
	}
}

if (!$nowrite) {
    open(NEW,"> $infodir/dir.new") || &ulquit("create $infodir/dir.new: $!");
    print(NEW @head,join("\n",@newwork)) || &ulquit("write $infodir/dir.new: $!");
    close(NEW) || &ulquit("close $infodir/dir.new: $!");

    unlink("$infodir/dir.old");
    link("$infodir/dir","$infodir/dir.old") ||
        &ulquit("cannot backup old $infodir/dir, giving up: $!");
    rename("$infodir/dir.new","$infodir/dir") ||
        &ulquit("install new $infodir/dir: $!");
unlink("$infodir/dir.lock") || die "$name: unlock $infodir/dir: $!\n";
system ("cp $infodir/dir $backup") && warn "$name: couldn't backup $infodir/dir in $backup: $!\n";
}

sub ulquit {
    unlink("$infodir/dir.lock") ||
        warn "$name: warning - unable to unlock $infodir/dir: $!\n";
    die "$name: $_[0]\n";
}

sub checkpipe {
    return if !$pipeit || !$? || $?==0x8D00 || $?==0x0D;
    die "$name: read $filename: $?\n";
}

sub dprint {
    print DEBUG "dbg: $_[0]\n" if ($debug);
}

exit 0;
