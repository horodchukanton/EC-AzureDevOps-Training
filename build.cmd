REM generate help
REM java -jar ..\PluginWizardHelp\build\libs\plugin-wizard-help-1.9-SNAPSHOT.jar -rd "Feb 01, 2019" --out pages\help.xml --pluginFolder .

REM generate plugin
del /Q build
..\ecpluginbuilder.exe --plugin-version "1.0.0" --plugin-name "EC-AzureDevOps-Training" --folder dsl,htdocs,pages,META-INF
ectool login admin changeme

REM install and promote
ectool installPlugin build\EC-AzureDevOps-Training-1.0.0.zip && ectool promotePlugin EC-AzureDevOps-Training-1.0.0
