#!/usr/bin/perl
while(<>) {
    if (m/^\s+\{\s+\"(\w[^"]+)\",\s+0,\s+\w+list\:\:kd_\w+,\s+qa_\w+\s+\},\s*$/ ||
        m/^\s+\{\s+\"(\w[^"]+)\",\s+\w+list\:\:kd_\w+,\s+0,\s+qa_\w+\s+\},\s*$/) {
        $implem{$1}= 1;
    } elsif (m/^\s+\{\s+(\S.{0,15}\S),\s+\"(\w[^"]+)\"\s+\},\s*$/) {
        $bound{$2} .= $1.', ';
    } elsif (m/^\s+\{\s+0,/ || m/^\s+\{\s+-1,/) {
    } elsif (m/^\s+\{\s+/) {
        print "huh ? $_";
    }
}
for $f (sort keys %bound) {
    next if defined($implem{$f});
    $b=$bound{$f}; $b =~ s/, $//;
    printf "unimplemented: %-20s (%s)\n", $f, $b;
}
