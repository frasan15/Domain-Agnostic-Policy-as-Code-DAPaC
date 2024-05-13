# The following Terraform code provisions an OpenStack compute instance (called web server) and associates a 
# floating IP address with it to make it accessible from the Internet

# Define required providers
terraform {
  required_version = ">= 0.14.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.53.0"
    }
  }
}

# Define a security group which exposes port 22
resource "openstack_networking_secgroup_v2" "secgroup_1" {
  name        = var.security_groups
  description = "Expose port 22"
}

# Specifically, you define the rules hereby
# If you want to define other rules, then you have the define other resources like the one below
resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_1" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.secgroup_1.id
}

# Create a web server instance
resource "openstack_compute_instance_v2" "web_server" {
  depends_on = [ openstack_networking_secgroup_rule_v2.secgroup_rule_1 ]
  name            = var.server_name
  flavor_name     = "gx1.2c4r"
  image_id        = "db1bc18e-81e3-477e-9067-eecaa459ec33"
  network {
    name = var.network_name
  }
  security_groups = [var.security_groups]
  key_pair = "MySecondKey"

# The following provisioner writes into the file server_ids.txt the id of the newly created server (N.B. I will use this file as a list of all the server's ids created)
# TODO: fix the \n problem
  provisioner "local-exec" {
    command = "echo '\n' >> server_ids.txt; echo '${self.id}' >> server_ids.txt"
  }

}

# Generate a floating ip
resource "openstack_networking_floatingip_v2" "myip"{
  depends_on = [ openstack_compute_instance_v2.web_server ]
  pool = "ntnu-internal"
  port_id = openstack_compute_instance_v2.web_server
  #fixed_ip = openstack_compute_instance_v2.web_server.access_ip_v4
}

# Define a floating ip
#resource "openstack_compute_floatingip_associate_v2" "myip" {
#  depends_on = [ openstack_compute_instance_v2.web_server ]
#  floating_ip = openstack_networking_floatingip_v2.myip.address
#  instance_id = openstack_compute_instance_v2.web_server.id # this is the id of the instance to associate the floating ip with
#  fixed_ip = openstack_compute_instance_v2.web_server.network.0.fixed_ip_v4 # the fixed ip address of the instance. This ensures that the floating IP is associated with the correct interface on the instance
#}

# Define all the information needed for the subnet here below
# This is needed since Terraform-OpenStack registry does not provide any function to retrieve such info
# about subnets

# TODO: look at the dependencies below, try to associate floating ip to fixed ip with another resource (the one above is deprecated)
#       find a nice way of exporting the information whether a server has a floating ip or not; since you can use this to determine whether is connected to Internet or not -> ASK TO PALMA MAYBE

locals {
  depends_on = [ openstack_networking_secgroup_rule_v2.secgroup_rule_1, openstack_networking_floatingip_v2.myip ]
  secgroup_info = {
    name        = openstack_networking_secgroup_v2.secgroup_1.name
    description = openstack_networking_secgroup_v2.secgroup_1.description
    id = openstack_networking_secgroup_v2.secgroup_1.id
    rules = [
      {
        direction       = openstack_networking_secgroup_rule_v2.secgroup_rule_1.direction
        ethertype       = openstack_networking_secgroup_rule_v2.secgroup_rule_1.ethertype
        protocol        = openstack_networking_secgroup_rule_v2.secgroup_rule_1.protocol
        port_range_min  = openstack_networking_secgroup_rule_v2.secgroup_rule_1.port_range_min
        port_range_max  = openstack_networking_secgroup_rule_v2.secgroup_rule_1.port_range_max
        remote_ip_prefix = openstack_networking_secgroup_rule_v2.secgroup_rule_1.remote_ip_prefix
      }
    ]
  }
  float_ip = {
    de = openstack_compute_instance_v2.web_server
    fixed_ip = openstack_networking_floatingip_v2.myip.fixed_ip
    floating_ip = openstack_networking_floatingip_v2.myip.address
    entire = openstack_networking_floatingip_v2.myip
  }
}

# Read server instance IDs from the file
data "local_file" "server_ids_file" {
  depends_on = [openstack_compute_instance_v2.web_server]
  filename   = "server_ids.txt"
}

# Store the ids' list inside server_instance_ids, splitting them by \n character
# Filter out values == ""
locals {
  server_instance_ids = [for id in split("\n", data.local_file.server_ids_file.content) : id if id != ""]
}

# After catching all the ids, the file server_ids.txt is resetted
resource "null_resource" "delete_file" {
  depends_on = [ local.server_instance_ids ]
  provisioner "local-exec" {
    command = "echo '' > server_ids.txt"
  }
}

# I fetch information about web server newly created
# N.B. If you need to fetch information from other server as well, you need to use the same code asking for the
# corresponding server's id
data "openstack_compute_instance_v2" "server_info" {
  id = openstack_compute_instance_v2.web_server.id
}

data "openstack_compute_instance_v2" "server_info_2" {
  id = "9733b23b-26d6-4078-8666-5e65da9e3cea"
}

data "openstack_networking_network_v2" "network" {
  name = var.network_name
}

data "openstack_networking_secgroup_v2" "secgroup" {
  depends_on = [ openstack_networking_secgroup_rule_v2.secgroup_rule_1 ]
  name = var.security_groups
}

data "openstack_networking_subnet_v2" "subnet_1" {
  subnet_id = var.subnet_id
}

data "openstack_networking_router_v2" "router" {
  name = "MySecondRouter"
}
