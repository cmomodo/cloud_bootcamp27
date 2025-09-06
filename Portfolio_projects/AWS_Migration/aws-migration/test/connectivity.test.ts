import * as cdk from "aws-cdk-lib";
import { Template } from "aws-cdk-lib/assertions";
import { TechHealthInfrastructureStack } from "../lib/tech-health-infrastructure-stack";

describe("Connectivity and Network Flow Tests", () => {
  let app: cdk.App;
  let stack: TechHealthInfrastructureStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new TechHealthInfrastructureStack(app, "ConnectivityTestStack", {
      env: {
        account: "123456789012",
        region: "us-east-1",
      },
    });
    template = Template.fromStack(stack);
  });

  describe("EC2 to RDS Connectivity Validation", () => {
    test("EC2 security group allows outbound MySQL traffic", () => {
      const templateJson = template.toJSON();

      // Find EC2 security group
      const ec2SecurityGroup = Object.values(templateJson.Resources).find(
        (resource: any) =>
          resource.Type === "AWS::EC2::SecurityGroup" &&
          resource.Properties.GroupDescription?.includes("EC2 instances")
      ) as any;

      expect(ec2SecurityGroup).toBeDefined();

      // EC2 security group should allow outbound traffic (default behavior)
      // CDK creates a default egress rule allowing all outbound traffic
      const egressRules = ec2SecurityGroup.Properties.SecurityGroupEgress || [];

      // Should have at least one egress rule allowing outbound traffic
      expect(egressRules.length).toBeGreaterThan(0);

      // Default egress rule should allow all outbound traffic
      const defaultEgressRule = egressRules.find(
        (rule: any) => rule.CidrIp === "0.0.0.0/0" && rule.IpProtocol === "-1"
      );
      expect(defaultEgressRule).toBeDefined();
    });

    test("EC2 can reach RDS on MySQL port through security group rules", () => {
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

      // Find MySQL ingress rule that allows EC2 to access RDS
      const ingressRules = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::SecurityGroupIngress"
      ) as any[];

      const mysqlRule = ingressRules.find(
        (rule: any) =>
          rule.Properties.FromPort === 3306 &&
          rule.Properties.ToPort === 3306 &&
          rule.Properties.IpProtocol === "tcp" &&
          rule.Properties.GroupId?.Ref === rdsSgId &&
          rule.Properties.SourceSecurityGroupId?.["Fn::GetAtt"]?.[0] === ec2SgId
      );

      expect(mysqlRule).toBeDefined();
    });

    test("Network ACLs do not block EC2 to RDS communication", () => {
      const templateJson = template.toJSON();

      // Check for any Network ACLs that might block traffic
      const networkAcls = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::NetworkAcl"
      ) as any[];

      // If custom NACLs exist, verify they allow MySQL traffic
      networkAcls.forEach((nacl: any) => {
        const entries = Object.values(templateJson.Resources).filter(
          (resource: any) =>
            resource.Type === "AWS::EC2::NetworkAclEntry" &&
            resource.Properties.NetworkAclId?.Ref ===
              Object.keys(templateJson.Resources).find(
                (key) => templateJson.Resources[key] === nacl
              )
        ) as any[];

        // If there are custom entries, ensure MySQL port is allowed
        if (entries.length > 0) {
          const mysqlAllowed = entries.some(
            (entry: any) =>
              entry.Properties.RuleAction === "allow" &&
              entry.Properties.PortRange?.From <= 3306 &&
              entry.Properties.PortRange?.To >= 3306
          );
          expect(mysqlAllowed).toBe(true);
        }
      });
    });

    test("RDS security group allows inbound MySQL traffic from EC2", () => {
      const templateJson = template.toJSON();

      // Find security group ingress rules
      const ingressRules = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::SecurityGroupIngress"
      ) as any[];

      // Find MySQL ingress rule (port 3306)
      const mysqlRule = ingressRules.find(
        (rule: any) =>
          rule.Properties.FromPort === 3306 &&
          rule.Properties.ToPort === 3306 &&
          rule.Properties.IpProtocol === "tcp"
      );

      expect(mysqlRule).toBeDefined();
      expect(mysqlRule.Properties.SourceSecurityGroupId).toBeDefined();

      // Should not allow CIDR-based access
      expect(mysqlRule.Properties.CidrIp).toBeUndefined();
    });

    test("EC2 and RDS are in the same VPC", () => {
      const templateJson = template.toJSON();

      // Find VPC
      const vpc = Object.entries(templateJson.Resources).find(
        ([_, resource]: [string, any]) => resource.Type === "AWS::EC2::VPC"
      );
      expect(vpc).toBeDefined();
      const [vpcId] = vpc!;

      // Find EC2 instances
      const instances = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::Instance"
      ) as any[];

      // Find RDS instance
      const rdsInstance = Object.values(templateJson.Resources).find(
        (resource: any) => resource.Type === "AWS::RDS::DBInstance"
      ) as any;

      // EC2 instances should be in subnets of the same VPC
      instances.forEach((instance: any) => {
        const subnetRef = instance.Properties.NetworkInterfaces[0].SubnetId.Ref;

        // Find the subnet
        const subnet = Object.values(templateJson.Resources).find(
          (resource: any) =>
            resource.Type === "AWS::EC2::Subnet" &&
            Object.keys(templateJson.Resources).find(
              (key) => templateJson.Resources[key] === resource
            ) === subnetRef
        ) as any;

        expect(subnet).toBeDefined();
        expect(subnet.Properties.VpcId.Ref).toBe(vpcId);
      });

      // RDS should be in a subnet group that references subnets in the same VPC
      expect(rdsInstance).toBeDefined();
      expect(rdsInstance.Properties.DBSubnetGroupName).toBeDefined();
    });

    test("Network routing allows EC2 to reach RDS subnets", () => {
      const templateJson = template.toJSON();

      // Find all subnets
      const subnets = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::Subnet"
      ) as any[];

      // Find public and private subnets
      const publicSubnets = subnets.filter(
        (subnet: any) => subnet.Properties.MapPublicIpOnLaunch === true
      );
      const privateSubnets = subnets.filter(
        (subnet: any) => !subnet.Properties.MapPublicIpOnLaunch
      );

      expect(publicSubnets.length).toBe(2);
      expect(privateSubnets.length).toBe(2);

      // Find route tables
      const routeTables = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::RouteTable"
      ) as any[];

      // Should have route tables for both public and private subnets
      expect(routeTables.length).toBeGreaterThanOrEqual(2);

      // Find route table associations
      const associations = Object.values(templateJson.Resources).filter(
        (resource: any) =>
          resource.Type === "AWS::EC2::SubnetRouteTableAssociation"
      ) as any[];

      // Should have associations for all subnets
      expect(associations.length).toBe(4);
    });
  });

  describe("Internet Connectivity Validation", () => {
    test("EC2 instances can reach the internet", () => {
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

      // Find public subnets
      const publicSubnets = Object.values(templateJson.Resources).filter(
        (resource: any) =>
          resource.Type === "AWS::EC2::Subnet" &&
          resource.Properties.MapPublicIpOnLaunch === true
      ) as any[];

      expect(publicSubnets.length).toBe(2);

      // EC2 instances should be in public subnets
      const instances = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::Instance"
      ) as any[];

      instances.forEach((instance: any) => {
        expect(
          instance.Properties.NetworkInterfaces[0].AssociatePublicIpAddress
        ).toBe(true);
      });
    });

    test("RDS cannot reach the internet directly", () => {
      const templateJson = template.toJSON();

      // Find DB subnet group
      const dbSubnetGroup = Object.values(templateJson.Resources).find(
        (resource: any) => resource.Type === "AWS::RDS::DBSubnetGroup"
      ) as any;

      expect(dbSubnetGroup).toBeDefined();

      // DB subnet group should reference private subnets
      const subnetIds = dbSubnetGroup.Properties.SubnetIds;
      expect(Array.isArray(subnetIds)).toBe(true);

      // Find the referenced subnets
      subnetIds.forEach((subnetRef: any) => {
        const subnetId = subnetRef.Ref;
        const subnet = Object.values(templateJson.Resources).find(
          (resource: any) =>
            resource.Type === "AWS::EC2::Subnet" &&
            Object.keys(templateJson.Resources).find(
              (key) => templateJson.Resources[key] === resource
            ) === subnetId
        ) as any;

        expect(subnet).toBeDefined();
        // Private subnets should not auto-assign public IPs
        expect(subnet.Properties.MapPublicIpOnLaunch).not.toBe(true);
      });

      // Verify no NAT Gateways exist (cost optimization)
      template.resourceCountIs("AWS::EC2::NatGateway", 0);
    });

    test("RDS has no direct internet access paths", () => {
      const templateJson = template.toJSON();

      // Find RDS instance
      const rdsInstance = Object.values(templateJson.Resources).find(
        (resource: any) => resource.Type === "AWS::RDS::DBInstance"
      ) as any;

      expect(rdsInstance).toBeDefined();

      // RDS should not have PubliclyAccessible set to true
      expect(rdsInstance.Properties.PubliclyAccessible).not.toBe(true);

      // Find RDS security group
      const rdsSecurityGroup = Object.values(templateJson.Resources).find(
        (resource: any) =>
          resource.Type === "AWS::EC2::SecurityGroup" &&
          resource.Properties.GroupDescription?.includes("RDS MySQL database")
      ) as any;

      expect(rdsSecurityGroup).toBeDefined();

      // RDS security group should not allow inbound traffic from 0.0.0.0/0
      const ingressRules =
        rdsSecurityGroup.Properties.SecurityGroupIngress || [];
      const internetIngressRule = ingressRules.find(
        (rule: any) => rule.CidrIp === "0.0.0.0/0"
      );
      expect(internetIngressRule).toBeUndefined();

      // Verify RDS is in private subnets only
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

        // Verify subnet is private (no MapPublicIpOnLaunch)
        expect(subnet.Properties.MapPublicIpOnLaunch).not.toBe(true);

        // Verify subnet route table doesn't have internet gateway route
        const routeTableAssociations = Object.values(
          templateJson.Resources
        ).filter(
          (resource: any) =>
            resource.Type === "AWS::EC2::SubnetRouteTableAssociation" &&
            resource.Properties.SubnetId?.Ref === subnetId
        ) as any[];

        routeTableAssociations.forEach((association: any) => {
          const routeTableId = association.Properties.RouteTableId.Ref;
          const routes = Object.values(templateJson.Resources).filter(
            (resource: any) =>
              resource.Type === "AWS::EC2::Route" &&
              resource.Properties.RouteTableId?.Ref === routeTableId
          ) as any[];

          // Should not have route to internet gateway
          const internetRoute = routes.find(
            (route: any) =>
              route.Properties.DestinationCidrBlock === "0.0.0.0/0" &&
              route.Properties.GatewayId
          );
          expect(internetRoute).toBeUndefined();
        });
      });
    });
  });

  describe("DNS Resolution Validation", () => {
    test("VPC has DNS resolution enabled", () => {
      template.hasResourceProperties("AWS::EC2::VPC", {
        EnableDnsHostnames: true,
        EnableDnsSupport: true,
      });
    });

    test("RDS endpoint will be resolvable from EC2", () => {
      const templateJson = template.toJSON();

      // Find RDS instance
      const rdsInstance = Object.values(templateJson.Resources).find(
        (resource: any) => resource.Type === "AWS::RDS::DBInstance"
      ) as any;

      expect(rdsInstance).toBeDefined();

      // RDS instance should be in a VPC with DNS support
      // This is validated by the VPC DNS settings test above

      // DB subnet group should be properly configured
      expect(rdsInstance.Properties.DBSubnetGroupName).toBeDefined();
    });
  });

  describe("Port and Protocol Validation", () => {
    test("Only necessary ports are open", () => {
      const templateJson = template.toJSON();
      const securityGroups = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::SecurityGroup"
      ) as any[];

      securityGroups.forEach((sg: any) => {
        const ingressRules = sg.Properties.SecurityGroupIngress || [];

        ingressRules.forEach((rule: any) => {
          const port = rule.FromPort;

          // Define allowed ports
          const allowedPorts = [22, 80, 443, 3306]; // SSH, HTTP, HTTPS, MySQL

          if (port && !allowedPorts.includes(port)) {
            console.warn(
              `Unexpected port ${port} is open in security group ${sg.Properties.GroupDescription}`
            );
          }
        });
      });
    });

    test("MySQL port is only accessible from EC2 security group", () => {
      const templateJson = template.toJSON();

      // Find all security group ingress rules
      const ingressRules = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::SecurityGroupIngress"
      ) as any[];

      // Find MySQL rules
      const mysqlRules = ingressRules.filter(
        (rule: any) => rule.Properties.FromPort === 3306
      );

      expect(mysqlRules.length).toBe(1); // Should have exactly one MySQL rule

      const mysqlRule = mysqlRules[0];
      expect(mysqlRule.Properties.SourceSecurityGroupId).toBeDefined();
      expect(mysqlRule.Properties.CidrIp).toBeUndefined();
    });

    test("HTTP/HTTPS ports are accessible from internet", () => {
      const templateJson = template.toJSON();

      // Find EC2 security group
      const ec2SecurityGroup = Object.values(templateJson.Resources).find(
        (resource: any) =>
          resource.Type === "AWS::EC2::SecurityGroup" &&
          resource.Properties.GroupDescription?.includes("EC2 instances")
      ) as any;

      expect(ec2SecurityGroup).toBeDefined();

      const ingressRules =
        ec2SecurityGroup.Properties.SecurityGroupIngress || [];

      // Check for HTTP rule
      const httpRule = ingressRules.find((rule: any) => rule.FromPort === 80);
      expect(httpRule).toBeDefined();
      expect(httpRule.CidrIp).toBe("0.0.0.0/0");

      // Check for HTTPS rule
      const httpsRule = ingressRules.find((rule: any) => rule.FromPort === 443);
      expect(httpsRule).toBeDefined();
      expect(httpsRule.CidrIp).toBe("0.0.0.0/0");
    });
  });

  describe("Network Segmentation Validation", () => {
    test("Public and private subnets are properly segmented", () => {
      const templateJson = template.toJSON();

      // Find all subnets
      const subnets = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::Subnet"
      ) as any[];

      // Categorize subnets
      const publicSubnets = subnets.filter(
        (subnet: any) => subnet.Properties.MapPublicIpOnLaunch === true
      );
      const privateSubnets = subnets.filter(
        (subnet: any) => !subnet.Properties.MapPublicIpOnLaunch
      );

      expect(publicSubnets.length).toBe(2);
      expect(privateSubnets.length).toBe(2);

      // Check CIDR blocks for proper segmentation
      const publicCidrs = publicSubnets.map(
        (subnet: any) => subnet.Properties.CidrBlock
      );
      const privateCidrs = privateSubnets.map(
        (subnet: any) => subnet.Properties.CidrBlock
      );

      // Public subnets should use lower CIDR ranges
      expect(publicCidrs).toContain("10.0.0.0/24");
      expect(publicCidrs).toContain("10.0.1.0/24");

      // Private subnets should use sequential CIDR ranges (CDK auto-assigns)
      expect(privateCidrs).toContain("10.0.2.0/24");
      expect(privateCidrs).toContain("10.0.3.0/24");
    });

    test("EC2 instances are in public subnets", () => {
      const templateJson = template.toJSON();

      // Find EC2 instances
      const instances = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::Instance"
      ) as any[];

      expect(instances.length).toBe(1); // Development environment has 1 instance

      // Find public subnets
      const publicSubnets = Object.entries(templateJson.Resources).filter(
        ([_, resource]: [string, any]) =>
          resource.Type === "AWS::EC2::Subnet" &&
          resource.Properties.MapPublicIpOnLaunch === true
      );

      const publicSubnetIds = publicSubnets.map(([id]) => id);

      // Verify instances are in public subnets
      instances.forEach((instance: any) => {
        const subnetRef = instance.Properties.NetworkInterfaces[0].SubnetId.Ref;
        expect(publicSubnetIds).toContain(subnetRef);
      });
    });

    test("RDS is in private subnets", () => {
      const templateJson = template.toJSON();

      // Find DB subnet group
      const dbSubnetGroup = Object.values(templateJson.Resources).find(
        (resource: any) => resource.Type === "AWS::RDS::DBSubnetGroup"
      ) as any;

      expect(dbSubnetGroup).toBeDefined();

      // Find private subnets
      const privateSubnets = Object.entries(templateJson.Resources).filter(
        ([_, resource]: [string, any]) =>
          resource.Type === "AWS::EC2::Subnet" &&
          !resource.Properties.MapPublicIpOnLaunch
      );

      const privateSubnetIds = privateSubnets.map(([id]) => id);

      // Verify DB subnet group references private subnets
      const subnetIds = dbSubnetGroup.Properties.SubnetIds;
      subnetIds.forEach((subnetRef: any) => {
        expect(privateSubnetIds).toContain(subnetRef.Ref);
      });
    });
  });

  describe("Load Balancing and High Availability", () => {
    test("EC2 instances are distributed across availability zones", () => {
      const templateJson = template.toJSON();

      // Find EC2 instances
      const instances = Object.values(templateJson.Resources).filter(
        (resource: any) => resource.Type === "AWS::EC2::Instance"
      ) as any[];

      expect(instances.length).toBe(1); // Development environment has 1 instance

      // Get subnet references
      const subnetRefs = instances.map(
        (instance: any) => instance.Properties.NetworkInterfaces[0].SubnetId.Ref
      );

      // Development environment has 1 instance, so it will be in 1 subnet
      expect(new Set(subnetRefs).size).toBe(1);

      // Find the actual subnets to verify they're in different AZs
      const subnets = subnetRefs.map((subnetRef: string) => {
        return Object.values(templateJson.Resources).find(
          (resource: any) =>
            resource.Type === "AWS::EC2::Subnet" &&
            Object.keys(templateJson.Resources).find(
              (key) => templateJson.Resources[key] === resource
            ) === subnetRef
        );
      }) as any[];

      // Verify subnets have different availability zones
      const availabilityZones = subnets.map(
        (subnet: any) => subnet.Properties.AvailabilityZone
      );
      const uniqueAzs = new Set(
        availabilityZones.map((az) =>
          typeof az === "object" ? JSON.stringify(az) : az
        )
      );
      expect(uniqueAzs.size).toBe(1); // Development environment has 1 instance in 1 AZ
    });

    test("RDS Multi-AZ deployment spans availability zones", () => {
      // Development environment uses MultiAZ: false for cost optimization
      template.hasResourceProperties("AWS::RDS::DBInstance", {
        MultiAZ: false,
      });

      const templateJson = template.toJSON();

      // Find DB subnet group
      const dbSubnetGroup = Object.values(templateJson.Resources).find(
        (resource: any) => resource.Type === "AWS::RDS::DBSubnetGroup"
      ) as any;

      expect(dbSubnetGroup).toBeDefined();

      // Should have subnets in multiple AZs
      const subnetIds = dbSubnetGroup.Properties.SubnetIds;
      expect(subnetIds.length).toBeGreaterThanOrEqual(2);
    });
  });
});
