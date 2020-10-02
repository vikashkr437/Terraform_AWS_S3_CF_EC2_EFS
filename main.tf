provider "aws" {
  region  = "ap-south-1"
  profile = "vkuser"
}


resource "aws_security_group" "allow_tls" {
  name        = "allow_tls"
  description = "Allow TLS HTTP NFS inbound traffic"
  vpc_id      = "vpc-2d9a8745"

  ingress     = [ {
    description      = "TLS from VPC"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    ipv6_cidr_blocks = null
    prefix_list_ids  = null
    security_groups  = null
    self             = null
    cidr_blocks      = ["0.0.0.0/0"]
      },  
      {
    description      = "HTTP from VPC"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    ipv6_cidr_blocks = null
    prefix_list_ids  = null
    security_groups  = null
    self             = null
    cidr_blocks      = ["0.0.0.0/0"]
     },
     {
    description      = "NFS from VPC"
    from_port        = 2049
    to_port          = 2049
    protocol         = "tcp"
    ipv6_cidr_blocks = null
    prefix_list_ids  = null
    security_groups  = null
    self             = null
    cidr_blocks      = ["0.0.0.0/0"]
     }
   ]

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags    = {
    Name  = "allow_tls"
  }
}



resource "aws_efs_file_system" "efs_for_instance" {
  creation_token = "myefs"

  tags = {
    Name = "efsforinstance"
  }
}

resource "aws_efs_mount_target" "mount_efs" {
  depends_on   = [  aws_efs_file_system.efs_for_instance, 
                    aws_security_group.allow_tls   ]
  file_system_id = aws_efs_file_system.efs_for_instance.id
  subnet_id      = "subnet-3de7dd55"
  security_groups = [ aws_security_group.allow_tls.id ]
}

resource "aws_instance" "myos" {
   depends_on      = [ aws_security_group.allow_tls,
                       aws_efs_mount_target.mount_efs,  ]
   ami             =  "ami-0447a12f28fddb066"
   instance_type   =  "t2.micro"
   key_name        =  "mykey2"
   subnet_id       = "subnet-3de7dd55"
   security_groups =  [ aws_security_group.allow_tls.id ]
  

   connection   {
       type        = "ssh"
       user        = "ec2-user"
       private_key = file("mykey2.pem")
       host        = aws_instance.myos.public_ip
   }
   
   provisioner "remote-exec"  {
       inline      = [
         "sudo yum install httpd php git amazon-efs-utils nfs-utils -y",
         "sudo setenforce 0",
         "sudo systemctl start httpd",
         "sudo systemctl enable httpd",
         "sudo mount -t efs ${aws_efs_file_system.efs_for_instance.id}:/ /var/www/html",
         "sudo echo '${aws_efs_file_system.efs_for_instance.id}:/ /var/www/html efs defaults,_netdev 0 0' >> /etc/fstab",
         "sudo rm -rf /var/www/html/*",
         "sudo git clone https://github.com/vikashkr437/TestCodes.git /var/www/html/"
       ]
   }


   tags            = {
      Name         = "terraos"
   }

}






resource "aws_s3_bucket" "ters3" {
    depends_on            =[  aws_instance.myos, ]
    bucket                = "vkb001"
    acl                   = "private"
    //region                = "ap-south-1"


  tags = {
    Name = "webbuc"
  }
}

resource "aws_s3_bucket_object" "pics" {
  depends_on   =  [ aws_s3_bucket.ters3,  ]
  bucket       = aws_s3_bucket.ters3.id
  key          = "sunflower.png"
  source       = "C:/Users/Vikash/Desktop/pics1/sunflower.png"
  content_type = "image/png"
  acl          = "public-read"

}






resource "aws_cloudfront_origin_access_identity" "terid" {
depends_on = [  aws_s3_bucket_object.pics, ]
}


resource "aws_cloudfront_distribution" "tercf" {
   depends_on      =   [ aws_cloudfront_origin_access_identity.terid, ]
   origin {
    domain_name    = aws_s3_bucket.ters3.bucket_regional_domain_name
    origin_id      = "s3_origin_id"
    s3_origin_config {
       origin_access_identity = aws_cloudfront_origin_access_identity.terid.cloudfront_access_identity_path
     }
    }
   enabled             = true
   is_ipv6_enabled     = true
   default_root_object = "sunflower.png"
   default_cache_behavior {
      allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cached_methods   = ["GET", "HEAD"]
      target_origin_id = "s3_origin_id"
      forwarded_values {
         query_string  = false
          cookies {
          forward      = "none"
      }
    }
   viewer_protocol_policy = "allow-all"
   min_ttl                = 0
   default_ttl            = 3600
   max_ttl                = 86400
   }
   price_class = "PriceClass_200"
   restrictions {
     geo_restriction {
        restriction_type = "none"
      
      }
    }
   tags = {
      Environment = "production"
    }
   viewer_certificate {
        cloudfront_default_certificate = true
   }
  connection {
        type        = "ssh"
	user        = "ec2-user"
	private_key = tls_private_key.mykey1a.private_key_pem
	host        = aws_instance.myos.public_ip
  }
}




output "cloudfront_ip" {
  value = aws_cloudfront_distribution.tercf.domain_name
}


output "ec2_ip" {
value = aws_instance.myos.public_ip
}