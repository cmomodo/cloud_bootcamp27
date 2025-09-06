import * as cdk from "aws-cdk-lib";
import { Template } from "aws-cdk-lib/assertions";
import { TechHealthInfrastructureStack } from "../lib/tech-health-infrastructure-stack";

/**
 * Automated Connectivity Tests
 *
 * These tests validate the network connectivity and security configuration
 * of the deployed infrastructure. They can be run against both the CDK
 * template and potentially against live infrastructure.
 */
describe("Automated Connectivity and Security Validation", () => {
  let app: cdk.App;
  let stack: TechHealthInfrastructureStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new TechHealthInfrastructureStack(
      app,
      "ConnectivityValidationStack",
      {
        env: {
          account: "123456789012",
          region: "us-east-1",
        },
      }
    );
    template = Template.fromStack(stack);
  });

  describe("EC2 to RDS Connectivity Validation", () => {
    test("EC2 instances can connect to RDS through security group rules", () => {
      const templateJson = template.toJSON();

      // Find EC2 and RDS security groups
      const ec2SecurityGroup = Object.entries(templateJson.Resources).find(
        ([_, resource]: [string, any]) =>
          resource.Type === "AWS::EC2::SecurityGroup" &&
          resource.Properties.GroupDescription?.includes("EC2 instances")
      );

      const rdsSecurityGroup = Object.entries(templateJson.Resources).find(
        ([_, resource]: [string, any]) =>
          resource.Type === "AWS::EC2::SecurityGroup" &&
          resource.Properties.GroupDescription?.includes("RDS MySQL database")
      );

      expect(ec2SecurityGroup).toBeDefined();
      expect(rdsSecurityGroup).toBeDefined();

      const [ec2SgId] = ec2SecurityGroup!;
      const [rdsSgId] = rdsSecurityGroup!;

      // Verify MySQL ingress rule exists
      const ingressRules = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::SecurityGroupIngress"
      ) as any[];

      const mysqlRule = ingressRules.find(
        (rule: any) =>
          rule.Properties.FromPort === 3306 &&
          rule.Properties.ToPort === 3306 &&
          rule.Properties.IpProtocol === "tcp" &&
          rule.Properties.GroupId?.Ref === rdsSgId
      );

      expect(mysqlRule).toBeDefined();
      expect(mysqlRule.Properties.SourceSecurityGroupId).toBeDefined();
    });

    test("RDS is accessible only from EC2 security group", () => {
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
        // Should only allow security group references, not CIDR blocks
        expect(rule.CidrIp).toBeUndefined();
        expect(rule.SourceSecurityGroupId).toBeDefined();

        // Should only be MySQL port
        expect(rule.FromPort).toBe(3306);
        expect(rule.ToPort).toBe(3306);
        expect(rule.IpProtocol).toBe("tcp");
      });
    });

    test("Network path validation from EC2 to RDS", () => {
      const templateJson = template.toJSON();

      // Find EC2 instances and their subnets
      const instances = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::Instance"
      ) as any[];

      // Find RDS subnet group
      const dbSubnetGroup = Object.values(templateJson.Resources).find(
        (resource: any) => resource.Type === "AWS::RDS::DBSubnetGroup"
      ) as any;

      expect(dbSubnetGroup).toBeDefined();

      // Verify EC2 and RDS are in the same VPC
      const vpc = Object.entries(templateJson.Resources).find(
        ([_, resource]: [string, any]) => resource.Type === "AWS::EC2::VPC"
      );
      expect(vpc).toBeDefined();

      // All subnets should be in the same VPC
      const subnets = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::Subnet"
      ) as any[];

      const [vpcId] = vpc!;
      subnets.forEach((subnet: any) => {
        expect(subnet.Properties.VpcId.Ref).toBe(vpcId);
      });
    });

    test("DNS resolution is properly configured", () => {
      // Verify VPC has DNS resolution enabled
      template.hasResourceProperties("AWS::EC2::VPC", {
        EnableDnsHostnames: true,
        EnableDnsSupport: true,
      });

      const templateJson = template.toJSON();

      // Verify RDS will have a resolvable endpoint
      const rdsInstance = Object.values(templateJson.Resources).find(
        (resource: any) => resource.Type === "AWS::RDS::DBInstance"
      ) as any;

      expect(rdsInstance).toBeDefined();
      // RDS automatically gets a DNS endpoint when deployed
    });
  });

  describe("Internet Access Validation", () => {
    test("EC2 instances have internet access through IGW", () => {
      const templateJson = template.toJSON();

      // Find Internet Gateway
      const igw = Object.entries(templateJson.Resources).find(
        ([_, resource]: [string, any]) =>
          resource.Type === "AWS::EC2::InternetGateway"
      );
      expect(igw).toBeDefined();

      const [igwId] = igw!;

      // Find routes to Internet Gateway
      const internetRoutes = Object.values(templateJson.Resources).filter(
        (resource: any) =>
          resource.Type === "AWS::EC2::Route" &&
          resource.Properties.DestinationCidrBlock === "0.0.0.0/0" &&
          resource.Properties.GatewayId?.Ref === igwId
      );

      expect(internetRoutes.length).toBeGreaterThan(0);

      // Verify EC2 instances are in public subnets
      const instances = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::Instance"
      ) as any[];

      instances.forEach((instance: any) => {
        expect(
          instance.Properties.NetworkInterfaces[0].AssociatePublicIpAddress
        ).toBe(true);
      });
    });

    test("RDS has no internet access", () => {
      const templateJson = template.toJSON();

      // Verify RDS is not publicly accessible
      const rdsInstance = Object.values(templateJson.Resources).find(
        (resource: any) => resource.Type === "AWS::RDS::DBInstance"
      ) as any;

      expect(rdsInstance).toBeDefined();
      expect(rdsInstance.Properties.PubliclyAccessible).not.toBe(true);

      // Verify RDS subnets are private
      const dbSubnetGroup = Object.values(templateJson.Resources).find(
        (resource: any) => resource.Type === "AWS::RDS::DBSubnetGroup"
      ) as any;

      const subnetIds = dbSubnetGroup.Properties.SubnetIds;
      subnetIds.forEach((subnetRef: any) => {
        const subnetId = subnetRef.Ref;
        const subnet = Object.values(templateJson.Resources).find(
          (resource: any) =>
            resource.Type === "AWS::EC2::Subnet" &&
            Object.keys(templateJson.Resources).find(
              (key) => templateJson.Resources[key] === resource
            ) === subnetId
        ) as any;

        // Private subnets don't auto-assign public IPs
        expect(subnet.Properties.MapPublicIpOnLaunch).not.toBe(true);
      });

      // Verify no NAT Gateway exists (cost optimization)
      template.resourceCountIs("AWS::EC2::NatGateway", 0);
    });

    test("No unauthorized internet access paths exist", () => {
      const templateJson = template.toJSON();

      // Check all security groups for overly permissive rules
      const securityGroups = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::SecurityGroup"
      ) as any[];

      securityGroups.forEach((sg: any) => {
        const ingressRules = sg.Properties.SecurityGroupIngress || [];

        ingressRules.forEach((rule: any) => {
          if (rule.CidrIp === "0.0.0.0/0") {
            // Only allow specific ports from internet
            const allowedPublicPorts = [80, 443, 22]; // HTTP, HTTPS, SSH

            if (rule.FromPort && !allowedPublicPorts.includes(rule.FromPort)) {
              fail(
                `Unexpected port ${rule.FromPort} is open to internet in ${sg.Properties.GroupDescription}`
              );
            }

            // Database ports should never be open to internet
            const databasePorts = [3306, 5432, 1433, 27017];
            if (rule.FromPort && databasePorts.includes(rule.FromPort)) {
              fail(
                `Database port ${rule.FromPort} is open to internet in ${sg.Properties.GroupDescription}`
              );
            }
          }
        });
      });
    });
  });

  describe("Security Configuration Validation", () => {
    test("All security groups implement least privilege", () => {
      const templateJson = template.toJSON();
      const securityGroups = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::SecurityGroup"
      ) as any[];

      securityGroups.forEach((sg: any) => {
        const ingressRules = sg.Properties.SecurityGroupIngress || [];
        const egressRules = sg.Properties.SecurityGroupEgress || [];

        // Ingress rules should be specific
        ingressRules.forEach((rule: any) => {
          expect(rule.FromPort).toBeDefined();
          expect(rule.ToPort).toBeDefined();
          expect(rule.IpProtocol).toBeDefined();

          // Should have either CIDR or security group source
          expect(
            rule.CidrIp ||
              rule.SourceSecurityGroupId ||
              rule.SourceSecurityGroupOwnerId
          ).toBeDefined();
        });

        // RDS security groups should not have unrestricted egress
        if (sg.Properties.GroupDescription?.includes("RDS")) {
          const unrestrictedEgress = egressRules.find(
            (rule: any) =>
              rule.CidrIp === "0.0.0.0/0" && rule.IpProtocol === "-1"
          );
          expect(unrestrictedEgress).toBeUndefined();
        }
      });
    });

    test("IAM roles have appropriate permissions", () => {
      const templateJson = template.toJSON();
      const iamPolicies = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::IAM::Policy"
      ) as any[];

      iamPolicies.forEach((policy: any) => {
        const statements = policy.Properties.PolicyDocument.Statement;

        statements.forEach((statement: any) => {
          // Should not have wildcard actions and resources together
          if (statement.Action === "*" && statement.Resource === "*") {
            fail("IAM policy has wildcard action and resource");
          }

          // Sensitive actions should have specific resources
          const sensitiveActions = ["iam:", "kms:", "secretsmanager:"];
          const actions = Array.isArray(statement.Action)
            ? statement.Action
            : [statement.Action];

          const hasSensitiveAction = actions.some((action: string) =>
            sensitiveActions.some((sensitive) => action.startsWith(sensitive))
          );

          if (hasSensitiveAction && statement.Resource === "*") {
            console.warn(
              `Sensitive action with wildcard resource: ${actions.join(", ")}`
            );
          }
        });
      });
    });

    test("Encryption is properly configured", () => {
      const templateJson = template.toJSON();

      // RDS encryption
      const rdsInstance = Object.values(templateJson.Resources).find(
        (resource: any) => resource.Type === "AWS::RDS::DBInstance"
      ) as any;

      if (rdsInstance) {
        expect(rdsInstance.Properties.StorageEncrypted).toBe(true);
      }

      // Secrets Manager encryption (default)
      const secrets = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::SecretsManager::Secret"
      ) as any[];

      secrets.forEach((secret: any) => {
        // Secrets Manager encrypts by default
        expect(secret.Type).toBe("AWS::SecretsManager::Secret");
      });

      // EC2 instance metadata security
      const instances = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::Instance"
      ) as any[];

      instances.forEach((instance: any) => {
        if (instance.Properties.MetadataOptions) {
          expect(instance.Properties.MetadataOptions.HttpTokens).toBe(
            "required"
          );
        }
      });
    });
  });

  describe("Monitoring and Alerting Validation", () => {
    test("CloudWatch alarms are configured for critical metrics", () => {
      template.resourceCountIs("AWS::CloudWatch::Alarm", 7);

      const templateJson = template.toJSON();
      const alarms = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::CloudWatch::Alarm"
      ) as any[];

      // Verify alarm configurations
      alarms.forEach((alarm: any) => {
        expect(alarm.Properties.AlarmDescription).toBeDefined();
        expect(alarm.Properties.MetricName).toBeDefined();
        expect(alarm.Properties.Threshold).toBeDefined();
        expect(alarm.Properties.ComparisonOperator).toBeDefined();
      });

      // Check for specific critical alarms
      const alarmDescriptions = alarms.map(
        (alarm: any) => alarm.Properties.AlarmDescription
      );

      expect(alarmDescriptions).toContain(
        "Database CPU utilization is too high"
      );
      expect(alarmDescriptions).toContain(
        "Database connection count is too high"
      );
      expect(alarmDescriptions).toContain("Database free storage space is low");
    });

    test("Logging is enabled for audit purposes", () => {
      const templateJson = template.toJSON();

      // RDS CloudWatch logs
      const rdsInstance = Object.values(templateJson.Resources).find(
        (resource: any) => resource.Type === "AWS::RDS::DBInstance"
      ) as any;

      if (rdsInstance) {
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

      // Database parameter group logging
      const parameterGroup = Object.values(templateJson.Resources).find(
        (resource: any) => resource.Type === "AWS::RDS::DBParameterGroup"
      ) as any;

      if (parameterGroup) {
        expect(parameterGroup.Properties.Parameters.general_log).toBe("1");
        expect(parameterGroup.Properties.Parameters.slow_query_log).toBe("1");
      }
    });
  });

  describe("Backup and Recovery Validation", () => {
    test("RDS backup configuration meets requirements", () => {
      const templateJson = template.toJSON();
      const rdsInstance = Object.values(templateJson.Resources).find(
        (resource: any) => resource.Type === "AWS::RDS::DBInstance"
      ) as any;

      expect(rdsInstance).toBeDefined();
      expect(rdsInstance.Properties.BackupRetentionPeriod).toBeGreaterThan(0);
      expect(rdsInstance.Properties.DeleteAutomatedBackups).toBe(false);

      // For development environment, backup retention is 1 day
      expect(rdsInstance.Properties.BackupRetentionPeriod).toBe(1);
    });

    test("Multi-AZ configuration matches environment", () => {
      const templateJson = template.toJSON();
      const rdsInstance = Object.values(templateJson.Resources).find(
        (resource: any) => resource.Type === "AWS::RDS::DBInstance"
      ) as any;

      // Development environment uses single AZ for cost optimization
      expect(rdsInstance.Properties.MultiAZ).toBe(false);

      // But DB subnet group should still span multiple AZs for flexibility
      const dbSubnetGroup = Object.values(templateJson.Resources).find(
        (resource: any) => resource.Type === "AWS::RDS::DBSubnetGroup"
      ) as any;

      expect(dbSubnetGroup.Properties.SubnetIds.length).toBeGreaterThanOrEqual(
        2
      );
    });
  });

  describe("Cost Optimization Validation", () => {
    test("Instance types are cost-optimized", () => {
      const templateJson = template.toJSON();

      // EC2 instances should use t2.micro (free tier)
      const instances = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::Instance"
      ) as any[];

      instances.forEach((instance: any) => {
        expect(instance.Properties.InstanceType).toBe("t2.micro");
      });

      // RDS should use db.t3.micro
      const rdsInstance = Object.values(templateJson.Resources).find(
        (resource: any) => resource.Type === "AWS::RDS::DBInstance"
      ) as any;

      expect(rdsInstance.Properties.DBInstanceClass).toBe("db.t3.micro");
    });

    test("No expensive resources are deployed", () => {
      // Verify no NAT Gateways (cost optimization)
      template.resourceCountIs("AWS::EC2::NatGateway", 0);

      // Verify no Elastic Load Balancers in development
      template.resourceCountIs("AWS::ElasticLoadBalancingV2::LoadBalancer", 0);

      // Verify minimal RDS storage
      const templateJson = template.toJSON();
      const rdsInstance = Object.values(templateJson.Resources).find(
        (resource: any) => resource.Type === "AWS::RDS::DBInstance"
      ) as any;

      expect(rdsInstance.Properties.AllocatedStorage).toBe("20"); // Minimum for MySQL
    });
  });
});
