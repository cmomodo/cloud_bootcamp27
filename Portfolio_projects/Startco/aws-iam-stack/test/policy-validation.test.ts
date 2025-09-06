import * as cdk from "aws-cdk-lib";
import { Template, Match } from "aws-cdk-lib/assertions";
import { AwsIamStackStack } from "../lib/aws-iam-stack-stack";

describe("IAM Policy Validation Tests", () => {
  let app: cdk.App;
  let stack: AwsIamStackStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new AwsIamStackStack(app, "PolicyValidationTestStack");
    template = Template.fromStack(stack);
  });

  describe("Policy Structure Validation", () => {
    test("All policies have valid JSON structure", () => {
      const policies = template.findResources("AWS::IAM::ManagedPolicy");

      Object.values(policies).forEach((policy: any) => {
        const policyDoc = policy.Properties.PolicyDocument;

        // Should have Version and Statement
        expect(policyDoc.Version).toBe("2012-10-17");
        expect(policyDoc.Statement).toBeDefined();
        expect(Array.isArray(policyDoc.Statement)).toBe(true);
        expect(policyDoc.Statement.length).toBeGreaterThan(0);

        // Each statement should have required fields
        policyDoc.Statement.forEach((statement: any) => {
          expect(statement.Effect).toMatch(/^(Allow|Deny)$/);
          expect(statement.Action || statement.NotAction).toBeDefined();
        });
      });
    });

    test("Policy statements follow AWS best practices", () => {
      const policies = template.findResources("AWS::IAM::ManagedPolicy");

      Object.values(policies).forEach((policy: any) => {
        const policyName = policy.Properties.ManagedPolicyName;
        const statements = policy.Properties.PolicyDocument.Statement;

        statements.forEach((statement: any, index: number) => {
          // Each statement should have a clear effect
          expect(statement.Effect).toBeDefined();

          // Allow statements should have actions and resources
          if (statement.Effect === "Allow") {
            expect(statement.Action).toBeDefined();

            // Most statements should have resource specification
            if (policyName !== "RequireMFAForAllActions") {
              expect(statement.Resource).toBeDefined();
            }
          }

          // Deny statements should have proper conditions
          if (statement.Effect === "Deny") {
            expect(statement.Condition || statement.NotAction).toBeDefined();
          }
        });
      });
    });

    test("No policies contain syntax errors", () => {
      const policies = template.findResources("AWS::IAM::ManagedPolicy");

      Object.values(policies).forEach((policy: any) => {
        const policyDoc = policy.Properties.PolicyDocument;

        // Should be valid JSON when stringified and parsed
        expect(() => {
          JSON.parse(JSON.stringify(policyDoc));
        }).not.toThrow();

        // Should not contain undefined or null values
        const policyString = JSON.stringify(policyDoc);
        expect(policyString).not.toContain("undefined");
        expect(policyString).not.toContain("null");
      });
    });
  });

  describe("Permission Boundary Analysis", () => {
    test("Developer permissions are properly scoped", () => {
      template.hasResourceProperties("AWS::IAM::ManagedPolicy", {
        ManagedPolicyName: "DeveloperPermissions",
        PolicyDocument: {
          Statement: Match.arrayWith([
            // EC2 permissions should be limited
            Match.objectLike({
              Effect: "Allow",
              Action: Match.arrayWith([
                "ec2:DescribeInstances",
                "ec2:StartInstances",
                "ec2:StopInstances",
              ]),
              Resource: "*",
            }),
            // S3 permissions should be scoped to app buckets
            Match.objectLike({
              Effect: "Allow",
              Action: Match.arrayWith(["s3:GetObject", "s3:PutObject"]),
              Resource: Match.arrayWith(["arn:aws:s3:::app-*/*"]),
            }),
            // CloudWatch logs should be read-only
            Match.objectLike({
              Effect: "Allow",
              Action: Match.arrayWith([
                "logs:DescribeLogGroups",
                "logs:GetLogEvents",
              ]),
            }),
          ]),
        },
      });
    });

    test("Operations permissions include infrastructure management", () => {
      template.hasResourceProperties("AWS::IAM::ManagedPolicy", {
        ManagedPolicyName: "OperationsPermissions",
        PolicyDocument: {
          Statement: Match.arrayWith([
            // Full EC2 access
            Match.objectLike({
              Effect: "Allow",
              Action: "ec2:*",
              Resource: "*",
            }),
            // Full RDS access
            Match.objectLike({
              Effect: "Allow",
              Action: "rds:*",
              Resource: "*",
            }),
            // CloudWatch access
            Match.objectLike({
              Effect: "Allow",
              Action: ["cloudwatch:*", "logs:*"],
              Resource: "*",
            }),
            // Systems Manager access
            Match.objectLike({
              Effect: "Allow",
              Action: ["ssm:*", "ssmmessages:*", "ec2messages:*"],
              Resource: "*",
            }),
          ]),
        },
      });
    });

    test("Finance permissions are limited to cost management", () => {
      template.hasResourceProperties("AWS::IAM::ManagedPolicy", {
        ManagedPolicyName: "FinancePermissions",
        PolicyDocument: {
          Statement: Match.arrayWith([
            // Cost Explorer access
            Match.objectLike({
              Effect: "Allow",
              Action: ["ce:*", "cur:*"],
              Resource: "*",
            }),
            // Budgets access
            Match.objectLike({
              Effect: "Allow",
              Action: "budgets:*",
              Resource: "*",
            }),
            // Read-only resource access
            Match.objectLike({
              Effect: "Allow",
              Action: Match.arrayWith([
                "ec2:Describe*",
                "rds:Describe*",
                "s3:ListAllMyBuckets",
              ]),
              Resource: "*",
            }),
          ]),
        },
      });
    });

    test("Analyst permissions are read-only and data-focused", () => {
      template.hasResourceProperties("AWS::IAM::ManagedPolicy", {
        ManagedPolicyName: "AnalystPermissions",
        PolicyDocument: {
          Statement: Match.arrayWith([
            // Data S3 bucket access
            Match.objectLike({
              Effect: "Allow",
              Action: ["s3:GetObject", "s3:ListBucket"],
              Resource: Match.arrayWith([
                "arn:aws:s3:::data-*/*",
                "arn:aws:s3:::data-*",
              ]),
            }),
            // CloudWatch metrics access
            Match.objectLike({
              Effect: "Allow",
              Action: Match.arrayWith([
                "cloudwatch:GetMetricStatistics",
                "cloudwatch:ListMetrics",
              ]),
              Resource: "*",
            }),
            // Read-only database access
            Match.objectLike({
              Effect: "Allow",
              Action: Match.arrayWith([
                "rds:DescribeDBInstances",
                "rds:DescribeDBClusters",
              ]),
              Resource: "*",
            }),
          ]),
        },
      });
    });
  });

  describe("Security Policy Validation", () => {
    test("MFA policy properly denies actions without MFA", () => {
      template.hasResourceProperties("AWS::IAM::ManagedPolicy", {
        ManagedPolicyName: "RequireMFAForAllActions",
        PolicyDocument: {
          Statement: Match.arrayWith([
            // Deny statement for actions without MFA
            Match.objectLike({
              Effect: "Deny",
              NotAction: Match.arrayWith([
                "iam:CreateVirtualMFADevice",
                "iam:EnableMFADevice",
                "iam:GetUser",
                "iam:ListMFADevices",
                "iam:ListVirtualMFADevices",
                "iam:ResyncMFADevice",
                "sts:GetSessionToken",
              ]),
              Resource: "*",
              Condition: {
                BoolIfExists: {
                  "aws:MultiFactorAuthPresent": "false",
                },
              },
            }),
            // Allow MFA device management
            Match.objectLike({
              Effect: "Allow",
              Action: Match.arrayWith([
                "iam:CreateVirtualMFADevice",
                "iam:EnableMFADevice",
                "iam:GetUser",
                "iam:ListMFADevices",
              ]),
              Resource: "*",
            }),
          ]),
        },
      });
    });

    test("MFA policy allows necessary MFA management actions", () => {
      const policies = template.findResources("AWS::IAM::ManagedPolicy");
      const mfaPolicy = Object.values(policies).find(
        (p: any) => p.Properties.ManagedPolicyName === "RequireMFAForAllActions"
      ) as any;

      expect(mfaPolicy).toBeDefined();

      const allowStatements =
        mfaPolicy.Properties.PolicyDocument.Statement.filter(
          (s: any) => s.Effect === "Allow"
        );

      expect(allowStatements.length).toBeGreaterThan(0);

      const mfaActions = allowStatements.flatMap((s: any) => s.Action);
      const requiredMfaActions = [
        "iam:CreateVirtualMFADevice",
        "iam:EnableMFADevice",
        "iam:ListMFADevices",
        "iam:ListVirtualMFADevices",
        "iam:ResyncMFADevice",
      ];

      requiredMfaActions.forEach((action) => {
        expect(mfaActions).toContain(action);
      });
    });
  });

  describe("Resource-Level Permission Analysis", () => {
    test("S3 permissions are properly scoped by role", () => {
      const policies = template.findResources("AWS::IAM::ManagedPolicy");

      // Developer should only access app buckets
      const devPolicy = Object.values(policies).find(
        (p: any) => p.Properties.ManagedPolicyName === "DeveloperPermissions"
      ) as any;

      if (devPolicy) {
        const s3Statements =
          devPolicy.Properties.PolicyDocument.Statement.filter(
            (s: any) =>
              s.Action && s.Action.some((a: string) => a.startsWith("s3:"))
          );

        s3Statements.forEach((statement: any) => {
          const resources = Array.isArray(statement.Resource)
            ? statement.Resource
            : [statement.Resource];
          resources.forEach((resource: string) => {
            if (resource.includes("s3")) {
              expect(resource).toMatch(/app-\*/);
            }
          });
        });
      }

      // Analyst should only access data buckets
      const analystPolicy = Object.values(policies).find(
        (p: any) => p.Properties.ManagedPolicyName === "AnalystPermissions"
      ) as any;

      if (analystPolicy) {
        const s3Statements =
          analystPolicy.Properties.PolicyDocument.Statement.filter(
            (s: any) =>
              s.Action && s.Action.some((a: string) => a.startsWith("s3:"))
          );

        s3Statements.forEach((statement: any) => {
          const resources = Array.isArray(statement.Resource)
            ? statement.Resource
            : [statement.Resource];
          resources.forEach((resource: string) => {
            if (resource.includes("s3")) {
              expect(resource).toMatch(/data-\*/);
            }
          });
        });
      }
    });

    test("EC2 permissions are appropriately scoped", () => {
      const policies = template.findResources("AWS::IAM::ManagedPolicy");

      // Developer should have limited EC2 permissions
      const devPolicy = Object.values(policies).find(
        (p: any) => p.Properties.ManagedPolicyName === "DeveloperPermissions"
      ) as any;

      if (devPolicy) {
        const ec2Statements =
          devPolicy.Properties.PolicyDocument.Statement.filter(
            (s: any) =>
              s.Action && s.Action.some((a: string) => a.startsWith("ec2:"))
          );

        ec2Statements.forEach((statement: any) => {
          const actions = Array.isArray(statement.Action)
            ? statement.Action
            : [statement.Action];

          // Should not have dangerous EC2 actions
          const dangerousActions = [
            "ec2:TerminateInstances",
            "ec2:RunInstances",
            "ec2:CreateSecurityGroup",
          ];
          actions.forEach((action: string) => {
            expect(dangerousActions).not.toContain(action);
          });
        });
      }

      // Operations should have full EC2 access
      const opsPolicy = Object.values(policies).find(
        (p: any) => p.Properties.ManagedPolicyName === "OperationsPermissions"
      ) as any;

      if (opsPolicy) {
        const ec2Statements =
          opsPolicy.Properties.PolicyDocument.Statement.filter(
            (s: any) =>
              s.Action &&
              (s.Action.includes("ec2:*") ||
                (Array.isArray(s.Action) && s.Action.includes("ec2:*")))
          );

        expect(ec2Statements.length).toBeGreaterThan(0);
      }
    });
  });

  describe("Policy Size and Complexity Validation", () => {
    test("Policies are within AWS size limits", () => {
      const policies = template.findResources("AWS::IAM::ManagedPolicy");

      Object.values(policies).forEach((policy: any) => {
        const policyDoc = policy.Properties.PolicyDocument;
        const policySize = JSON.stringify(policyDoc).length;

        // AWS managed policy size limit is 6,144 characters
        expect(policySize).toBeLessThan(6144);
      });
    });

    test("Policies have reasonable complexity", () => {
      const policies = template.findResources("AWS::IAM::ManagedPolicy");

      Object.values(policies).forEach((policy: any) => {
        const statements = policy.Properties.PolicyDocument.Statement;

        // Should not have too many statements (maintainability)
        expect(statements.length).toBeLessThan(20);

        statements.forEach((statement: any) => {
          // Each statement should not have too many actions
          if (statement.Action && Array.isArray(statement.Action)) {
            expect(statement.Action.length).toBeLessThan(50);
          }

          // Each statement should not have too many resources
          if (statement.Resource && Array.isArray(statement.Resource)) {
            expect(statement.Resource.length).toBeLessThan(20);
          }
        });
      });
    });
  });

  describe("Cross-Policy Consistency Validation", () => {
    test("No conflicting permissions between policies", () => {
      const policies = template.findResources("AWS::IAM::ManagedPolicy");
      const policyActions: { [key: string]: string[] } = {};

      // Collect all actions from each policy
      Object.values(policies).forEach((policy: any) => {
        const policyName = policy.Properties.ManagedPolicyName;
        const statements = policy.Properties.PolicyDocument.Statement;

        policyActions[policyName] = [];

        statements.forEach((statement: any) => {
          if (statement.Effect === "Allow" && statement.Action) {
            const actions = Array.isArray(statement.Action)
              ? statement.Action
              : [statement.Action];
            policyActions[policyName].push(...actions);
          }
        });
      });

      // Check for role separation
      const devActions = policyActions["DeveloperPermissions"] || [];
      const financeActions = policyActions["FinancePermissions"] || [];
      const analystActions = policyActions["AnalystPermissions"] || [];

      // Finance should not have infrastructure actions
      const infrastructureActions = devActions.filter(
        (action) =>
          action.startsWith("ec2:") ||
          action.startsWith("rds:") ||
          action.startsWith("s3:")
      );

      infrastructureActions.forEach((action) => {
        expect(financeActions).not.toContain(action);
      });

      // Analyst should not have write actions
      const writeActions = [
        "s3:PutObject",
        "s3:DeleteObject",
        "ec2:RunInstances",
        "rds:CreateDBInstance",
      ];
      writeActions.forEach((action) => {
        expect(analystActions).not.toContain(action);
      });
    });

    test("All role policies are attached to correct groups", () => {
      const policies = template.findResources("AWS::IAM::ManagedPolicy");

      Object.values(policies).forEach((policy: any) => {
        const policyName = policy.Properties.ManagedPolicyName;
        const groups = policy.Properties.Groups;

        if (groups && groups.length > 0) {
          // Each policy should be attached to exactly one group
          expect(groups.length).toBe(1);

          // Policy name should match group assignment
          const groupRef = groups[0].Ref;

          if (policyName === "DeveloperPermissions") {
            expect(groupRef).toMatch(/.*DeveloperGroup.*/);
          } else if (policyName === "OperationsPermissions") {
            expect(groupRef).toMatch(/.*OperationsGroup.*/);
          } else if (policyName === "FinancePermissions") {
            expect(groupRef).toMatch(/.*FinanceGroup.*/);
          } else if (policyName === "AnalystPermissions") {
            expect(groupRef).toMatch(/.*AnalystGroup.*/);
          }
        }
      });
    });
  });

  describe("Condition-Based Access Control Validation", () => {
    test("Time-based conditions are properly formatted", () => {
      const policies = template.findResources("AWS::IAM::ManagedPolicy");

      Object.values(policies).forEach((policy: any) => {
        const statements = policy.Properties.PolicyDocument.Statement;

        statements.forEach((statement: any) => {
          if (statement.Condition) {
            // Check for proper condition structure
            Object.keys(statement.Condition).forEach((conditionType) => {
              expect(conditionType).toMatch(
                /^(Bool|String|Numeric|Date|IpAddress|ArnLike|BoolIfExists|StringLike|StringEquals)/
              );

              const conditionBlock = statement.Condition[conditionType];
              expect(typeof conditionBlock).toBe("object");
              expect(conditionBlock).not.toBeNull();
            });
          }
        });
      });
    });

    test("MFA conditions are properly implemented", () => {
      const policies = template.findResources("AWS::IAM::ManagedPolicy");
      const mfaPolicy = Object.values(policies).find(
        (p: any) => p.Properties.ManagedPolicyName === "RequireMFAForAllActions"
      ) as any;

      if (mfaPolicy) {
        const denyStatements =
          mfaPolicy.Properties.PolicyDocument.Statement.filter(
            (s: any) => s.Effect === "Deny"
          );

        expect(denyStatements.length).toBeGreaterThan(0);

        denyStatements.forEach((statement: any) => {
          expect(statement.Condition).toBeDefined();
          expect(statement.Condition.BoolIfExists).toBeDefined();
          expect(
            statement.Condition.BoolIfExists["aws:MultiFactorAuthPresent"]
          ).toBe("false");
        });
      }
    });
  });
});
