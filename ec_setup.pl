#
# Copyright 2019 Electric Cloud, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

use Cwd;
use File::Spec;
use POSIX;
my $dir = getcwd;
my $logfile = "";
my $pluginDir;

if (defined $ENV{QUERY_STRING}) { # Promotion through UI
    $pluginDir = $ENV{COMMANDER_PLUGINS} . "/$pluginName";
}
else {
    my $commanderPluginDir = $commander->getProperty('/server/settings/pluginsDirectory')->findvalue('//value');
    # We are not checking for the directory, because we can run this script on a different machine
    $pluginDir = File::Spec->catfile($commanderPluginDir, $pluginName);
}

# Detecting running ec_setup on Windows for the Flow installed on Linux
my $win_to_lin = ($^O =~ /MSWin32/ && $pluginDir =~ /^\\/);

$pluginDir =~ s|\\|/|g if $win_to_lin;

$logfile .= "Plugin directory is $pluginDir";

$commander->setProperty("/plugins/$pluginName/project/pluginDir", { value => $pluginDir });
$logfile .= "Plugin Name: $pluginName\n";
$logfile .= "Current directory: $dir\n";

# Evaluate promote.groovy or demote.groovy based on whether plugin is being promoted or demoted ($promoteAction)
local $/ = undef;
# If env variable QUERY_STRING exists:
my $dslFilePath;
if (defined $ENV{QUERY_STRING}) { # Promotion through UI
    $dslFilePath = File::Spec->catfile($ENV{COMMANDER_PLUGINS}, $pluginName, "dsl", "$promoteAction.groovy");
}
else { # Promotion from the command line
    $dslFilePath = File::Spec->catfile($pluginDir, "dsl", "$promoteAction.groovy");
}
$dslFilePath =~ s|\\|/|g if $win_to_lin;

my $demoteDsl = q{
# demote.groovy placeholder

};

my $promoteDsl = q{
# promote.groovy placeholder
};

my $dsl;
if ($promoteAction eq 'promote') {
    $dsl = $promoteDsl;
}
else {
    $dsl = $demoteDsl;
}

# Running ec_setup on Windows for the Flow installed on Linux
my $serverLibraryPath = File::Spec->catdir($pluginDir, 'dsl');
$serverLibraryPath =~ s|\\|/|g if $win_to_lin;

my $dslReponse = $commander->evalDsl(
    $dsl, {
    parameters        => qq(
                     {
                       "pluginName":"$pluginName",
                       "upgradeAction":"$upgradeAction",
                       "otherPluginName":"$otherPluginName"
                     }
              ),
    debug             => 'false',
    serverLibraryPath => $serverLibraryPath,
},
);

$logfile .= $dslReponse->findnodes_as_string("/");

my $errorMessage = $commander->getError();

# Create output property for plugin setup debug logs
my $nowString = localtime;
$commander->setProperty("/plugins/$pluginName/project/logs/$nowString", { value => $logfile });

die $errorMessage unless ! $errorMessage;