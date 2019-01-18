package com.electriccloud.plugin.spec

import com.electriccloud.plugin.spec.tfs.TFSHelper
import net.sf.json.JSON
import spock.lang.*

class UpdateWorkItems extends PluginTestHelper {

    static String procedureName = "UpdateWorkItems"
    static String projectName = "Spec Tests $procedureName"
    static String configName = "config_${procedureName}"

    @Shared
    TFSHelper tfsClient

    /// Procedure parameters
    // Mandatory
    @Shared
    def config = configName

    @Shared
    String workItemIds

    @Shared
    def resultPropertySheet
    @Shared
    def resultFormat = 'propertySheet'

    // Optional
    @Shared
    def title,
        priority,
        assignTo,
        description,
        commentBody,
        additionalFields

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

    static def additionalFieldsJSON = [
        valid                 : '[{"op": "add", "path": "/fields/System.State", "value": "New" }]',
        withAttributes        : '[{"op": "add", "path": "/fields/System.State", "value": "New", "attributes": {"comment": "decomposition of work"} }]',
        withoutOperation      : '[{"path": "/fields/System.State", "value": "New" }]',
        empty                 : '',

        // Invalid
        linkWithoutaPermission: '[{"op": "add", "path": "/relations/-", "value": {"rel": "System.LinkTypes.Hierarchy-Reverse", "url": "https://fabrikam-fiber-inc.visualstudio.com/DefaultCollection/_apis/wit/workItems/297"} }]',
        withoutValue          : '[{"op": "add", "path": "/relations/-"}]',
        notJson               : 'just a simple text',
        withoutPath           : '[{"op": "add", "value": "Value that does not matters"}]'
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
    def '#caseId. Sanity. Update Single'() {
        given:
        String originalTitle = randomize('deleteme')
        String originalDescription = 'DELETE ME'

        JSON itemToUpdate = tfsClient.createWorkItem('Feature', [
            description: originalDescription,
            title      : originalTitle
        ])

        // Will be used later to get the result
        String resultJobProperty = 'updatedWorkItems'
        resultPropertySheet = '/myJob/' + resultJobProperty

        workItemIds = itemToUpdate.id

        Map procedureParams = [
            config             : config,
            workItemIds        : workItemIds,
            title              : title,
            priority           : priority,
            assignTo           : assignTo,
            description        : description,
            commentBody        : commentBody,
            additionalFields   : additionalFields,
            resultPropertySheet: resultPropertySheet,
            resultFormat       : resultFormat
        ]

        when:
        def result = runProcedure(projectName, procedureName, procedureParams)
        def jobProperties = getJobProperties(result.jobId)

        then:
        println getJobLink(result.jobId)
        assert result.outcome == 'success'

        def updatedItemsHash = jobProperties[resultJobProperty]

        // Will contain single ID
        String updatedItemId = updatedItemsHash['workItemIds']
        assert updatedItemId == workItemIds

        Map updatedItem = (Map) updatedItemsHash[updatedItemId]

        // Simply check we have something there
        assert updatedItem['id']

        if (title) {
            assert updatedItem['System.Title'] == title
        }
        if (description) {
            assert updatedItem['System.Description'] == description
        }
        if (commentBody) {
            // History contains last comment
            assert updatedItem['System.History'] == commentBody
        }

        cleanup:
        if (workItemIds) {
            workItemIds.split(/,\s?/).each { id ->
                tfsClient.deleteWorkItem(id)
            }
        }
        where:
        caseId     | title    | description | commentBody       | additionalFields
        // Update title
        'CHNGME_1' | rndStr() | ''          | ''                | ''
        'CHNGME_2' | ''       | rndStr()    | ''                | ''
        'CHNGME_3' | ''       | ''          | rndStr('COMMENT') | ''

        // Additional fields update result is not checked
        'CHNGME_4' | ''       | ''          | ''                | additionalFieldsJSON.valid
    }

    @Unroll
    def '#caseId. Sanity. Update Multiple'() {
        given:
        String originalTitle = randomize('deleteme')
        String originalDescription = 'DELETE ME'

        def workItemIdsArr = []
        [1, 2, 3].each {
            JSON itemToUpdate = tfsClient.createWorkItem('Feature', [
                description: originalDescription,
                title      : originalTitle
            ])
            workItemIdsArr.push(itemToUpdate.id)
        }

        // Will be used later to get the result
        String resultJobProperty = 'updatedWorkItems'
        resultPropertySheet = '/myJob/' + resultJobProperty

        workItemIds = workItemIdsArr.join(', ')

        Map procedureParams = [
            config             : config,
            workItemIds        : workItemIds,
            title              : title,
            priority           : priority,
            assignTo           : assignTo,
            description        : description,
            commentBody        : commentBody,
            additionalFields   : additionalFields,
            resultPropertySheet: resultPropertySheet,
            resultFormat       : resultFormat
        ]

        when:
        def result = runProcedure(projectName, procedureName, procedureParams)
        def jobProperties = getJobProperties(result.jobId)

        then:
        println getJobLink(result.jobId)
        assert result.outcome == 'success'

        def updatedItemsHash = jobProperties[resultJobProperty]

        // Will contain single ID
        String updatedResultIds = updatedItemsHash['workItemIds']
        assert updatedResultIds == workItemIds

        updatedResultIds.split(/,\s/).each { id ->
            Map updatedItem = (Map) updatedItemsHash[id]

            // Simply check we have something there
            assert updatedItem['id']

            if (title && title != originalTitle) {
                assert updatedItem['System.Title'] == title
            }
            if (description && description != originalDescription) {
                assert updatedItem['System.Description'] == description
            }
            if (commentBody) {
                // History contains last comment
                assert updatedItem['System.History'] == commentBody
            }

        }

        cleanup:
        if (workItemIdsArr.size()) {
            workItemIdsArr.each { id ->
                tfsClient.deleteWorkItem(id)
            }
        }
        where:
        caseId     | title    | description | commentBody       | additionalFields
        // Update title
        'CHNGME_5' | rndStr() | ''          | ''                | ''
        'CHNGME_6' | ''       | rndStr()    | ''                | ''
        'CHNGME_7' | ''       | ''          | rndStr('COMMENT') | ''

        // Additional fields update result is not checked
        'CHNGME_8' | ''       | ''          | ''                | additionalFieldsJSON.valid
    }

    @Unroll
    def '#caseId. Sanity. Warning on empty fields'(){
        given:
        // Don't need to create anything
        // Random
        workItemIds = '1234'
        resultFormat = 'none'
        resultPropertySheet = 'none'

        Map procedureParams = [
            config             : config,
            workItemIds        : workItemIds,
            title              : title,
            priority           : priority,
            assignTo           : assignTo,
            description        : description,
            commentBody        : commentBody,
            additionalFields   : additionalFields,
            resultPropertySheet: resultPropertySheet,
            resultFormat       : resultFormat
        ]

        when:
        def result = runProcedure(projectName, procedureName, procedureParams)

        then:
        assert result.outcome == 'warning'
    }


    // To make data table cleaner
    static String rndStr(String prefix = procedureName) {
        return randomize(prefix)
    }
}
