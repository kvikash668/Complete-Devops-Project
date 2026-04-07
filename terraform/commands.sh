#bin/bash

sudo apt-get update

# docker installation
1. sudo apt-get install docker.io -y;sudo apt-get install docker-compose -y;sudo usermod -aG docker ubuntu;docker ps

# jenkins installation
   16  sudo rm -f /etc/apt/sources.list.d/jenkins.list
   17  sudo rm -f /etc/apt/keyrings/jenkins-keyring.asc
   18  sudo rm -f /etc/apt/keyrings/jenkins.gpg
   19  sudo gpg --no-default-keyring --keyring /usr/share/keyrings/jenkins-archive-keyring.gpg --import <(curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io.key)
   20  echo "deb [signed-by=/usr/share/keyrings/jenkins-archive-keyring.gpg] https://pkg.jenkins.io/debian-stable binary/" | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
   21  sudo apt update
   22  curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io.key > /tmp/jenkins.key
   23  sudo gpg --no-default-keyring --keyring /usr/share/keyrings/jenkins-archive-keyring.gpg --import /tmp/jenkins.key
   24  rm /tmp/jenkins.key
   25  sudo apt update
   26  sudo gpg --no-default-keyring --keyring /usr/share/keyrings/jenkins-archive-keyring.gpg --keyserver keyserver.ubuntu.com --recv-keys 7198F4B714ABFC68
   27  sudo apt update
   28  sudo apt install jenkins -y

   Trivy installation
 sudo apt-get install wget apt-transport-https gnupg lsb-release
       sudo rm -f /etc/apt/sources.list.d/trivy.list
   41  curl -fsSL https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo gpg --dearmor -o /usr/share/keyrings/trivy.gpg
   42  echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" | sudo tee /etc/apt/sources.list.d/trivy.list > /dev/null
   43  sudo apt update
   44  sudo apt install trivy -y

