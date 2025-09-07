import { Stack, StackProps, aws_sns as sns } from "aws-cdk-lib";
import { Construct } from "constructs";

export class SnsStack extends Stack {
  public readonly topic: sns.Topic;

  constructor(scope: Construct, id: string, props?: StackProps) {
    super(scope, id, props);

    this.topic = new sns.Topic(this, "MyTopic", {
      displayName: "My CDK SNS Topic",
    });
  }
}
