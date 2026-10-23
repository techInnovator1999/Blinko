#!/usr/bin/perl
# Loads BlinkoMedia.dylib into Apple's platform perl so it may talk to MediaRemote.
# Protocol: JSON lines on stdout; commands on stdin; exits on stdin EOF.
use strict;
use DynaLoader;
my $path = shift @ARGV or die "usage: blinko-media.pl <dylib>\n";
my $lib = DynaLoader::dl_load_file($path, 0) or die "load failed: " . DynaLoader::dl_error() . "\n";
my $sym = DynaLoader::dl_find_symbol($lib, "blinko_media_main") or die "symbol missing\n";
my $fn = DynaLoader::dl_install_xsub("main::blinko_media_main", $sym);
&$fn();
