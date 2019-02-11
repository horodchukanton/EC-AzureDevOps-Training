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

    // Optional
    @Shared
    def project

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
            name : randomize("flat"),
            query: "Select [System.Id], [System.Title], [System.State] From WorkItems Where [System.WorkItemType] = 'Feature'",
            ref  : null
        ],
        oneHop       : [
            name : randomize("oneHop"),
            query: "Select [System.Id], [System.Title], [System.State] From WorkItems Where [System.WorkItemType] = 'Feature'",
            ref  : null
        ],
        tree         : [
            name : randomize("tree"),
            query: "Select [System.Id], [System.Title], [System.State] From WorkItems Where [System.WorkItemType] = 'Feature'",
            ref  : null
        ],
        empty        : [
            name : randomize("empty"),
            query: "Select [System.Id], [System.Title], [System.State] From WorkItems Where [System.WorkItemType] = 'Epic'",
            type : 'flat',
            ref  : null
        ],
        invalid        : [
            name : randomize("empty"),
            query: "Give me an error",
            type : 'flat',
            ref  : null,
            doNotCreate: true
        ]
    ]

    def doSetupSpec() {
        createConfiguration(configName)
        dslFile "dsl/$procedureName/procedure.dsl", [projectName: projectName]

        tfsClient = getClient()
        assert tfsClient

        // Create an instance of every query
        queries.each { String type, Map parameters ->
            if (parameters != null && !parameters['doNotCreate']) {
                // QueryType can be different from the name
                String queryType = type
                if (queries[type]['type']){
                    queryType = queries[type]['type']
                }

                def queryJSON = tfsClient.createWorkItemQuery(
                    (String) queries[type]['name'],
                    (String) queries[type]['query'],
                    [queryType: queryType]
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

        deleteConfiguration('EC-AzureDevOps-Training', configName)
        conditionallyDeleteProject(projectName)
    }

    @Unroll
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
        'CHANGEME_2' | 'oneHop'
        'CHANGEME_3' | 'tree'
    }

    @Unroll
    def '#caseId. Sanity. Query by WIQL'() {
        given:
        def resultFormat = 'propertySheet'
        def resultSheet = '/myJob/queryWorkItems'

        assert queries[queryType] && queries[queryType]['query']

        queryText = queries[queryType]['query']

        Map procedureParams = [
            config             : configName,
            project            : '',
            queryId            : '',
            queryText          : queryText,
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
        'CHANGEME_4' | 'flat'
        'CHANGEME_5' | 'oneHop'
        'CHANGEME_6' | 'tree'
    }

    @Unroll
    def '#caseId. Sanity. Warning for empty query result'() {
        given:
        def resultFormat = 'propertySheet'
        def resultSheet = '/myJob/queryWorkItems'

        assert queries[queryType] && queries[queryType]['query']

        queryText = queries[queryType]['query']

        Map procedureParams = [
            config             : configName,
            project            : '',
            queryId            : '',
            queryText          : queryText,
            timePrecision      : '',
            resultPropertySheet: resultSheet,
            resultFormat       : resultFormat,
        ]

        when:
        def result = runProcedure(projectName, procedureName, procedureParams)

        then:
        println getJobLink(result.jobId)
        println(result.logs)

        assert result.outcome == 'warning'

        where:
        caseId       | queryType
        'CHANGEME_7' | 'empty'
    }
}