package Sys::Syslog;
require 5.000;
require Exporter;
require DynaLoader;
use Carp;

@ISA = qw(Exporter DynaLoader);
@EXPORT = qw(openlog closelog setlogmask syslog);
@EXPORT_OK = qw(setlogsock);
$VERSION = '0.04';

# it would be nice to try stream/unix first, since that will be
# most efficient. However streams are dodgy - see _syslog_send_stream
#my @connectMethods = ( 'stream', 'unix', 'tcp', 'udp' );
my @connectMethods = ( 'tcp', 'udp', 'unix', 'stream', 'console' );
if ($^O =~ /^(freebsd|linux)$/) {
    @connectMethods = grep { $_ ne 'udp' } @connectMethods;
}
my @defaultMethods = @connectMethods;
my $syslog_path = undef;
my $transmit_ok = 0;
my $current_proto = undef;
my $failed = undef;
my $fail_time = undef;

use Socket;
use Sys::Hostname;

=head1 NAME

Sys::Syslog, openlog, closelog, setlogmask, syslog - Perl interface to the UNIX syslog(3) calls

=head1 SYNOPSIS

    use Sys::Syslog;                          # all except setlogsock, or:
    use Sys::Syslog qw(:DEFAULT setlogsock);  # default set, plus setlogsock

    setlogsock $sock_type;
    openlog $ident, $logopt, $facility;       # don't forget this
    syslog $priority, $format, @args;
    $oldmask = setlogmask $mask_priority;
    closelog;

=head1 DESCRIPTION

Sys::Syslog is an interface to the UNIX C<syslog(3)> program.
Call C<syslog()> with a string priority and a list of C<printf()> args
just like C<syslog(3)>.

Syslog provides the functions:

=over 4

=item openlog $ident, $logopt, $facility

I<$ident> is prepended to every message.  I<$logopt> contains zero or
more of the words I<pid>, I<ndelay>, I<nowait>.  The cons option is
ignored, since the failover mechanism will drop down to the console
automatically if all other media fail.  I<$facility> specifies the
part of the system to report about, for example LOG_USER or LOG_LOCAL0:
see your C<syslog(3)> documentation for the facilities available in
your system.

B<You should use openlog() before calling syslog().>

=item syslog $priority, $format, @args

If I<$priority> permits, logs I<($format, @args)>
printed as by C<printf(3V)>, with the addition that I<%m>
is replaced with C<"$!"> (the latest error message).

If you didn't use openlog() before using syslog(), syslog will try to
guess the I<$ident> by extracting the shortest prefix of I<$format>
that ends in a ":".

=item setlogmask $mask_priority

Sets log mask I<$mask_priority> and returns the old mask.

=item setlogsock $sock_type [$stream_location] (added in 5.004_02)

Sets the socket type to be used for the next call to
C<openlog()> or C<syslog()> and returns TRUE on success,
undef on failure.

A value of 'unix' will connect to the UNIX domain socket (in some
systems a character special device) returned by the C<_PATH_LOG> macro
(if your system defines it), or F</dev/log> or F</dev/conslog>,
whatever is writable.  A value of 'stream' will connect to the stream
indicated by the pathname provided as the optional second parameter.
A value of 'inet' will connect to an INET socket (either tcp or udp,
tried in that order) returned by getservbyname(). 'tcp' and 'udp' can
also be given as values. The value 'console' will send messages
directly to the console, as for the 'cons' option in the logopts in
openlog().

A reference to an array can also be passed as the first parameter.
When this calling method is used, the array should contain a list of
sock_types which are attempted in order.

The default is to try tcp, udp, unix, stream, console.

Giving an invalid value for sock_type will croak.

=item closelog

Closes the log file.

=back

Note that C<openlog> now takes three arguments, just like C<openlog(3)>.

=head1 EXAMPLES

    openlog($program, 'cons,pid', 'user');
    syslog('info', 'this is another test');
    syslog('mail|warning', 'this is a better test: %d', time);
    closelog();

    syslog('debug', 'this is the last test');

    setlogsock('unix');
    openlog("$program $$", 'ndelay', 'user');
    syslog('notice', 'fooprogram: this is really done');

    setlogsock('inet');
    $! = 55;
    syslog('info', 'problem was %m'); # %m == $! in syslog(3)

=head1 SEE ALSO

L<syslog(3)>

=head1 AUTHOR

Tom Christiansen E<lt>F<tchrist@perl.com>E<gt> and Larry Wall
E<lt>F<larry@wall.org>E<gt>.

UNIX domain sockets added by Sean Robinson
E<lt>F<robinson_s@sc.maricopa.edu>E<gt> with support from Tim Bunce 
E<lt>F<Tim.Bunce@ig.co.uk>E<gt> and the perl5-porters mailing list.

Dependency on F<syslog.ph> replaced with XS code by Tom Hughes
E<lt>F<tom@compton.nu>E<gt>.

Code for constant()s regenerated by Nicholas Clark E<lt>F<nick@ccl4.org>E<gt>.

Failover to different communication modes by Nick Williams
E<lt>F<Nick.Williams@morganstanley.com>E<gt>.

=cut

sub AUTOLOAD {
    # This AUTOLOAD is used to 'autoload' constants from the constant()
    # XS function.
    
    my $constname;
    our $AUTOLOAD;
    ($constname = $AUTOLOAD) =~ s/.*:://;
    croak "&Sys::Syslog::constant not defined" if $constname eq 'constant';
    my ($error, $val) = constant($constname);
    if ($error) {
	croak $error;
    }
    *$AUTOLOAD = sub { $val };
    goto &$AUTOLOAD;
}

bootstrap Sys::Syslog $VERSION;

$maskpri = &LOG_UPTO(&LOG_DEBUG);

sub openlog {
    ($ident, $logopt, $facility) = @_;  # package vars
    $lo_pid = $logopt =~ /\bpid\b/;
    $lo_ndelay = $logopt =~ /\bndelay\b/;
    $lo_nowait = $logopt =~ /\bnowait\b/;
    return 1 unless $lo_ndelay;
    &connect;
} 

sub closelog {
    $facility = $ident = '';
    &disconnect;
} 

sub setlogmask {
    local($oldmask) = $maskpri;
    $maskpri = shift;
    $oldmask;
}
 
sub setlogsock {
    local($setsock) = shift;
    $syslog_path = shift;
    &disconnect if $connected;
    $transmit_ok = 0;
    @fallbackMethods = ();
    @connectMethods = @defaultMethods;
    if (ref $setsock eq 'ARRAY') {
	@connectMethods = @$setsock;
    } elsif (lc($setsock) eq 'stream') {
	unless (defined $syslog_path) {
	    my @try = qw(/dev/log /dev/conslog);
	    if (length &_PATH_LOG) { # Undefined _PATH_LOG is "".
		unshift @try, &_PATH_LOG;
            }
	    for my $try (@try) {
		if (-w $try) {
		    $syslog_path = $try;
		    last;
		}
	    }
	    carp "stream passed to setlogsock, but could not find any device"
		unless defined $syslog_path;
        }
	unless (-w $syslog_path) {
	    carp "stream passed to setlogsock, but $syslog_path is not writable";
	    return undef;
	} else {
	    @connectMethods = ( 'stream' );
	}
    } elsif (lc($setsock) eq 'unix') {
        if (length _PATH_LOG() && !defined $syslog_path) {
	    $syslog_path = _PATH_LOG();
	    @connectMethods = ( 'unix' );
        } else {
	    carp 'unix passed to setlogsock, but path not available';
	    return undef;
        }
    } elsif (lc($setsock) eq 'tcp') {
	if (getservbyname('syslog', 'tcp') || getservbyname('syslogng', 'tcp')) {
	    @connectMethods = ( 'tcp' );
	} else {
	    carp "tcp passed to setlogsock, but tcp service unavailable";
	    return undef;
	}
    } elsif (lc($setsock) eq 'udp') {
	if (getservbyname('syslog', 'udp')) {
	    @connectMethods = ( 'udp' );
	} else {
	    carp "udp passed to setlogsock, but udp service unavailable";
	    return undef;
	}
    } elsif (lc($setsock) eq 'inet') {
	@connectMethods = ( 'tcp', 'udp' );
    } elsif (lc($setsock) eq 'console') {
	@connectMethods = ( 'console' );
    } else {
        carp "Invalid argument passed to setlogsock; must be 'stream', 'unix', 'tcp', 'udp' or 'inet'";
    }
    return 1;
}

sub syslog {
    local($priority) = shift;
    local($mask) = shift;
    local($message, $whoami);
    local(@words, $num, $numpri, $numfac, $sum);
    local($facility) = $facility;	# may need to change temporarily.

    croak "syslog: expecting argument \$priority" unless $priority;
    croak "syslog: expecting argument \$format"   unless $mask;

    @words = split(/\W+/, $priority, 2);# Allow "level" or "level|facility".
    undef $numpri;
    undef $numfac;
    foreach (@words) {
	$num = &xlate($_);		# Translate word to number.
	if (/^kern$/ || $num < 0) {
	    croak "syslog: invalid level/facility: $_";
	}
	elsif ($num <= &LOG_PRIMASK) {
	    croak "syslog: too many levels given: $_" if defined($numpri);
	    $numpri = $num;
	    return 0 unless &LOG_MASK($numpri) & $maskpri;
	}
	else {
	    croak "syslog: too many facilities given: $_" if defined($numfac);
	    $facility = $_;
	    $numfac = $num;
	}
    }

    croak "syslog: level must be given" unless defined($numpri);

    if (!defined($numfac)) {	# Facility not specified in this call.
	$facility = 'user' unless $facility;
	$numfac = &xlate($facility);
    }

    &connect unless $connected;

    $whoami = $ident;

    if (!$whoami && $mask =~ /^(\S.*?):\s?(.*)/) {
	$whoami = $1;
	$mask = $2;
    } 

    unless ($whoami) {
	($whoami = getlogin) ||
	    ($whoami = getpwuid($<)) ||
		($whoami = 'syslog');
    }

    $whoami .= "[$$]" if $lo_pid;

    $mask =~ s/%m/$!/g;
    $mask .= "\n" unless $mask =~ /\n$/;
    $message = sprintf ($mask, @_);

    $sum = $numpri + $numfac;
    my $buf = "<$sum>$whoami: $message\0";

    # it's possible that we'll get an error from sending
    # (e.g. if method is UDP and there is no UDP listener,
    # then we'll get ECONNREFUSED on the send). So what we
    # want to do at this point is to fallback onto a different
    # connection method.
    while (scalar @fallbackMethods || $syslog_send) {
	if ($failed && (time - $fail_time) > 60) {
	    # it's been a while... maybe things have been fixed
	    @fallbackMethods = ();
	    disconnect();
	    $transmit_ok = 0; # make it look like a fresh attempt
	    &connect;
        }
	if ($connected && !connection_ok()) {
	    # Something was OK, but has now broken. Remember coz we'll
	    # want to go back to what used to be OK.
	    $failed = $current_proto unless $failed;
	    $fail_time = time;
	    disconnect();
	}
	&connect unless $connected;
	$failed = undef if ($current_proto && $failed && $current_proto eq $failed);
	if ($syslog_send) {
	    if (&{$syslog_send}($buf)) {
		$transmit_ok++;
		return 1;
	    }
	    # typically doesn't happen, since errors are rare from write().
	    disconnect();
	}
    }
    # could not send, could not fallback onto a working
    # connection method. Lose.
    return 0;
}

sub _syslog_send_console {
    my ($buf) = @_;
    chop($buf); # delete the NUL from the end
    # The console print is a method which could block
    # so we do it in a child process and always return success
    # to the caller.
    if (my $pid = fork) {
	if ($lo_nowait) {
	    return 1;
	} else {
	    if (waitpid($pid, 0) >= 0) {
	    	return ($? >> 8);
	    } else {
		# it's possible that the caller has other
		# plans for SIGCHLD, so let's not interfere
		return 1;
	    }
	}
    } else {
        if (open(CONS, ">/dev/console")) {
	    my $ret = print CONS $buf . "\r";
	    exit ($ret) if defined $pid;
	    close CONS;
	}
	exit if defined $pid;
    }
}

sub _syslog_send_stream {
    my ($buf) = @_;
    # XXX: this only works if the OS stream implementation makes a write 
    # look like a putmsg() with simple header. For instance it works on 
    # Solaris 8 but not Solaris 7.
    # To be correct, it should use a STREAMS API, but perl doesn't have one.
    return syswrite(SYSLOG, $buf, length($buf));
}
sub _syslog_send_socket {
    my ($buf) = @_;
    return syswrite(SYSLOG, $buf, length($buf));
    #return send(SYSLOG, $buf, 0);
}

sub xlate {
    local($name) = @_;
    $name = uc $name;
    $name = "LOG_$name" unless $name =~ /^LOG_/;
    $name = "Sys::Syslog::$name";
    # Can't have just eval { &$name } || -1 because some LOG_XXX may be zero.
    my $value = eval { &$name };
    defined $value ? $value : -1;
}

sub connect {
    @fallbackMethods = @connectMethods unless (scalar @fallbackMethods);
    if ($transmit_ok && $current_proto) {
	# Retry what we were on, because it's worked in the past.
	unshift(@fallbackMethods, $current_proto);
    }
    $connected = 0;
    my @errs = ();
    my $proto = undef;
    while ($proto = shift(@fallbackMethods)) {
	my $fn = "connect_$proto";
	$connected = &$fn(\@errs) unless (!defined &$fn);
	last if ($connected);
    }

    $transmit_ok = 0;
    if ($connected) {
	$current_proto = $proto;
        local($old) = select(SYSLOG); $| = 1; select($old);
    } else {
	@fallbackMethods = ();
	foreach my $err (@errs) {
	    carp $err;
	}
	croak "no connection to syslog available";
    }
}

sub connect_tcp {
    my ($errs) = @_;
    unless ($host) {
	require Sys::Hostname;
	my($host_uniq) = Sys::Hostname::hostname();
	($host) = $host_uniq =~ /([A-Za-z0-9_.-]+)/; # allow FQDN (inc _)
    }
    my $tcp = getprotobyname('tcp');
    if (!defined $tcp) {
	push(@{$errs}, "getprotobyname failed for tcp");
	return 0;
    }
    my $syslog = getservbyname('syslog','tcp');
    $syslog = getservbyname('syslogng','tcp') unless (defined $syslog);
    if (!defined $syslog) {
	push(@{$errs}, "getservbyname failed for tcp");
	return 0;
    }

    my $this = sockaddr_in($syslog, INADDR_ANY);
    my $that = sockaddr_in($syslog, inet_aton($host));
    if (!$that) {
	push(@{$errs}, "can't lookup $host");
	return 0;
    }
    if (!socket(SYSLOG,AF_INET,SOCK_STREAM,$tcp)) {
	push(@{$errs}, "tcp socket: $!");
	return 0;
    }
    setsockopt(SYSLOG, SOL_SOCKET, SO_KEEPALIVE, 1);
    setsockopt(SYSLOG, IPPROTO_TCP, TCP_NODELAY, 1);
    if (!CORE::connect(SYSLOG,$that)) {
	push(@{$errs}, "tcp connect: $!");
	return 0;
    }
    $syslog_send = \&_syslog_send_socket;
    return 1;
}

sub connect_udp {
    my ($errs) = @_;
    unless ($host) {
	require Sys::Hostname;
	my($host_uniq) = Sys::Hostname::hostname();
	($host) = $host_uniq =~ /([A-Za-z0-9_.-]+)/; # allow FQDN (inc _)
    }
    my $udp = getprotobyname('udp');
    if (!defined $udp) {
	push(@{$errs}, "getprotobyname failed for udp");
	return 0;
    }
    my $syslog = getservbyname('syslog','udp');
    if (!defined $syslog) {
	push(@{$errs}, "getservbyname failed for udp");
	return 0;
    }
    my $this = sockaddr_in($syslog, INADDR_ANY);
    my $that = sockaddr_in($syslog, inet_aton($host));
    if (!$that) {
	push(@{$errs}, "can't lookup $host");
	return 0;
    }
    if (!socket(SYSLOG,AF_INET,SOCK_DGRAM,$udp)) {
	push(@{$errs}, "udp socket: $!");
	return 0;
    }
    if (!CORE::connect(SYSLOG,$that)) {
	push(@{$errs}, "udp connect: $!");
	return 0;
    }
    # We want to check that the UDP connect worked. However the only
    # way to do that is to send a message and see if an ICMP is returned
    _syslog_send_socket("");
    if (!connection_ok()) {
	push(@{$errs}, "udp connect: nobody listening");
	return 0;
    }
    $syslog_send = \&_syslog_send_socket;
    return 1;
}

sub connect_stream {
    my ($errs) = @_;
    # might want syslog_path to be variable based on syslog.h (if only
    # it were in there!)
    $syslog_path = '/dev/conslog'; 
    if (!-w $syslog_path) {
	push(@{$errs}, "stream $syslog_path is not writable");
	return 0;
    }
    if (!open(SYSLOG, ">" . $syslog_path)) {
	push(@{$errs}, "stream can't open $syslog_path: $!");
	return 0;
    }
    $syslog_send = \&_syslog_send_stream;
    return 1;
}

sub connect_unix {
    my ($errs) = @_;
    if (length _PATH_LOG()) {
	$syslog_path = _PATH_LOG();
    } else {
        push(@{$errs}, "_PATH_LOG not available in syslog.h");
	return 0;
    }
    my $that = sockaddr_un($syslog_path);
    if (!$that) {
	push(@{$errs}, "can't locate $syslog_path");
	return 0;
    }
    if (!socket(SYSLOG,AF_UNIX,SOCK_STREAM,0)) {
	push(@{$errs}, "unix stream socket: $!");
	return 0;
    }
    if (!CORE::connect(SYSLOG,$that)) {
        if (!socket(SYSLOG,AF_UNIX,SOCK_DGRAM,0)) {
	    push(@{$errs}, "unix dgram socket: $!");
	    return 0;
	}
        if (!CORE::connect(SYSLOG,$that)) {
	    push(@{$errs}, "unix dgram connect: $!");
	    return 0;
	}
    }
    $syslog_send = \&_syslog_send_socket;
    return 1;
}

sub connect_console {
    my ($errs) = @_;
    if (!-w '/dev/console') {
	push(@{$errs}, "console is not writable");
	return 0;
    }
    $syslog_send = \&_syslog_send_console;
    return 1;
}

# to test if the connection is still good, we need to check if any
# errors are present on the connection. The errors will not be raised
# by a write. Instead, sockets are made readable and the next read
# would cause the error to be returned. Unfortunately the syslog 
# 'protocol' never provides anything for us to read. But with 
# judicious use of select(), we can see if it would be readable...
sub connection_ok {
    return 1 if (defined $current_proto && $current_proto eq 'console');
    my $rin = '';
    vec($rin, fileno(SYSLOG), 1) = 1;
    my $ret = select $rin, undef, $rin, 0;
    return ($ret ? 0 : 1);
}

sub disconnect {
    close SYSLOG;
    $connected = 0;
    $syslog_send = undef;
}

1;
