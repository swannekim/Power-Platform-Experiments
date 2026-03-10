# Hands-On Resources

## Pre-requisites

### Power Platform Environment
- [Power Platform Admin Center (PPAC)](https://admin.powerplatform.microsoft.com/home)
![alt text](img/image.png)
![alt text](img/image-1.png)
![alt text](img/image-2.png)
- Trial Env, Korea Region used for this Hands-on session
    - The default (Contoso) environment is shared, unrestricted, and hard to govern—so it should never be used for production or sensitive Power Platform solutions.
    - [Official Guidance on Power Platform Environment](https://learn.microsoft.com/en-us/power-platform/guidance/adoption/manage-default-environment)

### Power Automate
- [Power Automate Web](https://make.powerautomate.com/): navigate to your environment
![alt text](img/image-3.png)

### Setup
- Create SharePoint Team Site > Create Document Library (`test-library` used for this hands-on)
![alt text](img/image-7.png)
![alt text](img/image-5.png)

- Upload [Sample Excel file](./resources/Work_Approval_Sample.xlsx) on your SharePoint Document Library
![alt text](img/image-6.png)
    - Customize `Requestor Email` & `Approver Email` as your Microsoft tenant setting

- Create Team
![alt text](img/image-25.png)
    - Team name: `Test Department`
    - First channel name: `Test Channel`

- Create SharePoint List > import from CSV: use [Sample CSV file](./resources/test-survey-responses.csv)
- List Name: `test-survey-responses`
![alt text](img/image-26.png)
![alt text](img/image-27.png)
![alt text](img/image-28.png)
![alt text](img/image-29.png)
    - Customize column types as below:
    - Title: `Title`
    - ResponseID: `Single line of text`
    - SubmittedAt: `Date and time`
    - EmployeeDept: `Single line of text`
    - FeedbackType: `Single line of text`
    - FeedbackText: `Multiple lines of text`
    - SatisfactionScore: `Single line of text`
    - IsReported: `Yes/No`

## 01. Batch Approvals for Work Requests in Excel
### 1.1. Create Cloud Flow: instant cloud flow, manual trigger
![alt text](img/image-4.png)

### 1.2. Excel Online (Business): List rows present in a table
![alt text](img/image-8.png)
![alt text](img/image-9.png)
![alt text](img/image-10.png)
- Filter Query: `Status eq 'New'`
- Name Update: `List rows present in a table - Filter New`

### 1.3. Control: Apply to Each
![alt text](img/image-11.png)
- Select an output from previous steps: `body/value`
    - for each filtered rows

### 1.4. Excel Online (Business): Update a Row
![alt text](img/image-13.png)
- Submitted At: `utcNow()` (insert expression)
- Status: `Submitted`
- Last Updated At: `utcNow()` (insert expression)
- Name Update: `Update a row - Idempotency`

### 1.5. Standard Approvals: Start and wait for an approval
![alt text](img/image-12.png)
- Details:
```
# ✅ New Work Request Approval

## Summary
- **Request ID:** @{outputs('Update_a_row_-_Idempotency')?['body/Request ID']}
- **Type:** @{outputs('Update_a_row_-_Idempotency')?['body/Request Type']}
- **Priority:** @{outputs('Update_a_row_-_Idempotency')?['body/Priority']}
- **Due Date:** @{outputs('Update_a_row_-_Idempotency')?['body/Requested Due Date']}
## Request Details
@{outputs('Update_a_row_-_Idempotency')?['body/Description']}

## Request from
- **Name:** @{outputs('Update_a_row_-_Idempotency')?['body/Requester Name']}
- **Email:** @{outputs('Update_a_row_-_Idempotency')?['body/Requester Email']}
```

### 1.6. Excel Online (Business): Update a Row
![alt text](img/image-14.png)
![alt text](img/image-15.png)
- Status: `In Progress`
- Approval Outcome: `Outcome` (dynamic expression)
- Approval Comment: `Responses Comments` (dynamic expression)
- Approved/Rejected At: `utcNow()` (insert expression)
- Last Updated At: `utcNow()` (insert expression)
- Name Update: `Update a row - Approval Result`

### 1.7. Control: Condition
![alt text](img/image-16.png)
- Name Update: `Condition - Approval`

### 1.8. Office 365 Outlook: Send an Email (V2)
![alt text](img/image-17.png)
- To: `@{outputs('Update_a_row_-_Idempotency')?['body/Requester Email']}`
- Subject: `[@{outputs('Update_a_row_-_Idempotency')?['body/Request ID']}] Approval Notification`
- Body:
    ```
    Your Request for @{outputs('Update_a_row_-_Idempotency')?['body/Request Type']} is Approved!

    Approver: @{outputs('Update_a_row_-_Idempotency')?['body/Approver Email']}
    ```
- Name Update: `Send an email (V2) - Approved`

![alt text](img/image-18.png)
- To: `@{outputs('Update_a_row_-_Idempotency')?['body/Requester Email']}`
- Subject: `[@{outputs('Update_a_row_-_Idempotency')?['body/Request ID']}] Rejection Notification`
- Body:
    ```
    Your Request for @{outputs('Update_a_row_-_Idempotency')?['body/Request Type']} is Rejected.
    Please check the comments below:
    @{items('For_each_1')?['comments']}

    Approver: @{outputs('Update_a_row_-_Idempotency')?['body/Approver Email']}
    ```
- Name Update: `Send an email (V2) - Rejected`

### 1.9. Excel Online (Business): Update a Row
![alt text](img/image-23.png)
- Last Updated At: `utcNow()` (insert expression)
- Name Update: `Update a row - Completion`

### Test
![alt text](img/image-19.png)
![alt text](img/image-20.png)
![alt text](img/image-21.png)
![alt text](img/image-22.png)
![alt text](img/image-24.png)

## 02. Automated Reporting of Structured Data from Survey

### 2A.1. Create Cloud Flow: instant cloud flow, manual trigger
![alt text](img/image-2030.png)

### 2A.2. Teams: Post adaptive card and wait for a response
![alt text](img/image-2031.png)
- Post as: `Flow bot`
- Post in: `Channel`
- Message:
    ```
    {
    "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
    "type": "AdaptiveCard",
    "version": "1.5",
    "body": [
        {
        "type": "Input.Text",
        "id": "surveyName",
        "value": "Internal Feedback Survey",
        "isVisible": false
        },
        {
        "type": "TextBlock",
        "text": "📝 Feedback Survey",
        "weight": "Bolder",
        "size": "Medium"
        },
        {
        "type": "TextBlock",
        "text": "All questions are required. (Takes less than 1 minute)",
        "wrap": true,
        "spacing": "Small"
        },
        {
        "type": "Input.ChoiceSet",
        "id": "Department",
        "label": "1. Department *",
        "isRequired": true,
        "errorMessage": "Please select your Department.",
        "style": "expanded",
        "choices": [
            { "title": "Engineering", "value": "Engineering" },
            { "title": "Sales", "value": "Sales" },
            { "title": "Marketing", "value": "Marketing" },
            { "title": "Finance", "value": "Finance" },
            { "title": "HR", "value": "HR" },
            { "title": "Management", "value": "Management" },
            { "title": "Other", "value": "Other" }
        ]
        },
        {
        "type": "Input.ChoiceSet",
        "id": "FeedbackType",
        "label": "2. Feedback Type *",
        "isRequired": true,
        "errorMessage": "Please select a Feedback Type.",
        "style": "expanded",
        "choices": [
            { "title": "Process", "value": "Process" },
            { "title": "Tool", "value": "Tool" },
            { "title": "Culture", "value": "Culture" },
            { "title": "Other", "value": "Other" }
        ]
        },
        {
        "type": "Input.ChoiceSet",
        "id": "Satisfaction",
        "label": "3. Satisfaction (1–5) *",
        "isRequired": true,
        "errorMessage": "Please select a Satisfaction rating.",
        "style": "expanded",
        "choices": [
            { "title": "1", "value": "1" },
            { "title": "2", "value": "2" },
            { "title": "3", "value": "3" },
            { "title": "4", "value": "4" },
            { "title": "5", "value": "5" }
        ]
        },
        {
        "type": "Input.Text",
        "id": "Feedback",
        "label": "4. Feedback *",
        "isRequired": true,
        "errorMessage": "Please enter your Feedback.",
        "isMultiline": true,
        "placeholder": "Enter your answer"
        }
    ],
    "actions": [
        {
        "type": "Action.Submit",
        "title": "Submit",
        "associatedInputs": "auto"
        }
    ]
    }
    ```
- Team: `Test Department`
- Channel: `Test Channel`

### 2A.3. SharePoint: Create item
![alt text](img/image-2032.png)
- Title: `@{outputs('Post_adaptive_card_and_wait_for_a_response')?['body/data/surveyName']}`
- ResponseID: `@{outputs('Post_adaptive_card_and_wait_for_a_response')?['body/messageId']}`
- SubmittedAt: `@{outputs('Post_adaptive_card_and_wait_for_a_response')?['body/responseTime']}`
- EmployeeDept: `@{outputs('Post_adaptive_card_and_wait_for_a_response')?['body/data/department']}`
- FeedbackType: `@{outputs('Post_adaptive_card_and_wait_for_a_response')?['body/data/feedbackType']}`
- FeedbackText: `@{outputs('Post_adaptive_card_and_wait_for_a_response')?['body/data/feedback']}`
- SatisfactionScore: `@{outputs('Post_adaptive_card_and_wait_for_a_response')?['body/data/satisfaction']}`
- IsReported: `No`

### 2B.1. Create Cloud Flow: scheduled cloud flow, reccurence trigger
![alt text](img/image-200.png)
![alt text](img/image-201.png)

### 2B.2. SharePoint: Get items
![alt text](img/image-202.png)
- Filter Query: `field_7 eq false`
    - alternative: `IsReported eq 0`
- Name Update: `Get items - Filter Not Reported`

### 2B.3. Variable: Initialize variable
![alt text](img/image-203.png)
- Name: `ResponseArr`
- Type: `Array`
    - for appending numerical values
- Name Update: `Initialize variable - ResponseArr`

![alt text](img/image-204.png)
- Name: `FeedbackArr`
- Type: `Array`
    - for appending string (text) values
- Name Update: `Initialize variable - FeedbackArr`

### 2B.4. Control: Apply to each
![alt text](img/image-205.png)
- for each not reported items on SharePoint List

### 2B.5. Variable: Append to array variable\
![alt text](img/image-206.png)
- Name: `ResponseArr`
- Value: 
    ```
    json(concat('{"Dept":"', items('Apply_to_each')?['field_3'], '","Type":"', items('Apply_to_each')?['field_4'], '","Score":"', items('Apply_to_each')?['field_6'], '"}'))
    ```
    - alternative:
        ```
        json(concat('{"Dept":"', item()?['EmployeeDept/Value'], '","Type":"', item()?['FeedbackType/Value'], '","Score":"', item()?['SatisfactionScore'], '"}'))
        ```
- Name Update: `Append to array variable - ResponseArr`

![alt text](img/image-207.png)
- Name: `FeedbackArr`
- Value: `@{items('Apply_to_each')?['field_5']}`
    - alternative: `@{items('Apply_to_each')?['FeedbackText']}`
`
- Name Update: `Append to array variable - FeedbackArr`

### 2B.6. Data Operation: Compose
![alt text](img/image-208.png)
- Inputs: `@{variables('FeedbackArr')}`
- Name Update: `Compose - Feedback`

### 2B.7. AI Builder: Run a prompt
![alt text](img/image-209.png)
- Name Update: `Run a prompt - Feedback Summary`

![alt text](img/image-2010.png)
- New Custom Prompt: `Survey Result JSON`
- Instructions:
    ```
    You are tasked with analyzing an array of user feedback texts. Follow these instructions carefully:

    ### Instructions:
    1. **Input Processing:** Receive an array containing multiple feedback texts.
    2. **Summarization:** Generate a concise summary that captures the overall sentiment and main points from all the feedback combined.
    3. **Keyword Extraction:** Identify and list up to 10 key keywords or phrases that best represent the core themes or topics found in the feedback.
    4. **Insight Generation:** If possible, provide meaningful insights or observations derived from the summary and keywords. These insights should help understand user opinions, trends, or areas for improvement.

    ### Output Format:
    - **Summary:** A clear and brief paragraph summarizing the collective feedback.
    - **Keywords:** A one long string consisting of up to 10 keywords or key phrases.
    - **Insights:** One or more sentences offering actionable or thoughtful insights based on the summary.

    ### Input
    Array of feedback texts: /Feedback Array
    ```
- Input sample:
    ```
    [The new internal tool is generally helpful, but the performance is inconsistent during peak hours. Documentation could also be improved., Approval processes take too long and often block campaign launches. Automation here would save a lot of time., The ticketing system works well for simple cases, but complex issues are hard to track across teams.]
    ```

![alt text](img/image-2011.png)
- Test > Save

![alt text](img/image-2012.png)
- Feedback Array*: `@{outputs('Compose_-_Feedback')}`

### 2B.8. Data Operation: Create CSV table
![alt text](img/image-2013.png)
- From: `@{variables('ResponseArr')}`
- Name Update: `Create CSV table - Response`

### 2B.9. AI Builder: Run a prompt
- Name Update: `Run a prompt - Survey Statistics`

![alt text](img/image-2014.png)
- New Custom Prompt: `Survey Result Statistics`
- Instructions:
    ```
    You are tasked with analyzing an internal employee survey dataset provided as a CSV file. The CSV contains three columns: Dept (department of the respondent), Type (category of feedback), and Score (satisfaction rating from 1 to 5 stars).

    ### Instructions:
    1. Load and parse the CSV file to extract the data.
    2. Aggregate and summarize the data to reveal meaningful insights, such as average scores by department and feedback type.

    ### Guidelines:
    - STRICT RULE: provide analysis results in HTML text format. (highest level h3)
    - Focus only on the data provided in the CSV format text.
    - Choose visualization types that best communicate the survey insights.
    - Keep the output concise and easy to interpret.

    Provide the CSV file containing the survey data here: Survey CSV
    ```
- Input sample:
    ```
    Dept,Type,Score,
    Engineering,Tool,4,
    Marketing,Culture,5,
    Sales,Tool,3
    ```
- Test > Save

![alt text](img/image-2015.png)
- Survey CSV: `@{body('Create_CSV_table_-_Response')}`

### 2B.10. Office 365 Outlook: Send an Email (V2)
![alt text](img/image-2016.png)
- To: `YOUR EMAIL`
- Subject: `Weekly Internal Survey Summary`
- Body:
    ```html
    <h2 class="editor-heading-h2">📊 Weekly Survey Summary<br></h2><h4 class="editor-heading-h4">Summary</h4><p class="editor-paragraph">@{outputs('Run_a_prompt_-_Feedback_Summary')?['body/responsev2/predictionOutput/structuredOutput/Summary']}</p><br><p class="editor-paragraph">Keywords: @{outputs('Run_a_prompt_-_Feedback_Summary')?['body/responsev2/predictionOutput/structuredOutput/Keywords']}</p><br><h4 class="editor-heading-h4">Insight</h4><p class="editor-paragraph">@{outputs('Run_a_prompt_-_Feedback_Summary')?['body/responsev2/predictionOutput/structuredOutput/Insights']}<br><br>---</p><h4 class="editor-heading-h4">Statistics</h4><p class="editor-paragraph">@{outputs('Run_a_prompt_-_Survey_Statistics')?['body/responsev2/predictionOutput/text']}</p><p class="editor-paragraph"><br>---<br>Automated by Power Automate</p>
    ```

### 2B.11. SharePoint: Update item
![alt text](img/image-2017.png)
- Name Update: `Update item - IsReported`

### Test
![alt text](img/image-2018.png)
![alt text](img/image-2019.png)
![alt text](img/image-2020.png)