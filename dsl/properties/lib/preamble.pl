#!/usr/bin/env perl
# line 3 "preamble.pl"

use strict;
use warnings;
use ElectricCommander::PropDB;

BEGIN {
    use Carp;
    use ElectricCommander;
    $|=1;

    my $load_debug = 1;

    # Make 'use Foo;' search in properties as well
    # If property exists, wrap it into a "file" and present to Perl CORE
    # Also makes errors/warnings show correct filename and line
    # The local versions of modules are preferred, load from prop as a last
    #     resort.
    my $ec = ElectricCommander->new;
    my $prefix = '/plugins/@PLUGIN_KEY@/project/lib/';

    my $load = sub {
        my ($self, $target) = @_;

        print "[DEBUG] Loading $target " . (join(',',  caller)) . "\n" if ($load_debug);

        # Undo perl'd require transformation
        my $prop = $target;
        $prop =~ s#\.pm$##;
        my $display = '[EC]@PLUGIN_KEY@-@PLUGIN_VERSION@/'.$prop;
        $prop = "$prefix$prop";
        my $code = eval {
            $ec->getProperty("$prop")->findvalue('//value')->string_value;
        };
        # return unless $code; # let other module paths try ;)
        unless( $code){
            print "[DEBUG] Failed to load $target from $prop\n" if ($load_debug);
            return # let other module paths try ;)
        };

        print "[DEBUG] Loaded $target from $prop\n" if ($load_debug);

        # Make it preferrable source for module
        $INC{$target} = $code;

        # Prepend comment for correct error attribution
        $code = qq{# line 1 "$display"\n$code};

        # We must return a file in perl < 5.10, in 5.10+ just return \$code
        #    would suffice.
        open my $fd, "<", \$code
            or die "Redirect failed when loading $target from $display";


        return $fd;
    };

    push @INC, $load;
};

1;