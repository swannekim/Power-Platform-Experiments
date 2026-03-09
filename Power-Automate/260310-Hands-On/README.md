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
- Customize `Requestor Email` & `Approver Email` as your Microsoft tenant setting
![alt text](img/image-6.png)

## 01. Batch Approvals for Work Requests in Excel
### Create Cloud Flow: instant cloud flow, manual trigger
![alt text](img/image-4.png)

### Excel Online (Business): List rows present in a table
![alt text](img/image-8.png)
![alt text](img/image-9.png)
![alt text](img/image-10.png)
- Filter Query: `Status eq 'New'`
- Name Update: `List rows present in a table - Filter New`

### Control: Apply to Each
![alt text](img/image-11.png)
- Select an output from previous steps: `body/value`
    - for each filtered rows

### Excel Online (Business): Update a Row
![alt text](img/image-13.png)
- Submitted At: `utcNow()` (insert expression)
- Status: `Submitted`
- Last Updated At: `utcNow()` (insert expression)
- Name Update: `Update a row - Idempotency`

### Standard Approvals: Start and wait for an approval
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

### Excel Online (Business): Update a Row
![alt text](img/image-14.png)
![alt text](img/image-15.png)
- Status: `In Progress`
- Approval Outcome: `Outcome` (dynamic expression)
- Approval Comment: `Responses Comments` (dynamic expression)
- Approved/Rejected At: `utcNow()` (insert expression)
- Last Updated At: `utcNow()` (insert expression)
- Name Update: `Update a row - Approval Result`

### Control: Condition
![alt text](img/image-16.png)
- Name Update: `Condition - Approval`

### Office 365 Outlook: Send an Email (V2)
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

### Excel Online (Business): Update a Row
![alt text](img/image-23.png)
- Last Updated At: `utcNow()` (insert expression)
- Name Update: `Update a row - Completion`

### Test
![alt text](img/image-19.png)
![alt text](img/image-20.png)
![alt text](img/image-21.png)
![alt text](img/image-22.png)
![alt text](img/image-24.png)