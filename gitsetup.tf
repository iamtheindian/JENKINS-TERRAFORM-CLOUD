#login to console
provider "aws" {
	region = "ap-south-1"
	profile= "rbterra"
}
//////////////////////////////////////////////////////
#creation of security group
resource "aws_default_vpc" "main" {
  tags = {
    Name = "Default VPC"
  }
}
resource "aws_security_group" "allow_tls" {
  name        = "allow_tls"
  description = "Allow TLS inbound traffic"
  vpc_id      =  aws_default_vpc.main.id

  ingress {
    description = "SSH CONFIG"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_tls"
  }
}
resource "aws_security_group_rule" "http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id =  aws_security_group.allow_tls.id
  description = "HTTP CONFIG"
}

resource "aws_security_group_rule" "https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id =  aws_security_group.allow_tls.id
  description = "HTTPS CONFIG"
}
#creating instance
#instance ami id
variable "ami_id" {
	#IMAGE NAME = Amazon Linux 2 AMI (HVM), SSD Volume Type
	default = "ami-0447a12f28fddb066"
}
#creating key pair and deleting when destroy command executed
resource "null_resource" "exec" {
	provisioner "local-exec" {
        command = "aws ec2 create-key-pair --key-name MyKeyPair --query 'KeyMaterial' --output text > /Terraform/MyKeyPair.pem --profile rbterra"
  }
  provisioner "local-exec" {
    when    = "destroy"
    command = "aws ec2 delete-key-pair --key-name MyKeyPair  --profile rbterra && rm -f /Terraform/MyKeyPair.pem"
	on_failure = "continue"
  }
}
#reading data of key pair file
data "local_file" "key_file" {
	depends_on =[null_resource.exec]
    filename = "/Terraform/MyKeyPair.pem"
}
#launching instance
resource "aws_instance" "webos" {
  ami           = var.ami_id
  instance_type = "t2.micro"
  
  depends_on = [null_resource.exec,aws_security_group.allow_tls,aws_security_group_rule.http,aws_security_group_rule.https]
  
  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = data.local_file.key_file.content 
    host        = aws_instance.webos.public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd git php -y",
      "sudo systemctl start httpd",
      "sudo systemctl enable httpd",
    ]
  }
	
  key_name = "MyKeyPair" 
  vpc_security_group_ids = [aws_security_group.allow_tls.id]
  tags = {
    Name = "TRedHat"
  }
}
#saving public ip to our local system
resource "local_file" "instance_public_ip" {
	depends_on  = [aws_instance.webos]
    content     = aws_instance.webos.public_ip
    filename    = "/Terraform/public_ip.txt"
}
#creation of ebs volume
resource "aws_ebs_volume" "myvol" {
  depends_on =[aws_instance.webos]
  availability_zone = aws_instance.webos.availability_zone
  size              = 1

  tags = {
    Name = "myvolume"
  }
}
resource "aws_volume_attachment" "ebs_att" {
  depends_on = [aws_ebs_volume.myvol]
  device_name = "/dev/sdd"
  volume_id   = aws_ebs_volume.myvol.id
  instance_id = aws_instance.webos.id
  force_detach = true
}


/////////////////////////////////////////////////////
#create snapshot of aws ebs volume
resource "aws_ebs_snapshot" "snapshot" {
  depends_on = [null_resource.nl1] 
  volume_id  = "${aws_ebs_volume.myvol.id}"

  tags = {
    Name = "terraform ebs snap"
  }
}
output "snapshot_id" {
	value = aws_ebs_snapshot.snapshot.id
}
/////////////////////////////////////////////////////
#variables and data

data "local_file" "pathfi" {
        filename = "/Terraform/img/path.txt"
}
/////////////////////////////////////////////////////
#buckets

resource "aws_s3_bucket" "b" {
  bucket = "aws-terraform-bucket-rahul3"
  acl    = "private"
  force_destroy = true
  tags = {
    Name        = "My bucket1"
    Environment = "Dev1"
  }
  versioning {
        enabled = false
  }

  provisioner "local-exec" {
        command = "aws s3 sync ${data.local_file.pathfi.content} s3://${aws_s3_bucket.b.id} --profile rbterra "
  }
  
}
#setting up cloudfron env
resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "myterra-access-generated"
}
locals {
  s3_origin_id = "myS3Origin"
}
resource "aws_cloudfront_distribution" "s3_distribution" {
  depends_on = [aws_s3_bucket.b]
  origin {
    domain_name = "${aws_s3_bucket.b.bucket_regional_domain_name}"
    origin_id   = "${local.s3_origin_id}"

    s3_origin_config {
   origin_access_identity = "${aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path}"
    }
  }
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "creating"
  default_root_object = "base.html"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
  }
   restrictions {
    geo_restriction {
      restriction_type = "blacklist"
      locations        = ["US", "CA", "GB", "DE"]
    }
  }
  price_class = "PriceClass_All"
  tags = {
    Environment = "production"
  }
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
#saving cloudfront_domain_name in our local file
resource "local_file" "cloud_dist_domain" {
	depends_on  = [aws_cloudfront_distribution.s3_distribution]
    content     = aws_cloudfront_distribution.s3_distribution.domain_name
    filename    = "/Terraform/php/domain_name.txt"
}
#updating bucket policy
data "aws_iam_policy_document" "s3_policy" {
  depends_on = [aws_cloudfront_distribution.s3_distribution]
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.b.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = ["${aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn}"]
    }
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = ["${aws_s3_bucket.b.arn}"]

    principals {
      type        = "AWS"
      identifiers = ["${aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn}"]
    }
  }
}

resource "aws_s3_bucket_policy" "s3_bucket_pol" {
  depends_on = [aws_cloudfront_distribution.s3_distribution]
  bucket = "${aws_s3_bucket.b.id}"
  policy = "${data.aws_iam_policy_document.s3_policy.json}"
}
#combined use of remote and local execution
resource "null_resource" "nl1" {
	depends_on = [ aws_volume_attachment.ebs_att,aws_s3_bucket.b,aws_cloudfront_distribution.s3_distribution ]
	#sending local data to remote instance using scp
	provisioner "local-exec" {
		command = "chmod 400 /Terraform/MyKeyPair.pem && scp -o StrictHostKeyChecking=no -r -i  /Terraform/MyKeyPair.pem   /Terraform/php  ec2-user@${aws_instance.webos.public_dns}:/home/ec2-user"
	}
	connection {
    type          = "ssh"
    user          = "ec2-user"
    private_key   = data.local_file.key_file.content
    host          = aws_instance.webos.public_ip
  }
  provisioner "remote-exec" {
    inline = [
	"sudo rm -Rf /var/www/html/*",
    "sudo  mkfs.ext4 /dev/xvdd",
    "sudo mount /dev/xvdd /var/www/html",
	"sudo mv  -f /home/ec2-user/php/* /var/www/html/"
    ]
  }
  provisioner "local-exec" {
	command = "curl ${aws_instance.webos.public_ip} "
  }
}

#deleting local files at the time of destroying
resource "null_resource" "dstry"{
	#commands if you want to destroy something at local 
}
//////////////////////////////////////////////////////////////////////////////////////////////////
#final outputs
output "instance_ip" {
	value = aws_instance.webos.public_ip
}
output "cloudfront_domain_name" {
	value = aws_cloudfront_distribution.s3_distribution.domain_name
}