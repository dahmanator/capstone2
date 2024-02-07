terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }
  required_version = ">= 1.2.0"
}

provider "aws" {
  region     = "us-west-2"
}

/* ------- Create S3 Bucket ------ */
resource "aws_s3_bucket" "grp1-tf-cp2-bucket" {
  bucket = "grp1-tf-cp2-bucket"
}

/* ------- Enable Verionsing on S3 Bucket ------ */
resource "aws_s3_bucket_versioning" "grp1-tf-cp2-bucket-version" {
  bucket = aws_s3_bucket.grp1-tf-cp2-bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

/* ------- Upload File to Bucket ------ */
resource "aws_s3_object" "grp1-tf-cp2-bucket-add" {
  bucket   = aws_s3_bucket.grp1-tf-cp2-bucket.id
  key      = "todo-data.json"
  source   = "../todo-data.json"
  etag     = filemd5("../todo-data.json")
}


/* ------- AWS Lambda ------ */
/* Looks like this role name needs to exist when defining this */
resource "aws_iam_role" "grp1-tf-cp2-lambda-role" {
  name = "grp1-ft-cp2-gettodos-lambda-role"
  assume_role_policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
   {
     "Action": "sts:AssumeRole",
     "Principal": {
       "Service": "lambda.amazonaws.com"
     },
     "Effect": "Allow",
     "Sid": ""
   }
 ]
}
EOF
}


resource "aws_iam_policy" "grp1-tf-cp2-lambda-policy" {
 
 name         = "grp1-tf-cp2-lambda-policy"
 path         = "/"
 description  = "AWS IAM Policy for managing aws lambda role"
 policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
   {
     "Action": [
       "logs:CreateLogGroup",
       "logs:CreateLogStream",
       "logs:PutLogEvents"
     ],
     "Resource": "arn:aws:logs:*:*:*",
     "Effect": "Allow"
   }
 ]
}
EOF
}

resource "aws_iam_policy" "grp1-tf-cp2-lambda-policy2" {
 
 name         = "grp1-tf-cp2-lambda-policy2"
 path         = "/"
 description  = "AWS IAM Policy for managing aws lambda role"
 policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject"
            ],
            "Resource": "arn:aws:s3:::*"
        }
    ]
}
EOF
}


resource "aws_iam_role_policy_attachment" "attach_iam_policy_to_iam_role1" {
 role        = aws_iam_role.grp1-tf-cp2-lambda-role.name
 policy_arn  = aws_iam_policy.grp1-tf-cp2-lambda-policy.arn
}

resource "aws_iam_role_policy_attachment" "attach_iam_policy_to_iam_role2" {
 role        = aws_iam_role.grp1-tf-cp2-lambda-role.name
 policy_arn  = aws_iam_policy.grp1-tf-cp2-lambda-policy2.arn
}

/* --- Does this create a zip file from the source_file? ---*/
/* --- this seems to handle creating / uploading zip file --*/
data "archive_file" "grp1-tf-cp2-lambda-zip" {
  type        = "zip"
  source_file = "./resources/lambda.py"
  output_path = "./resources/lambda_function.zip"
}

/* --- Create lambda function with local python code file --- */
/* --- Is TF smart enough to understand the state of the python file? --- */
/* --- Yes - TF sees the python file update and re-uploads to lambda --- */
/* --- the handler needs to match the source_file basename <sourcefile>.lambda_handler ---*/
resource "aws_lambda_function" "grp1-tf-cp2-lambda-create" {
  function_name    = "grp1-tf-cp2-lambda"
  filename         = data.archive_file.grp1-tf-cp2-lambda-zip.output_path
  source_code_hash = data.archive_file.grp1-tf-cp2-lambda-zip.output_base64sha256
  role             = aws_iam_role.grp1-tf-cp2-lambda-role.arn
  handler          = "lambda.lambda_handler"
  runtime          = "python3.9"
}


/* Mike D - added REGIONAL endpoint */

# API Gateway
resource "aws_api_gateway_rest_api" "grp1-tf-cp2-api" {
  name = "grp1-tf-cp2-api"
  endpoint_configuration {
      types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "resource" {
  path_part   = "grp1-tf-cp2-resource"
  parent_id   = aws_api_gateway_rest_api.grp1-tf-cp2-api.root_resource_id
  rest_api_id = aws_api_gateway_rest_api.grp1-tf-cp2-api.id
}

resource "aws_api_gateway_method" "method1" {
  rest_api_id   = aws_api_gateway_rest_api.grp1-tf-cp2-api.id
  resource_id   = aws_api_gateway_resource.resource.id
  http_method   = "GET"
  authorization = "NONE"
}

/* type = AWS sets API Gateway Lambda Proxy Integration to False */
resource "aws_api_gateway_integration" "integration" {
  rest_api_id             = aws_api_gateway_rest_api.grp1-tf-cp2-api.id
  resource_id             = aws_api_gateway_resource.resource.id
  http_method             = aws_api_gateway_method.method1.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = aws_lambda_function.grp1-tf-cp2-lambda-create.invoke_arn
}

# Lambda
resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.grp1-tf-cp2-lambda-create.function_name
  principal     = "apigateway.amazonaws.com"

  # More: http://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-control-access-using-iam-policies-to-invoke-api.html
  source_arn = "arn:aws:execute-api:us-west-2:962804699607:${aws_api_gateway_rest_api.grp1-tf-cp2-api.id}/*/${aws_api_gateway_method.method1.http_method}${aws_api_gateway_resource.resource.path}"
}


resource "aws_api_gateway_method_response" "response_200" {
  rest_api_id = aws_api_gateway_rest_api.grp1-tf-cp2-api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.method1.http_method
  status_code = "200"
  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "IntegrationResponse" {
  rest_api_id = aws_api_gateway_rest_api.grp1-tf-cp2-api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.method1.http_method
  status_code = aws_api_gateway_method_response.response_200.status_code

  # Transforms the backend JSON response to XML
  response_templates = {
       "application/json" = ""
   }
}

# resource "aws_api_gateway_method_settings" "grp1-cap2-tf" {
#  rest_api_id = aws_api_gateway_rest_api.grp1-tf-cp2-api.id
#  stage_name  = "test"  # Change this to your API Gateway stage name
#
#  method_path = "*/*"
#
#  settings {
#    logging_level = "OFF"
#  }
#}


/** i have added API integration and method response code above and tested. It is working good and can hit API.  **/
/* Well done bala */


/* ---- TO DO : Disable CORS ---- */
/*

module "cors" {
  source = "squidfunk/api-gateway-enable-cors/aws"
  version = "0.3.3"

  api_id          = aws_api_gateway_rest_api.grp1-tf-cp2-api.id
  api_resource_id = aws_api_gateway_resource.resource.path
}

*/

/* ------- ECR Repo ------ */
resource "aws_ecr_repository" "grp1-tf-cp2-ecr-repo" {
  name = "grp1-tf-cp2-ecr-repo"
}


resource "aws_ecs_cluster" "my_cluster_group1" {
  name = "grp1-tf-cp2-cluster" # Naming the cluster
}

resource "aws_ecs_task_definition" "my_first_task_group1" {
  family                   = "grp1-tf-cp2-task-group1" # Naming our first task
  container_definitions    = <<DEFINITION
  [
    {
      "name": "grp1-tf-cp2-task-group1",
      "image": "${aws_ecr_repository.grp1-tf-cp2-ecr-repo.repository_url}",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 3000,
          "hostPort": 3000
        }
      ],
      "memory": 512,
      "cpu": 256
    }
  ]
  DEFINITION
  requires_compatibilities = ["FARGATE"] # Stating that we are using ECS Fargate
  network_mode             = "awsvpc"    # Using awsvpc as our network mode as this is required for Fargate
  memory                   = 512         # Specifying the memory our container requires
  cpu                      = 256         # Specifying the CPU our container requires
  execution_role_arn       = "${aws_iam_role.ecsTaskExecutionRoleGroup_1.arn}"
}

resource "aws_iam_role" "ecsTaskExecutionRoleGroup_1" {
  name               = "grp1-tf-cp2-ecsTaskExecutionRole"
  assume_role_policy = "${data.aws_iam_policy_document.assume_role_policy.json}"
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecsTaskExecutionRole_policyGroup_1" {
  role       = "${aws_iam_role.ecsTaskExecutionRoleGroup_1.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_service" "my_first_service_group1" {
  name            = "grp1-tf-cp2-service-group1"                             # Naming our first service
  cluster         = "${aws_ecs_cluster.my_cluster_group1.id}"             # Referencing our created Cluster
  task_definition = "${aws_ecs_task_definition.my_first_task_group1.arn}" # Referencing the task our service will spin up
  launch_type     = "FARGATE"
  desired_count   = 3 # Setting the number of containers we want deployed to 3
  
  load_balancer {
    target_group_arn = "${aws_lb_target_group.target_group.arn}" # Referencing our target group
    container_name   = "${aws_ecs_task_definition.my_first_task_group1.family}"
    container_port   = 3000 # Specifying the container port
  }
  
  network_configuration {
    subnets          = ["${aws_default_subnet.default_subnet_a.id}", "${aws_default_subnet.default_subnet_b.id}", "${aws_default_subnet.default_subnet_c.id}"]
    assign_public_ip = true # Providing our containers with public IPs
    security_groups  = ["${aws_security_group.service_security_group1.id}"] # Setting the security group
  }
}

resource "aws_security_group" "service_security_group1" {
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    # Only allowing traffic in from the load balancer security group
    security_groups = ["${aws_security_group.load_balancer_security_group.id}"]
  }

  egress {
    from_port   = 0 # Allowing any incoming port
    to_port     = 0 # Allowing any outgoing port
    protocol    = "-1" # Allowing any outgoing protocol 
    cidr_blocks = ["0.0.0.0/0"] # Allowing traffic out to all IP addresses
  }
}


# Providing a reference to our default VPC
resource "aws_default_vpc" "default_vpc" {
}

# Providing a reference to our default subnets
resource "aws_default_subnet" "default_subnet_a" {
  availability_zone = "us-west-2a"
}

resource "aws_default_subnet" "default_subnet_b" {
  availability_zone = "us-west-2b"
}

resource "aws_default_subnet" "default_subnet_c" {
  availability_zone = "us-west-2c"
}


resource "aws_alb" "application_load_balancer" {
  name               = "grp1-tf-cp2-lb" # Naming our load balancer
  load_balancer_type = "application"
  subnets = [ # Referencing the default subnets
    "${aws_default_subnet.default_subnet_a.id}",
    "${aws_default_subnet.default_subnet_b.id}",
    "${aws_default_subnet.default_subnet_c.id}"
  ]
  # Referencing the security group
  security_groups = ["${aws_security_group.load_balancer_security_group.id}"]
}

# Creating a security group for the load balancer:
resource "aws_security_group" "load_balancer_security_group" {
  ingress {
    from_port   = 80 # Allowing traffic in from port 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allowing traffic in from all sources
  }

  egress {
    from_port   = 0 # Allowing any incoming port
    to_port     = 0 # Allowing any outgoing port
    protocol    = "-1" # Allowing any outgoing protocol 
    cidr_blocks = ["0.0.0.0/0"] # Allowing traffic out to all IP addresses
  }
}



resource "aws_lb_target_group" "target_group" {
  name        = "grp1-tf-cp2-target-group"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = "${aws_default_vpc.default_vpc.id}" # Referencing the default VPC
  health_check {
    matcher = "200,301,302"
    path = "/"
  }
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = "${aws_alb.application_load_balancer.arn}" # Referencing our load balancer
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.target_group.arn}" # Referencing our tagrte group
  }
}



