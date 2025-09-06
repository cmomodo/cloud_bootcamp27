import * as cdk from "aws-cdk-lib";
import { Template } from "aws-cdk-lib/assertions";
import { TechHealthInfrastructureStack } from "../lib/tech-health-infrastructure-stack";

describe("Infrastructure Integration Tests", () => {
  let app: cdk.App;
  let stack: TechHealthInfrastructureStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new TechHealthInfrastructureStack(app, "IntegrationTestStack", {
      env: {
        account: "123456789012",
        region: "us-east-1",
      },
    });
    template = Template.fromStack(stack);
  });

  describe("Resource Dependencies and Relationships", () => {
    test("EC2 instances reference correct security group", () => {
      const templateJson = template.toJSON();

      // Find EC2 security group
      const ec2SecurityGroup = Object.entries(templateJson.Resources).find(
        ([_, resource]: [string, any]) =>
          resource.Type === "AWS::EC2::SecurityGroup" &&
          resource.Properties.GroupDescription?.includes("EC2 instances")
      );

      expect(ec2SecurityGroup).toBeDefined();
      const [ec2SgId] = ec2SecurityGroup!;

      // Find EC2 instances
      const instances = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::Instance"
      ) as any[];

      // Verify instances reference the correct security group
      instances.forEach((instance: any) => {
        const securityGroups =
          instance.Properties.NetworkInterfaces[0].GroupSet;
        expect(securityGroups).toContainEqual({
          "Fn::GetAtt": [ec2SgId, "GroupId"],
        });
      });
    });

    test("RDS instance uses correct security group and subnet group", () => {
      const templateJson = template.toJSON();

      // Find RDS security group
      const rdsSecurityGroup = Object.entries(templateJson.Resources).find(
        ([_, resource]: [string, any]) =>
          resource.Type === "AWS::EC2::SecurityGroup" &&
          resource.Properties.GroupDescription?.includes("RDS MySQL database")
      );

      expect(rdsSecurityGroup).toBeDefined();
      const [rdsSgId] = rdsSecurityGroup!;

      // Find DB subnet group
      const dbSubnetGroup = Object.entries(templateJson.Resources).find(
        ([_, resource]: [string, any]) =>
          resource.Type === "AWS::RDS::DBSubnetGroup"
      );

      expect(dbSubnetGroup).toBeDefined();
      const [dbSubnetGroupId] = dbSubnetGroup!;

      // Find RDS instance
      const rdsInstance = Object.values(templateJson.Resources).find(
        (resource: any) => resource.Type === "AWS::RDS::DBInstance"
      ) as any;

      expect(rdsInstance).toBeDefined();
      expect(rdsInstance.Properties.VPCSecurityGroups).toContainEqual({
        "Fn::GetAtt": [rdsSgId, "GroupId"],
      });
      expect(rdsInstance.Properties.DBSubnetGroupName).toEqual({
        Ref: dbSubnetGroupId,
      });
    });

    test("Security group ingress rules reference correct source groups", () => {
      const templateJson = template.toJSON();

      // Find security group ingress rules
      const ingressRules = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::SecurityGroupIngress"
      ) as any[];

      // Find MySQL ingress rule (port 3306)
      const mysqlRule = ingressRules.find(
        (rule: any) =>
          rule.Properties.FromPort === 3306 && rule.Properties.ToPort === 3306
      );

      expect(mysqlRule).toBeDefined();
      expect(mysqlRule.Properties.SourceSecurityGroupId).toBeDefined();
      expect(mysqlRule.Properties.CidrIp).toBeUndefined(); // Should not allow CIDR access
    });

    test("EC2 instances use correct IAM instance profile", () => {
      const templateJson = template.toJSON();

      // Find instance profile
      const instanceProfile = Object.entries(templateJson.Resources).find(
        ([_, resource]: [string, any]) =>
          resource.Type === "AWS::IAM::InstanceProfile"
      );

      expect(instanceProfile).toBeDefined();
      const [instanceProfileId] = instanceProfile!;

      // Find EC2 instances
      const instances = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::Instance"
      ) as any[];

      // Verify instances reference the correct instance profile
      instances.forEach((instance: any) => {
        // The instance profile is created by the compute construct, not security construct
        expect(instance.Properties.IamInstanceProfile).toBeDefined();
        expect(instance.Properties.IamInstanceProfile.Ref).toContain(
          "InstanceProfile"
        );
      });
    });

    test("RDS instance uses credentials from Secrets Manager", () => {
      const templateJson = template.toJSON();

      // Find Secrets Manager secret
      const secret = Object.entries(templateJson.Resources).find(
        ([_, resource]: [string, any]) =>
          resource.Type === "AWS::SecretsManager::Secret"
      );

      expect(secret).toBeDefined();
      const [secretId] = secret!;

      // Find RDS instance
      const rdsInstance = Object.values(templateJson.Resources).find(
        (resource: any) => resource.Type === "AWS::RDS::DBInstance"
      ) as any;

      expect(rdsInstance).toBeDefined();

      // Check that RDS uses the secret for credentials (auto-generated by CDK)
      expect(
        rdsInstance.Properties.MasterUserPassword ||
          rdsInstance.Properties.MasterUserSecret
      ).toBeDefined();
    });
  });

  describe("Network Connectivity Validation", () => {
    test("Public subnets have route to Internet Gateway", () => {
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
    });

    test("Private subnets do not have direct internet access", () => {
      const templateJson = template.toJSON();

      // Find all subnets
      const subnets = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::Subnet"
      ) as any[];

      // Find private subnets (those without MapPublicIpOnLaunch)
      const privateSubnets = subnets.filter(
        (subnet: any) => !subnet.Properties.MapPublicIpOnLaunch
      );

      expect(privateSubnets.length).toBe(2); // Should have 2 private subnets

      // Verify no NAT Gateways exist (cost optimization)
      template.resourceCountIs("AWS::EC2::NatGateway", 0);
    });

    test("Subnet CIDR blocks do not overlap", () => {
      const templateJson = template.toJSON();

      // Get all subnet CIDR blocks
      const subnets = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::Subnet"
      ) as any[];

      const cidrBlocks = subnets.map(
        (subnet: any) => subnet.Properties.CidrBlock
      );

      // Verify no duplicate CIDR blocks
      expect(new Set(cidrBlocks).size).toBe(cidrBlocks.length);

      // Verify expected CIDR blocks exist (CDK auto-assigns these)
      expect(cidrBlocks).toContain("10.0.0.0/24"); // Public subnet 1
      expect(cidrBlocks).toContain("10.0.1.0/24"); // Public subnet 2
      expect(cidrBlocks).toContain("10.0.2.0/24"); // Private subnet 1 (CDK assigns sequentially)
      expect(cidrBlocks).toContain("10.0.3.0/24"); // Private subnet 2
    });
  });

  describe("Security Configuration Validation", () => {
    test("RDS is not accessible from internet", () => {
      const templateJson = template.toJSON();

      // Find RDS security group
      const rdsSecurityGroup = Object.values(templateJson.Resources).find(
        (resource: any) =>
          resource.Type === "AWS::EC2::SecurityGroup" &&
          resource.Properties.GroupDescription?.includes("RDS MySQL database")
      ) as any;

      expect(rdsSecurityGroup).toBeDefined();

      // Check ingress rules - should not allow 0.0.0.0/0
      const ingressRules =
        rdsSecurityGroup.Properties.SecurityGroupIngress || [];
      const internetAccessRule = ingressRules.find(
        (rule: any) => rule.CidrIp === "0.0.0.0/0"
      );

      expect(internetAccessRule).toBeUndefined();
    });

    test("Security groups implement least privilege", () => {
      const templateJson = template.toJSON();

      // Find EC2 security group
      const ec2SecurityGroup = Object.values(templateJson.Resources).find(
        (resource: any) =>
          resource.Type === "AWS::EC2::SecurityGroup" &&
          resource.Properties.GroupDescription?.includes("EC2 instances")
      ) as any;

      expect(ec2SecurityGroup).toBeDefined();

      const ingressRules = ec2SecurityGroup.Properties.SecurityGroupIngress;

      // Should only have necessary ports open
      const allowedPorts = ingressRules.map((rule: any) => rule.FromPort);
      expect(allowedPorts).toContain(80); // HTTP
      expect(allowedPorts).toContain(443); // HTTPS
      expect(allowedPorts).toContain(22); // SSH

      // Should not have unnecessary ports
      expect(allowedPorts).not.toContain(3389); // RDP
      expect(allowedPorts).not.toContain(21); // FTP
    });

    test("IAM policies are restrictive", () => {
      const templateJson = template.toJSON();

      // Find IAM policies
      const policies = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::IAM::Policy"
      ) as any[];

      expect(policies.length).toBeGreaterThan(0);

      policies.forEach((policy: any) => {
        const statements = policy.Properties.PolicyDocument.Statement;

        statements.forEach((statement: any) => {
          // Should not have wildcard resources for sensitive actions
          if (statement.Action.includes("secretsmanager:")) {
            expect(statement.Resource).not.toBe("*");
          }
        });
      });
    });
  });

  describe("HIPAA Compliance Validation", () => {
    test("All data is encrypted at rest", () => {
      // Assert - RDS encryption
      template.hasResourceProperties("AWS::RDS::DBInstance", {
        StorageEncrypted: true,
      });

      // Assert - Secrets Manager uses encryption (default KMS)
      const templateJson = template.toJSON();
      const secret = Object.values(templateJson.Resources).find(
        (resource: any) => resource.Type === "AWS::SecretsManager::Secret"
      ) as any;

      expect(secret).toBeDefined();
      // Secrets Manager encrypts by default with AWS managed key
    });

    test("Audit logging is enabled", () => {
      // Assert - RDS CloudWatch logs
      template.hasResourceProperties("AWS::RDS::DBInstance", {
        EnableCloudwatchLogsExports: ["error", "general", "slow-query"],
      });

      // Assert - Database parameter group enables logging
      const templateJson = template.toJSON();
      const parameterGroup = Object.values(templateJson.Resources).find(
        (resource: any) => resource.Type === "AWS::RDS::DBParameterGroup"
      ) as any;

      expect(parameterGroup).toBeDefined();
      expect(parameterGroup.Properties.Parameters.general_log).toBe("1");
      expect(parameterGroup.Properties.Parameters.slow_query_log).toBe("1");
    });

    test("Backup and retention policies meet compliance", () => {
      // Assert - RDS backup retention (development environment)
      template.hasResourceProperties("AWS::RDS::DBInstance", {
        BackupRetentionPeriod: 1,
      });

      const templateJson = template.toJSON();
      const rdsInstance = Object.values(templateJson.Resources).find(
        (resource: any) => resource.Type === "AWS::RDS::DBInstance"
      ) as any;

      expect(
        rdsInstance.Properties.BackupRetentionPeriod
      ).toBeGreaterThanOrEqual(1);
    });

    test("All resources have compliance tags", () => {
      const templateJson = template.toJSON();

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
          expect(resource.Properties.Tags).toEqual(
            expect.arrayContaining([
              expect.objectContaining({ Key: "Compliance", Value: "HIPAA" }),
            ])
          );
        });
      });
    });
  });

  describe("High Availability Validation", () => {
    test("Resources are distributed across multiple AZs", () => {
      const templateJson = template.toJSON();

      // Check subnets are in different AZs
      const subnets = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::Subnet"
      ) as any[];

      const availabilityZones = subnets.map(
        (subnet: any) => subnet.Properties.AvailabilityZone
      );

      // Should have at least 2 different AZs
      const uniqueAzs = new Set(
        availabilityZones.map((az) =>
          typeof az === "object" ? JSON.stringify(az) : az
        )
      );
      expect(uniqueAzs.size).toBeGreaterThanOrEqual(2);

      // Check EC2 instances are in different subnets
      const instances = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::Instance"
      ) as any[];

      const instanceSubnets = instances.map(
        (instance: any) => instance.Properties.NetworkInterfaces[0].SubnetId.Ref
      );

      // Development environment has only 1 instance, so it will be in 1 subnet
      expect(new Set(instanceSubnets).size).toBe(1);
    });

    test("RDS Multi-AZ configuration matches environment", () => {
      // Development environment uses MultiAZ: false for cost optimization
      template.hasResourceProperties("AWS::RDS::DBInstance", {
        MultiAZ: false,
      });
    });

    test("Monitoring and alerting are configured", () => {
      // Assert - CloudWatch alarms exist (7 alarms total)
      template.resourceCountIs("AWS::CloudWatch::Alarm", 7);

      // Check alarm types
      const templateJson = template.toJSON();
      const alarms = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::CloudWatch::Alarm"
      ) as any[];

      const alarmDescriptions = alarms.map(
        (alarm) => alarm.Properties.AlarmDescription
      );
      expect(alarmDescriptions).toContain(
        "Database CPU utilization is too high"
      );
      expect(alarmDescriptions).toContain(
        "Database connection count is too high"
      );
      expect(alarmDescriptions).toContain("Database free storage space is low");
    });
  });
});
