import * as cdk from "aws-cdk-lib";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as iam from "aws-cdk-lib/aws-iam";
import { Template } from "aws-cdk-lib/assertions";
import { ComputeConstruct } from "../lib/constructs/compute-construct";

describe("ComputeConstruct", () => {
  let app: cdk.App;
  let stack: cdk.Stack;
  let vpc: ec2.Vpc;
  let securityGroup: ec2.SecurityGroup;
  let instanceProfile: iam.InstanceProfile;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new cdk.Stack(app, "TestStack");

    // Create test VPC
    vpc = new ec2.Vpc(stack, "TestVPC", {
      ipAddresses: ec2.IpAddresses.cidr("10.0.0.0/16"),
      maxAzs: 2,
    });

    // Create test security group
    securityGroup = new ec2.SecurityGroup(stack, "TestSecurityGroup", {
      vpc: vpc,
      description: "Test security group",
    });

    // Create test IAM role and instance profile
    const role = new iam.Role(stack, "TestRole", {
      assumedBy: new iam.ServicePrincipal("ec2.amazonaws.com"),
    });

    instanceProfile = new iam.InstanceProfile(stack, "TestInstanceProfile", {
      role: role,
    });
  });

  test("Creates EC2 instances with correct configuration", () => {
    // Arrange & Act
    new ComputeConstruct(stack, "TestCompute", {
      vpc: vpc,
      publicSubnets: vpc.publicSubnets,
      securityGroup: securityGroup,
      instanceProfile: instanceProfile,
    });

    template = Template.fromStack(stack);

    // Assert - Should create EC2 instances
    template.hasResourceProperties("AWS::EC2::Instance", {
      InstanceType: "t2.micro",
      IamInstanceProfile: {
        Ref: expect.stringMatching(/.*TestInstanceProfile.*/),
      },
    });
  });

  test("Creates correct number of instances", () => {
    // Arrange & Act
    new ComputeConstruct(stack, "TestCompute", {
      vpc: vpc,
      publicSubnets: vpc.publicSubnets,
      securityGroup: securityGroup,
      instanceProfile: instanceProfile,
      instanceCount: 2,
    });

    template = Template.fromStack(stack);

    // Assert - Should create 2 instances
    template.resourceCountIs("AWS::EC2::Instance", 2);
  });

  test("Instances have public IP addresses", () => {
    // Arrange & Act
    new ComputeConstruct(stack, "TestCompute", {
      vpc: vpc,
      publicSubnets: vpc.publicSubnets,
      securityGroup: securityGroup,
      instanceProfile: instanceProfile,
    });

    template = Template.fromStack(stack);

    // Assert - Instances should have public IP addresses
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
  });

  test("Uses Amazon Linux 2023 AMI", () => {
    // Arrange & Act
    new ComputeConstruct(stack, "TestCompute", {
      vpc: vpc,
      publicSubnets: vpc.publicSubnets,
      securityGroup: securityGroup,
      instanceProfile: instanceProfile,
    });

    template = Template.fromStack(stack);

    // Assert - Should use Amazon Linux 2023 AMI
    template.hasResourceProperties("AWS::EC2::Instance", {
      ImageId: {
        Ref: expect.stringMatching(/.*AmazonLinux2023.*/),
      },
    });
  });

  test("Creates key pair when specified", () => {
    // Arrange & Act
    new ComputeConstruct(stack, "TestCompute", {
      vpc: vpc,
      publicSubnets: vpc.publicSubnets,
      securityGroup: securityGroup,
      instanceProfile: instanceProfile,
      keyPairName: "test-keypair",
    });

    template = Template.fromStack(stack);

    // Assert - Should create key pair
    template.hasResourceProperties("AWS::EC2::KeyPair", {
      KeyName: "test-keypair",
      KeyType: "rsa",
      KeyFormat: "pem",
    });
  });

  test("Does not create key pair when not specified", () => {
    // Arrange & Act
    new ComputeConstruct(stack, "TestCompute", {
      vpc: vpc,
      publicSubnets: vpc.publicSubnets,
      securityGroup: securityGroup,
      instanceProfile: instanceProfile,
    });

    template = Template.fromStack(stack);

    // Assert - Should not create key pair
    template.resourceCountIs("AWS::EC2::KeyPair", 0);
  });

  test("Instances have proper tags", () => {
    // Arrange & Act
    new ComputeConstruct(stack, "TestCompute", {
      vpc: vpc,
      publicSubnets: vpc.publicSubnets,
      securityGroup: securityGroup,
      instanceProfile: instanceProfile,
    });

    template = Template.fromStack(stack);

    // Assert - Check that instances have HIPAA compliance tags
    const templateJson = template.toJSON();
    const instances = Object.values(templateJson.Resources).filter(
      (resource: any) => resource.Type === "AWS::EC2::Instance"
    ) as any[];

    expect(instances.length).toBeGreaterThan(0);

    instances.forEach((instance: any) => {
      expect(instance.Properties.Tags).toEqual(
        expect.arrayContaining([
          expect.objectContaining({ Key: "Compliance", Value: "HIPAA" }),
          expect.objectContaining({
            Key: "Purpose",
            Value: "Patient-Portal-WebServer",
          }),
        ])
      );
    });
  });

  test("Instances have user data script", () => {
    // Arrange & Act
    new ComputeConstruct(stack, "TestCompute", {
      vpc: vpc,
      publicSubnets: vpc.publicSubnets,
      securityGroup: securityGroup,
      instanceProfile: instanceProfile,
    });

    template = Template.fromStack(stack);

    // Assert - Instances should have user data
    template.hasResourceProperties("AWS::EC2::Instance", {
      UserData: expect.any(Object),
    });

    // Check that user data contains expected setup commands
    const templateJson = template.toJSON();
    const instance = Object.values(templateJson.Resources).find(
      (resource: any) => resource.Type === "AWS::EC2::Instance"
    ) as any;

    const userData = instance.Properties.UserData["Fn::Base64"]["Fn::Join"][1];
    const userDataScript = userData.join("");

    expect(userDataScript).toContain("yum update -y");
    expect(userDataScript).toContain("yum install -y httpd mysql jq aws-cli");
    expect(userDataScript).toContain("/opt/techhealth");
    expect(userDataScript).toContain("systemctl start httpd");
    expect(userDataScript).toContain("setup-database.sh");
    expect(userDataScript).toContain("db-health-check.sh");
  });

  test("Creates outputs for instance information", () => {
    // Arrange & Act
    new ComputeConstruct(stack, "TestCompute", {
      vpc: vpc,
      publicSubnets: vpc.publicSubnets,
      securityGroup: securityGroup,
      instanceProfile: instanceProfile,
      instanceCount: 2,
    });

    template = Template.fromStack(stack);

    // Assert - Check that outputs exist
    const templateJson = template.toJSON();
    const outputs = Object.keys(templateJson.Outputs || {});

    expect(outputs.some((name) => name.includes("EC2Instance1Id"))).toBe(true);
    expect(outputs.some((name) => name.includes("EC2Instance1PublicIp"))).toBe(
      true
    );
    expect(outputs.some((name) => name.includes("EC2Instance1PrivateIp"))).toBe(
      true
    );
    expect(outputs.some((name) => name.includes("EC2Instance2Id"))).toBe(true);
  });

  test("Validation methods work correctly", () => {
    // Arrange & Act
    const compute = new ComputeConstruct(stack, "TestCompute", {
      vpc: vpc,
      publicSubnets: vpc.publicSubnets,
      securityGroup: securityGroup,
      instanceProfile: instanceProfile,
      instanceCount: 2,
    });

    // Assert - Validation should pass
    expect(() => compute.validateComputeConfiguration()).not.toThrow();

    // Assert - Should have correct instance information
    expect(compute.getInstanceIds().length).toBe(2);
    expect(compute.getPublicIpAddresses().length).toBe(2);
    expect(compute.getPrivateIpAddresses().length).toBe(2);
  });

  test("Uses custom instance type when specified", () => {
    // Arrange & Act
    new ComputeConstruct(stack, "TestCompute", {
      vpc: vpc,
      publicSubnets: vpc.publicSubnets,
      securityGroup: securityGroup,
      instanceProfile: instanceProfile,
      instanceType: ec2.InstanceType.of(
        ec2.InstanceClass.T3,
        ec2.InstanceSize.SMALL
      ),
    });

    template = Template.fromStack(stack);

    // Assert - Should use specified instance type
    template.hasResourceProperties("AWS::EC2::Instance", {
      InstanceType: "t3.small",
    });
  });

  test("Enables detailed monitoring when specified", () => {
    // Arrange & Act
    new ComputeConstruct(stack, "TestCompute", {
      vpc: vpc,
      publicSubnets: vpc.publicSubnets,
      securityGroup: securityGroup,
      instanceProfile: instanceProfile,
      enableDetailedMonitoring: true,
    });

    template = Template.fromStack(stack);

    // Assert - Should enable detailed monitoring
    template.hasResourceProperties("AWS::EC2::Instance", {
      Monitoring: true,
    });
  });

  test("Distributes instances across availability zones", () => {
    // Arrange & Act
    new ComputeConstruct(stack, "TestCompute", {
      vpc: vpc,
      publicSubnets: vpc.publicSubnets,
      securityGroup: securityGroup,
      instanceProfile: instanceProfile,
      instanceCount: 2,
    });

    template = Template.fromStack(stack);

    // Assert - Instances should be in different subnets (different AZs)
    const templateJson = template.toJSON();
    const instances = Object.values(templateJson.Resources).filter(
      (resource: any) => resource.Type === "AWS::EC2::Instance"
    ) as any[];

    expect(instances.length).toBe(2);

    // Check that instances have different subnet references
    const subnetRefs = instances.map(
      (instance: any) => instance.Properties.NetworkInterfaces[0].SubnetId.Ref
    );

    expect(new Set(subnetRefs).size).toBe(2); // Should be in different subnets
  });

  test("User data includes database connectivity setup", () => {
    // Arrange & Act
    const compute = new ComputeConstruct(stack, "TestCompute", {
      vpc: vpc,
      publicSubnets: vpc.publicSubnets,
      securityGroup: securityGroup,
      instanceProfile: instanceProfile,
      databaseSecretName: "test-secret",
    });

    const userDataScript = compute.getUserDataScript();

    // Assert - Should include database setup components
    expect(userDataScript).toContain("setup-database.sh");
    expect(userDataScript).toContain("get_database_credentials");
    expect(userDataScript).toContain("test_database_connection");
    expect(userDataScript).toContain("db-health-check.sh");
    expect(userDataScript).toContain("secretsmanager get-secret-value");
    expect(userDataScript).toContain("test-secret");
  });

  test("Generates database endpoint configuration script", () => {
    // Arrange & Act
    const compute = new ComputeConstruct(stack, "TestCompute", {
      vpc: vpc,
      publicSubnets: vpc.publicSubnets,
      securityGroup: securityGroup,
      instanceProfile: instanceProfile,
    });

    const endpointScript = compute.generateDatabaseEndpointScript(
      "test-db-endpoint.amazonaws.com"
    );

    // Assert - Should include endpoint configuration
    expect(endpointScript).toContain("test-db-endpoint.amazonaws.com");
    expect(endpointScript).toContain("aws ssm send-command");
    expect(endpointScript).toContain("setup-database.sh");
    expect(endpointScript).toContain("DB_ENDPOINT");
  });

  test("User data includes health check API endpoint", () => {
    // Arrange & Act
    const compute = new ComputeConstruct(stack, "TestCompute", {
      vpc: vpc,
      publicSubnets: vpc.publicSubnets,
      securityGroup: securityGroup,
      instanceProfile: instanceProfile,
    });

    const userDataScript = compute.getUserDataScript();

    // Assert - Should include health check API
    expect(userDataScript).toContain("/var/www/html/api/health");
    expect(userDataScript).toContain("application/json");
    expect(userDataScript).toContain("database");
    expect(userDataScript).toContain("instance_id");
    expect(userDataScript).toContain("availability_zone");
  });

  test("Instances are properly configured for high availability", () => {
    // Arrange & Act
    new ComputeConstruct(stack, "TestCompute", {
      vpc: vpc,
      publicSubnets: vpc.publicSubnets,
      securityGroup: securityGroup,
      instanceProfile: instanceProfile,
      instanceCount: 2,
    });

    template = Template.fromStack(stack);

    // Assert - Instances should be distributed across AZs
    const templateJson = template.toJSON();
    const instances = Object.values(templateJson.Resources).filter(
      (resource: any) => resource.Type === "AWS::EC2::Instance"
    ) as any[];

    expect(instances.length).toBe(2);

    // Check that instances are in different subnets (different AZs)
    const subnetRefs = instances.map(
      (instance: any) => instance.Properties.NetworkInterfaces[0].SubnetId.Ref
    );
    expect(new Set(subnetRefs).size).toBe(2);
  });

  test("User data script includes security hardening", () => {
    // Arrange & Act
    const compute = new ComputeConstruct(stack, "TestCompute", {
      vpc: vpc,
      publicSubnets: vpc.publicSubnets,
      securityGroup: securityGroup,
      instanceProfile: instanceProfile,
    });

    const userDataScript = compute.getUserDataScript();

    // Assert - Should include security hardening steps
    expect(userDataScript).toContain("yum update -y"); // System updates
    expect(userDataScript).toContain("chmod 600"); // Secure file permissions
    expect(userDataScript).toContain("chown root:root"); // Proper ownership
    expect(userDataScript).toContain("systemctl enable httpd"); // Service management
  });

  test("Database connectivity validation is included", () => {
    // Arrange & Act
    const compute = new ComputeConstruct(stack, "TestCompute", {
      vpc: vpc,
      publicSubnets: vpc.publicSubnets,
      securityGroup: securityGroup,
      instanceProfile: instanceProfile,
      databaseSecretName: "test-secret",
    });

    const userDataScript = compute.getUserDataScript();

    // Assert - Should include database connectivity tests
    expect(userDataScript).toContain("test_database_connection");
    expect(userDataScript).toContain("mysql -h");
    expect(userDataScript).toContain("SELECT 1");
    expect(userDataScript).toContain("Connection successful");
  });

  test("CloudWatch agent is configured for monitoring", () => {
    // Arrange & Act
    const compute = new ComputeConstruct(stack, "TestCompute", {
      vpc: vpc,
      publicSubnets: vpc.publicSubnets,
      securityGroup: securityGroup,
      instanceProfile: instanceProfile,
      enableDetailedMonitoring: true,
    });

    const userDataScript = compute.getUserDataScript();

    // Assert - Should include CloudWatch agent setup
    expect(userDataScript).toContain("amazon-cloudwatch-agent");
    expect(userDataScript).toContain("/opt/aws/amazon-cloudwatch-agent");
    expect(userDataScript).toContain("cloudwatch-config.json");
  });

  test("Instance metadata service is configured securely", () => {
    // Arrange & Act
    new ComputeConstruct(stack, "TestCompute", {
      vpc: vpc,
      publicSubnets: vpc.publicSubnets,
      securityGroup: securityGroup,
      instanceProfile: instanceProfile,
    });

    template = Template.fromStack(stack);

    // Assert - Should configure IMDSv2 for security
    template.hasResourceProperties("AWS::EC2::Instance", {
      MetadataOptions: {
        HttpEndpoint: "enabled",
        HttpTokens: "required", // IMDSv2
        HttpPutResponseHopLimit: 1,
      },
    });
  });

  test("Compute validation catches configuration issues", () => {
    // Arrange & Act
    const compute = new ComputeConstruct(stack, "TestCompute", {
      vpc: vpc,
      publicSubnets: [], // Empty subnets array
      securityGroup: securityGroup,
      instanceProfile: instanceProfile,
    });

    // Assert - Should catch empty subnets configuration
    expect(() => compute.validateComputeConfiguration()).toThrow();
  });
});
