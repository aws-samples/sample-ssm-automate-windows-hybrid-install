# Automate Registering Windows Managed Nodes in AWS Systems Manager

This code is used in the AWS Cloud Operations Blog post "Automate Registering Windows Managed Nodes in AWS Systems Manager"

## Overview

To automate installing Windows managed nodes in Systems Manager, you will deploy a group policy that creates an immediate scheduled task to run a PowerShell script, and link the policy in appropriate organizational units within your Active Directory structure. When you create a hybrid activation using the AWS CLI or AWS Console, you receive an activation code and ID. This activation code and ID have a registration limit and expiration date that you can set. The registration limit specifies the maximum number of managed nodes you want to register. The expiration date for the activation request can be set up to 30 days forward, necessitating creation of a new hybrid activation at least every 30 days.
There are two instance tiers for Systems manager, and both support managed nodes. The standard-instances tier allows you to register a maximum of 1,000 machines in a single account and Region. If you need to register more than 1,000 machines in a single account and region, want to patch applications released by Microsoft on virtual machines (VMs) on hybrid nodes, or want to use AWS Systems Manager Session Manager to connect to your managed nodes, [turn on advanced-instances tier](https://docs.aws.amazon.com/systems-manager/latest/userguide/fleet-manager-enable-advanced-instances-tier.html).
To automate this process, you will create a PowerShell script that runs on a domain joined utility server running in Amazon EC2 that:

1. Creates a new hybrid activation and store the activation code and ID.
2. Updates the variables PowerShell script with the activation code and ID environment variables.
3. Saves the updated script to the network share referenced in the group policy deployment.
In this example, you will deploy the within a single AWS account and link a single group policy in 3 steps. You can modify this approach to support multiple activations, group policies, and AWS accounts as needed.

## Prerequisites

- AWS Account with access to [AWS Systems Manager](https://aws.amazon.com/systems-manager/), [Amazon Elastic Compute Cloud (EC2)](https://aws.amazon.com/pm/ec2/), and [AWS Identity and Access Management (IAM).](https://aws.amazon.com/iam/)
- Access to create and link group policy in the Active Directory Domain.
- A network shared folder. This folder will store the activation script and dynamically generated activation code and ID which can be used to register hybrid nodes. Ensure this location only allows access from Active Directory computer accounts and privileged accounts.
- A service account in Active Directory for the Systems Manager automation with access to the shared network folder.
- A domain joined utility server running on EC2.

Download the [win-ssm-activate.ps1](win-ssm-activate.ps1) and [win-ssm-script-automation.ps1](win-ssm-script-automation.ps1) files and store them in a location on your utility server, such as c:\scripts. You will use them in the following steps.

You can use [group policy filtering](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/manage/group-policy/group-policy-processing#group-policy-filtering) or [Organizational Units (OUs)](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/plan/creating-an-organizational-unit-design) in Active Directory to ensure that you only include the target servers for Systems Manager agent installation.

## Create IAM Roles for Systems Manager use

Create two IAM roles used in this solution. The first role is used on the hybrid nodes deployed by group policy and the second is a role to use on your utility server running in EC2.

### To create the first role (Console)

1. Open the [Identity and Access Management console](https://console.aws.amazon.com/iam).
2. Choose your selected region.
3. Choose **Roles** under Access Management.
4. Choose **Create Role**.
5. For trusted entity type, choose **AWS service** and choose **EC2** for service or use case.
6. For add permissions, choose the **AmazonSSMManagedInstanceCore** and **CloudWatchAgentServerPolicy** managed policies.
7. For role name, choose **SSMHybridNodeRole**.

### To create the second role (Console)

1. Open the [Identity and Access Management console](https://console.aws.amazon.com/iam).
2. Choose **Roles** under Access Management.
3. Choose **Create Role.**
4. For trusted entity type, choose **AWS service** and choose **EC2** for service or use case.
5. For add permissions, choose the **AmazonSSMManagedInstanceCore** and **CloudWatchAgentServerPolicy** managed policies.
6. For role name, choose **SSMUtilityServerRole**.
7. Choose **SSMUtilityServerRole** and choose **Add permissions** and **Create inline policy**.
8. Choose JSON and replace the policy in the policy editor with the following, updating the “YOURAWSACCOUNTNUMBER” to your AWS account number.

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "CreateSSMActivations",
            "Effect": "Allow",
            "Action": "ssm:CreateActivation",
            "Resource": "*"
        },
        {
            "Sid": "PassRolePermission",
            "Effect": "Allow",
            "Action": "iam:PassRole",
            "Resource": "arn:aws:iam::YOURAWSACCOUNTNUMBER:role/SSMHybridNodeRole"
        }
    ]
}
```

If any of your instances require additional service permissions, add the appropriate permissions to the role in addition to what is outlined in this post.

## Create SSM Hybrid Activation Automation

Create the scheduled task to run the PowerShell script win-ssm-script-automation.ps1 every 15 days. This script creates a hybrid activation and updates the automation PowerShell script, win-ssm-variables.ps1, for use in the group policy deployment. This scheduled script will use the Amazon EC2 instance role permissions to interact with the AWS API, so ensure that the instance has the SSMUtilityServerRole IAM role attached.

### To add or update the IAM role (Console)

1. Open the [Amazon EC2 console](https://console.aws.amazon.com/ec2/).
2. Choose your selected region.
3. Choose **Instances** under instances.
4. Choose the utility server instance.
5. Choose **Actions, Security, Modify IAM role.**
6. Under IAM role, choose **EC2-UtilityAutomation.**
7. Choose **Update IAM role.**

Log in to the utility server running in EC2. Open the win-ssm-script-automation.ps1 script and update script variables:

1. \$SharedFolder – Set to a shared folder location that computer accounts can access.
2. \$LocalFolder – Set to the local folder where you unzipped the scripts.zip file.
3. \$Region – Set to the AWS region you want to create hybrid activations in.
4. \$Dir – Defaults to a temporary folder location but can be changed if needed.
5. \$RegistrationLimit – Set to a limit that accommodates the number of servers you provision on average per month.
6. \$HybridActivationRole – Set to the IAM Role created for hybrid node use, SSMHybridNodeRole.

### To create the scheduled task

1. Log in to the utility server and Open Task Scheduler.
2. Choose **Create Task.**
3. On the General tab, choose a name for the task and choose **Run whether user is logged in or not.** If you are signed in with an account that does not have access to the shared folder location, choose **Change User or Group** and select a service account that has access.
4. On the Triggers tab, choose **New**, then choose **Daily** and recur every 15 days. Choose a date & time for the initial execution.
5. On the Actions tab, choose **New**, then for Program/script, enter ```powershell.exe``` and for Add arguments, enter ```-ExecutionPolicy Bypass -File “c:\scripts\win-ssm-script-automation.ps1”```.
6. Choose OK and enter the service account password.

## Create the group policy deployment

Open the win-ssm-activate.ps1 script and set the \$Region variable to the AWS region that you want to register hybrid nodes in and the \$SharedFolder variable with the same location you used in win-ssm-script-automation.ps1. Copy this script to the location you are using for the $SharedFolder variable.

### To create the group policy deployment

1. Log in to a server that has access to Group Policy Management in the domain and open Group Policy Management in Windows Tools.
2. Select Group Policy Objects in your domain and choose **New** in the Action menu.
3. Choose a name for the GPO like Install Systems Manager Agent.
4. Select the GPO under Group Policy Objects and choose Edit in the Action menu.
5. Choose **Scheduled Tasks** in the Control Panel Settings path under Computer Configuration/Preferences.
6. Choose **New->Immediate Task (At least Windows 7)** in the Action menu.
7. On the General tab:
    1. Choose a name for the task like Install Systems Manager Agent.
    2. Choose **Change User or Group** and enter the name **SYSTEM**.
    3. Choose **Run whether user is logged in or not.**
8. On the Actions tab, choose New, then for Program/script, enter ```powershell.exe``` and for Add arguments, enter ```-ExecutionPolicy Bypass -File “\\ServerShareLocation\ServerFolderLocation\win-ssm-activate.ps1”``` adjusting the path to your shared folder location.
9. Choose **OK**
10. Select one or more Organizational Units in your domain and choose **Link an Existing GPO** in the Action menu, then select the GPO you created and press **OK**.

## Clean-up

To remove this solution, complete the following steps:

1. Delete the downloaded scripts.zip file downloaded in step 1.
2. If you no longer need the utility server, terminate the EC2 instance created in step 1. If you still need the server, delete the win-ssm-script-automation.ps1 file and remove the scheduled task from step 1.
3. Delete the win-ssm-activate.ps1 and win-ssm-variables.ps1 from the shared server folder location in step 1.
4. Remove the IAM roles **SSMHybridNodeRole** and **SSMUtilityServerRole** created in step 2.
5. Delete the group policy created in step 3.
6. Deregister any hybrid-activated nodes in the AWS Systems Manager console.

## Contributing

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the [LICENSE](LICENSE) file.
