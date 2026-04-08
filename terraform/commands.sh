#!/bin/bash
set -e

echo "===== SYSTEM UPDATE ====="
sudo apt-get update -y

echo "===== INSTALL DEPENDENCIES ====="
sudo apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  apt-transport-https

##################################
# DOCKER INSTALLATION
##################################
echo "===== INSTALL DOCKER ====="
sudo apt-get install -y docker.io docker-compose
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker ubuntu

##################################
# JENKINS INSTALLATION (FIXED)
##################################
echo "===== INSTALL JENKINS ====="

sudo rm -f /etc/apt/sources.list.d/jenkins.list
sudo rm -f /etc/apt/keyrings/jenkins.gpg

curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io.key > /tmp/jenkins.key

sudo gpg --no-default-keyring   --keyring /usr/share/keyrings/jenkins-archive-keyring.gpg   --import /tmp/jenkins.key

echo "deb [signed-by=/usr/share/keyrings/jenkins-archive-keyring.gpg] https://pkg.jenkins.io/debian-stable binary/" | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null

sudo gpg --no-default-keyring   --keyring /usr/share/keyrings/jenkins-archive-keyring.gpg   --keyserver keyserver.ubuntu.com   --recv-keys 7198F4B714ABFC68

sudo apt update

sudo apt install jenkins -y

# Start Jenkins
sudo systemctl enable jenkins
sudo systemctl start jenkins

sudo apt update
sudo apt install -y nodejs npm

##################################
# TRIVY INSTALLATION (FIXED)
##################################
echo "===== INSTALL TRIVY ====="

# Add Trivy key
curl -fsSL https://aquasecurity.github.io/trivy-repo/deb/public.key \
  | sudo gpg --dearmor -o /usr/share/keyrings/trivy.gpg

# Add correct repo (IMPORTANT FIX: 'generic main')
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" \
  | sudo tee /etc/apt/sources.list.d/trivy.list > /dev/null

sudo apt-get update -y
sudo apt-get install -y trivy

##################################
# SONARQUBE (LIGHTWEIGHT DOCKER)
##################################
echo "===== RUN SONARQUBE ====="

sudo docker run -d \
  --name sonarqube \
  -p 9000:9000 \
  -e SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true \
  sonarqube:lts-community

##################################
# FINAL INFO
##################################
echo "===== SETUP COMPLETE ====="
echo "Jenkins: http://<EC2-IP>:8080"
echo "SonarQube: http://<EC2-IP>:9000"