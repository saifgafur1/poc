@IsTest
private class POC_FollowUpTaskServiceTest {
    private static final Integer BULK_SIZE = 251;

    @IsTest
    static void shouldCreateTask_WhenOpportunityClosedWon() {
        // Given
        User owner = createStandardUser();
        Opportunity opportunity = createOpportunities(1, owner.Id)[0];

        // When
        Test.startTest();
        List<POC_FollowUpTaskService.Response> responses = POC_FollowUpTaskService.createFollowUpTasks(
            new List<POC_FollowUpTaskService.Request>{ buildRequest(opportunity.Id, owner.Id) }
        );
        Test.stopTest();

        // Then
        List<Task> tasks = queryFollowUpTasks(opportunity.Id);
        Assert.areEqual(1, tasks.size(), 'Exactly one follow-up Task should be created');
        Assert.areEqual('Onboarding follow-up', tasks[0].Subject, 'Subject should match');
        Assert.areEqual(owner.Id, tasks[0].OwnerId, 'Task should be owned by the Opportunity owner');
        Assert.areEqual(opportunity.Id, tasks[0].WhatId, 'Task should be related to the Opportunity');
        Assert.areEqual(Date.today().addDays(3), tasks[0].ActivityDate, 'Task should be due in 3 days');
        Assert.areEqual('Not Started', tasks[0].Status, 'Status should be Not Started');
        Assert.isTrue(responses[0].isSuccess, 'Response should report success');
        Assert.areEqual(tasks[0].Id, responses[0].taskId, 'Response should carry the Task Id');
        Assert.isFalse(responses[0].skipped, 'Response should not be marked skipped');
    }

    @IsTest
    static void shouldNotCreateSecondTask_WhenOpenFollowUpExists() {
        // Given
        Opportunity opportunity = createOpportunities(1, UserInfo.getUserId())[0];
        POC_FollowUpTaskService.createFollowUpTasks(
            new List<POC_FollowUpTaskService.Request>{ buildRequest(opportunity.Id, UserInfo.getUserId()) }
        );

        // When
        Test.startTest();
        List<POC_FollowUpTaskService.Response> responses = POC_FollowUpTaskService.createFollowUpTasks(
            new List<POC_FollowUpTaskService.Request>{ buildRequest(opportunity.Id, UserInfo.getUserId()) }
        );
        Test.stopTest();

        // Then
        Assert.areEqual(1, queryFollowUpTasks(opportunity.Id).size(), 'No second Task should be created');
        Assert.isTrue(responses[0].isSuccess, 'Skipping should still report success');
        Assert.isTrue(responses[0].skipped, 'Response should be marked skipped');
        Assert.isNull(responses[0].taskId, 'No Task Id should be returned when skipped');
    }

    @IsTest
    static void shouldCreateNewTask_WhenPriorFollowUpCompleted() {
        // Given
        Opportunity opportunity = createOpportunities(1, UserInfo.getUserId())[0];
        POC_FollowUpTaskService.createFollowUpTasks(
            new List<POC_FollowUpTaskService.Request>{ buildRequest(opportunity.Id, UserInfo.getUserId()) }
        );
        Task completedTask = queryFollowUpTasks(opportunity.Id)[0];
        completedTask.Status = 'Completed';
        update completedTask;

        // When
        Test.startTest();
        POC_FollowUpTaskService.createFollowUpTasks(
            new List<POC_FollowUpTaskService.Request>{ buildRequest(opportunity.Id, UserInfo.getUserId()) }
        );
        Test.stopTest();

        // Then
        Assert.areEqual(2, queryFollowUpTasks(opportunity.Id).size(), 'A completed Task should not block a new one');
    }

    @IsTest
    static void shouldCreateOneTask_WhenSameOpportunityRequestedTwice() {
        // Given
        Opportunity opportunity = createOpportunities(1, UserInfo.getUserId())[0];
        List<POC_FollowUpTaskService.Request> requests = new List<POC_FollowUpTaskService.Request>{
            buildRequest(opportunity.Id, UserInfo.getUserId()),
            buildRequest(opportunity.Id, UserInfo.getUserId())
        };

        // When
        Test.startTest();
        List<POC_FollowUpTaskService.Response> responses = POC_FollowUpTaskService.createFollowUpTasks(requests);
        Test.stopTest();

        // Then
        Assert.areEqual(1, queryFollowUpTasks(opportunity.Id).size(), 'Duplicate requests should create one Task');
        Assert.areEqual(2, responses.size(), 'One response per request');
        Assert.isFalse(responses[0].skipped, 'First request creates the Task');
        Assert.isTrue(responses[1].skipped, 'Second request is skipped');
    }

    @IsTest
    static void shouldCreateTaskForEachOpportunity_WhenBulk() {
        // Given
        List<Opportunity> opportunities = createOpportunities(BULK_SIZE, UserInfo.getUserId());
        List<POC_FollowUpTaskService.Request> requests = new List<POC_FollowUpTaskService.Request>();
        for (Opportunity opportunity : opportunities) {
            requests.add(buildRequest(opportunity.Id, UserInfo.getUserId()));
        }

        // When
        Test.startTest();
        List<POC_FollowUpTaskService.Response> responses = POC_FollowUpTaskService.createFollowUpTasks(requests);
        Test.stopTest();

        // Then
        Assert.areEqual(BULK_SIZE, responses.size(), 'One response per request');
        Assert.areEqual(
            BULK_SIZE,
            [SELECT COUNT() FROM Task WHERE WhatId IN :opportunities AND Subject = 'Onboarding follow-up'],
            'One Task per Opportunity'
        );
        for (POC_FollowUpTaskService.Response response : responses) {
            Assert.isTrue(response.isSuccess, 'Every response should report success');
        }
    }

    @IsTest
    static void shouldReturnFailure_WhenRequiredFieldsMissing() {
        // Given
        POC_FollowUpTaskService.Request missingOpportunity = new POC_FollowUpTaskService.Request();
        missingOpportunity.ownerId = UserInfo.getUserId();

        // When
        Test.startTest();
        List<POC_FollowUpTaskService.Response> responses = POC_FollowUpTaskService.createFollowUpTasks(
            new List<POC_FollowUpTaskService.Request>{ missingOpportunity, null }
        );
        Test.stopTest();

        // Then
        Assert.areEqual(2, responses.size(), 'One response per request, including null');
        for (POC_FollowUpTaskService.Response response : responses) {
            Assert.isFalse(response.isSuccess, 'Invalid request should fail');
            Assert.areEqual('InvalidRequest', response.errorType, 'Error type should identify an invalid request');
        }
    }

    @IsTest
    static void shouldReturnFailure_WhenTaskInsertFails() {
        // Given
        Opportunity opportunity = createOpportunities(1, UserInfo.getUserId())[0];
        Account notAUser = new Account(Name = 'Not a user');
        insert notAUser;

        // When
        Test.startTest();
        List<POC_FollowUpTaskService.Response> responses = POC_FollowUpTaskService.createFollowUpTasks(
            new List<POC_FollowUpTaskService.Request>{ buildRequest(opportunity.Id, notAUser.Id) }
        );
        Test.stopTest();

        // Then
        Assert.isFalse(responses[0].isSuccess, 'Insert failure should be reported');
        Assert.isNotNull(responses[0].errorMessage, 'Error message should be returned');
        Assert.isNotNull(responses[0].errorType, 'Error type should be returned');
        Assert.areEqual(0, queryFollowUpTasks(opportunity.Id).size(), 'No Task should be created');
    }

    @IsTest
    static void shouldReturnEmptyList_WhenRequestsEmptyOrNull() {
        // When
        Test.startTest();
        List<POC_FollowUpTaskService.Response> emptyResponses = POC_FollowUpTaskService.createFollowUpTasks(
            new List<POC_FollowUpTaskService.Request>()
        );
        List<POC_FollowUpTaskService.Response> nullResponses = POC_FollowUpTaskService.createFollowUpTasks(null);
        Test.stopTest();

        // Then
        Assert.isTrue(emptyResponses.isEmpty(), 'Empty input returns empty output');
        Assert.isTrue(nullResponses.isEmpty(), 'Null input returns empty output');
    }

    private static POC_FollowUpTaskService.Request buildRequest(Id opportunityId, Id ownerId) {
        POC_FollowUpTaskService.Request request = new POC_FollowUpTaskService.Request();
        request.opportunityId = opportunityId;
        request.ownerId = ownerId;
        return request;
    }

    private static List<Opportunity> createOpportunities(Integer count, Id ownerId) {
        List<Opportunity> opportunities = new List<Opportunity>();
        for (Integer i = 0; i < count; i++) {
            opportunities.add(
                new Opportunity(
                    Name = 'POC Follow-up ' + i,
                    StageName = 'Closed Won',
                    CloseDate = Date.today(),
                    OwnerId = ownerId
                )
            );
        }
        insert opportunities;
        return opportunities;
    }

    private static User createStandardUser() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uniqueKey = String.valueOf(Crypto.getRandomInteger()).replace('-', 'n');
        User user = new User(
            Alias = 'pocfu',
            Email = 'poc.followup.' + uniqueKey + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'FollowUp',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'poc.followup.' + uniqueKey + '@example.com.test'
        );
        insert user;
        return user;
    }

    private static List<Task> queryFollowUpTasks(Id opportunityId) {
        return [
            SELECT Id, Subject, OwnerId, WhatId, ActivityDate, Status
            FROM Task
            WHERE WhatId = :opportunityId AND Subject = 'Onboarding follow-up'
        ];
    }
}