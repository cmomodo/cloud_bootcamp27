import { type ClientSchema, a, defineData } from "@aws-amplify/backend";
import { contactFormHandler } from "../functions/contactFormHandler/resource";

const schema = a.schema({
  ContactFormSubmission: a
    .model({
      name: a.string().required(),
      email: a.email().required(),
      phone: a.phone(),
      inquiryType: a.enum(["VACATION_PACKAGE", "PRICING", "AVAILABILITY"]),
      message: a.string().required(),
    })
    .authorization((allow) => [allow.guest()]),

  submitContactForm: a
    .mutation()
    .arguments({
      name: a.string().required(),
      email: a.email().required(),
      phone: a.phone(),
      inquiryType: a.enum(["VACATION_PACKAGE", "PRICING", "AVAILABILITY"]),
      message: a.string().required(),
    })
    .handler(a.handler.function(contactFormHandler))
    .returns(a.string()), // returns the reference ID
});

export type Schema = ClientSchema<typeof schema>;

export const data = defineData({
  schema,
  authorizationModes: {
    defaultAuthorizationMode: "identityPool",
  },
});
