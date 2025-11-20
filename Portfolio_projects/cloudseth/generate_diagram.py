#!/usr/bin/env python3
"""
CloudSleuth Disaster Recovery Architecture Diagram Generator
"""
from diagrams import Diagram, Cluster, Edge
from diagrams.aws.compute import EC2, Lambda
from diagrams.aws.network import GlobalAccelerator, InternetGateway
from diagrams.aws.general import GenericFirewall, User
from diagrams.aws.network import Route53
from diagrams.aws.management import Cloudwatch, CloudwatchAlarm, SystemsManagerAutomation
from diagrams.aws.integration import SNS

with Diagram("CloudSleuth Multi-Region Disaster Recovery", show=False, direction="LR", filename="architecture_diagram", outformat="png"):
    user = User("User")
    
    ga = GlobalAccelerator("Global Accelerator\nStatic IP")
    
    with Cluster("Primary Region (us-east-1)"):
        with Cluster("VPC 10.0.0.0/16"):
            igw_primary = InternetGateway("Internet Gateway")
            with Cluster("Public Subnet"):
                primary_ec2 = EC2("Primary Web Server\nRunning")
                sg_primary = GenericFirewall("Security Group\nHTTP/80")
    
    with Cluster("Secondary Region (us-west-2)"):
        with Cluster("VPC 10.0.0.0/16"):
            igw_secondary = InternetGateway("Internet Gateway")
            with Cluster("Public Subnet"):
                secondary_ec2 = EC2("Secondary Web Server\nStopped (Pilot Light)")
                sg_secondary = GenericFirewall("Security Group\nHTTP/80")

    # Traffic Flow
    user >> Edge(label="HTTPS Request") >> ga
    ga >> Edge(label="Weight: 100", color="green", style="bold") >> primary_ec2
    ga >> Edge(label="Weight: 0", color="gray", style="dashed") >> secondary_ec2
    
    # Monitoring & Automation Components
    with Cluster("Monitoring & Automation"):
        r53_hc = Route53("Route53\nHealth Check")
        cw_alarm = CloudwatchAlarm("CloudWatch Alarm\nHealthCheckStatus < 1")
        sns_topic = SNS("SNS Topic\nAlerts")
        lambda_func = Lambda("Recovery Lambda\nPython 3.11")
        ssm_auto = SystemsManagerAutomation("SSM Automation\nRecovery Workflow")
    
    # Monitoring Flow
    r53_hc >> Edge(label="HTTP Check :80") >> primary_ec2
    r53_hc >> Edge(label="Publish Metric") >> cw_alarm
    cw_alarm >> Edge(label="Trigger on Failure") >> sns_topic
    sns_topic >> Edge(label="Invoke") >> lambda_func
    lambda_func >> Edge(label="StartAutomationExecution") >> ssm_auto
    
    # Recovery Actions
    ssm_auto >> Edge(label="1. Start Instance", color="red", style="bold") >> secondary_ec2
    ssm_auto >> Edge(label="2. Update Endpoint Weights", color="red", style="bold") >> ga

print("✅ Diagram generated successfully: architecture_diagram.png")
