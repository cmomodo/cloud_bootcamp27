import * as cdk from "aws-cdk-lib";
import { Template } from "aws-cdk-lib/assertions";
import { AwsIamStackStack } from "../lib/aws-iam-stack-stack";

describe("AWS Security Stack", () => {
  let app: cdk.App;
  let stack: AwsIamStackStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new AwsIamStackStack(app, "TestStack");
    template = Template.fromStack(stack);
  });

  test("Password Policy Custom Resource Created", () => {
    template.resourceCountIs("Custom::AWS", 1);

    const customResources = template.findResources("Custom::AWS");
    const passwordPolicyResource = Object.values(customResources)[0];

    expect(passwordPolicyResource.Properties.Create).toContain(
      '"service":"IAM"'
    );
    expect(passwordPolicyResource.Properties.Create).toContain(
      '"action":"updateAccountPasswordPolicy"'
    );
    expect(passwordPolicyResource.Properties.Create).toContain(
      '"MinimumPasswordLength":12'
    );
  });

  test("MFA Required Policy Created", () => {
    template.hasResourceProperties("AWS::IAM::ManagedPolicy", {
      ManagedPolicyName: "RequireMFAForAllActions",
      Description: "Policy that requires MFA for all AWS actions",
    });
  });

  test("IAM Groups Created", () => {
    template.resourceCountIs("AWS::IAM::Group", 4);

    template.hasResourceProperties("AWS::IAM::Group", {
      GroupName: "Developers",
      Path: "/teams/",
    });

    template.hasResourceProperties("AWS::IAM::Group", {
      GroupName: "Operations",
      Path: "/teams/",
    });

    template.hasResourceProperties("AWS::IAM::Group", {
      GroupName: "Finance",
      Path: "/teams/",
    });

    template.hasResourceProperties("AWS::IAM::Group", {
      GroupName: "Analysts",
      Path: "/teams/",
    });
  });

  test("IAM Users Created", () => {
    // Should create 10 users total (3 devs + 2 ops + 2 finance + 3 analysts)
    template.resourceCountIs("AWS::IAM::User", 10);
  });

  test("IAM Policies Created", () => {
    template.resourceCountIs("AWS::IAM::ManagedPolicy", 5);

    template.hasResourceProperties("AWS::IAM::ManagedPolicy", {
      ManagedPolicyName: "DeveloperPermissions",
    });

    template.hasResourceProperties("AWS::IAM::ManagedPolicy", {
      ManagedPolicyName: "OperationsPermissions",
    });

    template.hasResourceProperties("AWS::IAM::ManagedPolicy", {
      ManagedPolicyName: "FinancePermissions",
    });

    template.hasResourceProperties("AWS::IAM::ManagedPolicy", {
      ManagedPolicyName: "AnalystPermissions",
    });
  });

  test("Stack has proper tags on users", () => {
    template.hasResourceProperties("AWS::IAM::User", {
      Tags: [
        { Key: "Environment", Value: "Production" },
        { Key: "Owner", Value: "StartupCorp-DevOps" },
        { Key: "Project", Value: "AWS-Security-Implementation" },
      ],
    });
  });
});
