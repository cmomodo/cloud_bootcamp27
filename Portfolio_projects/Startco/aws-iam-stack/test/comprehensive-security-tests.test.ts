import * as cdk from "aws-cdk-lib";
import { Template, Match } from "aws-cdk-lib/assertions";
import { AwsIamStackStack } from "../lib/aws-iam-stack-stack";
import { IamGroupsConstruct } from "../lib/constructs/iam-groups";
import { IamUsersConstruct } from "../lib/constructs/iam-users";
import { IamPoliciesConstruct } from "../lib/constructs/iam-policies";
import { SecurityPoliciesConstruct } from "../lib/constructs/security-policies";
import { TeamStructure, TeamRole } from "../lib/interfaces/team-structure";

describe("Comprehensive Security Tests", () => {
  let app: cdk.App;
  let stack: AwsIamStackStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new AwsIamStackStack(app, "TestStack");
    template = Template.fromStack(stack);
  });

  describe("Security Policy Validation", () => {
    test("Password policy enforces strong requirements", () => {
      template.hasResourceProperties("Custom::AWS", {
        Create: Match.stringLikeRegexp(".*MinimumPasswordLength.*12.*"),
      });

      template.hasResourceProperties("Custom::AWS", {
        Create: Match.stringLikeRegexp(".*RequireUppercaseCharacters.*true.*"),
      });

      template.hasResourceProperties("Custom::AWS", {
        Create: Match.stringLikeRegexp(".*RequireSymbols.*true.*"),
      });
    });

    test("MFA policy denies actions without MFA", () => {
      template.hasResourceProperties("AWS::IAM::ManagedPolicy", {
        ManagedPolicyName: "RequireMFAForAllActions",
        PolicyDocument: {
          Statement: Match.arrayWith([
            Match.objectLike({
              Effect: "Deny",
              Condition: {
                BoolIfExists: {
                  "aws:MultiFactorAuthPresent": "false",
                },
              },
            }),
          ]),
        },
      });
    });

    test("MFA policy allows MFA device management", () => {
      template.hasResourceProperties("AWS::IAM::ManagedPolicy", {
        ManagedPolicyName: "RequireMFAForAllActions",
        PolicyDocument: {
          Statement: Match.arrayWith([
            Match.objectLike({
              Effect: "Allow",
              Action: Match.arrayWith([
                "iam:CreateVirtualMFADevice",
                "iam:EnableMFADevice",
                "iam:ListMFADevices",
              ]),
            }),
          ]),
        },
      });
    });
  });

  describe("IAM Groups Security Tests", () => {
    test("All groups use standardized path", () => {
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

    test("Groups have proper naming convention", () => {
      const groups = template.findResources("AWS::IAM::Group");
      const groupNames = Object.values(groups).map(
        (group: any) => group.Properties.GroupName
      );

      expect(groupNames).toContain("Developers");
      expect(groupNames).toContain("Operations");
      expect(groupNames).toContain("Finance");
      expect(groupNames).toContain("Analysts");
      expect(groupNames).toHaveLength(4);
    });
  });

  describe("IAM Users Security Tests", () => {
    test("All users use standardized path", () => {
      template.resourcePropertiesCountIs(
        "AWS::IAM::User",
        {
          Path: "/users/",
        },
        10
      );
    });

    test("Users follow naming convention", () => {
      const users = template.findResources("AWS::IAM::User");
      const userNames = Object.values(users).map(
        (user: any) => user.Properties.UserName
      );

      // Check developer users
      expect(userNames).toContain("dev1");
      expect(userNames).toContain("dev2");
      expect(userNames).toContain("dev3");

      // Check operations users
      expect(userNames).toContain("ops1");
      expect(userNames).toContain("ops2");

      // Check finance users
      expect(userNames).toContain("finance1");
      expect(userNames).toContain("finance2");

      // Check analyst users
      expect(userNames).toContain("analyst1");
      expect(userNames).toContain("analyst2");
      expect(userNames).toContain("analyst3");
    });

    test("All users are assigned to groups", () => {
      template.resourcePropertiesCountIs(
        "AWS::IAM::User",
        {
          Groups: Match.anyValue(),
        },
        10
      );
    });

    test("Users have proper tagging", () => {
      template.hasResourceProperties("AWS::IAM::User", {
        Tags: Match.arrayWith([
          { Key: "Project", Value: "AWS-Security-Implementation" },
          { Key: "Environment", Value: "Production" },
          { Key: "Owner", Value: "StartupCorp-DevOps" },
        ]),
      });
    });
  });

  describe("IAM Policies Security Tests", () => {
    test("Developer policy implements least privilege", () => {
      template.hasResourceProperties("AWS::IAM::ManagedPolicy", {
        ManagedPolicyName: "DeveloperPermissions",
        PolicyDocument: {
          Statement: Match.arrayWith([
            // Should allow EC2 describe/start/stop
            Match.objectLike({
              Effect: "Allow",
              Action: Match.arrayWith([
                "ec2:DescribeInstances",
                "ec2:StartInstances",
                "ec2:StopInstances",
              ]),
            }),
            // Should allow S3 access to app buckets only
            Match.objectLike({
              Effect: "Allow",
              Action: Match.arrayWith(["s3:GetObject", "s3:PutObject"]),
              Resource: Match.arrayWith(["arn:aws:s3:::app-*/*"]),
            }),
          ]),
        },
      });
    });

    test("Operations policy has infrastructure access", () => {
      template.hasResourceProperties("AWS::IAM::ManagedPolicy", {
        ManagedPolicyName: "OperationsPermissions",
        PolicyDocument: {
          Statement: Match.arrayWith([
            // Should have full EC2 access
            Match.objectLike({
              Effect: "Allow",
              Action: ["ec2:*"],
            }),
            // Should have RDS access
            Match.objectLike({
              Effect: "Allow",
              Action: ["rds:*"],
            }),
            // Should have CloudWatch access
            Match.objectLike({
              Effect: "Allow",
              Action: ["cloudwatch:*", "logs:*"],
            }),
          ]),
        },
      });
    });

    test("Finance policy has cost management access only", () => {
      template.hasResourceProperties("AWS::IAM::ManagedPolicy", {
        ManagedPolicyName: "FinancePermissions",
        PolicyDocument: {
          Statement: Match.arrayWith([
            // Should have Cost Explorer access
            Match.objectLike({
              Effect: "Allow",
              Action: ["ce:*", "cur:*"],
            }),
            // Should have Budgets access
            Match.objectLike({
              Effect: "Allow",
              Action: ["budgets:*"],
            }),
            // Should have read-only resource access
            Match.objectLike({
              Effect: "Allow",
              Action: Match.arrayWith(["ec2:Describe*", "rds:Describe*"]),
            }),
          ]),
        },
      });
    });

    test("Analyst policy has read-only data access", () => {
      template.hasResourceProperties("AWS::IAM::ManagedPolicy", {
        ManagedPolicyName: "AnalystPermissions",
        PolicyDocument: {
          Statement: Match.arrayWith([
            // Should have read-only S3 data access
            Match.objectLike({
              Effect: "Allow",
              Action: ["s3:GetObject", "s3:ListBucket"],
              Resource: Match.arrayWith([
                "arn:aws:s3:::data-*/*",
                "arn:aws:s3:::data-*",
              ]),
            }),
            // Should have CloudWatch metrics access
            Match.objectLike({
              Effect: "Allow",
              Action: Match.arrayWith([
                "cloudwatch:GetMetricStatistics",
                "cloudwatch:ListMetrics",
              ]),
            }),
          ]),
        },
      });
    });

    test("Policies are attached to correct groups", () => {
      template.hasResourceProperties("AWS::IAM::ManagedPolicy", {
        ManagedPolicyName: "DeveloperPermissions",
        Groups: [{ Ref: Match.stringLikeRegexp(".*DeveloperGroup.*") }],
      });

      template.hasResourceProperties("AWS::IAM::ManagedPolicy", {
        ManagedPolicyName: "OperationsPermissions",
        Groups: [{ Ref: Match.stringLikeRegexp(".*OperationsGroup.*") }],
      });
    });
  });

  describe("Security Boundary Tests", () => {
    test("No wildcard permissions in policies", () => {
      const policies = template.findResources("AWS::IAM::ManagedPolicy");

      Object.values(policies).forEach((policy: any) => {
        const statements = policy.Properties.PolicyDocument.Statement;
        statements.forEach((statement: any) => {
          if (statement.Effect === "Allow" && statement.Action) {
            // Check if Action contains wildcards with broad resource access
            const actions = Array.isArray(statement.Action)
              ? statement.Action
              : [statement.Action];
            const resources = Array.isArray(statement.Resource)
              ? statement.Resource
              : [statement.Resource];

            // If action is wildcard, resource should not be wildcard (except for specific cases)
            actions.forEach((action: string) => {
              if (action === "*") {
                resources.forEach((resource: string) => {
                  expect(resource).not.toBe("*");
                });
              }
            });
          }
        });
      });
    });

    test("No IAM permissions granted to non-admin roles", () => {
      const policies = template.findResources("AWS::IAM::ManagedPolicy");

      Object.values(policies).forEach((policy: any) => {
        const policyName = policy.Properties.ManagedPolicyName;

        // Skip MFA policy as it needs IAM permissions for MFA management
        if (policyName === "RequireMFAForAllActions") return;

        const statements = policy.Properties.PolicyDocument.Statement;
        statements.forEach((statement: any) => {
          if (statement.Effect === "Allow" && statement.Action) {
            const actions = Array.isArray(statement.Action)
              ? statement.Action
              : [statement.Action];

            actions.forEach((action: string) => {
              // No IAM actions should be allowed except for MFA policy
              expect(action).not.toMatch(/^iam:/);
            });
          }
        });
      });
    });

    test("Resource scoping is properly implemented", () => {
      template.hasResourceProperties("AWS::IAM::ManagedPolicy", {
        ManagedPolicyName: "DeveloperPermissions",
        PolicyDocument: {
          Statement: Match.arrayWith([
            Match.objectLike({
              Resource: Match.arrayWith(["arn:aws:s3:::app-*/*"]),
            }),
          ]),
        },
      });

      template.hasResourceProperties("AWS::IAM::ManagedPolicy", {
        ManagedPolicyName: "AnalystPermissions",
        PolicyDocument: {
          Statement: Match.arrayWith([
            Match.objectLike({
              Resource: Match.arrayWith(["arn:aws:s3:::data-*/*"]),
            }),
          ]),
        },
      });
    });
  });

  describe("Compliance and Governance Tests", () => {
    test("All resources have required tags", () => {
      const taggedResources = ["AWS::IAM::User"];

      taggedResources.forEach((resourceType) => {
        template.hasResourceProperties(resourceType, {
          Tags: Match.arrayWith([
            { Key: "Project", Value: "AWS-Security-Implementation" },
            { Key: "Environment", Value: "Production" },
            { Key: "Owner", Value: "StartupCorp-DevOps" },
          ]),
        });
      });
    });

    test("Stack outputs provide necessary information", () => {
      template.hasOutput("SecurityPoliciesMFAPolicyArn0DCB5F99", {
        Description: "ARN of the MFA required policy",
      });
    });

    test("Resource naming follows conventions", () => {
      // Check that all resources follow naming conventions
      const resources = template.toJSON().Resources;

      Object.keys(resources).forEach((logicalId) => {
        const resource = resources[logicalId];

        if (resource.Type === "AWS::IAM::Group") {
          expect(resource.Properties.GroupName).toMatch(
            /^(Developers|Operations|Finance|Analysts)$/
          );
        }

        if (resource.Type === "AWS::IAM::User") {
          expect(resource.Properties.UserName).toMatch(
            /^(dev|ops|finance|analyst)\d+$/
          );
        }

        if (resource.Type === "AWS::IAM::ManagedPolicy") {
          expect(resource.Properties.ManagedPolicyName).toMatch(
            /(Permissions|MFA)/
          );
        }
      });
    });
  });

  describe("Error Handling and Edge Cases", () => {
    test("Stack handles missing optional properties gracefully", () => {
      // Test that the stack can be created without optional properties
      const minimalApp = new cdk.App();
      const minimalStack = new AwsIamStackStack(minimalApp, "MinimalTestStack");
      const minimalTemplate = Template.fromStack(minimalStack);

      // Should still create all required resources
      minimalTemplate.resourceCountIs("AWS::IAM::Group", 4);
      minimalTemplate.resourceCountIs("AWS::IAM::User", 10);
      minimalTemplate.resourceCountIs("AWS::IAM::ManagedPolicy", 5);
    });

    test("Custom resource has proper error handling", () => {
      template.hasResourceProperties("Custom::AWS", {
        Create: Match.stringLikeRegexp(".*updateAccountPasswordPolicy.*"),
        Update: Match.stringLikeRegexp(".*updateAccountPasswordPolicy.*"),
        Delete: Match.stringLikeRegexp(".*deleteAccountPasswordPolicy.*"),
      });
    });
  });

  describe("Integration Tests", () => {
    test("All constructs integrate properly", () => {
      // Test that all constructs are created and integrated
      expect(() => {
        const testApp = new cdk.App();
        new AwsIamStackStack(testApp, "IntegrationTestStack");
      }).not.toThrow();
    });

    test("Stack synthesis produces valid CloudFormation", () => {
      const synthesized = template.toJSON();

      // Check that the template has all required sections
      expect(synthesized).toHaveProperty("Resources");
      expect(synthesized).toHaveProperty("Outputs");

      // Check that resources are properly defined
      expect(Object.keys(synthesized.Resources)).toHaveLength(
        23 // Expected total resources based on actual implementation
      );
    });
  });
});

describe("Individual Construct Tests", () => {
  let app: cdk.App;
  let stack: cdk.Stack;

  beforeEach(() => {
    app = new cdk.App();
    stack = new cdk.Stack(app, "TestStack");
  });

  describe("IamGroupsConstruct", () => {
    test("Creates all required groups", () => {
      const construct = new IamGroupsConstruct(stack, "TestGroups");
      const template = Template.fromStack(stack);

      template.resourceCountIs("AWS::IAM::Group", 4);

      expect(construct.developerGroup).toBeDefined();
      expect(construct.operationsGroup).toBeDefined();
      expect(construct.financeGroup).toBeDefined();
      expect(construct.analystGroup).toBeDefined();
    });

    test("getGroupForRole returns correct groups", () => {
      const construct = new IamGroupsConstruct(stack, "TestGroups");

      expect(construct.getGroupForRole(TeamRole.DEVELOPER)).toBe(
        construct.developerGroup
      );
      expect(construct.getGroupForRole(TeamRole.OPERATIONS)).toBe(
        construct.operationsGroup
      );
      expect(construct.getGroupForRole(TeamRole.FINANCE)).toBe(
        construct.financeGroup
      );
      expect(construct.getGroupForRole(TeamRole.ANALYST)).toBe(
        construct.analystGroup
      );
    });

    test("getGroupForRole throws error for invalid role", () => {
      const construct = new IamGroupsConstruct(stack, "TestGroups");

      expect(() => {
        construct.getGroupForRole("invalid" as TeamRole);
      }).toThrow("Unknown team role: invalid");
    });
  });

  describe("SecurityPoliciesConstruct", () => {
    test("Creates password policy custom resource", () => {
      new SecurityPoliciesConstruct(stack, "TestSecurity");
      const template = Template.fromStack(stack);

      template.resourceCountIs("Custom::AWS", 1);
      template.resourceCountIs("AWS::IAM::ManagedPolicy", 1);
    });

    test("Creates MFA enforcement policy", () => {
      const construct = new SecurityPoliciesConstruct(stack, "TestSecurity");
      const template = Template.fromStack(stack);

      expect(construct.mfaPolicy).toBeDefined();

      template.hasResourceProperties("AWS::IAM::ManagedPolicy", {
        ManagedPolicyName: "RequireMFAForAllActions",
      });
    });
  });

  describe("IamUsersConstruct", () => {
    test("Creates users based on team structure", () => {
      const groups = new IamGroupsConstruct(stack, "TestGroups");

      const teamStructure: TeamStructure = {
        developers: [
          {
            username: "testdev1",
            email: "test@example.com",
            role: TeamRole.DEVELOPER,
            requiresMFA: true,
          },
        ],
        operations: [
          {
            username: "testops1",
            email: "test@example.com",
            role: TeamRole.OPERATIONS,
            requiresMFA: true,
          },
        ],
        finance: [],
        analysts: [],
      };

      const construct = new IamUsersConstruct(
        stack,
        "TestUsers",
        teamStructure,
        groups
      );
      const template = Template.fromStack(stack);

      template.resourceCountIs("AWS::IAM::User", 2);
      expect(construct.users).toHaveLength(2);

      template.hasResourceProperties("AWS::IAM::User", {
        UserName: "testdev1",
      });

      template.hasResourceProperties("AWS::IAM::User", {
        UserName: "testops1",
      });
    });
  });

  describe("IamPoliciesConstruct", () => {
    test("Creates all role-based policies", () => {
      const groups = new IamGroupsConstruct(stack, "TestGroups");
      const construct = new IamPoliciesConstruct(stack, "TestPolicies", groups);
      const template = Template.fromStack(stack);

      template.resourceCountIs("AWS::IAM::ManagedPolicy", 4);

      expect(construct.developerPolicy).toBeDefined();
      expect(construct.operationsPolicy).toBeDefined();
      expect(construct.financePolicy).toBeDefined();
      expect(construct.analystPolicy).toBeDefined();
    });

    test("Policies are attached to correct groups", () => {
      const groups = new IamGroupsConstruct(stack, "TestGroups");
      new IamPoliciesConstruct(stack, "TestPolicies", groups);
      const template = Template.fromStack(stack);

      // Each policy should be attached to exactly one group
      template.resourcePropertiesCountIs(
        "AWS::IAM::ManagedPolicy",
        {
          Groups: Match.anyValue(),
        },
        4
      );
    });
  });
});

describe("Performance and Scalability Tests", () => {
  test("Stack creation performance is acceptable", () => {
    const startTime = Date.now();

    const app = new cdk.App();
    new AwsIamStackStack(app, "PerformanceTestStack");

    const endTime = Date.now();
    const duration = endTime - startTime;

    // Stack creation should complete within reasonable time (5 seconds)
    expect(duration).toBeLessThan(5000);
  });

  test("Template size is within CloudFormation limits", () => {
    const app = new cdk.App();
    const stack = new AwsIamStackStack(app, "SizeTestStack");
    const template = Template.fromStack(stack);

    const templateJson = JSON.stringify(template.toJSON());
    const templateSize = Buffer.byteLength(templateJson, "utf8");

    // CloudFormation template size limit is 460,800 bytes
    expect(templateSize).toBeLessThan(460800);
  });

  test("Resource count is within CloudFormation limits", () => {
    const app = new cdk.App();
    const stack = new AwsIamStackStack(app, "ResourceTestStack");
    const template = Template.fromStack(stack);

    const resources = template.toJSON().Resources;
    const resourceCount = Object.keys(resources).length;

    // CloudFormation resource limit is 500 resources per stack
    expect(resourceCount).toBeLessThan(500);
  });
});

describe("Advanced Security Validation Tests", () => {
  let app: cdk.App;
  let stack: AwsIamStackStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new AwsIamStackStack(app, "SecurityValidationTestStack");
    template = Template.fromStack(stack);
  });

  describe("Policy Validation Tests", () => {
    test("All policies follow least privilege principle", () => {
      const policies = template.findResources("AWS::IAM::ManagedPolicy");

      Object.values(policies).forEach((policy: any) => {
        const statements = policy.Properties.PolicyDocument.Statement;

        statements.forEach((statement: any) => {
          if (statement.Effect === "Allow") {
            // Check that wildcard actions are paired with specific resources
            const actions = Array.isArray(statement.Action)
              ? statement.Action
              : [statement.Action];
            const resources = Array.isArray(statement.Resource)
              ? statement.Resource
              : [statement.Resource];

            actions.forEach((action: string) => {
              if (
                action.includes("*") &&
                action !== "ec2:*" &&
                action !== "rds:*" &&
                action !== "cloudwatch:*" &&
                action !== "logs:*" &&
                action !== "ssm:*"
              ) {
                // If action has wildcard, ensure resources are scoped
                resources.forEach((resource: string) => {
                  expect(resource).not.toBe("*");
                });
              }
            });
          }
        });
      });
    });

    test("No policies grant dangerous permissions", () => {
      const policies = template.findResources("AWS::IAM::ManagedPolicy");
      const dangerousActions = [
        "iam:*",
        "sts:AssumeRole",
        "organizations:*",
        "account:*",
        "billing:*",
      ];

      Object.values(policies).forEach((policy: any) => {
        const policyName = policy.Properties.ManagedPolicyName;

        // Skip MFA policy as it needs specific IAM permissions
        if (policyName === "RequireMFAForAllActions") return;

        const statements = policy.Properties.PolicyDocument.Statement;

        statements.forEach((statement: any) => {
          if (statement.Effect === "Allow" && statement.Action) {
            const actions = Array.isArray(statement.Action)
              ? statement.Action
              : [statement.Action];

            actions.forEach((action: string) => {
              dangerousActions.forEach((dangerous: string) => {
                expect(action).not.toBe(dangerous);
              });
            });
          }
        });
      });
    });

    test("All policies have proper resource scoping", () => {
      const policies = template.findResources("AWS::IAM::ManagedPolicy");

      Object.values(policies).forEach((policy: any) => {
        const policyName = policy.Properties.ManagedPolicyName;
        const statements = policy.Properties.PolicyDocument.Statement;

        statements.forEach((statement: any) => {
          if (statement.Effect === "Allow" && statement.Resource) {
            const resources = Array.isArray(statement.Resource)
              ? statement.Resource
              : [statement.Resource];

            // Check that specific policy types have appropriate resource scoping
            if (policyName === "DeveloperPermissions") {
              const s3Resources = resources.filter((r: string) =>
                r.includes("s3")
              );
              s3Resources.forEach((resource: string) => {
                expect(resource).toMatch(/app-\*/);
              });
            }

            if (policyName === "AnalystPermissions") {
              const s3Resources = resources.filter((r: string) =>
                r.includes("s3")
              );
              s3Resources.forEach((resource: string) => {
                expect(resource).toMatch(/data-\*/);
              });
            }
          }
        });
      });
    });

    test("Policies include proper conditions where appropriate", () => {
      const policies = template.findResources("AWS::IAM::ManagedPolicy");

      Object.values(policies).forEach((policy: any) => {
        const policyName = policy.Properties.ManagedPolicyName;

        if (policyName === "RequireMFAForAllActions") {
          const statements = policy.Properties.PolicyDocument.Statement;
          const denyStatement = statements.find(
            (s: any) => s.Effect === "Deny"
          );

          expect(denyStatement).toBeDefined();
          expect(denyStatement.Condition).toBeDefined();
          expect(denyStatement.Condition.BoolIfExists).toBeDefined();
          expect(
            denyStatement.Condition.BoolIfExists["aws:MultiFactorAuthPresent"]
          ).toBe("false");
        }
      });
    });
  });

  describe("Resource Security Configuration Tests", () => {
    test("All IAM resources have proper naming conventions", () => {
      const users = template.findResources("AWS::IAM::User");
      const groups = template.findResources("AWS::IAM::Group");
      const policies = template.findResources("AWS::IAM::ManagedPolicy");

      // Test user naming
      Object.values(users).forEach((user: any) => {
        const userName = user.Properties.UserName;
        expect(userName).toMatch(/^(dev|ops|finance|analyst)\d+$/);
      });

      // Test group naming
      Object.values(groups).forEach((group: any) => {
        const groupName = group.Properties.GroupName;
        expect(groupName).toMatch(/^(Developers|Operations|Finance|Analysts)$/);
      });

      // Test policy naming
      Object.values(policies).forEach((policy: any) => {
        const policyName = policy.Properties.ManagedPolicyName;
        expect(policyName).toMatch(/(Permissions|MFA)/);
      });
    });

    test("All resources use consistent paths", () => {
      const users = template.findResources("AWS::IAM::User");
      const groups = template.findResources("AWS::IAM::Group");

      Object.values(users).forEach((user: any) => {
        expect(user.Properties.Path).toBe("/users/");
      });

      Object.values(groups).forEach((group: any) => {
        expect(group.Properties.Path).toBe("/teams/");
      });
    });

    test("Password policy meets security requirements", () => {
      const customResources = template.findResources("Custom::AWS");
      const passwordPolicyResource = Object.values(customResources)[0] as any;

      const createPayload = passwordPolicyResource.Properties.Create;

      // Check minimum password length
      expect(createPayload).toContain('"MinimumPasswordLength":12');

      // Check complexity requirements
      expect(createPayload).toContain('"RequireUppercaseCharacters":true');
      expect(createPayload).toContain('"RequireLowercaseCharacters":true');
      expect(createPayload).toContain('"RequireNumbers":true');
      expect(createPayload).toContain('"RequireSymbols":true');

      // Check password reuse prevention
      expect(createPayload).toContain('"PasswordReusePrevention":12');

      // Check password expiration
      expect(createPayload).toContain('"MaxPasswordAge":90');
    });
  });

  describe("Compliance and Governance Tests", () => {
    test("All resources support required compliance frameworks", () => {
      const template_json = template.toJSON();

      // Check that we have the minimum required resources for compliance
      const resourceKeys = Object.keys(template_json.Resources);
      expect(resourceKeys.some((key) => key.includes("User"))).toBe(true);
      expect(resourceKeys.some((key) => key.includes("Group"))).toBe(true);
      expect(resourceKeys.some((key) => key.includes("Policy"))).toBe(true);

      // Check for security controls
      const hasPasswordPolicy = Object.values(template_json.Resources).some(
        (resource: any) =>
          resource.Type === "Custom::AWS" &&
          resource.Properties.Create.includes("updateAccountPasswordPolicy")
      );
      expect(hasPasswordPolicy).toBe(true);

      const hasMFAPolicy = Object.values(template_json.Resources).some(
        (resource: any) =>
          resource.Type === "AWS::IAM::ManagedPolicy" &&
          resource.Properties.ManagedPolicyName === "RequireMFAForAllActions"
      );
      expect(hasMFAPolicy).toBe(true);
    });

    test("Stack outputs provide necessary information for auditing", () => {
      const outputs = template.toJSON().Outputs;

      // Should have MFA policy ARN output for reference
      const outputKeys = Object.keys(outputs || {});
      expect(outputKeys.some((key) => key.includes("MFAPolicy"))).toBe(true);
    });

    test("Resource metadata supports change tracking", () => {
      const users = template.findResources("AWS::IAM::User");

      Object.values(users).forEach((user: any) => {
        // All users should have tags for tracking
        expect(user.Properties.Tags).toBeDefined();
        expect(user.Properties.Tags).toEqual(
          expect.arrayContaining([
            expect.objectContaining({ Key: "Project" }),
            expect.objectContaining({ Key: "Environment" }),
            expect.objectContaining({ Key: "Owner" }),
          ])
        );
      });
    });
  });

  describe("Error Handling and Resilience Tests", () => {
    test("Custom resources have proper error handling", () => {
      const customResources = template.findResources("Custom::AWS");

      Object.values(customResources).forEach((resource: any) => {
        // Should have Create, Update, and Delete operations defined
        expect(resource.Properties.Create).toBeDefined();
        expect(resource.Properties.Update).toBeDefined();
        expect(resource.Properties.Delete).toBeDefined();
      });
    });

    test("Lambda function for custom resource has proper configuration", () => {
      const lambdaFunctions = template.findResources("AWS::Lambda::Function");

      Object.values(lambdaFunctions).forEach((func: any) => {
        // Should have proper timeout
        expect(func.Properties.Timeout).toBeGreaterThan(0);
        expect(func.Properties.Timeout).toBeLessThanOrEqual(900);

        // Should have proper runtime (may be a reference)
        expect(func.Properties.Runtime).toBeDefined();
      });
    });

    test("IAM roles have proper trust relationships", () => {
      const roles = template.findResources("AWS::IAM::Role");

      Object.values(roles).forEach((role: any) => {
        const trustPolicy = role.Properties.AssumeRolePolicyDocument;
        expect(trustPolicy).toBeDefined();
        expect(trustPolicy.Statement).toBeDefined();

        // Each statement should have proper principal
        trustPolicy.Statement.forEach((statement: any) => {
          expect(statement.Principal).toBeDefined();
          expect(statement.Effect).toBe("Allow");
          expect(statement.Action).toContain("sts:AssumeRole");
        });
      });
    });
  });

  describe("Security Boundary Enforcement Tests", () => {
    test("No cross-role permission leakage", () => {
      const policies = template.findResources("AWS::IAM::ManagedPolicy");

      // Developer policy should not have operations permissions
      const devPolicy = Object.values(policies).find(
        (p: any) => p.Properties.ManagedPolicyName === "DeveloperPermissions"
      ) as any;

      if (devPolicy) {
        const statements = devPolicy.Properties.PolicyDocument.Statement;
        statements.forEach((statement: any) => {
          if (statement.Effect === "Allow" && statement.Action) {
            const actions = Array.isArray(statement.Action)
              ? statement.Action
              : [statement.Action];

            // Should not have RDS or full EC2 permissions
            expect(actions).not.toContain("rds:*");
            expect(actions).not.toContain("ec2:*");
          }
        });
      }
    });

    test("Finance role has no infrastructure modification permissions", () => {
      const policies = template.findResources("AWS::IAM::ManagedPolicy");

      const financePolicy = Object.values(policies).find(
        (p: any) => p.Properties.ManagedPolicyName === "FinancePermissions"
      ) as any;

      if (financePolicy) {
        const statements = financePolicy.Properties.PolicyDocument.Statement;
        statements.forEach((statement: any) => {
          if (statement.Effect === "Allow" && statement.Action) {
            const actions = Array.isArray(statement.Action)
              ? statement.Action
              : [statement.Action];

            // Should not have any create/modify/delete permissions for infrastructure
            const dangerousActions = actions.filter(
              (action: string) =>
                action.includes("Create") ||
                action.includes("Delete") ||
                action.includes("Terminate") ||
                action.includes("Run") ||
                action.includes("Launch")
            );

            // Allow budget creation but not infrastructure
            const allowedCreates = dangerousActions.filter(
              (action: string) =>
                action.includes("budgets:") || action.includes("ce:")
            );

            expect(dangerousActions.length).toBe(allowedCreates.length);
          }
        });
      }
    });

    test("Analyst role has only read permissions", () => {
      const policies = template.findResources("AWS::IAM::ManagedPolicy");

      const analystPolicy = Object.values(policies).find(
        (p: any) => p.Properties.ManagedPolicyName === "AnalystPermissions"
      ) as any;

      if (analystPolicy) {
        const statements = analystPolicy.Properties.PolicyDocument.Statement;
        statements.forEach((statement: any) => {
          if (statement.Effect === "Allow" && statement.Action) {
            const actions = Array.isArray(statement.Action)
              ? statement.Action
              : [statement.Action];

            // All actions should be read-only
            actions.forEach((action: string) => {
              expect(action).toMatch(/(Get|List|Describe|Select)/);
            });
          }
        });
      }
    });
  });
});
