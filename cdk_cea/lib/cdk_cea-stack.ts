import * as cdk from "aws-cdk-lib";
import { Construct } from "constructs";
import * as ec2 from "aws-cdk-lib/aws-ec2";

export class CdkCeaStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const vpc = new ec2.Vpc(this, "MyVpc", {
      maxAzs: 2,
      cidr: "10.0.0.0/16",
      subnetConfiguration: [
        {
          name: "Public",
          subnetType: ec2.SubnetType.PUBLIC,
          cidrMask: 24,
        },
        {
          name: "Private",
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
          cidrMask: 24,
        },
      ],
    });

    //create security group
    const securityGroup = new ec2.SecurityGroup(this, "EC2SecurityGroup", {
      vpc,
      description: "Allow SSH access from anywhere",
      allowAllOutbound: true,
    });
    securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(22),
      "Allow SSH access from anywhere",
    );

    //create EC2 instance
    const instance = new ec2.Instance(this, "EC2Instance", {
      vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PUBLIC, // placed inside subnet created earlier
      },
      instanceType: ec2.InstanceType.of(
        ec2.InstanceClass.T2,
        ec2.InstanceSize.MICRO,
      ),
      machineImage: ec2.MachineImage.latestAmazonLinux2(),
      securityGroup,
    });

    //name tag of ec2 instance.
    cdk.Tags.of(instance).add("Name", "MyCdkInstance");

    //EC2 into private instance
    const privateInstance = new ec2.Instance(this, "PrivateEC2Instance", {
      vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      },
      instanceType: ec2.InstanceType.of(
        ec2.InstanceClass.T2,
        ec2.InstanceSize.MICRO,
      ),
      machineImage: ec2.MachineImage.latestAmazonLinux2(),
      securityGroup,
    });

    //name off the private instance
    cdk.Tags.of(privateInstance).add("Name", "MyCdkPrivateInstance");

    //name off the public instance
    cdk.Tags.of(instance).add("Name", "MyCdkPublicInstance");

    new cdk.CfnOutput(this, "VpcId", {
      value: vpc.vpcId,
      description: "The ID of the VPC",
    });

    //output instance id
    new cdk.CfnOutput(this, "InstanceId", {
      value: instance.instanceId,
      description: "The ID of the EC2 instance",
    });
  }
}
