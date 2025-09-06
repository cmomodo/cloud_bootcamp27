import * as cdk from "aws-cdk-lib";
import { Template } from "aws-cdk-lib/assertions";
import { NetworkingConstruct } from "../lib/constructs/networking-construct";

describe("NetworkingConstruct", () => {
  let app: cdk.App;
  let stack: cdk.Stack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new cdk.Stack(app, "TestStack");
  });

  test("VPC created with correct CIDR block", () => {
    // Arrange & Act
    new NetworkingConstruct(stack, "TestNetworking", {
      vpcCidr: "10.0.0.0/16",
    });

    template = Template.fromStack(stack);

    // Assert
    template.hasResourceProperties("AWS::EC2::VPC", {
      CidrBlock: "10.0.0.0/16",
      EnableDnsHostnames: true,
      EnableDnsSupport: true,
    });
  });

  test("Creates correct number of subnets", () => {
    // Arrange & Act
    new NetworkingConstruct(stack, "TestNetworking", {
      maxAzs: 2,
    });

    template = Template.fromStack(stack);

    // Assert - Should create 4 subnets (2 public, 2 private)
    template.resourceCountIs("AWS::EC2::Subnet", 4);
  });

  test("Public subnets have correct configuration", () => {
    // Arrange & Act
    new NetworkingConstruct(stack, "TestNetworking");

    template = Template.fromStack(stack);

    // Assert - Public subnets should have MapPublicIpOnLaunch set to true
    template.hasResourceProperties("AWS::EC2::Subnet", {
      MapPublicIpOnLaunch: true,
    });
  });

  test("Internet Gateway is created", () => {
    // Arrange & Act
    new NetworkingConstruct(stack, "TestNetworking");

    template = Template.fromStack(stack);

    // Assert
    template.resourceCountIs("AWS::EC2::InternetGateway", 1);
  });

  test("Route tables are configured correctly", () => {
    // Arrange & Act
    new NetworkingConstruct(stack, "TestNetworking");

    template = Template.fromStack(stack);

    // Assert - Should have route tables for public subnets
    template.hasResourceProperties("AWS::EC2::Route", {
      DestinationCidrBlock: "0.0.0.0/0",
    });
  });

  test("No NAT Gateways created for cost optimization", () => {
    // Arrange & Act
    new NetworkingConstruct(stack, "TestNetworking");

    template = Template.fromStack(stack);

    // Assert - Should not create NAT Gateways
    template.resourceCountIs("AWS::EC2::NatGateway", 0);
  });

  test("VPC has proper tags", () => {
    // Arrange & Act
    new NetworkingConstruct(stack, "TestNetworking");

    template = Template.fromStack(stack);

    // Assert - Check that VPC exists with basic properties
    template.hasResourceProperties("AWS::EC2::VPC", {
      CidrBlock: "10.0.0.0/16",
      EnableDnsHostnames: true,
      EnableDnsSupport: true,
    });

    // Check that tags are applied (they exist as an array)
    const templateJson = template.toJSON();
    const vpcResource = Object.values(templateJson.Resources).find(
      (resource: any) => resource.Type === "AWS::EC2::VPC"
    ) as any;

    expect(vpcResource.Properties.Tags).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ Key: "Name", Value: "TechHealth-VPC" }),
        expect.objectContaining({ Key: "Compliance", Value: "HIPAA" }),
      ])
    );
  });

  test("Outputs are created correctly", () => {
    // Arrange & Act
    new NetworkingConstruct(stack, "TestNetworking");

    template = Template.fromStack(stack);

    // Debug: Let's see what outputs are actually created
    const templateJson = template.toJSON();
    console.log("Outputs:", Object.keys(templateJson.Outputs || {}));

    // Assert - Check that we have the expected number of outputs
    expect(Object.keys(templateJson.Outputs || {}).length).toBe(5);
  });

  test("Internet Gateway is properly tagged", () => {
    // Arrange & Act
    new NetworkingConstruct(stack, "TestNetworking");

    template = Template.fromStack(stack);

    // Assert - Internet Gateway should exist
    template.resourceCountIs("AWS::EC2::InternetGateway", 1);

    // Check that Internet Gateway has proper tags
    const templateJson = template.toJSON();
    const igwResource = Object.values(templateJson.Resources).find(
      (resource: any) => resource.Type === "AWS::EC2::InternetGateway"
    ) as any;

    expect(igwResource.Properties.Tags).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Key: "Name",
          Value: "TechHealth-Internet-Gateway",
        }),
        expect.objectContaining({
          Key: "Purpose",
          Value: "Public-Internet-Access",
        }),
      ])
    );
  });

  test("Route tables are configured for internet access", () => {
    // Arrange & Act
    new NetworkingConstruct(stack, "TestNetworking");

    template = Template.fromStack(stack);

    // Assert - Should have routes to Internet Gateway for public subnets
    template.hasResourceProperties("AWS::EC2::Route", {
      DestinationCidrBlock: "0.0.0.0/0",
    });

    // Check that the route references an Internet Gateway
    const templateJson = template.toJSON();
    const routes = Object.values(templateJson.Resources).filter(
      (resource: any) => resource.Type === "AWS::EC2::Route"
    );

    const internetRoutes = routes.filter(
      (route: any) => route.Properties.DestinationCidrBlock === "0.0.0.0/0"
    );

    expect(internetRoutes.length).toBeGreaterThan(0);
    expect((internetRoutes[0] as any).Properties.GatewayId.Ref).toMatch(
      /.*IGW.*/
    );
  });

  test("Network validation methods work correctly", () => {
    // Arrange & Act
    const networking = new NetworkingConstruct(stack, "TestNetworking");

    // Assert - Validation should pass
    expect(() => networking.validateNetworkConfiguration()).not.toThrow();

    // Assert - Should have Internet Gateway ID
    expect(networking.getInternetGatewayId()).toBeDefined();

    // Assert - Should have correct subnet counts
    expect(networking.getSubnetIds(true).length).toBe(2); // 2 public subnets
    expect(networking.getSubnetIds(false).length).toBe(2); // 2 private subnets
  });

  test("CIDR blocks do not overlap and allow for expansion", () => {
    // Arrange & Act
    new NetworkingConstruct(stack, "TestNetworking", {
      vpcCidr: "10.0.0.0/16",
    });

    template = Template.fromStack(stack);

    // Assert - Check subnet CIDR blocks
    const templateJson = template.toJSON();
    const subnets = Object.values(templateJson.Resources).filter(
      (resource: any) => resource.Type === "AWS::EC2::Subnet"
    ) as any[];

    const cidrBlocks = subnets.map(
      (subnet: any) => subnet.Properties.CidrBlock
    );

    // Verify expected CIDR blocks
    expect(cidrBlocks).toContain("10.0.0.0/24"); // Public subnet 1
    expect(cidrBlocks).toContain("10.0.1.0/24"); // Public subnet 2
    expect(cidrBlocks).toContain("10.0.128.0/24"); // Private subnet 1
    expect(cidrBlocks).toContain("10.0.129.0/24"); // Private subnet 2

    // Verify no overlapping CIDR blocks
    expect(new Set(cidrBlocks).size).toBe(cidrBlocks.length);
  });

  test("Subnets are distributed across multiple availability zones", () => {
    // Arrange & Act
    new NetworkingConstruct(stack, "TestNetworking", {
      maxAzs: 2,
    });

    template = Template.fromStack(stack);

    // Assert - Check that subnets are in different AZs
    const templateJson = template.toJSON();
    const subnets = Object.values(templateJson.Resources).filter(
      (resource: any) => resource.Type === "AWS::EC2::Subnet"
    ) as any[];

    const availabilityZones = subnets.map(
      (subnet: any) => subnet.Properties.AvailabilityZone
    );

    // Should have subnets in at least 2 different AZs
    const uniqueAzs = new Set(
      availabilityZones.map((az) =>
        typeof az === "object" ? JSON.stringify(az) : az
      )
    );
    expect(uniqueAzs.size).toBeGreaterThanOrEqual(2);
  });

  test("Private subnets have no direct internet access", () => {
    // Arrange & Act
    new NetworkingConstruct(stack, "TestNetworking");

    template = Template.fromStack(stack);

    // Assert - Private subnets should not have MapPublicIpOnLaunch
    const templateJson = template.toJSON();
    const subnets = Object.values(templateJson.Resources).filter(
      (resource: any) => resource.Type === "AWS::EC2::Subnet"
    ) as any[];

    const privateSubnets = subnets.filter(
      (subnet: any) => !subnet.Properties.MapPublicIpOnLaunch
    );

    expect(privateSubnets.length).toBe(2); // Should have 2 private subnets
  });

  test("Route tables provide proper isolation", () => {
    // Arrange & Act
    new NetworkingConstruct(stack, "TestNetworking");

    template = Template.fromStack(stack);

    // Assert - Should have separate route tables for public and private subnets
    template.resourceCountIs("AWS::EC2::RouteTable", 4); // 2 public + 2 private

    // Check route table associations
    template.resourceCountIs("AWS::EC2::SubnetRouteTableAssociation", 4);
  });
});
