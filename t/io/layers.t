#!./perl

BEGIN {
    chdir 't' if -d 't';
    @INC = '../lib';
    require './test.pl';
    unless (find PerlIO::Layer 'perlio') {
	print "1..0 # Skip: not perlio\n";
	exit 0;
    }
    if (exists $ENV{PERLIO} && $ENV{PERLIO} !~ /^(stdio|perlio|mmap)$/) {
	print "1..0 # PERLIO='$ENV{PERLIO}' unknown\n";
	exit 0;
    }
}

plan tests => 43;

use Config;

my $DOSISH   = $^O =~ /^(?:MSWin32|cygwin|os2|dos|NetWare|mint)$/;
my $NONSTDIO = exists $ENV{PERLIO} && $ENV{PERLIO} ne 'stdio';

SKIP: {
    skip("This perl does not have Encode", 43)
	unless " $Config{extensions} " =~ / Encode /;

    sub check {
	my ($result, $expected, $id) = @_;
	if ($NONSTDIO) {
	    # Get rid of "unix".
	    shift @$result if $result->[0] eq "unix";
	    # Change expectations.
	    $expected->[0] = $ENV{PERLIO} if $expected->[0] eq "stdio";
	} elsif ($DOSISH) {
	    splice(@$result, 0, 2, "stdio")
		if $result->[0] eq "unix" &&
		   $result->[1] eq "crlf";
	}
	my $n = scalar @$expected;
	is($n, scalar @$expected, "$id - layers = $n");
	for (my $i = 0; $i < $n; $i++) {
	    my $j = $expected->[$i];
	    if (ref $j eq 'CODE') {
		ok($j->($result->[$i]), "$id - $i is ok");
	    } else {
		is($result->[$i], $j,
		   sprintf("$id - $i is %s",
			   defined $j ? $j : "undef"));
	    }
	}
    }

    check([ PerlIO::get_layers(STDIN) ],
	  [ "stdio" ],
	  "STDIN");

    open(F, ">:crlf", "afile");

    check([ PerlIO::get_layers(F) ],
	  [ qw(stdio crlf) ],
	  "open :crlf");

    binmode(F, ":encoding(sjis)"); # "sjis" will be canonized to "shiftjis"

    check([ PerlIO::get_layers(F) ],
	  [ qw[stdio crlf encoding(shiftjis) utf8] ],
	  ":encoding(sjis)");
    
    binmode(F, ":pop");

    check([ PerlIO::get_layers(F) ],
	  [ qw(stdio crlf) ],
	  ":pop");

    binmode(F, ":raw");

    check([ PerlIO::get_layers(F) ],
	  [ "stdio" ],
	  ":raw");

    binmode(F, ":pop") if $DOSISH; # Drop one extra :crlf.
    binmode(F, ":utf8");

    check([ PerlIO::get_layers(F) ],
	  [ qw(stdio utf8) ],
	  ":utf8");

    binmode(F, ":bytes");

    check([ PerlIO::get_layers(F) ],
	  [ "stdio" ],
	  ":bytes");

    binmode(F, ":encoding(utf8)");

    check([ PerlIO::get_layers(F) ],
	    [ qw[stdio encoding(utf8) utf8] ],
	    ":encoding(utf8)");

    binmode(F, ":raw :crlf");

    check([ PerlIO::get_layers(F) ],
	  [ qw(stdio crlf) ],
	  ":raw:crlf");

    binmode(F, ":raw :encoding(latin1)"); # "latin1" will be canonized

    SKIP: {
	skip("too complex layer coreography", 7) if $DOSISH;

	my @results = PerlIO::get_layers(F, details => 1);

	# Get rid of the args and the flags.
	splice(@results, 1, 2) if $NONSTDIO;

	check([ @results ],
	      [ "stdio",    undef,        sub { $_[0] > 0 },
		"encoding", "iso-8859-1", sub { $_[0] & PerlIO::F_UTF8() } ],
	      ":raw:encoding(latin1)");
    }

    binmode(F);

    check([ PerlIO::get_layers(F) ],
	  [ "stdio" ],
	  "binmode");

    close F;

    {
	use open(IN => ":crlf", OUT => ":encoding(cp1252)");

	open F, "<afile";
	open G, ">afile";

	check([ PerlIO::get_layers(F, input  => 1) ],
	      [ qw(stdio crlf) ],
	      "use open IN");
	
	check([ PerlIO::get_layers(G, output => 1) ],
	      [ qw[stdio encoding(cp1252) utf8] ],
	      "use open OUT");

	close F;
	close G;
    }

    1 while unlink "afile";
}
