import { Stack, StackProps, CfnOutput } from "aws-cdk-lib";
import { aws_ses as ses } from "aws-cdk-lib";
import { Construct } from "constructs";

export interface SesStackProps extends StackProps {
  readonly emailAddress?: string;
}

export class SesStack extends Stack {
  public readonly emailIdentity: ses.EmailIdentity;
  public readonly emailAddress: string;

  constructor(scope: Construct, id: string, props?: SesStackProps) {
    super(scope, id, props);

    const emailAddress = props?.emailAddress ?? "ceesay.ml@outlook.com";
    this.emailAddress = emailAddress;

    this.emailIdentity = new ses.EmailIdentity(this, "EmailIdentity", {
      identity: ses.Identity.email(emailAddress),
    });

    new CfnOutput(this, "SesEmailAddress", {
      value: emailAddress,
    });

    new CfnOutput(this, "SesEmailIdentityArn", {
      value: this.emailIdentity.emailIdentityArn,
    });

    new CfnOutput(this, "SesEmailIdentityName", {
      value: this.emailIdentity.emailIdentityName,
    });
  }
}
