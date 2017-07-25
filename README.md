# OpenStack Scripts

Scripts to facilitate creating a virtual environment for OpenStack experiments.

## Motivation

At [Ocata] (https://docs.openstack.org/ocata/install-guide-ubuntu/) you can find a complete installation guide for a testing environment of OpenStack Ocata. I believe that everyone interested in setting up an OpenStack based cloud should go through the guide at least once, but after the first time, the process becomes very tedious. That's why I created these scripts. 

## Requirements

VirtualBox was my first option, but for some reason *linuxbridge* doesn't seem to work with NAT networking. So instead of VirtualBox, I created virtual machines with *kvm+libvirt+virt-manager*. Any distribution with *virt-manager* should work. You'll need at least 8 GB of RAM for this to work smoothly. 

## Virtual Machines Setup

* Create two virtual machines
   * controller (4GB RAM, 30 GB Disk)
   * compute (4 GB RAM, 30 GB Disk)
* Operating System: Ubuntu 16.04 LTS
* Create two virtual networks in virt-manager, both NAT
   * management (10.0.0.0/24)
   * provider (10.0.1.0/24)
* Attach the first NIC of each VM to management, and add a second NIC to provider
* Run *controller_install.sh* in the controller and *compute_install.sh* in compute.

There are variables in the beginning of each script that allows customization. That's it!!!


