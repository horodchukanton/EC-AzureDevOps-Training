package com.electriccloud.plugin.spec

import com.electriccloud.plugin.spec.tfs.TFSHelper
import spock.lang.*

class CreateWorkItems extends PluginTestHelper {

    static String procedureName = "CreateWorkItems"
    static String projectName = "Spec Tests $procedureName"
    static String configName = "config_${procedureName}"

    @Shared
    TFSHelper tfsClient

    /// Procedure parameters
    // Mandatory
    @Shared
    def config = configName
    @Shared
    def project
    @Shared
    def type
    @Shared
    def title

    @Shared
    def resultPropertySheet
    @Shared
    def resultFormat = 'propertySheet'

    // Optional
    @Shared
    def priority
    @Shared
    def assignTo
    @Shared
    def description
    @Shared
    def additionalFields
    @Shared
    def workItemsJSON

    /// Specs parameters
    @Shared
    def caseId,
        expectedSummary,
        expectedOutcome

    static def assignees = [
        valid  : 'Administrator',
        empty  : '',
        invalid: 'Some invalid assignee'
    ]

    static def types = [
        valid         : 'Feature',
        withDollarSign: '$Feature', // Valid, too

        empty         : '',
        unexisting    : 'Unexisting',
        invalid       : '?H3I_I_#',
    ]

    def doSetupSpec() {
        createConfiguration(configName)
        dslFile "dsl/$procedureName/procedure.dsl", [projectName: projectName]

        tfsClient = getClient()
        assert tfsClient
    }

    def doCleanupSpec() {
        deleteConfiguration('EC-AzureDevOps', configName)
        conditionallyDeleteProject(projectName)
    }

    @Unroll
    def '#caseId. Sanity. Create Single'() {
        given:
        project = getADOSProjectName()
        title = randomize(procedureName + '_' + caseId)
        description = "Delete me"

        // Will be used later to get the result
        String resultJobProperty = 'newWorkItems'
        resultPropertySheet = '/myJob/' + resultJobProperty

        Map procedureParams = [
            config             : config,
            project            : project,
            type               : type,
            title              : title,
            priority           : priority,
            assignTo           : assignTo,
            description        : description,
            additionalFields   : additionalFields,
            workItemsJSON      : workItemsJSON,
            resultPropertySheet: resultPropertySheet,
            resultFormat       : resultFormat
        ]

        when:
        def result = runProcedure(projectName, procedureName, procedureParams)
        def jobProperties = getJobProperties(result.jobId)

        then:
        println getJobLink(result.jobId)
        assert result.outcome == 'success'

        def newItemsHash = jobProperties[resultJobProperty]

        // Will contain single ID
        String newItemId = newItemsHash['workItemIds']
        Map newItem = (Map) newItemsHash[newItemId]

        assert newItem['id']
        assert newItem['System.Title'] == title

        cleanup:
        if (newItemId) {
            tfsClient.deleteWorkItem(newItemId)
        }

        where:
        caseId       | type                 | assignTo
        'CHANGEME_1' | types.valid          | assignees.empty
        'CHANGEME_2' | types.withDollarSign | assignees.empty
    }

    @Unroll
    def '#caseId. Sanity. Create Multiple'() {
        given:
        project = getADOSProjectName()

        def itemObjects = []
        [1, 2, 3].each { n ->
            itemObjects.push(["Title": randomize(procedureName + '_' + caseId + 'workItem' + n)])
        }
        workItemsJSON = objectToJson(itemObjects)

        description = "Delete me" + randomize("Something to identify the set")

        // Will be used later to get the result
        String resultJobProperty = 'newWorkItems'
        resultPropertySheet = '/myJob/' + resultJobProperty

        Map procedureParams = [
            config             : config,
            project            : project,
            type               : type,
            title              : title,
            priority           : priority,
            assignTo           : assignTo,
            description        : description,
            additionalFields   : additionalFields,
            workItemsJSON      : workItemsJSON,
            resultPropertySheet: resultPropertySheet,
            resultFormat       : resultFormat
        ]

        when:
        def result = runProcedure(projectName, procedureName, procedureParams)
        def jobProperties = getJobProperties(result.jobId)

        then:
        println getJobLink(result.jobId)
        assert result.outcome == 'success'

        def newItemsHash = jobProperties[resultJobProperty]

        // Will contain comma-separated IDs
        String newItemIds = newItemsHash['workItemIds']

        newItemIds.split(/,\s/).each { it ->
            def newItem = newItemsHash[it]
            assert newItem['System.Description'] == description
        }

        cleanup:
        if (newItemIds) {
            newItemIds.split(/,\s/).each { id ->
                tfsClient.deleteWorkItem(id)
            }
        }

        where:
        caseId       | type                 | assignTo
        'CHANGEME_3' | types.valid          | assignees.empty
        'CHANGEME_4' | types.withDollarSign | assignees.empty
    }

}
