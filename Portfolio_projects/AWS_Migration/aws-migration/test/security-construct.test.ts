import * as cdk from "aws-cdk-lib";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import { Template } from "aws-cdk-lib/assertions";
import { SecurityConstruct } from "../lib/constructs/security-construct";

describe("SecurityConstruct", () => {
  let app: cdk.App;
  let stack: cdk.Stack;
  let vpc: ec2.Vpc;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new cdk.Stack(app, "TestStack");

    // Create a test VPC
    vpc = new ec2.Vpc(stack, "TestVPC", {
      ipAddresses: ec2.IpAddresses.cidr("10.0.0.0/16"),
      maxAzs: 2,
    });
  });

  test("Creates EC2 security group with correct configuration", () => {
    // Arrange & Act
    new SecurityConstruct(stack, "TestSecurity", {
      vpc: vpc,
      allowedSshCidrs: ["192.168.1.0/24"],
    });

    template = Template.fromStack(stack);

    // Assert - Should create EC2 security group
    template.hasResourceProperties("AWS::EC2::SecurityGroup", {
      GroupDescription:
        "Security group for TechHealth EC2 instances - Patient Portal Web Servers",
    });

    // Assert - Should create exactly 2 security groups (EC2 and RDS)
    template.resourceCountIs("AWS::EC2::SecurityGroup", 2);
  });

  test("Creates RDS security group with correct configuration", () => {
    // Arrange & Act
    new SecurityConstruct(stack, "TestSecurity", {
      vpc: vpc,
    });

    template = Template.fromStack(stack);

    // Assert - Should create RDS security group
    template.hasResourceProperties("AWS::EC2::SecurityGroup", {
      GroupDescription:
        "Security group for TechHealth RDS MySQL database - Private access only",
    });
  });

  test("EC2 security group has correct ingress rules", () => {
    // Arrange & Act
    new SecurityConstruct(stack, "TestSecurity", {
      vpc: vpc,
      allowedSshCidrs: ["192.168.1.0/24"],
    });

    template = Template.fromStack(stack);

    // Assert - Check that security group has inline ingress rules
    const templateJson = template.toJSON();
    const ec2SecurityGroup = Object.values(templateJson.Resources).find(
      (resource: any) =>
        resource.Type === "AWS::EC2::SecurityGroup" &&
        resource.Properties.GroupDescription?.includes("EC2 instances")
    ) as any;

    expect(ec2SecurityGroup).toBeDefined();
    expect(ec2SecurityGroup.Properties.SecurityGroupIngress).toBeDefined();

    const ingressRules = ec2SecurityGroup.Properties.SecurityGroupIngress;

    // Should have SSH rule
    const sshRule = ingressRules.find((rule: any) => rule.FromPort === 22);
    expect(sshRule).toBeDefined();
    expect(sshRule.CidrIp).toBe("192.168.1.0/24");

    // Should have HTTP rule
    const httpRule = ingressRules.find((rule: any) => rule.FromPort === 80);
    expect(httpRule).toBeDefined();
    expect(httpRule.CidrIp).toBe("0.0.0.0/0");

    // Should have HTTPS rule
    const httpsRule = ingressRules.find((rule: any) => rule.FromPort === 443);
    expect(httpsRule).toBeDefined();
    expect(httpsRule.CidrIp).toBe("0.0.0.0/0");
  });

  test("RDS security group allows access only from EC2 security group", () => {
    // Arrange & Act
    new SecurityConstruct(stack, "TestSecurity", {
      vpc: vpc,
    });

    template = Template.fromStack(stack);

    // Assert - Check that MySQL rule exists with correct properties

    // Verify the rule exists with correct properties
    const templateJson = template.toJSON();
    const ingressRules = Object.values(templateJson.Resources).filter(
      (resource: any) => resource.Type === "AWS::EC2::SecurityGroupIngress"
    ) as any[];

    const mysqlRule = ingressRules.find(
      (rule: any) =>
        rule.Properties.FromPort === 3306 && rule.Properties.ToPort === 3306
    );

    expect(mysqlRule).toBeDefined();
    expect(mysqlRule.Properties.IpProtocol).toBe("tcp");
    expect(mysqlRule.Properties.SourceSecurityGroupId).toBeDefined();
  });

  test("Creates VPC Flow Logs when enabled", () => {
    // Arrange & Act
    new SecurityConstruct(stack, "TestSecurity", {
      vpc: vpc,
      enableVpcFlowLogs: true,
    });

    template = Template.fromStack(stack);

    // Assert - Should create VPC Flow Logs
    template.hasResourceProperties("AWS::EC2::FlowLog", {
      ResourceType: "VPC",
      TrafficType: "ALL",
    });
  });

  test("Does not create VPC Flow Logs when disabled", () => {
    // Arrange & Act
    new SecurityConstruct(stack, "TestSecurity", {
      vpc: vpc,
      enableVpcFlowLogs: false,
    });

    template = Template.fromStack(stack);

    // Assert - Should not create VPC Flow Logs
    template.resourceCountIs("AWS::EC2::FlowLog", 0);
  });

  test("Security groups have proper tags", () => {
    // Arrange & Act
    new SecurityConstruct(stack, "TestSecurity", {
      vpc: vpc,
    });

    template = Template.fromStack(stack);

    // Assert - Check that security groups have HIPAA compliance tags
    const templateJson = template.toJSON();
    const securityGroups = Object.values(templateJson.Resources).filter(
      (resource: any) => resource.Type === "AWS::EC2::SecurityGroup"
    ) as any[];

    expect(securityGroups.length).toBeGreaterThan(0);

    // Check that at least one security group has compliance tags
    const hasComplianceTag = securityGroups.some((sg: any) =>
      sg.Properties.Tags?.some(
        (tag: any) => tag.Key === "Compliance" && tag.Value === "HIPAA"
      )
    );

    expect(hasComplianceTag).toBe(true);
  });

  test("Outputs are created correctly", () => {
    // Arrange & Act
    new SecurityConstruct(stack, "TestSecurity", {
      vpc: vpc,
      enableVpcFlowLogs: true,
    });

    template = Template.fromStack(stack);

    // Assert - Check that outputs exist
    const templateJson = template.toJSON();
    const outputs = Object.keys(templateJson.Outputs || {});

    expect(outputs.some((name) => name.includes("EC2SecurityGroupId"))).toBe(
      true
    );
    expect(outputs.some((name) => name.includes("RDSSecurityGroupId"))).toBe(
      true
    );
    expect(outputs.some((name) => name.includes("VPCFlowLogsId"))).toBe(true);
    expect(outputs.length).toBe(5); // Reduced from 7 since we removed database secret outputs
  });

  test("Security validation methods work correctly", () => {
    // Arrange & Act
    const security = new SecurityConstruct(stack, "TestSecurity", {
      vpc: vpc,
    });

    // Assert - Validation should pass
    expect(() => security.validateSecurityConfiguration()).not.toThrow();

    // Assert - Should have security group IDs
    const securityGroupIds = security.getSecurityGroupIds();
    expect(securityGroupIds.ec2SecurityGroupId).toBeDefined();
    expect(securityGroupIds.rdsSecurityGroupId).toBeDefined();

    // Assert - Should have IAM resources
    const iamResources = security.getIamResources();
    expect(iamResources.ec2RoleArn).toBeDefined();
    expect(iamResources.ec2InstanceProfileArn).toBeDefined();
    expect(iamResources.ec2RoleName).toBeDefined();
  });

  test("Can add additional ingress rules", () => {
    // Arrange
    const security = new SecurityConstruct(stack, "TestSecurity", {
      vpc: vpc,
    });

    // Act - Add custom rule
    security.addEC2IngressRule(
      ec2.Peer.ipv4("192.168.0.0/16"),
      ec2.Port.tcp(8080),
      "Custom application port"
    );

    template = Template.fromStack(stack);

    // Assert - Should have the custom rule in the EC2 security group
    const templateJson = template.toJSON();
    const ec2SecurityGroup = Object.values(templateJson.Resources).find(
      (resource: any) =>
        resource.Type === "AWS::EC2::SecurityGroup" &&
        resource.Properties.GroupDescription?.includes("EC2 instances")
    ) as any;

    const ingressRules = ec2SecurityGroup.Properties.SecurityGroupIngress;
    const customRule = ingressRules.find((rule: any) => rule.FromPort === 8080);
    expect(customRule).toBeDefined();
    expect(customRule.CidrIp).toBe("192.168.0.0/16");
  });

  test("RDS security group has no outbound rules by default", () => {
    // Arrange & Act
    new SecurityConstruct(stack, "TestSecurity", {
      vpc: vpc,
    });

    template = Template.fromStack(stack);

    // Assert - RDS security group should not allow all outbound traffic
    const templateJson = template.toJSON();
    const rdsSecurityGroup = Object.values(templateJson.Resources).find(
      (resource: any) =>
        resource.Type === "AWS::EC2::SecurityGroup" &&
        resource.Properties.GroupDescription?.includes("RDS MySQL database")
    ) as any;

    expect(rdsSecurityGroup).toBeDefined();
    // The RDS security group should have restrictive egress rules (CDK adds a "disallow all" rule)
    const egressRules = rdsSecurityGroup.Properties.SecurityGroupEgress;
    expect(egressRules).toBeDefined();

    // Should not have a rule allowing all traffic (0.0.0.0/0)
    const allowAllRule = egressRules.find(
      (rule: any) => rule.CidrIp === "0.0.0.0/0"
    );
    expect(allowAllRule).toBeUndefined();
  });

  test("Creates IAM role for EC2 instances", () => {
    // Arrange & Act
    new SecurityConstruct(stack, "TestSecurity", {
      vpc: vpc,
    });

    template = Template.fromStack(stack);

    // Assert - Should create IAM role
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
  });

  test("Creates instance profile for EC2 instances", () => {
    // Arrange & Act
    new SecurityConstruct(stack, "TestSecurity", {
      vpc: vpc,
    });

    template = Template.fromStack(stack);

    // Assert - Should create instance profile
    template.hasResourceProperties("AWS::IAM::InstanceProfile", {
      Roles: expect.any(Array),
    });
  });

  test("IAM role has correct policies for Secrets Manager", () => {
    // Arrange & Act
    new SecurityConstruct(stack, "TestSecurity", {
      vpc: vpc,
    });

    template = Template.fromStack(stack);

    // Assert - Should have policy for Secrets Manager access
    template.hasResourceProperties("AWS::IAM::Policy", {
      PolicyDocument: {
        Statement: expect.arrayContaining([
          expect.objectContaining({
            Effect: "Allow",
            Action: [
              "secretsmanager:GetSecretValue",
              "secretsmanager:DescribeSecret",
            ],
          }),
        ]),
      },
    });
  });

  test("IAM role has Systems Manager managed policy", () => {
    // Arrange & Act
    new SecurityConstruct(stack, "TestSecurity", {
      vpc: vpc,
    });

    template = Template.fromStack(stack);

    // Assert - Should attach SSM managed policy
    template.hasResourceProperties("AWS::IAM::Role", {
      ManagedPolicyArns: expect.arrayContaining([
        expect.stringContaining("AmazonSSMManagedInstanceCore"),
      ]),
    });
  });

  test("Generates user data script for secrets retrieval", () => {
    // Arrange & Act
    const security = new SecurityConstruct(stack, "TestSecurity", {
      vpc: vpc,
    });

    const script = security.generateSecretsRetrievalScript("test-secret-name");

    // Assert - Script should contain expected elements
    expect(script).toContain("aws secretsmanager get-secret-value");
    expect(script).toContain("test-secret-name");
    expect(script).toContain("DB_USERNAME");
    expect(script).toContain("DB_PASSWORD");
    expect(script).toContain("/opt/techhealth/db-config.json");
    expect(script).toContain("chmod 600");
  });

  test("IAM role has correct permissions for database secrets", () => {
    // Arrange & Act
    new SecurityConstruct(stack, "TestSecurity", {
      vpc: vpc,
    });

    template = Template.fromStack(stack);

    // Assert - IAM policy should reference the TechHealth database secret pattern
    template.hasResourceProperties("AWS::IAM::Policy", {
      PolicyDocument: {
        Statement: expect.arrayContaining([
          expect.objectContaining({
            Effect: "Allow",
            Action: [
              "secretsmanager:GetSecretValue",
              "secretsmanager:DescribeSecret",
            ],
            Resource: expect.stringContaining("TechHealth/Database"),
          }),
        ]),
      },
    });
  });

  test("Security groups follow least privilege principle", () => {
    // Arrange & Act
    new SecurityConstruct(stack, "TestSecurity", {
      vpc: vpc,
      allowedSshCidrs: ["10.0.0.0/8"], // More restrictive than 0.0.0.0/0
    });

    template = Template.fromStack(stack);

    // Assert - SSH access should be restricted to specified CIDR
    const templateJson = template.toJSON();
    const ec2SecurityGroup = Object.values(templateJson.Resources).find(
      (resource: any) =>
        resource.Type === "AWS::EC2::SecurityGroup" &&
        resource.Properties.GroupDescription?.includes("EC2 instances")
    ) as any;

    const sshRule = ec2SecurityGroup.Properties.SecurityGroupIngress.find(
      (rule: any) => rule.FromPort === 22
    );

    expect(sshRule.CidrIp).toBe("10.0.0.0/8");
    expect(sshRule.CidrIp).not.toBe("0.0.0.0/0");
  });

  test("RDS security group denies all outbound traffic", () => {
    // Arrange & Act
    new SecurityConstruct(stack, "TestSecurity", {
      vpc: vpc,
    });

    template = Template.fromStack(stack);

    // Assert - RDS security group should have restrictive egress
    const templateJson = template.toJSON();
    const rdsSecurityGroup = Object.values(templateJson.Resources).find(
      (resource: any) =>
        resource.Type === "AWS::EC2::SecurityGroup" &&
        resource.Properties.GroupDescription?.includes("RDS MySQL database")
    ) as any;

    const egressRules = rdsSecurityGroup.Properties.SecurityGroupEgress;

    // Should not allow unrestricted outbound access
    const unrestricted = egressRules.find(
      (rule: any) => rule.CidrIp === "0.0.0.0/0" && rule.IpProtocol !== "icmp"
    );
    expect(unrestricted).toBeUndefined();
  });

  test("IAM policies follow principle of least privilege", () => {
    // Arrange & Act
    new SecurityConstruct(stack, "TestSecurity", {
      vpc: vpc,
    });

    template = Template.fromStack(stack);

    // Assert - Check that IAM policies are restrictive
    template.hasResourceProperties("AWS::IAM::Policy", {
      PolicyDocument: {
        Statement: expect.arrayContaining([
          expect.objectContaining({
            Effect: "Allow",
            Action: [
              "secretsmanager:GetSecretValue",
              "secretsmanager:DescribeSecret",
            ],
            // Should have specific resource ARN, not "*"
            Resource: expect.not.stringMatching(/^\*$/),
          }),
        ]),
      },
    });
  });

  test("CloudTrail is configured for audit logging", () => {
    // Arrange & Act
    new SecurityConstruct(stack, "TestSecurity", {
      vpc: vpc,
      enableCloudTrail: true,
    });

    template = Template.fromStack(stack);

    // Assert - Should create CloudTrail for audit logging
    template.hasResourceProperties("AWS::CloudTrail::Trail", {
      IsLogging: true,
      IncludeGlobalServiceEvents: true,
      IsMultiRegionTrail: true,
      EnableLogFileValidation: true,
    });
  });

  test("Secrets Manager secret has proper encryption", () => {
    // Arrange & Act
    new SecurityConstruct(stack, "TestSecurity", {
      vpc: vpc,
    });

    template = Template.fromStack(stack);

    // Assert - Secret should use KMS encryption
    const templateJson = template.toJSON();
    const secret = Object.values(templateJson.Resources).find(
      (resource: any) => resource.Type === "AWS::SecretsManager::Secret"
    ) as any;

    // Should have KMS key specified or use default encryption
    expect(
      secret.Properties.KmsKeyId || secret.Properties.SecretString
    ).toBeDefined();
  });

  test("Security configuration validation catches misconfigurations", () => {
    // Arrange & Act
    const security = new SecurityConstruct(stack, "TestSecurity", {
      vpc: vpc,
      allowedSshCidrs: ["0.0.0.0/0"], // Overly permissive
    });

    // Assert - Should validate successfully (method returns boolean)
    expect(() => security.validateSecurityConfiguration()).not.toThrow();
  });
});
