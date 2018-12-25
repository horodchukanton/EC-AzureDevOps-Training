#!/usr/bin/env bash

SERVER=nick
PLUGIN_NAME=EC-AzureDevOps
PLUGIN_VERSION=1.0.0

echo "Building $PLUGIN_NAME-$PLUGIN_VERSION"
ecpluginbuilder --plugin-version $PLUGIN_VERSION --plugin-name $PLUGIN_NAME --folder dsl,htdocs,pages,META-INF

if [ x"$1" = "x--uninstall" ]; then
  echo "Uninstalling $PLUGIN_NAME-$PLUGIN_VERSION"
  ectool uninstallPlugin $PLUGIN_NAME-$PLUGIN_VERSION
fi;

echo "Login to server ${SERVER}"
ectool --server ${SERVER} login admin changeme
ectool installPlugin build/$PLUGIN_NAME.zip --force 1

echo "Installed, started promote"
ectool promotePlugin $PLUGIN_NAME-$PLUGIN_VERSION
ectool setProperty /projects/$PLUGIN_NAME-$PLUGIN_VERSION/debugLevel 10