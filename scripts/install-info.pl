#!/usr/bin/perl --

BEGIN { # Work-around for bug #479711 in perl
    $ENV{PERL_DL_NONLAZY} = 1;
}

use Text::Wrap;
use Dpkg;
use Dpkg::Gettext;

textdomain("dpkg");

# fixme: sort entries
# fixme: send to FSF ?

sub version {
    printf _g("Debian %s version %s.\n"), $progname, $version;

    printf _g("
Copyright (C) 1994,1995 Ian Jackson.");

    printf _g("
This is free software; see the GNU General Public Licence version 2 or
later for copying conditions. There is NO warranty.
");
}

sub usage {
    $file = $_[0];
    printf $file _g(
"Usage: %s [<options> ...] [--] <filename>

Options:
  --section <regexp> <title>
                           put the new entry in the <regex> matched section
                           or create a new one with <title> if non-existent.
  --menuentry=<text>       set the menu entry.
  --description=<text>     set the description to be used in the menu entry.
  --info-file=<path>       specify info file to install in the directory.
  --dir-file=<path>        specify file name of info directory file.
  --infodir=<directory>    same as '--dir-file=<directory>/dir'.
  --info-dir=<directory>   likewise.
  --keep-old               do not replace entries nor remove empty ones.
  --remove                 remove the entry specified by <filename> basename.
  --remove-exactly         remove the exact <filename> entry.
  --test                   enables test mode (no actions taken).
  --debug                  enables debug mode (show more information).
  --quiet                  do not show output messages.
  --help                   show this help message.
  --version                show the version.
"), $progname;
}

$dirfile = '/usr/share/info/dir';
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
    } elsif ($_ eq '--version') {
        &version; exit 0;
    } elsif ($_ eq '--debug') {
	open(DEBUG,">&STDERR")
	    || &quit(sprintf(_g("could not open stderr for output! %s"), $!));
	$debug=1;
    } elsif ($_ eq '--section') {
        if (@ARGV < 2) {
	    printf STDERR _g("%s: --section needs two more args")."\n", $name;
            &usage(STDERR); exit 1;
        }
        $sectionre= shift(@ARGV);
        $sectiontitle= shift(@ARGV);
    } elsif (m/^--(c?align|maxwidth)=([0-9]+)$/) {
	warn(sprintf(_g("%s: option --%s is deprecated (ignored)"), $name, $1)."\n");
    } elsif (m/^--info-?dir=/) {
	$dirfile = $' . '/dir';
    } elsif (m/^--info-file=/) {
	$filename = $';
    } elsif (m/^--menuentry=/) {
	$menuentry = $';
    } elsif (m/^--description=/) {
	$description = $';
    } elsif (m/^--dir-file=/) { # for compatibility with GNU install-info
	$dirfile = $';
    } else {
        printf STDERR _g("%s: unknown option \`%s'")."\n", $name, $_;
        &usage(STDERR); exit 1;
    }
}

if (!@ARGV) { &usage(STDERR); exit 1; }

if ( !$filename ) {
	$filename= shift(@ARGV);
	$name = "$name($filename)";
}
if (@ARGV) { printf STDERR _g("%s: too many arguments")."\n", $name; &usage(STDERR); exit 1; }

if ($remove) {
    printf(STDERR _g("%s: --section ignored with --remove")."\n", $name) if length($sectiontitle);
    printf(STDERR _g("%s: --description ignored with --remove")."\n", $name) if length($description);
}

printf(STDERR _g("%s: test mode - dir file will not be updated")."\n", $name)
    if $nowrite && !$quiet;

umask(umask(0777) & ~0444);

if($remove_exactly) {
    $remove_exactly = $filename;
}

$filename =~ m|[^/]+$|; $basename= $&; $basename =~ s/(\.info)?(\.gz)?$//;

# The location of the info files from the dir entry, i.e. (emacs-20/emacs).
my $fileinentry;

&dprint("dirfile='$dirfile' filename='$filename' maxwidth='$maxwidth'");
&dprint("menuentry='$menuentry' basename='$basename'");
&dprint("description='$description' remove=$remove");

if (!$remove) {

    if (!-f $filename && -f "$filename.gz" || $filename =~ s/\.gz$//) {
        $filename= "gzip -cd <$filename.gz |";  $pipeit= 1;
    } else {
        $filename= "< $filename";
    }

    if (!length($description)) {
        
        open(IF,"$filename") || &quit(sprintf(_g("unable to read %s: %s"), $filename, $!));
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
            $description = $';
            $fileinentry = $3;
            &dprint("infile menuentry '$menuentry' description '$description'");
        } elsif (length($asread)) {
            printf STDERR _g("%s: warning, ignoring confusing INFO-DIR-ENTRY in file.")."\n", $name;
        }
    }

    if (length($infoentry)) {

        $infoentry =~ m/\n/;
        print "$`\n" unless $quiet;
        $infoentry =~ m/^\*\s*([^:]+):\s*\(([^\)]+)\)/ || 
            &quit(_g("invalid info entry")); # internal error
        $sortby= $1;
        $fileinentry= $2;

    } else {

        if (!length($description)) {
            open(IF,"$filename") || &quit(_g("unable to read %s: %s"), $filename, $!);
            $asread='';
            while(<IF>) {
                if (m/^\s*[Tt]his file documents/) {
                    $asread = $';
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
            printf STDERR _g("
No \`START-INFO-DIR-ENTRY' and no \`This file documents'.
%s: unable to determine description for \`dir' entry - giving up
"), $name;
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

if (!$nowrite && ( ! -e $dirfile || ! -s _ )) {
    if (-r $backup) {
	printf( STDERR _g("%s: no file %s, retrieving backup file %s.")."\n",
		$name, $dirfile, "$backup" );
	if (system ('cp', $backup, $dirfile)) {
	    printf( STDERR _g("%s: copying %s to %s failed, giving up: %s")."\n",
		    $name, $backup, $dirfile, $! );
	    exit 1;
	}
    } else {
        if (-r $default) {
	    printf( STDERR _g("%s: no backup file %s available, retrieving default file.")."\n",
		    $name, $backup );

	    if (system('cp', $default, $dirfile)) {
		printf( STDERR _g("%s: copying %s to %s failed, giving up: %s")."\n",
			$name, $default, $dirfile, $! );
		exit 1;
	    }
	} else {
	    printf STDERR _g("%s: no backup file %s available.")."\n", $name, $backup;
	    printf STDERR _g("%s: no default file %s available, giving up.")."\n", $name, $default;
	    exit 1;
	}
    }
}

if (!$nowrite && !link($dirfile, "$dirfile.lock")) {
    printf( STDERR _g("%s: failed to lock dir for editing! %s")."\n",
	    $name, $! );
    printf( STDERR _g("try deleting %s?")."\n", "$dirfile.lock")
	if $!{EEXIST};
    exit 1;
}

open(OLD, $dirfile) || &ulquit(sprintf(_g("unable to open %s: %s"), $dirfile, $!));
@work= <OLD>;
eof(OLD) || &ulquit(sprintf(_g("unable to read %s: %s"), $dirfile, $!));
close(OLD) || &ulquit(sprintf(_g("unable to close %s after read: %s"),
				 $dirfile, $!));

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
            printf(_g("%s: existing entry for \`%s' not replaced")."\n", $name, $target_entry) unless $quiet;
            $nowrite=1;
        } else {
            printf(_g("%s: replacing existing dir entry for \`%s'")."\n", $name, $target_entry) unless $quiet;
        }
        $mss= $i;
        @work= (@work[0..$i-1], @work[$j..$#work]);
    } elsif (length($sectionre)) {
        $mss= -1;
        for ($i=0; $i<=$#work; $i++) {
            $_= $work[$i];
            next if m/^(\*|\s)/;
            next unless m/$sectionre/io;
            $mss= $i+1; last;
        }
        if ($mss < 0) {
            printf(_g("%s: creating new section \`%s'")."\n", $name, $sectiontitle) unless $quiet;
            for ($i= $#work; $i>=0 && $work[$i] =~ m/\S/; $i--) { }
            if ($i <= 0) { # We ran off the top, make this section and Misc.
                printf(_g("%s: no sections yet, creating Miscellaneous section too.")."\n", $name)
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
        printf(_g("%s: no section specified for new entry, placing at end")."\n", $name)
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
        printf(_g("%s: deleting entry \`%s ...'")."\n", $name, $match) unless $quiet;
        $_= $work[$i-1];
        unless (m/^\s/ || m/^\*/ || m/^$/ ||
                $j > $#work || $work[$j] !~ m/^\s*$/) {
            s/:?\s+$//;
            if ($keepold) {
                printf(_g("%s: empty section \`%s' not removed")."\n", $name, $_) unless $quiet;
            } else {
                $i--; $j++;
                printf(_g("%s: deleting empty section \`%s'")."\n", $name, $_) unless $quiet;
            }
        }
        @work= (@work[0..$i-1], @work[$j..$#work]);
    } else {
        unless ($quiet) {
            if (length($menuentry)) {
                printf _g("%s: no entry for file \`%s' and menu entry \`%s'")."\n", $name, $target_entry, $menuentry;
            } else {
                printf _g("%s: no entry for file \`%s'")."\n", $name, $target_entry;
            }
        }
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
    open(NEW,"> $dirfile.new") || &ulquit(sprintf(_g("unable to create %s: %s"),
						     "$dirfile.new", $!));
    print(NEW @head,join("\n",@newwork)) ||
	&ulquit(sprintf(_g("unable to write %s: %s"), "$dirfile.new", $!));
    close(NEW) || &ulquit(sprintf(_g("unable to close %s: %s"), "$dirfile.new", $!));

    unlink("$dirfile.old");
    link($dirfile, "$dirfile.old") ||
	&ulquit(sprintf(_g("unable to backup old %s, giving up: %s"),
			   $dirfile, $!));
    rename("$dirfile.new", $dirfile) ||
	&ulquit(sprintf(_g("unable to install new %s: %s"), $dirfile, $!));

    unlink("$dirfile.lock") ||
	&quit(sprintf(_g("unable to unlock %s: %s"), $dirfile, $!));
    system ('cp', $dirfile, $backup) &&
	warn sprintf(_g("%s: could not backup %s in %s: %s"), $name, $dirfile, $backup, $!)."\n";
}

sub quit
{
    die "$name: $@\n";
}

sub ulquit {
    unlink("$dirfile.lock") ||
	warn sprintf(_g("%s: warning - unable to unlock %s: %s"),
		     $name, $dirfile, $!)."\n";
    &quit($_[0]);
}

sub checkpipe {
    return if !$pipeit || !$? || $?==0x8D00 || $?==0x0D;
    &quit(sprintf(_g("unable to read %s: %d"), $filename, $?));
}

sub dprint {
    printf(DEBUG _g("dbg: %s")."\n", $_[0]) if ($debug);
}

exit 0;
