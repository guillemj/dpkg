#!/usr/bin/perl --
# I hereby place this in the public domain - Ian Jackson, 1995.
# Changes by Klee Dienes also placed in public domain (1997). 

# time structure:
# [ sec min hour mday mon year wday yday isdst ]

@ARGV && die "usage: 822-date\n";

$curtime = time;
@localtm = localtime ($curtime);
$localtms = localtime ($curtime);
@gmttm = gmtime ($curtime);
$gmttms = gmtime ($curtime);

if ($localtm[0] != $gmttm[0]) {
    die (sprintf ("local timezone differs from GMT by a non-minute interval\n"
		 . "local time: %s\n"
		 . "GMT time: %s\n", $localtms, $gmttms));
}

$localmin = $localtm[1] + $localtm[2] * 60;
$gmtmin = $gmttm[1] + $gmttm[2] * 60;

if ((($gmttm[6] + 1) % 7) == $localtm[6]) {
    $localmin += 1440;
} elsif ((($gmttm[6] - 1) % 7) == $localtm[6]) {
    $localmin -= 1440;
} elsif ($gmttm[6] == $localtm[6]) {
    1;
} else {
    die ("822-date: local time offset greater than or equal to 24 hours\n");
}

$offset = $localmin - $gmtmin;
$offhour = $offset / 60;
$offmin = abs ($offset % 60);

if (abs ($offhour) >= 24) { 
    die ("822-date: local time offset greater than or equal to 24 hours\n");
}

printf 
    (
     "%s, %2d %s %d %02d:%02d:%02d %s%02d%02d\n",
     (Sun,Mon,Tue,Wed,Thu,Fri,Sat)[$localtm[6]], # day of week
     $localtm[3],		# day of month
     (Jan,Feb,Mar,Apr,May,Jun,Jul,Aug,Sep,Oct,Nov,Dec)[$localtm[4]], # month
     $localtm[5]+1900,		# year
     $localtm[2],		# hour
     $localtm[1],		# minute
     $localtm[0],		# sec
     ($offset >= 0) ? '+' : '-',# TZ offset direction
     abs ($offhour),		# TZ offset hour
     $offmin,			# TZ offset minute
     ) || die "822-date: output error: $!\n";
