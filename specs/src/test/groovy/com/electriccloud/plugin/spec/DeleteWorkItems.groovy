package com.electriccloud.plugin.spec

import com.electriccloud.plugin.spec.tfs.TFSHelper
import net.sf.json.JSON
import spock.lang.*

@Stepwise
class DeleteWorkItems extends PluginTestHelper {

    static String procedureName = "DeleteWorkItems"
    static String projectName = "Spec Tests $procedureName"
    static String configName = "config_${procedureName}"

    /// Procedure parameters
    // Mandatory
    @Shared
    def config = configName
    @Shared
    String workItemIds
    @Shared
    def resultFormat = 'none'

    // Optional
    @Shared
    def resultPropertySheet

    // Specs
    @Shared
    TFSHelper tfsClient

    @Shared
    def caseId

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
    def '#caseId. Sanity. Delete Single'() {
        given:

        JSON itemToDelete = tfsClient.createWorkItem('Feature', [
            description: 'DeleteMe',
            title      : randomize(procedureName + caseId)
        ])

        // Will be used later to get the result
        String resultJobProperty = 'deletedWorkItems'
        resultPropertySheet = '/myJob/' + resultJobProperty

        workItemIds = itemToDelete.id

        Map procedureParams = [
            config             : config,
            workItemIds        : workItemIds,
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
        if (resultFormat != 'json') {
            String deletedItemId = updatedItemsHash['workItemIds']
            assert deletedItemId == workItemIds
        }

        cleanup:
        if (result.outcome != 'success' && workItemIds) {
            workItemIds.split(/,\s?/).each { id ->
                // Item can be already deleted
                try {
                    println "\n -- Ignore 404 error. This means item is already deleted"
                    tfsClient.deleteWorkItem(id)
                }
                catch (AssertionError e) {
                    // Do nothing
                }
            }
        }
        where:
        caseId     | resultFormat
        'CHNGME_1' | 'none'
        'CHNGME_2' | 'json'
        'CHNGME_3' | 'propertySheet'
    }

    @Unroll
    def '#caseId. Sanity. Delete Multiple'() {
        given:
        def workItemIdsArr = []
        [1, 2, 3].each {
            JSON itemToDelete = tfsClient.createWorkItem('Feature', [
                description: 'deleteMe',
                title      : randomize(procedureName + caseId)
            ])
            workItemIdsArr.push(itemToDelete.id)
        }

        // Will be used later to get the result
        String resultJobProperty = 'deletedWorkItems'
        resultPropertySheet = '/myJob/' + resultJobProperty

        workItemIds = workItemIdsArr.join(', ')

        Map procedureParams = [
            config             : config,
            workItemIds        : workItemIds,
            resultPropertySheet: resultPropertySheet,
            resultFormat       : resultFormat
        ]

        when:
        def result = runProcedure(projectName, procedureName, procedureParams)
        def jobProperties = getJobProperties(result.jobId)

        then:
        println getJobLink(result.jobId)
        assert result.outcome == 'success'

        def deletedItemsHash = jobProperties[resultJobProperty]

        // Will contain multiple comma-separated IDs
        if (resultFormat != 'json') {
            String deletedItemId = deletedItemsHash['workItemIds']
            assert deletedItemId == workItemIds
        }

        cleanup:
        if (workItemIdsArr.size()) {
            workItemIdsArr.each { id ->
                // Item can be already deleted
                try {
                    println "\n -- Ignore 404 error. This means item is already deleted"
                    tfsClient.deleteWorkItem(id)
                }
                catch (AssertionError e) {
                    // Do nothing
                }
            }
        }

        where:
        caseId     | resultFormat
        'CHNGME_4' | 'none'
        'CHNGME_5' | 'json'
        'CHNGME_6' | 'propertySheet'
    }
}
