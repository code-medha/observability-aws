# Observability-AWS


## AWS X-Ray Architecture

Before we instrument x-ray into our application, it's important to understand how x-ray works behind the scenes. Because it's not a striaght forward implementation like Honeycomb.io tool.

When you instrument your application with AWS X-Ray client SDKs, they don't directly send your application trace data directly to X-Ray. Instead each client SDK generates trace segments and sends them to x-ray daemon, which in turn sends to x-ray.

> So, What is X-Ray daemon?

The X-Ray daemon is a service that gathers the trace segments from the AWS X-Ray client SDKs and relays it to the AWS X-Ray dashboard.


> You might get a question now why X-Ray client SDKs doesn't directly send your application trace to X-Ray?

Because X-Ray SDKs don’t directly push trace data to the AWS X-Ray service to avoid network overhead on every trace event.


The X-Ray daemon runs separately from your application and can be deployed in several ways:

- As a standalone process on EC2 instances
- As a sidecar container in containerized environments
- Built into AWS services like Lambda, App Runner, and Elastic Beanstalk

In this project we will use it as a sidecar container along with other services.

> Data Flow Visualization:

Application → X-Ray SDK → X-Ray Daemon → X-Ray Service → X-Ray Console


## AWS-Vault

When we are working with AWS X-Ray, we need to configure AWS_SECRET_ACCESS_KEY and AWS_ACCESS_KEY_ID to send the traces to our AWS account. So, let's understand how we can store AWS_SECRET_ACCESS_KEY and AWS_ACCESS_KEY_ID:

- .env file: Yes, we can store the AWS creds in your project's .env file. However, it comes with a security risk because it may appear in build logs or container inspection

- AWS Credentials File Mounting: This is more secure when compared to storing in .env file. However, it may include in system backups, docker image layers.

- AWS Vault: One of the most secure ways to store your AWS creds. One of the advantage of AWS vault is it never share the creds with services. Instead, it shares a tempoprary token and jummbled up AWS creds. This way your creds don't leave your local developement. I will use AWS Vault in this project.

AWS Vault:

- Stores credentials in OS keystore (encrypted)
- Generates temporary credentials
- No plain text credential files
- Works seamlessly with Docker Compose
- Supports MFA and assume role

## Installing aws-vault

On a Linux machine, follow these steps:

1. Download the aws-vault pre-compiled binary file:
```
$ sudo curl -L -o /usr/local/bin/aws-vault https://github.com/99designs/aws-vault/releases/download/v7.2.0/aws-vault-linux-amd64
```
2. Set executable permissions:
```
$ sudo chmod 755 /usr/local/bin/aws-vault
```
3. Confirm the installation:
```
$ aws-vault --version
```

## Configuring aws-vault

1. Add a profile:
```
$ aws-vault add <profilename>
```

2. Enter your AWS_ACCESS_KEY_ID

2. Enter your AWS_SECRET_ACCESS_KEY

3. (Optional) Skip setting the password for oskeychain. I skipped it.

4. Confirm your account details:
```
$ aws-vault exec dock -- aws sts get-caller-identity
```

After configuration is complete, you need to append the docker compose command with aws-vault exec command anytime you run the docker compose.
```
aws-vault exec <profile_name> -- <docker_compose_command>
```

aws-vault exec dock -- docker compose -f ./docker-compose.dev.yml up -d

## Instrumenting X-ray

Insturmenting X-ray in our app includes the following steps:
1. Add X-ray env variables
2. Add X-ray as a service in the `docker-compose.dev.yml`
3. Install the X-ray python package
4. Instrument the `app.py`
5. Create custom X-ray Sampling Rule
6. Create X-ray groups

### X-ray env variables



### Containerized X-ray service

Append the following in the `docker-compose.dev.yml`:
```
  xray-daemon:
    image: "amazon/aws-xray-daemon"
    environment:
      - AWS_REGION=us-east-1           
      - AWS_ACCESS_KEY_ID           
      - AWS_SECRET_ACCESS_KEY
      - AWS_SESSION_TOKEN
    command:
      - "xray -o -b xray-daemon:2000"
    ports:
      - 2000:2000/udp 
```

### Install the X-ray python package

Add the following package in the `requirements.txt`:
```
aws-xray-sdk
```

### Instrument Your Application

Add the following import statements in `app.py`:
```
#x-ray
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.ext.flask.middleware import XRayMiddleware
```

Add XRayMiddleware function to patch your Flask application in code:
```
xray_url = os.getenv("AWS_XRAY_URL")
xray_recorder.configure(
    service='backend-flask',
    sampling=True,
    daemon_address='xray-daemon:2000',
    dynamic_naming=xray_url
)
XRayMiddleware(app, xray_recorder)
```

### Create x-ray sampling rule and groups

> Why we need to create a x-ray sampling rule:

 By default, the X-Ray SDK records the first request each second, and five percent of any additional requests. One request per second is the reservoir. So you can create a custom sampling rule to control the amount of data that you record. Custom Sampling rules tell the X-Ray SDK how many requests to record for a set of criteria.


> Why we need to create a x-ray groups:
An X-Ray Group is basically a saved filter expression that lets you slice and dice traces. Think of it like a “saved view” of your traces.


To create x-ray sampling rule and groups, let's make use of terraform.

Create `~/terraform/` directory from the root and add the following files:

`xray.tf`

```
# X-Ray Sampling Rule for Flask service traces            

resource "aws_xray_sampling_rule" "xray" {
  rule_name      = "Flask"
  resource_arn   = "*"
  priority       = 9000
  fixed_rate     = 0.1
  reservoir_size = 5
  service_name   = "backend-flask"
  service_type   = "*"
  host           = "*"
  http_method    = "*"
  url_path       = "*"
  version        = 1
}

# X-Ray Group for Flask service traces  
resource "aws_xray_group" "backend" {
  group_name        = "backend"
  filter_expression = "service(\"backend-flask\")"
}
```

`variables.tf`
```
variable "aws_region" {
  description = "AWS region to deploy to"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS CLI profile to use"
  type        = string
  default     = "default"
}
```

`providers.tf`
```
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}
```

To run the terrform, follow these steps:
```
cd terraform/
terraform init
terraform plan
terraform apply -y
```

## Testing the AWS X-Ray Implementation

After you've insturmneted the app.py and created sampling rule and groups, now it's time to see the AWS X-ray in action:

Run the following command to run the docker compose file:
```
aws-vault exec dock -- docker compose -f ./docker-compose.dev.yml up -d --build
```

Go to your browser and enter localhost:5000/api/activities/home and refersh multiple times to send the request. (more than 15 times)

Login to AWS web-console. Enter x-ray settings from the search bar. You will be redirected to Cloudwatch page.

To view the spans,from the left naviagtion, select **Application Signals --> Transaction Search**

![](/images/transaction-search.png)

To view the traces, from the left naviagtion, select **Application Signals --> Traces**

![](/images/traces.png)

![](/images/trace-details.png)

To view the trace map, from the left naviagtion, select **Application Signals --> Trace Map**

![](/images/trace-map.png)

(Optional) Docker AWS X-ray daemon logs to verify the data.
![](/images/cmd-xray.png)


