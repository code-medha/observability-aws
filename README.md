# Observability-AWS

The scope of this project is to learn observability skills by configuring AWS X-Ray with a Python Flask backend.

In this project, I will document the process involved in configuring AWS X-Ray.

---

## AWS X-Ray Architecture

Before we instrument X-Ray into our application, it's important to understand how X-Ray works behind the scenes. It's not as straightforward as implementing some other observability tools (like [Honeycomb.io](https://www.honeycomb.io/)). X-Ray follows a slightly different approach.

When you instrument your application with AWS X-Ray client SDKs, they don't send your application trace data directly to X-Ray. Instead, each client SDK generates trace segments and sends them to a local process.

> **So, what is the X-Ray daemon?**

The X-Ray daemon is a service that gathers the trace segments from the AWS X-Ray client SDKs, batches them, and relays them to the AWS X-Ray dashboard.

> **Why don't X-Ray client SDKs send traces directly to X-Ray?**

The SDKs avoid sending traces directly to the AWS X-Ray service to minimize network overhead on every trace event. The daemon batches and transmits data efficiently.

**The X-Ray daemon runs separately from your application and can be deployed in several ways:**

- As a standalone process on EC2 instances
- As a sidecar container in containerized environments
- Built into AWS services like Lambda, App Runner, and Elastic Beanstalk

In this project, we will use it as a sidecar container along with other services.

> **Data Flow Visualization:**

```
Application → X-Ray SDK → X-Ray Daemon → X-Ray Service → X-Ray Console
```

---

## AWS-Vault

When working with AWS X-Ray, we need to configure `AWS_SECRET_ACCESS_KEY` and `AWS_ACCESS_KEY_ID` to send the traces to our AWS account. Let's look at secure ways to store AWS credentials:

- **.env file:**  
  Storing AWS creds in your project's `.env` file is possible, but risky. Credentials may leak via build logs or container inspection.

- **AWS Credentials File Mounting:**  
  More secure than a `.env` file, but credentials could be included in system backups or Docker image layers.

- **AWS Vault:**  
  One of the most secure ways to store your AWS credentials locally. AWS Vault never shares your real credentials with services—instead, it provides temporary tokens and obfuscated keys.

**AWS Vault Key Points:**

- Stores credentials in your OS keystore (encrypted)
- Generates temporary credentials
- No plain text credential files
- Works seamlessly with Docker Compose
- Supports MFA and role assumption

---

## Installing aws-vault

On a Linux machine, follow these steps:

1. Download the aws-vault pre-compiled binary file:
   ```
   sudo curl -L -o /usr/local/bin/aws-vault https://github.com/99designs/aws-vault/releases/download/v7.2.0/aws-vault-linux-amd64
   ```

2. Set executable permissions:
   ```
   sudo chmod 755 /usr/local/bin/aws-vault
   ```

3. Confirm the installation:
   ```
   aws-vault --version
   ```

---

## Configuring aws-vault

1. Add a profile:
   ```
   aws-vault add <profilename>
   ```

2. Enter your `AWS_ACCESS_KEY_ID`

3. Enter your `AWS_SECRET_ACCESS_KEY`

4. (Optional) Skip setting the password for oskeychain. I skipped it.

5. Confirm your account details:
   ```
   aws-vault exec <profilename> -- aws sts get-caller-identity
   ```

After configuration, you need to prepend your docker compose command with `aws-vault exec` every time you run it:
```
aws-vault exec <profile_name> -- <docker_compose_command>
```

**Example:**
```
aws-vault exec dock -- docker compose -f ./docker-compose.dev.yml up -d
```

---

## Instrumenting X-Ray

Instrumenting X-Ray in our app includes the following steps:
1. Add X-Ray environment variables
2. Add X-Ray as a service in the `docker-compose.dev.yml`
3. Install the X-Ray Python package
4. Instrument the `app.py`
5. Create a custom X-Ray Sampling Rule
6. Create X-Ray groups

### 1. X-Ray Environment Variables

You will need to provide these variables to both the X-Ray Daemon and your application:
- `AWS_REGION`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_SESSION_TOKEN`

### 2. Containerized X-Ray Service

Append the following to your `docker-compose.dev.yml`:
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

### 3. Install the X-Ray Python Package

Add the following package to `requirements.txt`:
```
aws-xray-sdk
```

### 4. Instrument Your Application

Add these import statements to `app.py`:
```python
# x-ray
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.ext.flask.middleware import XRayMiddleware
```

Patch your Flask application with:
```python
import os

xray_url = os.getenv("AWS_XRAY_URL")
xray_recorder.configure(
    service='backend-flask',
    sampling=True,
    daemon_address='xray-daemon:2000',
    dynamic_naming=xray_url
)
XRayMiddleware(app, xray_recorder)
```


### 5. Create X-Ray Sampling Rule and Groups

> **Why create a custom X-Ray sampling rule?**  
By default, the X-Ray SDK records the first request each second, and 5% of any additional requests (1 request/sec is the reservoir). Custom sampling rules let you control trace volume for your environment.

> **Why create X-Ray groups?**  
An X-Ray Group is a saved filter expression that lets you segment, slice, and analyze traces—like a “saved view” of your traces.

To create X-Ray sampling rules and groups, let's use Terraform.

---

## Terraform Setup for X-Ray Sampling Rules & Groups

Create a `./terraform/` directory in your project root and add the following files:

**`xray.tf`**
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

**`variables.tf`**
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

**`providers.tf`**
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

**To deploy with Terraform:**
```
cd terraform/
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply -y
```

---

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

*Happy tracing!*

