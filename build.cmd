del /Q build
..\ecpluginbuilder.exe --plugin-version "1.0.0" --plugin-name "EC-AzureDevOps" --folder dsl,htdocs,pages,META-INF
ectool login admin changeme
ectool installPlugin build\EC-AzureDevOps-1.0.0.zip && ectool promotePlugin EC-AzureDevOps-1.0.0
