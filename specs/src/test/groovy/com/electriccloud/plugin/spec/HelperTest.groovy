package com.electriccloud.plugin.spec

import com.electriccloud.plugin.spec.tfs.TFSHelper
import com.electriccloud.plugin.spec.tfs.WorkItemFields
import net.sf.json.JSON

import spock.lang.*

@Stepwise
class HelperTest extends PluginTestHelper {

    @Shared
    TFSHelper tfs

    @Shared
    int workItemId

    def doSetupSpec() {
        def apiVersion = getADOSApiVersion()
        tfs = getTFSHelper(apiVersion)
    }

    def "CreateWorkItem"(){
        given:
        Map params = [
            title: "Spec Test Work Item",
            description: "Test description"
        ]

        when:
        JSON workItem = tfs.createWorkItem('Task', params)

        // Saving id
        workItemId = workItem.id

        then:
        assert workItem.id

        assert workItem.fields

        Map resultMap = WorkItemFields.toParametersMap(workItem.fields)

        // Will get the 'params' existing keys from resultMap and then assert that values are equal
        assert resultMap.intersect(params) == params
    }

    def "GetWorkItem"(){
        when:
        JSON workItem = tfs.getWorkItemById(workItemId)

        then:
        assert workItem.id == workItemId
    }

    def "DeleteWorkItem"(){
        when:
        JSON workItem = tfs.deleteWorkItem(workItemId)

        then:
        assert workItem.id == workItemId
    }


}

