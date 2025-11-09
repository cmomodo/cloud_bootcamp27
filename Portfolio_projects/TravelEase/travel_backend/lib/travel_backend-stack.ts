import {
  Duration,
  RemovalPolicy,
  Stack,
  StackProps,
  CfnOutput,
  SecretValue,
} from "aws-cdk-lib";
import { aws_apigatewayv2 as apigwv2 } from "aws-cdk-lib";
import { HttpLambdaIntegration } from "aws-cdk-lib/aws-apigatewayv2-integrations";
import { aws_dynamodb as dynamodb } from "aws-cdk-lib";
import { aws_iam as iam } from "aws-cdk-lib";
import { aws_lambda as lambda } from "aws-cdk-lib";
import { aws_sns as sns } from "aws-cdk-lib";
import { aws_sns_subscriptions as subscriptions } from "aws-cdk-lib";
import { aws_sqs as sqs } from "aws-cdk-lib";
import { aws_ses as ses } from "aws-cdk-lib";
import { aws_secretsmanager as secretsmanager } from "aws-cdk-lib";
import { Construct } from "constructs";
import * as path from "path";

export interface TravelBackendStackProps extends StackProps {
  readonly emailIdentity: ses.IEmailIdentity;
  readonly emailAddress: string;
  readonly notificationEmail?: string;
}

export class TravelBackendStack extends Stack {
  public readonly api: apigwv2.HttpApi;
  public readonly queue: sqs.Queue;
  public readonly table: dynamodb.Table;
  public readonly notificationTopic: sns.Topic;
  public readonly configurationSet: ses.CfnConfigurationSet;

  constructor(scope: Construct, id: string, props: TravelBackendStackProps) {
    super(scope, id, props);

    const notificationEmail = props.notificationEmail ?? props.emailAddress;

    this.table = new dynamodb.Table(this, "ContactFormSubmissions", {
      partitionKey: {
        name: "submission_id",
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: RemovalPolicy.DESTROY,
      tableName: "travelease-form",
      pointInTimeRecovery: true,
    });

    this.queue = new sqs.Queue(this, "TravelBackendQueue", {
      visibilityTimeout: Duration.minutes(5),
    });

    this.notificationTopic = new sns.Topic(this, "FormSubmissionTopic", {
      displayName: "TravelEase Form Notifications",
    });

    this.notificationTopic.addSubscription(
      new subscriptions.EmailSubscription(notificationEmail)
    );

    this.configurationSet = new ses.CfnConfigurationSet(
      this,
      "TravelEaseConfigSet",
      {
        name: "TravelEaseBounceConfig",
      }
    );

    new ses.CfnConfigurationSetEventDestination(
      this,
      "BounceEventDestination",
      {
        configurationSetName:
          this.configurationSet.name ?? this.configurationSet.ref,
        eventDestination: {
          name: "BounceAndComplaintNotifications",
          enabled: true,
          matchingEventTypes: ["BOUNCE", "COMPLAINT"],
          snsDestination: {
            topicArn: this.notificationTopic.topicArn,
          },
        },
      }
    );

    // Create secrets for sensitive data
    const emailSecret = new secretsmanager.Secret(this, "EmailSecrets", {
      description: "Email addresses for TravelEase contact form",
      secretObjectValue: {
        sourceEmail: SecretValue.unsafePlainText(props.emailAddress),
        ownerEmail: SecretValue.unsafePlainText(notificationEmail),
        businessEmail: SecretValue.unsafePlainText(notificationEmail),
      },
    });

    const formHandler = new lambda.Function(this, "ContactFormLambda", {
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: "app.lambda_handler",
      code: lambda.Code.fromAsset(path.join(__dirname, "../lambda")),
      timeout: Duration.seconds(30),
      environment: {
        TABLE_NAME: this.table.tableName,
        QUEUE_URL: this.queue.queueUrl,
        EMAIL_SECRET_ARN: emailSecret.secretArn,
        SNS_TOPIC_ARN: this.notificationTopic.topicArn,
        SES_CONFIGURATION_SET: this.configurationSet.ref,
      },
    });

    // Grant Lambda function permission to read the secret
    emailSecret.grantRead(formHandler);

    this.table.grantWriteData(formHandler);
    this.queue.grantSendMessages(formHandler);
    this.notificationTopic.grantPublish(formHandler);
    props.emailIdentity.grantSendEmail(formHandler);

    // Grant permission to use the SES configuration set
    formHandler.addToRolePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ["ses:SendEmail", "ses:SendRawEmail"],
        resources: [
          `arn:aws:ses:${this.region}:${this.account}:configuration-set/${this.configurationSet.ref}`,
          `arn:aws:ses:${this.region}:${this.account}:identity/*`,
        ],
      })
    );

    this.api = new apigwv2.HttpApi(this, "ContactFormApi", {
      corsPreflight: {
        allowOrigins: ["*"],
        allowMethods: [
          apigwv2.CorsHttpMethod.POST,
          apigwv2.CorsHttpMethod.OPTIONS,
        ],
        allowHeaders: ["*"],
      },
    });

    const formIntegration = new HttpLambdaIntegration(
      "contact-form-integration",
      formHandler
    );

    this.api.addRoutes({
      path: "/submit",
      methods: [apigwv2.HttpMethod.POST],
      integration: formIntegration,
    });

    new CfnOutput(this, "ApiEndpoint", {
      value: this.api.url ?? "",
    });

    new CfnOutput(this, "QueueUrl", {
      value: this.queue.queueUrl,
    });

    new CfnOutput(this, "TableName", {
      value: this.table.tableName,
    });

    new CfnOutput(this, "NotificationTopicArn", {
      value: this.notificationTopic.topicArn,
    });

    new CfnOutput(this, "SesConfigurationSetName", {
      value: this.configurationSet.name ?? this.configurationSet.ref,
    });
  }
}
