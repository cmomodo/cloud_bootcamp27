import * as cdk from "aws-cdk-lib";
import { Construct } from "constructs";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as rds from "aws-cdk-lib/aws-rds";
import * as secretsmanager from "aws-cdk-lib/aws-secretsmanager";

interface RDSStackProps extends cdk.StackProps {
  vpc: ec2.Vpc;
}

export class RDSStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: RDSStackProps) {
    super(scope, id, props);

    // Create a Secrets Manager secret for the RDS instance
    const dbSecret = new secretsmanager.Secret(this, "RDSSecret", {
      generateSecretString: {
        secretStringTemplate: JSON.stringify({ username: "admin" }),
        generateStringKey: "password",
        excludePunctuation: true,
      },
    });

    // Create the RDS instance
    const rdsInstance = new rds.DatabaseInstance(this, "RDSInstance", {
      engine: rds.DatabaseInstanceEngine.mysql({
        version: rds.MysqlEngineVersion.VER_8_0,
      }),
      vpc: props.vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      },
      instanceType: ec2.InstanceType.of(
        ec2.InstanceClass.T3,
        ec2.InstanceSize.MICRO,
      ),
      allocatedStorage: 20,
      maxAllocatedStorage: 30,
      credentials: rds.Credentials.fromSecret(dbSecret),
      deletionProtection: false, // Only disabled for this exercise
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For cleanup in the exercise
    });

    // Output the RDS endpoint
    new cdk.CfnOutput(this, "DBEndpoint", {
      value: rdsInstance.dbInstanceEndpointAddress,
      description: "The endpoint of the RDS instance",
    });
  }
}
