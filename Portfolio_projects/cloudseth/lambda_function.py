import json
import boto3
import os

ssm = boto3.client('ssm')

def lambda_handler(event, context):
    print("Received event: " + json.dumps(event, indent=2))
    
    # Get the SSM Document Name from environment variable
    document_name = os.environ['SSM_DOCUMENT_NAME']
    
    try:
        # Trigger the SSM Automation
        response = ssm.start_automation_execution(
            DocumentName=document_name,
            Parameters={
                'SecondaryInstanceId': [os.environ['SECONDARY_INSTANCE_ID']],
                'SecondaryRegion': [os.environ['SECONDARY_REGION']],
                'EndpointGroupArn': [os.environ['ENDPOINT_GROUP_ARN']],
                'AutomationAssumeRole': [os.environ['SSM_ROLE_ARN']]
            }
        )
        print("Automation started: " + response['AutomationExecutionId'])
        return {
            'statusCode': 200,
            'body': json.dumps('Automation started successfully')
        }
    except Exception as e:
        print(e)
        return {
            'statusCode': 500,
            'body': json.dumps('Error starting automation')
        }
