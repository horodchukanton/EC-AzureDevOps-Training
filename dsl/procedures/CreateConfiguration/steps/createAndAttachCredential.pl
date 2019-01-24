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

##########################
# createAndAttachCredential.pl
##########################
use ElectricCommander;
use JSON;
use Data::Dumper;
use strict;
use warnings;

use constant {
    SUCCESS => 0,
    ERROR   => 1,
};

## get an EC object
my ElectricCommander $ec = ElectricCommander->new();
$ec->abortOnError(0);

my $config = '$[/myJob/config]';
my $credential = $config;
my $proxyCredential = $credential . '_proxy_credential';

my %credentials = (
    $credential      => 'credential',
    $proxyCredential => 'proxy_credential'
);

sub try_to_attach_the_credential {
    my ( $credName, $credValue ) = @_;

    my $xpath;
    eval {
        $xpath = $ec->getFullCredential($credValue);
        1;
    } or do {
        print "Failed to get credential $credName, next.\n";
        return;
    };
    $ec->abortOnError(0);

    my $userName = $xpath->findvalue("//userName");
    my $password = $xpath->findvalue("//password");
    my $errors = $ec->checkAllErrors($xpath);

    # Create credential
    my $projName = '$[/myProject/projectName]';
    $ec->deleteCredential($projName, $credName);
    $xpath = $ec->createCredential($projName, $credName, $userName, $password);
    $errors .= $ec->checkAllErrors($xpath);

    # Give config the credential's real name
    my $configPath = "/projects/$projName/ec_plugin_cfgs/$config";
    print "Creating credential $credName in project $projName with user $userName\n";
    $errors .= $ec->checkAllErrors($xpath);
    $xpath = $ec->setProperty($configPath . '/' . $credValue, $credName);
    $errors .= $ec->checkAllErrors($xpath);

    # Give job launcher full permissions on the credential
    my $user = '$[/myJob/launchedByUser]';
    $xpath = $ec->createAclEntry("user", $user, {
        projectName                => $projName,
        credentialName             => $credName,
        readPrivilege              => "allow",
        modifyPrivilege            => "allow",
        executePrivilege           => "allow",
        changePermissionsPrivilege => "allow"
    });
    $errors .= $ec->checkAllErrors($xpath);

    # Attach credential to steps that will need it
    my $stepsJSON = $ec->getPropertyValue("/projects/$projName/procedures/CreateConfiguration/ec_stepsWithAttachedCredentials");
    if (defined $stepsJSON && $stepsJSON ne "") {
        #parse as json
        my $steps = from_json($stepsJSON);
        foreach my $step (@$steps) {
            print "Attaching credential to procedure " . $step->{procedureName} . " at step " . $step->{stepName} . "\n";
            my $apath = $ec->attachCredential($projName, $credName, {
                procedureName => $step->{procedureName},
                stepName      => $step->{stepName}
            });
            $errors .= $ec->checkAllErrors($apath);
        }
    }

    if ($errors ne "") {
        # Cleanup the partially created configuration we just created
        $ec->deleteProperty($configPath);
        $ec->deleteCredential($projName, $credName);
        my $errMsg = "Error creating configuration credential: " . $errors;
        $ec->setProperty("/myJob/configError", $errMsg);
        print $errMsg;
        exit 1;
    }
}

for my $credName (keys %credentials) {
    $ec->abortOnError(1);
    print "CredName: $credName\n";
    try_to_attach_the_credential($credName, $credentials{$credName});
}

1;