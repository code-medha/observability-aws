# Observability-aws


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
