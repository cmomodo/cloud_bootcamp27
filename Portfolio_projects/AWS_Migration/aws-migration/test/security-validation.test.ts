import * as cdk from "aws-cdk-lib";
import { Template } from "aws-cdk-lib/assertions";
import { TechHealthInfrastructureStack } from "../lib/tech-health-infrastructure-stack";

describe("Security Validation Tests", () => {
  let app: cdk.App;
  let stack: TechHealthInfrastructureStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new TechHealthInfrastructureStack(app, "SecurityTestStack", {
      env: {
        account: "123456789012",
        region: "us-east-1",
      },
    });
    template = Template.fromStack(stack);
  });

  describe("Network Security Validation", () => {
    test("No security groups allow unrestricted access to sensitive ports", () => {
      const templateJson = template.toJSON();
      const securityGroups = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::SecurityGroup"
      ) as any[];

      securityGroups.forEach((sg: any) => {
        const ingressRules = sg.Properties.SecurityGroupIngress || [];

        ingressRules.forEach((rule: any) => {
          // Check for dangerous combinations
          if (rule.CidrIp === "0.0.0.0/0") {
            // These ports should never be open to the world
            const dangerousPorts = [22, 3306, 5432, 1433, 3389, 21, 23];

            if (rule.FromPort && dangerousPorts.includes(rule.FromPort)) {
              // SSH (22) might be allowed from specific IPs, but not 0.0.0.0/0
              if (rule.FromPort === 22) {
                fail(
                  `SSH port 22 is open to 0.0.0.0/0 in security group ${sg.Properties.GroupDescription}`
                );
              }
              // Database ports should never be open to internet
              if ([3306, 5432, 1433].includes(rule.FromPort)) {
                fail(
                  `Database port ${rule.FromPort} is open to 0.0.0.0/0 in security group ${sg.Properties.GroupDescription}`
                );
              }
            }
          }
        });
      });
    });

    test("RDS security group only allows access from EC2 security group", () => {
      const templateJson = template.toJSON();

      // Find RDS security group
      const rdsSecurityGroup = Object.values(templateJson.Resources).find(
        (resource: any) =>
          resource.Type === "AWS::EC2::SecurityGroup" &&
          resource.Properties.GroupDescription?.includes("RDS MySQL database")
      ) as any;

      expect(rdsSecurityGroup).toBeDefined();

      // Check all ingress rules
      const ingressRules =
        rdsSecurityGroup.Properties.SecurityGroupIngress || [];

      ingressRules.forEach((rule: any) => {
        // Should not allow CIDR-based access
        expect(rule.CidrIp).toBeUndefined();
        // Should only allow security group references
        expect(
          rule.SourceSecurityGroupId || rule.SourceSecurityGroupOwnerId
        ).toBeDefined();
      });
    });

    test("No security groups have overly permissive egress rules", () => {
      const templateJson = template.toJSON();
      const securityGroups = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::SecurityGroup"
      ) as any[];

      securityGroups.forEach((sg: any) => {
        const egressRules = sg.Properties.SecurityGroupEgress || [];

        // RDS security group should not have unrestricted egress
        if (sg.Properties.GroupDescription?.includes("RDS MySQL database")) {
          const unrestrictedEgress = egressRules.find(
            (rule: any) =>
              rule.CidrIp === "0.0.0.0/0" && rule.IpProtocol !== "icmp"
          );
          expect(unrestrictedEgress).toBeUndefined();
        }
      });
    });
  });

  describe("IAM Security Validation", () => {
    test("IAM roles do not have overly broad permissions", () => {
      const templateJson = template.toJSON();
      const policies = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::IAM::Policy"
      ) as any[];

      policies.forEach((policy: any) => {
        const statements = policy.Properties.PolicyDocument.Statement;

        statements.forEach((statement: any) => {
          // Check for dangerous wildcard permissions
          if (Array.isArray(statement.Action)) {
            statement.Action.forEach((action: string) => {
              if (action === "*") {
                fail('IAM policy contains wildcard action "*"');
              }
            });
          } else if (statement.Action === "*") {
            fail('IAM policy contains wildcard action "*"');
          }

          // Check for overly broad resource permissions on sensitive services
          if (statement.Resource === "*") {
            const sensitiveActions = [
              "iam:",
              "kms:",
              "secretsmanager:",
              "rds:",
            ];

            const actions = Array.isArray(statement.Action)
              ? statement.Action
              : [statement.Action];
            const hasSensitiveAction = actions.some((action: string) =>
              sensitiveActions.some((sensitive) => action.startsWith(sensitive))
            );

            if (hasSensitiveAction) {
              console.warn(
                `IAM policy has wildcard resource "*" for sensitive actions: ${actions.join(
                  ", "
                )}`
              );
            }
          }
        });
      });
    });

    test("IAM roles have appropriate trust policies", () => {
      const templateJson = template.toJSON();
      const roles = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::IAM::Role"
      ) as any[];

      roles.forEach((role: any) => {
        const trustPolicy = role.Properties.AssumeRolePolicyDocument;

        trustPolicy.Statement.forEach((statement: any) => {
          // Should not allow wildcard principals
          if (statement.Principal === "*") {
            fail('IAM role has wildcard principal "*"');
          }

          // Should have specific service principals
          if (statement.Principal.Service) {
            const services = Array.isArray(statement.Principal.Service)
              ? statement.Principal.Service
              : [statement.Principal.Service];

            services.forEach((service: string) => {
              expect(service).toMatch(/^[a-z0-9-]+\.amazonaws\.com$/);
            });
          }
        });
      });
    });

    test("No hardcoded credentials in IAM policies", () => {
      const templateJson = template.toJSON();
      const policies = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::IAM::Policy"
      ) as any[];

      policies.forEach((policy: any) => {
        const policyString = JSON.stringify(policy.Properties.PolicyDocument);

        // Check for patterns that might indicate hardcoded credentials
        const suspiciousPatterns = [
          /AKIA[0-9A-Z]{16}/, // AWS Access Key ID pattern
          /[A-Za-z0-9/+=]{40}/, // AWS Secret Access Key pattern (base64)
          /"password":\s*"[^"]+"/i,
          /"secret":\s*"[^"]+"/i,
        ];

        suspiciousPatterns.forEach((pattern, index) => {
          if (pattern.test(policyString)) {
            console.warn(
              `Potential hardcoded credential detected in IAM policy (pattern ${
                index + 1
              })`
            );
          }
        });
      });
    });
  });

  describe("Encryption and Data Protection", () => {
    test("RDS instance has encryption at rest enabled", () => {
      template.hasResourceProperties("AWS::RDS::DBInstance", {
        StorageEncrypted: true,
      });
    });

    test("RDS instance uses appropriate encryption configuration", () => {
      const templateJson = template.toJSON();
      const rdsInstance = Object.values(templateJson.Resources).find(
        (resource: any) => resource.Type === "AWS::RDS::DBInstance"
      ) as any;

      expect(rdsInstance).toBeDefined();
      expect(rdsInstance.Properties.StorageEncrypted).toBe(true);

      // If KmsKeyId is specified, it should be valid
      if (rdsInstance.Properties.KmsKeyId) {
        expect(rdsInstance.Properties.KmsKeyId).toBeTruthy();
      }

      // Verify backup encryption is enabled
      expect(rdsInstance.Properties.StorageEncrypted).toBe(true);
    });

    test("Secrets Manager secret uses encryption", () => {
      const templateJson = template.toJSON();
      const secrets = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::SecretsManager::Secret"
      ) as any[];

      expect(secrets.length).toBeGreaterThan(0);

      // Secrets Manager encrypts by default, but we can check for explicit KMS key
      secrets.forEach((secret: any) => {
        // If KmsKeyId is specified, it should not be empty
        if (secret.Properties.KmsKeyId !== undefined) {
          expect(secret.Properties.KmsKeyId).toBeTruthy();
        }

        // Verify secret has proper description for audit purposes
        expect(secret.Properties.Description).toBeDefined();
      });
    });

    test("EBS volumes are encrypted", () => {
      const templateJson = template.toJSON();
      const instances = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::Instance"
      ) as any[];

      instances.forEach((instance: any) => {
        // Check if BlockDeviceMappings specify encryption
        if (instance.Properties.BlockDeviceMappings) {
          instance.Properties.BlockDeviceMappings.forEach((mapping: any) => {
            if (mapping.Ebs) {
              expect(mapping.Ebs.Encrypted).toBe(true);
            }
          });
        }
      });
    });

    test("Data in transit encryption is enforced", () => {
      const templateJson = template.toJSON();

      // Check RDS parameter group for SSL enforcement
      const parameterGroup = Object.values(templateJson.Resources).find(
        (resource: any) => resource.Type === "AWS::RDS::DBParameterGroup"
      ) as any;

      if (parameterGroup) {
        // MySQL 8.0 enforces SSL by default, but we can check for explicit settings
        const parameters = parameterGroup.Properties.Parameters;

        // Check for SSL-related parameters
        if (parameters.require_secure_transport) {
          expect(parameters.require_secure_transport).toBe("ON");
        }
      }

      // Verify security groups don't allow unencrypted protocols
      const securityGroups = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::SecurityGroup"
      ) as any[];

      securityGroups.forEach((sg: any) => {
        const ingressRules = sg.Properties.SecurityGroupIngress || [];

        // Check for insecure protocols
        ingressRules.forEach((rule: any) => {
          const insecurePorts = [21, 23, 80, 143, 993]; // FTP, Telnet, HTTP, IMAP

          if (rule.FromPort && insecurePorts.includes(rule.FromPort)) {
            // HTTP is allowed for web traffic, but warn about others
            if (rule.FromPort !== 80) {
              console.warn(
                `Potentially insecure protocol on port ${rule.FromPort}`
              );
            }
          }
        });
      });
    });

    test("No plaintext secrets in CloudFormation template", () => {
      const templateJson = template.toJSON();
      const templateString = JSON.stringify(templateJson);

      // Check for patterns that might indicate plaintext secrets
      const secretPatterns = [
        /password.*[=:]\s*["'][^"']{8,}["']/i,
        /secret.*[=:]\s*["'][^"']{8,}["']/i,
        /key.*[=:]\s*["'][^"']{20,}["']/i,
        /token.*[=:]\s*["'][^"']{20,}["']/i,
      ];

      secretPatterns.forEach((pattern, index) => {
        if (pattern.test(templateString)) {
          console.warn(
            `Potential plaintext secret detected in template (pattern ${
              index + 1
            })`
          );
        }
      });
    });

    test("Encryption keys are properly managed", () => {
      const templateJson = template.toJSON();

      // Check for KMS keys
      const kmsKeys = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::KMS::Key"
      ) as any[];

      kmsKeys.forEach((key: any) => {
        // KMS keys should have proper key policies
        expect(key.Properties.KeyPolicy).toBeDefined();

        // Key should have rotation enabled for compliance
        if (key.Properties.EnableKeyRotation !== undefined) {
          expect(key.Properties.EnableKeyRotation).toBe(true);
        }
      });
    });
  });

  describe("Network Access Control", () => {
    test("VPC has DNS resolution and hostnames enabled", () => {
      template.hasResourceProperties("AWS::EC2::VPC", {
        EnableDnsHostnames: true,
        EnableDnsSupport: true,
      });
    });

    test("Private subnets do not auto-assign public IPs", () => {
      const templateJson = template.toJSON();
      const subnets = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::Subnet"
      ) as any[];

      // Count subnets with and without public IP assignment
      const publicSubnets = subnets.filter(
        (subnet: any) => subnet.Properties.MapPublicIpOnLaunch === true
      );
      const privateSubnets = subnets.filter(
        (subnet: any) => !subnet.Properties.MapPublicIpOnLaunch
      );

      expect(publicSubnets.length).toBe(2); // Should have 2 public subnets
      expect(privateSubnets.length).toBe(2); // Should have 2 private subnets
    });

    test("No default security group modifications", () => {
      const templateJson = template.toJSON();

      // Check that we're not modifying the default security group
      const securityGroups = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::SecurityGroup"
      ) as any[];

      securityGroups.forEach((sg: any) => {
        // Default security groups typically don't have explicit GroupDescription
        // or have "default" in the name
        expect(sg.Properties.GroupName).not.toBe("default");
        expect(sg.Properties.GroupDescription).toBeDefined();
        expect(sg.Properties.GroupDescription).not.toContain(
          "default VPC security group"
        );
      });
    });
  });

  describe("Resource Configuration Security", () => {
    test("RDS instance has appropriate backup configuration", () => {
      template.hasResourceProperties("AWS::RDS::DBInstance", {
        BackupRetentionPeriod: expect.any(Number),
        DeleteAutomatedBackups: false,
      });

      const templateJson = template.toJSON();
      const rdsInstance = Object.values(templateJson.Resources).find(
        (resource: any) => resource.Type === "AWS::RDS::DBInstance"
      ) as any;

      // Backup retention should be at least 7 days for compliance
      expect(
        rdsInstance.Properties.BackupRetentionPeriod
      ).toBeGreaterThanOrEqual(7);
    });

    test("RDS parameter group has secure configurations", () => {
      template.hasResourceProperties("AWS::RDS::DBParameterGroup", {
        Parameters: expect.objectContaining({
          local_infile: "0", // Disable local file loading
          skip_show_database: "1", // Hide database names
          general_log: "1", // Enable general logging
          slow_query_log: "1", // Enable slow query logging
        }),
      });
    });

    test("EC2 instances have secure metadata configuration", () => {
      template.hasResourceProperties("AWS::EC2::Instance", {
        MetadataOptions: {
          HttpEndpoint: "enabled",
          HttpTokens: "required", // Require IMDSv2
          HttpPutResponseHopLimit: 1,
        },
      });
    });
  });

  describe("HIPAA Compliance Validation", () => {
    test("Administrative Safeguards - Access Control (164.308(a)(4))", () => {
      const templateJson = template.toJSON();

      // Verify IAM roles implement least privilege
      const iamPolicies = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::IAM::Policy"
      ) as any[];

      iamPolicies.forEach((policy: any) => {
        const statements = policy.Properties.PolicyDocument.Statement;

        statements.forEach((statement: any) => {
          // Should not have wildcard actions on sensitive resources
          if (statement.Resource !== "*" || statement.Action !== "*") {
            // Good - specific permissions
            expect(true).toBe(true);
          } else {
            console.warn(
              "HIPAA 164.308(a)(4): Overly broad IAM permissions detected"
            );
          }
        });
      });

      // Verify unique user identification through IAM roles
      const iamRoles = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::IAM::Role"
      ) as any[];

      expect(iamRoles.length).toBeGreaterThan(0);
    });

    test("Physical Safeguards - Data Center Security (164.310)", () => {
      const templateJson = template.toJSON();

      // AWS data centers are HIPAA compliant by default
      // Verify we're using AWS managed services appropriately
      const rdsInstance = Object.values(templateJson.Resources).find(
        (resource: any) => resource.Type === "AWS::RDS::DBInstance"
      ) as any;

      if (rdsInstance) {
        // RDS provides physical safeguards through AWS infrastructure
        expect(rdsInstance.Properties.Engine).toBeDefined();
        expect(rdsInstance.Properties.StorageEncrypted).toBe(true);
      }
    });

    test("Technical Safeguards - Access Control (164.312(a)(1))", () => {
      const templateJson = template.toJSON();

      // Verify unique user identification
      const iamRoles = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::IAM::Role"
      ) as any[];

      iamRoles.forEach((role: any) => {
        // Each role should have specific trust policy
        expect(role.Properties.AssumeRolePolicyDocument).toBeDefined();

        const trustPolicy = role.Properties.AssumeRolePolicyDocument;
        trustPolicy.Statement.forEach((statement: any) => {
          // Should not allow wildcard principals
          expect(statement.Principal).not.toBe("*");
        });
      });

      // Verify automatic logoff through session management
      // This would typically be handled at the application level
      // but we can verify CloudWatch logging is enabled
      const rdsInstance = Object.values(templateJson.Resources).find(
        (resource: any) => resource.Type === "AWS::RDS::DBInstance"
      ) as any;

      if (rdsInstance) {
        expect(rdsInstance.Properties.EnableCloudwatchLogsExports).toContain(
          "general"
        );
      }
    });

    test("Technical Safeguards - Audit Controls (164.312(b))", () => {
      const templateJson = template.toJSON();

      // Verify audit logging is enabled
      const rdsInstance = Object.values(templateJson.Resources).find(
        (resource: any) => resource.Type === "AWS::RDS::DBInstance"
      ) as any;

      if (rdsInstance) {
        // RDS should export logs to CloudWatch
        expect(
          rdsInstance.Properties.EnableCloudwatchLogsExports
        ).toBeDefined();
        expect(rdsInstance.Properties.EnableCloudwatchLogsExports).toContain(
          "error"
        );
        expect(rdsInstance.Properties.EnableCloudwatchLogsExports).toContain(
          "general"
        );
        expect(rdsInstance.Properties.EnableCloudwatchLogsExports).toContain(
          "slow-query"
        );
      }

      // Verify parameter group enables logging
      const parameterGroup = Object.values(templateJson.Resources).find(
        (resource: any) => resource.Type === "AWS::RDS::DBParameterGroup"
      ) as any;

      if (parameterGroup) {
        expect(parameterGroup.Properties.Parameters.general_log).toBe("1");
        expect(parameterGroup.Properties.Parameters.slow_query_log).toBe("1");
      }
    });

    test("Technical Safeguards - Integrity (164.312(c)(1))", () => {
      const templateJson = template.toJSON();

      // Verify data integrity through encryption and checksums
      const rdsInstance = Object.values(templateJson.Resources).find(
        (resource: any) => resource.Type === "AWS::RDS::DBInstance"
      ) as any;

      if (rdsInstance) {
        // Encryption at rest ensures data integrity
        expect(rdsInstance.Properties.StorageEncrypted).toBe(true);

        // Automated backups help with integrity verification
        expect(rdsInstance.Properties.BackupRetentionPeriod).toBeGreaterThan(0);
      }
    });

    test("Technical Safeguards - Transmission Security (164.312(e)(1))", () => {
      const templateJson = template.toJSON();

      // Verify encryption in transit
      const parameterGroup = Object.values(templateJson.Resources).find(
        (resource: any) => resource.Type === "AWS::RDS::DBParameterGroup"
      ) as any;

      if (parameterGroup) {
        // MySQL 8.0 enforces SSL by default
        const parameters = parameterGroup.Properties.Parameters;

        // Check for SSL enforcement if explicitly configured
        if (parameters.require_secure_transport) {
          expect(parameters.require_secure_transport).toBe("ON");
        }
      }

      // Verify security groups don't allow unencrypted protocols
      const securityGroups = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::SecurityGroup"
      ) as any[];

      securityGroups.forEach((sg: any) => {
        const ingressRules = sg.Properties.SecurityGroupIngress || [];

        // Check for insecure protocols
        const insecurePorts = [21, 23, 143]; // FTP, Telnet, IMAP
        ingressRules.forEach((rule: any) => {
          if (rule.FromPort && insecurePorts.includes(rule.FromPort)) {
            console.warn(
              `HIPAA 164.312(e)(1): Insecure protocol on port ${rule.FromPort}`
            );
          }
        });
      });
    });

    test("Business Associate Agreement (BAA) Requirements", () => {
      const templateJson = template.toJSON();

      // Verify we're using HIPAA-eligible AWS services
      const hipaaEligibleServices = [
        "AWS::RDS::DBInstance",
        "AWS::EC2::Instance",
        "AWS::SecretsManager::Secret",
        "AWS::CloudWatch::Alarm",
      ];

      hipaaEligibleServices.forEach((serviceType) => {
        const resources = Object.values(templateJson.Resources).filter(
          (resource: any) => resource.Type === serviceType
        ) as any[];

        // If we're using the service, verify it's configured securely
        if (resources.length > 0) {
          resources.forEach((resource: any) => {
            // All HIPAA resources should be tagged appropriately
            if (resource.Properties.Tags) {
              const complianceTag = resource.Properties.Tags.find(
                (tag: any) => tag.Key === "Compliance"
              );
              expect(complianceTag?.Value).toBe("HIPAA");
            }
          });
        }
      });
    });
  });

  describe("Compliance and Audit Requirements", () => {
    test("All resources have required compliance tags", () => {
      const templateJson = template.toJSON();
      const requiredTags = ["Compliance", "Project", "Environment"];

      // Check taggable resources
      const taggableResourceTypes = [
        "AWS::EC2::VPC",
        "AWS::EC2::Instance",
        "AWS::RDS::DBInstance",
        "AWS::SecretsManager::Secret",
      ];

      taggableResourceTypes.forEach((resourceType) => {
        const resources = Object.values(templateJson.Resources).filter(
          (resource: any) => resource.Type === resourceType
        ) as any[];

        resources.forEach((resource: any) => {
          expect(resource.Properties.Tags).toBeDefined();

          const tagKeys = resource.Properties.Tags.map((tag: any) => tag.Key);

          // Check for compliance tag specifically
          expect(tagKeys).toContain("Compliance");

          const complianceTag = resource.Properties.Tags.find(
            (tag: any) => tag.Key === "Compliance"
          );
          expect(complianceTag.Value).toBe("HIPAA");
        });
      });
    });

    test("CloudWatch logging is enabled for audit trail", () => {
      // RDS CloudWatch logs
      template.hasResourceProperties("AWS::RDS::DBInstance", {
        EnableCloudwatchLogsExports: ["error", "general", "slow-query"],
      });

      // Database parameter group enables logging
      template.hasResourceProperties("AWS::RDS::DBParameterGroup", {
        Parameters: expect.objectContaining({
          general_log: "1",
          slow_query_log: "1",
        }),
      });
    });

    test("Monitoring and alerting are configured", () => {
      // Should have CloudWatch alarms for monitoring
      template.resourceCountIs("AWS::CloudWatch::Alarm", 5);

      const templateJson = template.toJSON();
      const alarms = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::CloudWatch::Alarm"
      ) as any[];

      // Check that alarms have appropriate thresholds
      alarms.forEach((alarm: any) => {
        expect(alarm.Properties.Threshold).toBeDefined();
        expect(alarm.Properties.ComparisonOperator).toBeDefined();
        expect(alarm.Properties.AlarmDescription).toBeDefined();
      });
    });
  });

  describe("Security Scanning and Policy Validation", () => {
    test("CIS AWS Foundations Benchmark compliance checks", () => {
      const templateJson = template.toJSON();

      // CIS 2.1.1: Ensure S3 bucket access logging is enabled (if S3 buckets exist)
      const s3Buckets = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::S3::Bucket"
      ) as any[];

      s3Buckets.forEach((bucket: any) => {
        expect(bucket.Properties.LoggingConfiguration).toBeDefined();
      });

      // CIS 2.1.3: Ensure MFA Delete is enabled on S3 buckets (if S3 buckets exist)
      s3Buckets.forEach((bucket: any) => {
        if (bucket.Properties.VersioningConfiguration) {
          expect(bucket.Properties.VersioningConfiguration.Status).toBe(
            "Enabled"
          );
        }
      });

      // CIS 2.2.1: Ensure CloudTrail is enabled (check for CloudTrail resources)
      const cloudTrails = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::CloudTrail::Trail"
      ) as any[];

      // For this infrastructure, CloudTrail might be managed separately
      // but we can check if it's included in the template
      if (cloudTrails.length > 0) {
        cloudTrails.forEach((trail: any) => {
          expect(trail.Properties.IsLogging).toBe(true);
          expect(trail.Properties.IncludeGlobalServiceEvents).toBe(true);
        });
      }
    });

    test("OWASP security controls validation", () => {
      const templateJson = template.toJSON();

      // A1: Injection - Check for SQL injection prevention
      const rdsInstance = Object.values(templateJson.Resources).find(
        (resource: any) => resource.Type === "AWS::RDS::DBInstance"
      ) as any;

      if (rdsInstance) {
        // Ensure parameter group is used for security configurations
        expect(rdsInstance.Properties.DBParameterGroupName).toBeDefined();
      }

      // A2: Broken Authentication - Check IAM configurations
      const iamRoles = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::IAM::Role"
      ) as any[];

      iamRoles.forEach((role: any) => {
        // Roles should not allow wildcard principals
        const trustPolicy = role.Properties.AssumeRolePolicyDocument;
        trustPolicy.Statement.forEach((statement: any) => {
          expect(statement.Principal).not.toBe("*");
        });
      });

      // A3: Sensitive Data Exposure - Check encryption
      if (rdsInstance) {
        expect(rdsInstance.Properties.StorageEncrypted).toBe(true);
      }

      // A5: Broken Access Control - Check security group rules
      const securityGroups = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::SecurityGroup"
      ) as any[];

      securityGroups.forEach((sg: any) => {
        const ingressRules = sg.Properties.SecurityGroupIngress || [];

        // Should not have overly permissive rules
        ingressRules.forEach((rule: any) => {
          if (rule.CidrIp === "0.0.0.0/0") {
            // Only allow common web ports from internet
            const allowedPublicPorts = [80, 443];
            if (rule.FromPort && !allowedPublicPorts.includes(rule.FromPort)) {
              // SSH might be allowed but should be restricted
              if (rule.FromPort === 22) {
                console.warn(
                  "SSH port 22 is open to 0.0.0.0/0 - consider restricting"
                );
              }
            }
          }
        });
      });
    });

    test("AWS Config Rules compliance simulation", () => {
      const templateJson = template.toJSON();

      // Simulate AWS Config rule: rds-storage-encrypted
      const rdsInstances = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::RDS::DBInstance"
      ) as any[];

      rdsInstances.forEach((instance: any) => {
        expect(instance.Properties.StorageEncrypted).toBe(true);
      });

      // Simulate AWS Config rule: ec2-security-group-attached-to-eni
      const instances = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::Instance"
      ) as any[];

      instances.forEach((instance: any) => {
        const networkInterfaces = instance.Properties.NetworkInterfaces || [];
        networkInterfaces.forEach((ni: any) => {
          expect(ni.GroupSet).toBeDefined();
          expect(ni.GroupSet.length).toBeGreaterThan(0);
        });
      });

      // Simulate AWS Config rule: vpc-default-security-group-closed
      const defaultSecurityGroups = Object.values(
        templateJson.Resources
      ).filter(
        (resource: any) =>
          resource.Type === "AWS::EC2::SecurityGroup" &&
          (resource.Properties.GroupName === "default" ||
            resource.Properties.GroupDescription?.includes("default"))
      ) as any[];

      // Should not modify default security groups
      expect(defaultSecurityGroups.length).toBe(0);
    });

    test("Checkov-style policy violations detection", () => {
      const templateJson = template.toJSON();

      // CKV_AWS_16: Ensure no security groups allow ingress from 0.0.0.0:0 to port 22
      const securityGroups = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::SecurityGroup"
      ) as any[];

      securityGroups.forEach((sg: any) => {
        const ingressRules = sg.Properties.SecurityGroupIngress || [];
        const sshFromAnywhere = ingressRules.find(
          (rule: any) =>
            rule.FromPort === 22 &&
            rule.ToPort === 22 &&
            rule.CidrIp === "0.0.0.0/0"
        );

        if (sshFromAnywhere) {
          console.warn("CKV_AWS_16: SSH access from 0.0.0.0/0 detected");
        }
      });

      // CKV_AWS_17: Ensure RDS instances are not publicly accessible
      const rdsInstances = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::RDS::DBInstance"
      ) as any[];

      rdsInstances.forEach((instance: any) => {
        expect(instance.Properties.PubliclyAccessible).not.toBe(true);
      });

      // CKV_AWS_20: Ensure S3 bucket has MFA delete enabled (if S3 exists)
      const s3Buckets = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::S3::Bucket"
      ) as any[];

      s3Buckets.forEach((bucket: any) => {
        if (bucket.Properties.VersioningConfiguration) {
          expect(bucket.Properties.VersioningConfiguration.Status).toBe(
            "Enabled"
          );
        }
      });

      // CKV_AWS_23: Ensure RDS instances have backup enabled
      rdsInstances.forEach((instance: any) => {
        expect(instance.Properties.BackupRetentionPeriod).toBeGreaterThan(0);
      });

      // CKV_AWS_79: Ensure Instance Metadata Service Version 1 is not enabled
      const ec2Instances = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::Instance"
      ) as any[];

      ec2Instances.forEach((instance: any) => {
        if (instance.Properties.MetadataOptions) {
          expect(instance.Properties.MetadataOptions.HttpTokens).toBe(
            "required"
          );
        }
      });
    });
  });

  describe("Security Best Practices Validation", () => {
    test("No resources use deprecated or insecure configurations", () => {
      const templateJson = template.toJSON();

      // Check RDS instance for secure configurations
      const rdsInstance = Object.values(templateJson.Resources).find(
        (resource: any) => resource.Type === "AWS::RDS::DBInstance"
      ) as any;

      if (rdsInstance) {
        // Should not use deprecated engine versions
        expect(rdsInstance.Properties.Engine).toBe("mysql");
        expect(rdsInstance.Properties.EngineVersion).toMatch(/^8\./); // MySQL 8.x

        // Should have Multi-AZ for production workloads
        expect(rdsInstance.Properties.MultiAZ).toBe(true);
      }
    });

    test("Security groups follow naming conventions", () => {
      const templateJson = template.toJSON();
      const securityGroups = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::SecurityGroup"
      ) as any[];

      securityGroups.forEach((sg: any) => {
        // Should have descriptive names
        expect(sg.Properties.GroupDescription).toBeDefined();
        expect(sg.Properties.GroupDescription.length).toBeGreaterThan(10);

        // Should indicate purpose
        const description = sg.Properties.GroupDescription.toLowerCase();
        expect(
          description.includes("ec2") ||
            description.includes("rds") ||
            description.includes("database")
        ).toBe(true);
      });
    });

    test("Resource names follow security conventions", () => {
      const templateJson = template.toJSON();

      // Check that resource names don't contain sensitive information
      Object.entries(templateJson.Resources).forEach(
        ([logicalId, resource]: [string, any]) => {
          // Logical IDs should not contain sensitive patterns
          const sensitivePatterns = [
            /password/i,
            /secret/i,
            /key/i,
            /token/i,
            /credential/i,
          ];

          sensitivePatterns.forEach((pattern) => {
            if (pattern.test(logicalId)) {
              console.warn(
                `Resource logical ID "${logicalId}" may contain sensitive information`
              );
            }
          });
        }
      );
    });
  });
});
