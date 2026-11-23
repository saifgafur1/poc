/**
 * Creates the "Onboarding follow-up" Task for Opportunities that reach Closed Won.
 * Called from the POC_Opportunity_Closed_Won_Follow_Up record-triggered Flow.
 */
public with sharing class POC_FollowUpTaskService {
    @TestVisible
    private static final String TASK_SUBJECT = 'Onboarding follow-up';
    @TestVisible
    private static final String TASK_STATUS_NOT_STARTED = 'Not Started';
    @TestVisible
    private static final Integer DUE_IN_DAYS = 3;

    /**
     * Flow input for one Opportunity.
     */
    public class Request {
        @InvocableVariable(label='Opportunity Id' description='Opportunity that reached Closed Won' required=true)
        public Id opportunityId;

        @InvocableVariable(label='Opportunity Owner Id' description='Becomes the Task owner' required=true)
        public Id ownerId;
    }

    /**
     * Flow output for one Opportunity, in the same order as the requests.
     */
    public class Response {
        @InvocableVariable(label='Opportunity Id')
        public Id opportunityId;

        @InvocableVariable(label='Is Success' description='True when a Task was created or an open one already existed')
        public Boolean isSuccess;

        @InvocableVariable(label='Task Id' description='Id of the Task created, blank when skipped or failed')
        public Id taskId;

        @InvocableVariable(label='Skipped' description='True when an open follow-up Task already existed')
        public Boolean skipped;

        @InvocableVariable(label='Error Message')
        public String errorMessage;

        @InvocableVariable(label='Error Type')
        public String errorType;
    }

    /**
     * Creates one follow-up Task per Opportunity, skipping Opportunities that already have an open one.
     *
     * @param requests One request per Opportunity
     * @return One response per request, in the same order
     * @example
     * List<POC_FollowUpTaskService.Response> results = POC_FollowUpTaskService.createFollowUpTasks(requests);
     */
    @InvocableMethod(
        label='Create Onboarding Follow-Up Tasks'
        description='Creates an Onboarding follow-up Task for each Opportunity unless an open one already exists'
        category='Opportunity'
    )
    public static List<Response> createFollowUpTasks(List<Request> requests) {
        List<Response> responses = new List<Response>();
        if (requests == null || requests.isEmpty()) {
            return responses;
        }

        Set<Id> opportunityIds = new Set<Id>();
        for (Request request : requests) {
            if (request?.opportunityId != null) {
                opportunityIds.add(request.opportunityId);
            }
        }
        Set<Id> opportunityIdsWithOpenTask = getOpportunityIdsWithOpenFollowUp(opportunityIds);

        Date dueDate = Date.today().addDays(DUE_IN_DAYS);
        List<Task> tasksToInsert = new List<Task>();
        List<Response> pendingResponses = new List<Response>();
        Set<Id> queuedOpportunityIds = new Set<Id>();

        for (Request request : requests) {
            Response response = new Response();
            responses.add(response);
            response.opportunityId = request?.opportunityId;
            response.skipped = false;

            if (request?.opportunityId == null || request.ownerId == null) {
                response.isSuccess = false;
                response.errorType = 'InvalidRequest';
                response.errorMessage = 'Opportunity Id and Owner Id are required.';
            } else if (opportunityIdsWithOpenTask.contains(request.opportunityId) || queuedOpportunityIds.contains(request.opportunityId)) {
                response.isSuccess = true;
                response.skipped = true;
            } else {
                queuedOpportunityIds.add(request.opportunityId);
                tasksToInsert.add(buildTask(request, dueDate));
                pendingResponses.add(response);
            }
        }

        if (!tasksToInsert.isEmpty()) {
            List<Database.SaveResult> saveResults = Database.insert(tasksToInsert, false, AccessLevel.USER_MODE);
            for (Integer i = 0; i < saveResults.size(); i++) {
                applySaveResult(pendingResponses[i], saveResults[i]);
            }
        }
        return responses;
    }

    private static Task buildTask(Request request, Date dueDate) {
        return new Task(
            Subject = TASK_SUBJECT,
            WhatId = request.opportunityId,
            OwnerId = request.ownerId,
            ActivityDate = dueDate,
            Status = TASK_STATUS_NOT_STARTED
        );
    }

    private static Set<Id> getOpportunityIdsWithOpenFollowUp(Set<Id> opportunityIds) {
        Set<Id> opportunityIdsWithOpenTask = new Set<Id>();
        if (opportunityIds.isEmpty()) {
            return opportunityIdsWithOpenTask;
        }
        for (Task existingTask : [
            SELECT WhatId
            FROM Task
            WHERE WhatId IN :opportunityIds AND Subject = :TASK_SUBJECT AND IsClosed = FALSE
            WITH USER_MODE
        ]) {
            opportunityIdsWithOpenTask.add(existingTask.WhatId);
        }
        return opportunityIdsWithOpenTask;
    }

    private static void applySaveResult(Response response, Database.SaveResult saveResult) {
        response.isSuccess = saveResult.isSuccess();
        if (saveResult.isSuccess()) {
            response.taskId = saveResult.getId();
            return;
        }
        Database.Error firstError = saveResult.getErrors()[0];
        response.errorType = String.valueOf(firstError.getStatusCode());
        response.errorMessage = firstError.getMessage();
    }
}