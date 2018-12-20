package com.electriccloud.plugin.spec.tfs

import net.sf.json.JSON
import net.sf.json.JSONArray

class WorkItemFields {

    static def FIELDS_MAPPING = [
        title      : 'System.Title',
        description: 'System.Description',
        assignTo   : 'System.AssignedTo',
        priority   : 'Microsoft.VSTS.Common.Priority',
        commentBody: 'System.History'
    ]

    Map parametersMap

    WorkItemFields(Map fieldsMap) {
        this.parametersMap = fieldsMap
    }

    Map getAsEFParameters() {
        return this.parametersMap
    }

    Map getAsTFSFieldsMap() {
        return toTFSFieldsMap(this.parametersMap)
    }

    static Map toTFSFieldsMap(Map efParametersMap) {
        Map result = [:]

        efParametersMap.each { k, v ->
            String tfsFieldName = FIELDS_MAPPING[(String) k]
            assert tfsFieldName

            result[tfsFieldName] = v
        }

        return result
    }

    static Map toParametersMap(Map tfsFieldsMap) {
        Map result = [:]

        def reversedMapping = [:]
        FIELDS_MAPPING.each { k,v ->
            reversedMapping[v] = k
        }

        tfsFieldsMap.each { k, v ->
            String parameterName = reversedMapping[(String) k]
            // Can receive more that cat decode, so just skipping
//            assert parametersName
            if (parameterName){
                result[parameterName] = v
            }

        }

        return result
    }

    JSON getAsJSONPayload() {
        Map tfsFieldsMap = this.getAsTFSFieldsMap()

        ArrayList operationsList = []

        tfsFieldsMap.each { k, v ->
            operationsList.push([
                op   : 'add',
                path : '/fields/' + k,
                value: v
            ])
        }

        JSON jsonArray = new JSONArray()
        jsonArray.addAll(operationsList)

        return jsonArray
    }
}
