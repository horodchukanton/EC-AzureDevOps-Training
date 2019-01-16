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

    @Shared
    def queries = [
        flat         : [
            name : randomize("simple"),
            query: "Select [System.Id], [System.Title], [System.State] From WorkItems Where [System.WorkItemType] = 'Feature'",
            ref  : null
        ],
        oneHop       : null,
        tree         : null,
        empty        : null,
        invalidSyntax: null,
    ]

    def doSetupSpec() {
        createConfiguration(configName)
        dslFile "dsl/$procedureName/procedure.dsl", [projectName: projectName]

        tfsClient = getClient()
        assert tfsClient

        // Create an instance of every query
        queries.each { String type, Map parameters ->
            if (parameters != null) {
                def queryJSON = tfsClient.createWorkItemQuery(
                    (String) queries[type]['name'],
                    (String) queries[type]['query'],
                    [queryType: type]
                )

                queries[type]['ref'] = queryJSON
            }
        }
    }

    def doCleanupSpec() {
        // Clean the queries
        queries.each { String type, Map parameters ->
            if (parameters != null && parameters['ref'] != null)
                tfsClient.deleteWorkItemQuery(parameters['ref']['id'])
        }

//        deleteConfiguration('EC-AzureDevOps', configName)
        conditionallyDeleteProject(projectName)
    }

    def '#caseId. Sanity. Query by ID'() {
        given:
        def resultFormat = 'propertySheet'
        def resultSheet = '/myJob/queryWorkItems'

        assert queries[queryType] && queries[queryType]['ref']

        queryId = queries[queryType]['ref']['id']

        Map procedureParams = [
            config             : configName,
            project            : '',
            queryId            : queryId,
            queryText          : '',
            timePrecision      : '',
            resultPropertySheet: resultSheet,
            resultFormat       : resultFormat,
        ]

        when:
        def result = runProcedure(projectName, procedureName, procedureParams)

        then:
        println getJobLink(result.jobId)
        println(result.logs)

        assert result.outcome == 'success'

        where:
        caseId       | queryType
        'CHANGEME_1' | 'flat'
    }
}