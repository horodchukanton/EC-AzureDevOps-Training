#
#  Copyright 2019 Electric Cloud, Inc.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#

#########################
## checkConnection.pl
#########################
$[/myProject/scripts/preamble]

use Data::Dumper;
use ElectricCommander;
use ElectricCommander::PropDB;

use EC::AzureDevOps::Plugin;

my $ec = ElectricCommander->new();
$ec->abortOnError(0);

my $endpoint     = get_step_property_value('endpoint');
my $collection   = get_step_property_value('collection');
my $api_version  = get_step_property_value('apiVersion');
my $proxy        = get_step_property_value('http_proxy');
my $auth         = get_step_property_value('auth');

my $xpath         = $ec->getFullCredential('credential');
my $client_id     = $xpath->findvalue("//userName");
my $client_secret = $xpath->findvalue("//password");

my $proxy_xpath    = ( $proxy ) ? $ec->getFullCredential('proxy_credential') : '';
my $proxy_user     = ( $proxy_xpath ) ? $proxy_xpath->findvalue("//userName") : '';
my $proxy_password = ( $proxy_xpath ) ? $proxy_xpath->findvalue("//password") : '';

my $custom_api_version  = get_step_property_value('customApiVersions');

my $plugin = EC::AzureDevOps::Plugin->new(
    # Enable the full debug
    debug_level => 3
);

eval {
    my %config = (
        endpoint          => $endpoint,
        collection        => $collection,
        userName          => $client_id,
        password          => $client_secret,
        debugLevel        => 2,

        # Auth type params
        auth              => $auth,
        apiVersion        => $api_version,
        customApiVersions => $custom_api_version,

        # Proxy params
        http_proxy        => $proxy,
        proxy_username    => $proxy_user,
        proxy_password    => $proxy_password,
    );
    $plugin->{_config} = \%config;

    $plugin->check_connection(\%config);

    1;
} or do {
    print "Failed to check connection with given credentials\n";
    my $msg = $@;
    if ($msg){
        $msg .= "\n";
        print $msg;
        $ec->setProperty('/myJob/configError', $msg);
        $ec->setProperty('/myJobStep/summary', $msg);
        exit 1;
    }
};

exit 0;

sub get_step_property_value{
    my $param_name = shift;
    return $ec->getProperty($param_name)->findvalue('//value')->string_value;
}