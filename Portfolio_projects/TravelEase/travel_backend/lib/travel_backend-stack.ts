import { Duration, RemovalPolicy, Stack, StackProps, CfnOutput } from "aws-cdk-lib";
import { aws_apigateway as apigw } from "aws-cdk-lib";
import { aws_dynamodb as dynamodb } from "aws-cdk-lib";
import { aws_lambda as lambda } from "aws-cdk-lib";
import { aws_sns as sns } from "aws-cdk-lib";
import { aws_sns_subscriptions as subscriptions } from "aws-cdk-lib";
import { aws_sqs as sqs } from "aws-cdk-lib";
import { aws_ses as ses } from "aws-cdk-lib";
import { Construct } from "constructs";
import * as path from "path";

export interface TravelBackendStackProps extends StackProps {
  readonly emailIdentity: ses.IEmailIdentity;
  readonly emailAddress: string;
  readonly notificationEmail?: string;
}

export class TravelBackendStack extends Stack {
  public readonly api: apigw.RestApi;
  public readonly queue: sqs.Queue;
  public readonly table: dynamodb.Table;
  public readonly notificationTopic: sns.Topic;
  public readonly configurationSet: ses.CfnConfigurationSet;

  constructor(scope: Construct, id: string, props: TravelBackendStackProps) {
    super(scope, id, props);

    const notificationEmail = props.notificationEmail ?? props.emailAddress;

    this.table = new dynamodb.Table(this, "FormTable", {
      partitionKey: { name: "submission_id", type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: RemovalPolicy.DESTROY,
      tableName: "travelease-form",
    });

    this.queue = new sqs.Queue(this, "FormQueue", {
      visibilityTimeout: Duration.minutes(5),
    });

    this.notificationTopic = new sns.Topic(this, "FormSubmissionTopic", {
      displayName: "TravelEase Form Notifications",
    });

    this.notificationTopic.addSubscription(
      new subscriptions.EmailSubscription(notificationEmail)
    );

    this.configurationSet = new ses.CfnConfigurationSet(this, "TravelEaseConfigSet", {
      name: "TravelEaseBounceConfig",
    });

    new ses.CfnConfigurationSetEventDestination(this, "BounceEventDestination", {
      configurationSetName: this.configurationSet.name ?? this.configurationSet.ref,
      eventDestination: {
        name: "BounceAndComplaintNotifications",
        enabled: true,
        matchingEventTypes: ["BOUNCE", "COMPLAINT"],
        snsDestination: {
          topicArn: this.notificationTopic.topicArn,
        },
      },
    });

    const formHandler = new lambda.Function(this, "FormHandlerFunction", {
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: "app.lambda_handler",
      code: lambda.Code.fromAsset(path.join(__dirname, "../lambda")),
      timeout: Duration.seconds(30),
      environment: {
        TABLE_NAME: this.table.tableName,
        QUEUE_URL: this.queue.queueUrl,
        SOURCE_EMAIL: props.emailAddress,
        OWNER_EMAIL: notificationEmail,
        BUSINESS_EMAIL: notificationEmail,
        SNS_TOPIC_ARN: this.notificationTopic.topicArn,
        SES_CONFIGURATION_SET: this.configurationSet.ref,
      },
    });

    this.table.grantWriteData(formHandler);
    this.queue.grantSendMessages(formHandler);
    this.notificationTopic.grantPublish(formHandler);
    props.emailIdentity.grantSendEmail(formHandler);

    this.api = new apigw.RestApi(this, "TravelEaseApi", {
      restApiName: "TravelEase Backend Service",
      defaultCorsPreflightOptions: {
        allowOrigins: apigw.Cors.ALL_ORIGINS,
        allowMethods: apigw.Cors.ALL_METHODS,
      },
    });

    const submitResource = this.api.root.addResource("submit");
    submitResource.addMethod("POST", new apigw.LambdaIntegration(formHandler));

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
