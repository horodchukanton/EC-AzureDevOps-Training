package com.electriccloud.plugin.spec

import com.electriccloud.plugin.spec.tfs.TFSHelper
import spock.lang.*

@Stepwise
class QueryWorkItems extends PluginTestHelper {

    static String procedureName = "QueryWorkItems"
    static String projectName = "Spec Tests $procedureName"
    static String configName = "config_${procedureName}"

    @Shared
    TFSHelper tfsClient

    /// Procedure parameters
    // Mandatory
    @Shared
    def resultPropertySheet = '/myJob/workItems'
    @Shared
    def resultFormat = 'propertySheet'

    @Shared
    def asOf = ''

    @Shared
    def queryId

    @Shared
    def queryText

    @Shared
    def timePrecision

    /// Specs parameters
    @Shared
    def caseId,
        expectedSummary,
        expectedOutcome

    def doSetupSpec() {
        createConfiguration(configName)
        dslFile "dsl/$procedureName/procedure.dsl", [projectName: projectName]

        tfsClient = getClient()
        assert tfsClient
    }

    def doCleanupSpec() {
//        deleteConfiguration('EC-AzureDevOps', configName)
        conditionallyDeleteProject(projectName)
    }

    def '#caseId. Sanity'() {
        given:
        // TODO: move query creation to helper
        queryId = 'c30a3d1f-fd32-49ad-839e-2cf883c33e83'

        Map procedureParams = [
            config             : configName,
            project            : '',
            queryId            : queryId,
            queryText          : '',
            timePrecision      : '',
            resultPropertySheet: '/myJob/queryWorkItems',
            resultFormat       : 'propertySheet',
        ]

        when:
        def result = runProcedure(projectName, procedureName, procedureParams)

        then:
        println getJobLink(result.jobId)

        println(result.logs)

        assert result.outcome == 'success'
    }
}