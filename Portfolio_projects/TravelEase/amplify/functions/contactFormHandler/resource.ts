import { defineFunction } from "@aws-amplify/backend";

export const contactFormHandler = defineFunction({
  entry: "./handler.ts",
});
