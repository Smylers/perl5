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

use Thread 'async';

$t = async {
    sleep 1;
    print "here\n";
    die "success if preceded by 'thread died...'";
    print "shouldn't get here\n";
};

print "joining...\n";
@r = eval { $t->join; };
if ($@) {
    print "thread died with message: $@";
} else {
    print "thread failed to die successfully\n";
}
