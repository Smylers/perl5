#!./perl

print "1..5\n";

my $test = 0;

# symbolic filehandles should only result in glob entries with FH constructors

my $a = "SYM000";
print "not " if defined(fileno($a)) or defined *{$a};
++$test; print "ok $test\n";

select select $a;
print "not " if defined *{$a};
++$test; print "ok $test\n";

print "not " if close $a or defined *{$a};
++$test; print "ok $test\n";

print "not " unless open($a, ">&STDOUT") and defined *{$a};
++$test; print $a "ok $test\n";

print "not " unless close $a;
++$test; print $a "not "; print "ok $test\n";
