BEGIN {
    eval { require Config; import Config };
    if ($@) {
	print "1..0 # Skip: no Config\n";
	exit(0);
    }
    if ($Config{extensions} !~ /\bThread\b/) {
	print "1..0 # Skip: no use5005threads\n";
	exit(0);
    }
}

use Thread;

use Thread::Specific qw(foo);

sub count {
    my $tid = Thread->self->tid;
    my Thread::Specific $tsd = Thread::Specific::data;
    for (my $i = 0; $i < 5; $i++) {
	$tsd->{foo} = $i;
	print "thread $tid count: $tsd->{foo}\n";
	select(undef, undef, undef, rand(2));
    }
};

for(my $t = 0; $t < 5; $t++) {
    new Thread \&count;
}
