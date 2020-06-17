provider "aws" {
  region = "ap-south-1"
  profile = "hitkool"
}


//step 1 : making a private key and storing it to computer

resource "tls_private_key" "SSH_key" {    
  algorithm = "RSA"
}


resource "local_file" "SSH_privatekey" {
    content     = tls_private_key.SSH_key.private_key_pem
    filename = "nokey.pem"
    file_permission = 0400                             
}


resource "aws_key_pair" "key1"{            
	key_name= "nokey"
	public_key = tls_private_key.SSH_key.public_key_openssh
}
/*
// creating a vpc group for security grp

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "TFvpc"
}
*/
// step 2 : Create security group : hitsec
// tip : when i write vpc id then code is working fine.

resource "aws_security_group" "hit_sec" {
  name        = "hit_security"
  description = "Made using TF"
  vpc_id 	= "vpc-608d9b08"
  //vpc_id      = aws_vpc.main.id
  
  tags = {
    Name = "hitsec"
  }
  
  //For inbound rules in security group : hitsec
  ingress {     
    description = "creating inbound rule for port no 443"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {     
    description = "creating inbound rule for port no 80"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {     
    description = "creating inbound rule for port no 22"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  //creating outbount rules for PN 22 443 80
  egress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

//launching aws instance

resource "aws_instance" "web" {
  //ami 		= "ami-005956c5f0f757d37"   //amzn linux 2
  ami           = "ami-052c08d70def0ac62"   // redhat
  instance_type = "t2.micro"
  key_name	= aws_key_pair.key1.key_name
  security_groups = [ aws_security_group.hit_sec.name ]
  //security_groups = [ "launch-wizard-1" ]
  
  connection {
    	type     = "ssh"
    	user     = "ec2-user"
    	private_key = tls_private_key.SSH_key.private_key_pem
	//private_key = file("C:/Users/hites/Downloads/27apr.pem")
	//password = file("C:/Users/hites/Downloads/27apr.pem")
	host     = aws_instance.web.public_ip
    }  

  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd git php -y",
      "sudo systemctl start httpd",
      "sudo systemctl enable httpd",
    ]
  }

  provisioner "remote-exec" {
    when = destroy
    inline = [ "sudo poweroff" ]
  }

  tags = {
    Name = "ami2os1"
  }
}

output "ins_web_public_ip" {
  value = aws_instance.web.public_ip
}

output "ins_web_id" {
  value = aws_instance.web.id
}


//step 4.1 : create a ebs : hitebs

resource "aws_ebs_volume" "hitebs" {

  depends_on = [ 
     aws_instance.web, 
   ] 

  availability_zone = aws_instance.web.availability_zone
  //picking value of subnet of myin1 and creating a vol there
  size              = 1
  //skip_destroy	= True

  tags = {
    Name = "hitebs"
  }
}


//step 4.2 : attach a ebs volume to /dev/sdh

resource "aws_volume_attachment" "attach_hit1_hitebs" {
  device_name = "/dev/xvdh"
  volume_id   = aws_ebs_volume.hitebs.id
  instance_id = aws_instance.web.id
}


//Saving instance public ip in a txt file

resource "null_resource" "nulllocall" {
  provisioner "local-exec"   {
      command = "echo ${aws_instance.web.public_ip} > publicip.txt"
  }                   //string interpolation
}


//step 4.3 : formatting mounting and downloading git repo in ebs storage

resource "null_resource" "vol-attach"  { 
  
 depends_on = [ 
     aws_volume_attachment.attach_hit1_hitebs, 
   ] 
  
  
   connection { 
     type     = "ssh" 
     user     = "ec2-user" 
     private_key = tls_private_key.SSH_key.private_key_pem 
     host     = aws_instance.web.public_ip
   } 
  
 provisioner "remote-exec" { 
     inline = [ 
       "sudo mkfs.ext4  /dev/xvdh", 
       "sudo mount  /dev/xvdh  /var/www/html", 
       "sudo rm -rf /var/www/html/*", 
       "sudo git clone https://github.com/hitk6/hitcloud.git /var/www/html"  
     ] 
   } 
 } 

// error when destroying ebs vol is not disconnected from instance and shows error
/*
provisioner "remote-exec" {
    when = "destroy"
    inline = [ "sudo poweroff" ]
  }
*/
//step 5 : creating a s3 bucket

resource "aws_s3_bucket" "bucket-img" { 
   depends_on = [ 
        null_resource.vol-attach, 
    ] 
  
   bucket = "aws-task-1" 
   acl    = "public-read" 
   tags = { 
     Name = "mybucket1" 
       Environment="Dev" 
    } 
  } 
  
    
//step 6 : uploading my image to s3 bucket    
  
 resource "aws_s3_bucket_object" "image" { 
  
 depends_on = [ 
        aws_s3_bucket.bucket-img 
 ] 
   key                    = "hitesh.jpg" 
   bucket                 = aws_s3_bucket.bucket-img.bucket 
   acl                    = "public-read" 
   source                 = "C:\\Users\\hites\\Desktop\\terra\\hitesh.jpg" 
   etag                   = "${filemd5("C:\\Users\\hites\\Desktop\\terra\\hitesh.jpg")}" 
 } 
  
 locals { 
   s3_origin_id = "S3-${aws_s3_bucket.bucket-img.bucket}" 
 } 



resource "aws_cloudfront_distribution" "s3_distribution" { 
   origin { 
     domain_name = "${aws_s3_bucket.bucket-img.bucket_regional_domain_name}" 
     origin_id   = "${aws_s3_bucket.bucket-img.id}" 
   } 
  
   enabled             = true 
   is_ipv6_enabled     = true 
   comment             = "S3 bucket" 
  
   default_cache_behavior { 
     allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"] 
     cached_methods   = ["GET", "HEAD"] 
     target_origin_id = "${aws_s3_bucket.bucket-img.id}" 
  
     forwarded_values { 
       query_string = false 
  
       cookies { 
         forward = "none" 
       } 
     } 
  
     viewer_protocol_policy = "allow-all" 
     min_ttl                = 0 
     default_ttl            = 3600 
     max_ttl                = 86400 
   } 
  
   # Cache behavior with precedence 0 
   ordered_cache_behavior { 
     path_pattern     = "/content/immutable/*" 
     allowed_methods  = ["GET", "HEAD", "OPTIONS"] 
     cached_methods   = ["GET", "HEAD", "OPTIONS"] 
     target_origin_id = "${aws_s3_bucket.bucket-img.id}" 
       forwarded_values { 
       query_string = false 
       headers      = ["Origin"] 
  
       cookies { 
         forward = "none" 
       } 
     } 
  
     min_ttl                = 0 
     default_ttl            = 86400 
     max_ttl                = 31536000 
     compress               = true 
     viewer_protocol_policy = "redirect-to-https" 
   } 
  
   restrictions { 
     geo_restriction { 
       restriction_type = "whitelist" 
       locations        = ["IN"] 
     } 
   } 
  
   tags = { 
     Environment = "production" 
   } 
  
   viewer_certificate { 
     cloudfront_default_certificate = true 
   } 
    
    connection { 
     type     = "ssh" 
     user     = "ec2-user" 
     private_key = tls_private_key.SSH_key.private_key_pem 
     host     = aws_instance.web.public_ip 
   } 

 provisioner "remote-exec"{ 
       inline= [ 
          "sudo su << EOF", 
                    "echo \"<img src='http://${self.domain_name}/${aws_s3_bucket_object.image.key}' width='300' height='400'>\" >> /var/www/html/index.html", 
                                        "EOF", 
        ]
 }
}
