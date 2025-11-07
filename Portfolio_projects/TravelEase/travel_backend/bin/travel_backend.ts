#!/usr/bin/env node
import * as cdk from "aws-cdk-lib";
import { TravelBackendStack } from "../lib/travel_backend-stack";
import { SesStack } from "../lib/ses-stack";

const app = new cdk.App();

const notificationEmail = "ceesay.ml@outlook.com";

const sesStack = new SesStack(app, "SesStack", {
  emailAddress: notificationEmail,
});

const travelBackendStack = new TravelBackendStack(app, "TravelBackendStack", {
  emailIdentity: sesStack.emailIdentity,
  emailAddress: sesStack.emailAddress,
  notificationEmail,
});

travelBackendStack.addDependency(sesStack);
