# install

A collections of scripts for daily use

## debian

Used to install any official supported version of debian on almost all cloud services, like Oracle Cloud, Linode, Digital Ocean, etc.

* Supports the following architectures: amd64, arm64, i386, powerpc64le.
* Automatically provision the system:
  * create new user
  * install necessary packages
  * configure system
* usage:

  ```bash
  curl -sL debian.lol/debian -o debian &&                             \
    chmod +x debian &&                                                \
    ./debian --user new_user_name                                     \
           --uid 1024                                                 \
           --password your_password_here                              \
           --authorized-keys-url your_authorized_keys_url_here        \
           --cloud                                                    \
           --efi                                                      \
           --hostname some_hostname
  ```
  
## ubuntu

Similar to debian, only support version lower or equal to 20.04

## provision

Install necessary packages, configure system and users

## other scripts
