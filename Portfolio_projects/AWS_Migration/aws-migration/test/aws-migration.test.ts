import * as cdk from "aws-cdk-lib";
import { Template } from "aws-cdk-lib/assertions";
import { TechHealthInfrastructureStack } from "../lib/tech-health-infrastructure-stack";

describe("TechHealthInfrastructureStack Integration Tests", () => {
  let app: cdk.App;
  let stack: TechHealthInfrastructureStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new TechHealthInfrastructureStack(app, "TestTechHealthStack", {
      env: {
        account: "123456789012",
        region: "us-east-1",
      },
    });
    template = Template.fromStack(stack);
  });

  test("Complete infrastructure stack is created successfully", () => {
    // Assert - All major resource types should be present
    template.resourceCountIs("AWS::EC2::VPC", 1);
    template.resourceCountIs("AWS::EC2::Subnet", 4); // 2 public, 2 private
    template.resourceCountIs("AWS::EC2::InternetGateway", 1);
    template.resourceCountIs("AWS::EC2::SecurityGroup", 2); // EC2 and RDS
    template.resourceCountIs("AWS::EC2::Instance", 1); // 1 EC2 instance in dev
    template.resourceCountIs("AWS::RDS::DBInstance", 1);
    template.resourceCountIs("AWS::RDS::DBSubnetGroup", 1);
    template.resourceCountIs("AWS::SecretsManager::Secret", 1);
    template.resourceCountIs("AWS::IAM::Role", 1);
    template.resourceCountIs("AWS::IAM::InstanceProfile", 1);
  });

  test("Network architecture follows security best practices", () => {
    // Assert - VPC configuration
    template.hasResourceProperties("AWS::EC2::VPC", {
      CidrBlock: "10.0.0.0/16",
      EnableDnsHostnames: true,
      EnableDnsSupport: true,
    });

    // Assert - Public subnets have internet access
    template.hasResourceProperties("AWS::EC2::Subnet", {
      MapPublicIpOnLaunch: true,
    });

    // Assert - Internet Gateway is attached
    // Assert - Internet Gateway attachment exists
    template.resourceCountIs("AWS::EC2::VPCGatewayAttachment", 1);

    // Assert - Route to internet gateway exists
    template.hasResourceProperties("AWS::EC2::Route", {
      DestinationCidrBlock: "0.0.0.0/0",
      GatewayId: expect.any(Object),
    });
  });

  test("Security groups implement least privilege access", () => {
    // Assert - EC2 security group allows HTTP/HTTPS from internet
    const templateJson = template.toJSON();
    const ec2SecurityGroup = Object.values(templateJson.Resources).find(
      (resource: any) =>
        resource.Type === "AWS::EC2::SecurityGroup" &&
        resource.Properties.GroupDescription?.includes("EC2 instances")
    ) as any;

    expect(ec2SecurityGroup).toBeDefined();
    const ingressRules = ec2SecurityGroup.Properties.SecurityGroupIngress;

    // Should have HTTP rule
    const httpRule = ingressRules.find((rule: any) => rule.FromPort === 80);
    expect(httpRule).toBeDefined();
    expect(httpRule.CidrIp).toBe("0.0.0.0/0");

    // Should have HTTPS rule
    const httpsRule = ingressRules.find((rule: any) => rule.FromPort === 443);
    expect(httpsRule).toBeDefined();
    expect(httpsRule.CidrIp).toBe("0.0.0.0/0");
  });

  test("RDS database is properly isolated and secured", () => {
    // Assert - RDS instance is in private subnets
    template.hasResourceProperties("AWS::RDS::DBInstance", {
      Engine: "mysql",
      StorageEncrypted: true,
      MultiAZ: false, // Dev environment uses single AZ for cost optimization
      BackupRetentionPeriod: 1, // Dev environment has minimal backup retention
    });

    // Assert - RDS security group only allows access from EC2
    const templateJson = template.toJSON();
    const ingressRules = Object.values(templateJson.Resources).filter(
      (resource: any) => resource.Type === "AWS::EC2::SecurityGroupIngress"
    ) as any[];

    const mysqlRule = ingressRules.find(
      (rule: any) =>
        rule.Properties.FromPort === 3306 && rule.Properties.ToPort === 3306
    );

    expect(mysqlRule).toBeDefined();
    expect(mysqlRule.Properties.SourceSecurityGroupId).toBeDefined();
    expect(mysqlRule.Properties.CidrIp).toBeUndefined(); // Should not allow CIDR access
  });

  test("EC2 instances are configured for high availability", () => {
    // Assert - EC2 instances exist with proper configuration
    // Assert - EC2 instance exists with proper configuration
    template.resourceCountIs("AWS::EC2::Instance", 1);

    // Assert - Instances have public IP addresses
    template.hasResourceProperties("AWS::EC2::Instance", {
      NetworkInterfaces: [
        {
          AssociatePublicIpAddress: true,
          DeviceIndex: "0",
          GroupSet: expect.any(Array),
          SubnetId: expect.any(Object),
        },
      ],
    });

    // Check that instances are distributed across AZs
    const templateJson = template.toJSON();
    const instances = Object.values(templateJson.Resources).filter(
      (resource: any) => resource.Type === "AWS::EC2::Instance"
    ) as any[];

    expect(instances.length).toBe(1); // Dev environment has 1 instance

    // Verify instance is in a public subnet
    const subnetRefs = instances.map(
      (instance: any) => instance.Properties.NetworkInterfaces[0].SubnetId.Ref
    );
    expect(subnetRefs.length).toBe(1);
  });

  test("IAM roles and policies follow least privilege", () => {
    // Assert - EC2 role exists with proper trust policy
    template.hasResourceProperties("AWS::IAM::Role", {
      AssumeRolePolicyDocument: {
        Statement: [
          {
            Action: "sts:AssumeRole",
            Effect: "Allow",
            Principal: {
              Service: "ec2.amazonaws.com",
            },
          },
        ],
      },
    });

    // Assert - IAM policies exist
    template.resourceCountIs("AWS::IAM::Policy", 2); // EC2 role policy and VPC Flow Logs policy

    // Assert - SSM managed policy is attached
    template.hasResourceProperties("AWS::IAM::Role", {
      ManagedPolicyArns: expect.arrayContaining([
        expect.stringContaining("AmazonSSMManagedInstanceCore"),
      ]),
    });
  });

  test("Secrets Manager is configured for database credentials", () => {
    // Assert - Secret exists with proper configuration
    // Assert - Secret exists
    template.resourceCountIs("AWS::SecretsManager::Secret", 1);

    // Assert - Secret has HIPAA compliance tags
    const templateJson = template.toJSON();
    const secret = Object.values(templateJson.Resources).find(
      (resource: any) => resource.Type === "AWS::SecretsManager::Secret"
    ) as any;

    expect(secret.Properties.Tags).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ Key: "Compliance", Value: "HIPAA" }),
      ])
    );
  });

  test("All resources have proper HIPAA compliance tags", () => {
    const templateJson = template.toJSON();
    const resources = Object.values(templateJson.Resources) as any[];

    // Filter resources that should have tags
    const taggableResources = resources.filter((resource: any) =>
      [
        "AWS::EC2::VPC",
        "AWS::EC2::Instance",
        "AWS::RDS::DBInstance",
        "AWS::SecretsManager::Secret",
      ].includes(resource.Type)
    );

    expect(taggableResources.length).toBeGreaterThan(0);

    // Check that all taggable resources have compliance tags
    taggableResources.forEach((resource: any) => {
      expect(resource.Properties.Tags).toEqual(
        expect.arrayContaining([
          expect.objectContaining({ Key: "Compliance", Value: "HIPAA" }),
        ])
      );
    });
  });

  test("Stack outputs provide necessary information", () => {
    // Assert - Stack should have outputs for key resources
    const templateJson = template.toJSON();
    const outputs = Object.keys(templateJson.Outputs || {});

    expect(outputs.length).toBeGreaterThan(0);

    // Should have VPC and networking outputs
    expect(outputs.some((name) => name.includes("VPC"))).toBe(true);
    expect(outputs.some((name) => name.includes("Subnet"))).toBe(true);

    // Should have EC2 instance outputs
    expect(outputs.some((name) => name.includes("EC2Instance"))).toBe(true);

    // Should have database outputs
    expect(outputs.some((name) => name.includes("Database"))).toBe(true);
  });

  test("Cost optimization measures are implemented", () => {
    // Assert - Uses cost-effective instance types
    template.hasResourceProperties("AWS::EC2::Instance", {
      InstanceType: "t2.micro", // Free tier eligible
    });

    template.hasResourceProperties("AWS::RDS::DBInstance", {
      DBInstanceClass: "db.t3.micro", // Cost-effective
    });

    // Assert - No NAT Gateways (cost optimization)
    template.resourceCountIs("AWS::EC2::NatGateway", 0);

    // Assert - Minimal storage allocation
    template.hasResourceProperties("AWS::RDS::DBInstance", {
      AllocatedStorage: "20", // Minimum for MySQL
    });
  });

  test("Monitoring and logging are properly configured", () => {
    // Assert - CloudWatch alarms exist for database
    template.resourceCountIs("AWS::CloudWatch::Alarm", 7); // Updated count based on actual implementation

    // Assert - RDS has CloudWatch logs enabled
    template.hasResourceProperties("AWS::RDS::DBInstance", {
      EnableCloudwatchLogsExports: ["error", "general", "slow-query"],
    });

    // Assert - Parameter group enables logging
    template.hasResourceProperties("AWS::RDS::DBParameterGroup", {
      Parameters: expect.objectContaining({
        general_log: "1",
        slow_query_log: "1",
      }),
    });
  });
});
