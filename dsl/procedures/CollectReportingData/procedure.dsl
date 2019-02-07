
def procName = 'CollectReportingData'
def stepName = 'collect reporting data'
procedure procName, description: 'Queries specified work items ans sends it as a reporting payload', {

    step stepName,
        command: """
\$[/myProject/scripts/preamble]
use EC::AzureDevOps::Plugin;
\$[/myProject/scripts/collectReportingData]
""",
        errorHandling: 'failProcedure',
        exclusiveMode: 'none',
        releaseMode: 'none',
        shell: 'ec-perl',
        timeLimitUnits: 'minutes'

}
