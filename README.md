#updating file.

Making new changes

Made changes from tutorial/git branch

This is a project that works on implementing techniques used to implement a server and deply resources there we have different availability zones and regions. We have used AWS services to implement this project. We have used the following services:

- EC2
- Internet Gateway
- VPC
- Route Table
- Subnet
- Security Group

## Steps to implement the project:

1. Create the EC2 instance
2. create the Security groups
3. create the subnets
4. Attach the Internet Gateway to the public subnets.

## Installation

To install the conda dependencies.

```bash
  aws cloudformation create-stack --stack-name <your-stack-name> --template-body file:<include the saved file location>

```

## Feedback

If you have any feedback, please reach out to me at ceesay.ml@outlook.com
