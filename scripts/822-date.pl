#!/usr/bin/perl --
# I hereby place this in the public domain - Ian Jackson, 1995.
@ARGV && die "usage: 822-date\n";
$x=time; sub z { $_[1]+$_[2]*60; }; @l=localtime($x); $od=1440;
$d=&z(@l)-&z(gmtime($x)); $d+=$od; $d%=$od; $s=$d>$od/2?($d=$od-$d,'-'):'+';
printf("%s, %d %s %d %02d:%02d:%02d %s%02d%02d\n",
 (Sun,Mon,Tue,Wed,Thu,Fri,Sat)[$l[6]], $l[3],
 (Jan,Feb,Mar,Apr,May,Jun,Jul,Aug,Sep,Oct,Nov,Dec)[$l[4]], $l[5]+1900,
 $l[2],$l[1],$l[0], $s,$d/60,$d%60) || die "822-date: output error: $!\n";
