import * as cdk from "aws-cdk-lib";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import { Template } from "aws-cdk-lib/assertions";
import { DatabaseConstruct } from "../lib/constructs/database-construct";

describe("DatabaseConstruct", () => {
  let app: cdk.App;
  let stack: cdk.Stack;
  let vpc: ec2.Vpc;
  let securityGroup: ec2.SecurityGroup;
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
      description: "Test security group for RDS",
    });
  });

  test("Creates RDS MySQL instance with correct configuration", () => {
    // Arrange & Act
    new DatabaseConstruct(stack, "TestDatabase", {
      vpc: vpc,
      privateSubnets: vpc.isolatedSubnets,
      securityGroup: securityGroup,
    });

    template = Template.fromStack(stack);

    // Assert - Should create RDS instance
    template.hasResourceProperties("AWS::RDS::DBInstance", {
      Engine: "mysql",
      EngineVersion: "8.0.35",
      DBInstanceClass: "db.t3.micro",
      AllocatedStorage: "20",
      StorageType: "gp2",
      StorageEncrypted: true,
      MultiAZ: true,
      BackupRetentionPeriod: 7,
      DeletionProtection: false,
    });
  });

  test("Creates DB subnet group with correct configuration", () => {
    // Arrange & Act
    new DatabaseConstruct(stack, "TestDatabase", {
      vpc: vpc,
      privateSubnets: vpc.isolatedSubnets,
      securityGroup: securityGroup,
    });

    template = Template.fromStack(stack);

    // Assert - Should create DB subnet group
    template.hasResourceProperties("AWS::RDS::DBSubnetGroup", {
      DBSubnetGroupDescription:
        "Subnet group for TechHealth RDS MySQL database",
    });
  });

  test("Creates custom parameter group", () => {
    // Arrange & Act
    new DatabaseConstruct(stack, "TestDatabase", {
      vpc: vpc,
      privateSubnets: vpc.isolatedSubnets,
      securityGroup: securityGroup,
    });

    template = Template.fromStack(stack);

    // Assert - Should create parameter group
    template.hasResourceProperties("AWS::RDS::DBParameterGroup", {
      Description: "Custom parameter group for TechHealth MySQL database",
      Family: "mysql8.0",
      Parameters: {
        general_log: "1",
        slow_query_log: "1",
        character_set_server: "utf8mb4",
        collation_server: "utf8mb4_unicode_ci",
        log_bin_trust_function_creators: "1",
        long_query_time: "2",
        log_queries_not_using_indexes: "1",
        innodb_buffer_pool_size: "{DBInstanceClassMemory*3/4}",
        max_connections: "100",
        query_cache_type: "1",
        query_cache_size: "32M",
        local_infile: "0",
        skip_show_database: "1",
      },
    });
  });

  test("Creates custom option group", () => {
    // Arrange & Act
    new DatabaseConstruct(stack, "TestDatabase", {
      vpc: vpc,
      privateSubnets: vpc.isolatedSubnets,
      securityGroup: securityGroup,
    });

    template = Template.fromStack(stack);

    // Assert - Should create option group
    template.hasResourceProperties("AWS::RDS::OptionGroup", {
      OptionGroupDescription:
        "Custom option group for TechHealth MySQL database",
      EngineName: "mysql",
      MajorEngineVersion: "8.0",
    });
  });

  test("Creates CloudWatch alarms for monitoring", () => {
    // Arrange & Act
    new DatabaseConstruct(stack, "TestDatabase", {
      vpc: vpc,
      privateSubnets: vpc.isolatedSubnets,
      securityGroup: securityGroup,
    });

    template = Template.fromStack(stack);

    // Assert - Should create CloudWatch alarms
    template.resourceCountIs("AWS::CloudWatch::Alarm", 7); // Updated count for all alarms

    // Check specific alarms
    template.hasResourceProperties("AWS::CloudWatch::Alarm", {
      AlarmDescription: "Database CPU utilization is too high",
      Threshold: 80,
      ComparisonOperator: "GreaterThanThreshold",
    });

    template.hasResourceProperties("AWS::CloudWatch::Alarm", {
      AlarmDescription: "Database connection count is too high",
      Threshold: 80,
    });

    template.hasResourceProperties("AWS::CloudWatch::Alarm", {
      AlarmDescription: "Database free storage space is low",
      Threshold: 2147483648, // 2GB in bytes
      ComparisonOperator: "LessThanThreshold",
    });
  });

  test("Uses auto-generated credentials", () => {
    // Arrange & Act
    const database = new DatabaseConstruct(stack, "TestDatabase", {
      vpc: vpc,
      privateSubnets: vpc.isolatedSubnets,
      securityGroup: securityGroup,
    });

    template = Template.fromStack(stack);

    // Assert - Should have a secret reference
    expect(database.secret).toBeDefined();

    // Should create a secret for credentials
    template.resourceCountIs("AWS::SecretsManager::Secret", 1);
  });

  test("Validation methods work correctly", () => {
    // Arrange & Act
    const database = new DatabaseConstruct(stack, "TestDatabase", {
      vpc: vpc,
      privateSubnets: vpc.isolatedSubnets,
      securityGroup: securityGroup,
    });

    // Assert - Validation should pass
    expect(() => database.validateDatabaseConfiguration()).not.toThrow();

    // Assert - Should have correct connection information
    const connectionInfo = database.getDatabaseConnectionInfo();
    expect(connectionInfo.endpoint).toBeDefined();
    expect(typeof connectionInfo.port).toBe("number");
    expect(connectionInfo.instanceArn).toBeDefined();
  });
});
