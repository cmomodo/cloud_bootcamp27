## TravelEase

TravelEase is a simple travel booking prototype. It provides an easy way for users to submit flight requests and is built with a serverless mindset.

## Project Structure

- **amplify/** – Frontend application managed by AWS Amplify.
- **travel_backend/** – Backend infrastructure defined using the AWS Cloud Development Kit (CDK).

## Prerequisites

- Node.js installed on your machine
- AWS account with Amplify CLI configured
- AWS CDK CLI

## Getting Started

### Frontend

```
cd amplify
npm install
npm start
```

### Backend

```
cd travel_backend
npm install
npm run build
cdk deploy
```

## System Design

![Contact Form GIF](system_design/contact_form.gif)
