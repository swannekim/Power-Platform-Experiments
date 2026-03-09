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

- Create SharePoint List > import from CSV: use [Sample CSV file](./resources/internal-survey-responses-test.csv)
- List Name: `test-survey-responses`
![alt text](img/image-26.png)
![alt text](img/image-27.png)
![alt text](img/image-28.png)
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

