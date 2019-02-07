use strict;
use warnings FATAL => 'all';

use ElectricCommander;
use EC::AzureDevOps::Plugin;

my $plugin = EC::AzureDevOps::Plugin->new();
$plugin->logger->info("Hello, world");

exit 0;